import NetworkExtension
import SporaKit
import SystemConfiguration
import Darwin

// From <netinet/in.h> — not always surfaced in the Darwin overlay.
private let IP_BOUND_IF_OPT: Int32 = 25
private let IPV6_BOUND_IF_OPT: Int32 = 125

/// Diagnostic log for the sandboxed appex — its NSLogs don't surface in
/// `log show`, so mirror them to a file in the extension's container
/// (`~/Library/Containers/to.spora.mac.tunnel/Data/tmp/spora-tunnel.log`).
private let tunnelLogPath = NSHomeDirectory() + "/tmp/spora-tunnel.log"

func tlog(_ msg: String) {
    NSLog("[spora-tunnel] \(msg)")
    guard let data = "\(Date()) \(msg)\n".data(using: .utf8) else { return }
    let dir = NSHomeDirectory() + "/tmp"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if let fh = FileHandle(forWritingAtPath: tunnelLogPath) {
        fh.seekToEndOfFile(); fh.write(data); try? fh.close()
    } else {
        FileManager.default.createFile(atPath: tunnelLogPath, contents: data)
    }
}

func tlogReset() { try? FileManager.default.removeItem(atPath: tunnelLogPath) }

/// The packet-tunnel provider (connect/use side). Stays a thin, sandboxed shim:
/// it configures the tunnel, locates the utun fd, `dup()`s it, and hands the dup
/// to Rust's `connect_utun()`, which owns it and pumps packets (4-byte AF
/// framing) in the core's tokio runtime. All tunnel logic lives in Rust.
///
/// On Darwin, provider-originated sockets (the relay dial inside `connect_utun`)
/// bypass the tunnel automatically, so no socket protector is needed and the
/// default route can be installed up front (ADR D2).
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var handle: Int32?
    private var mtuCallback: TunnelMtuCallback?
    private var eventCallback: TunnelEventCallback?
    private var protector: TunnelProtector?

    private let tunnelAddress = "10.11.0.2"
    private let tunnelMTU = 1280

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        SporaKit.initLogging()
        tlogReset()
        tlog("startTunnel")

        guard let url = resolveURL(options: options), !url.isEmpty else {
            completionHandler(TunnelError.missingURL); return
        }

        // Capture the physical interface NOW — before the tunnel becomes the
        // primary interface — so the protector can bind relay sockets to it.
        let physIfIndex = Self.primaryInterfaceIndex()
        tlog("physical interface index: \(physIfIndex.map(String.init(describing:)) ?? "nil")")

        setTunnelNetworkSettings(makeSettings(excluding: Self.relayHosts(from: url))) { [weak self] error in
            guard let self else { return }
            if let error {
                tlog("setTunnelNetworkSettings failed: \(error)")
                completionHandler(error); return
            }
            guard let fd = self.tunnelFileDescriptor() else {
                tlog("could not locate utun fd")
                completionHandler(TunnelError.noUtunFD); return
            }
            let dupFd = dup(fd)
            guard dupFd >= 0 else { completionHandler(TunnelError.dupFailed); return }

            let mtuCb = TunnelMtuCallback()
            let eventCb = TunnelEventCallback(provider: self)
            let protector = physIfIndex.map { TunnelProtector(ifIndex: $0) }
            self.mtuCallback = mtuCb
            self.eventCallback = eventCb
            self.protector = protector

            // connect_utun blocks through relay negotiation, then returns a
            // handle and pumps packets in the background — run it off the NE
            // callback thread.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let h = try connectUtun(url: url, tunFd: dupFd, protector: protector,
                                            mtuCallback: mtuCb, eventCallback: eventCb)
                    self.handle = h
                    try? setKeepalive(handle: h, intervalSecs: 20) // screen-on default
                    tlog("connected, handle=\(h)")
                    completionHandler(nil)
                } catch {
                    Darwin.close(dupFd)
                    tlog("connect_utun failed: \(error)")
                    completionHandler(self.mapError(error))
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        tlog("stopTunnel reason=\(reason.rawValue)")
        if let h = handle { try? disconnect(handle: h) }
        handle = nil
        mtuCallback = nil
        eventCallback = nil
        completionHandler()
    }

    // Keepalive follows machine sleep/wake (mirrors Android screen on/off).
    override func sleep(completionHandler: @escaping () -> Void) {
        if let h = handle { try? setKeepalive(handle: h, intervalSecs: 0) }
        completionHandler()
    }

    override func wake() {
        if let h = handle { try? setKeepalive(handle: h, intervalSecs: 20) }
    }

    // MARK: - Helpers

    private func resolveURL(options: [String: NSObject]?) -> String? {
        if let u = options?["url"] as? String { return u }
        if let proto = protocolConfiguration as? NETunnelProviderProtocol,
           let u = proto.providerConfiguration?["url"] as? String { return u }
        return nil
    }

    private func makeSettings(excluding relayHosts: [String]) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.11.0.1")
        let ipv4 = NEIPv4Settings(addresses: [tunnelAddress], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        // Exclude the relay's own address(es) from the tunnel — otherwise the
        // provider's QUIC dial to the relay routes back into the tunnel it is
        // trying to establish and dead-locks (the classic "exclude the VPN
        // server address" rule). Provider-originated sockets are NOT auto-bypassed
        // on macOS, contrary to ADR D2's assumption.
        ipv4.excludedRoutes = relayHosts.map {
            NEIPv4Route(destinationAddress: $0, subnetMask: "255.255.255.255")
        }
        settings.ipv4Settings = ipv4
        settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8"])
        settings.mtu = NSNumber(value: tunnelMTU)
        tlog("excluding relay routes: \(relayHosts)")
        return settings
    }

    /// Relay IPv4 addresses to keep off the tunnel: the built-in default plus any
    /// `?r=host:port` hints carried in the share URL.
    private static func relayHosts(from url: String) -> [String] {
        var hosts = Set(["167.71.66.250"]) // spora-core default relay
        if let comps = URLComponents(string: url) {
            for item in comps.queryItems ?? [] where item.name == "r" {
                guard let value = item.value, let colon = value.lastIndex(of: ":") else { continue }
                let host = String(value[..<colon])
                var buf = in_addr()
                if inet_pton(AF_INET, host, &buf) == 1 { hosts.insert(host) }
            }
        }
        return Array(hosts)
    }

    /// The kernel index of the primary physical interface (e.g. en0), read from
    /// SystemConfiguration before the tunnel takes over routing.
    private static func primaryInterfaceIndex() -> UInt32? {
        guard let store = SCDynamicStoreCreate(nil, "to.spora.tunnel" as CFString, nil, nil),
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let name = dict["PrimaryInterface"] as? String else { return nil }
        let idx = if_nametoindex(name)
        return idx == 0 ? nil : idx
    }

    /// The utun socket fd backing `packetFlow`. Primary is the widely-used KVC
    /// path; fallback scans for the AF_SYSTEM control socket.
    private func tunnelFileDescriptor() -> Int32? {
        if let value = packetFlow.value(forKeyPath: "socket.fileDescriptor") {
            if let n = value as? Int32 { return n }
            if let n = value as? NSNumber { return n.int32Value }
        }
        for fd in Int32(0)..<1024 {
            var addr = sockaddr_ctl()
            var len = socklen_t(MemoryLayout<sockaddr_ctl>.size)
            let matched = withUnsafeMutablePointer(to: &addr) { ptr -> Bool in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getpeername(fd, $0, &len) == 0 }
            }
            if matched && Int32(addr.sc_family) == AF_SYSTEM { return fd }
        }
        return nil
    }

    private func mapError(_ error: Error) -> NSError {
        let mapped = SporaError.from(error, defaultCase: .connectFailed)
        return NSError(domain: "to.spora.tunnel", code: 1,
                       userInfo: ["sporaError": mapped.messageKey])
    }

    func setReasserting(_ value: Bool) {
        DispatchQueue.main.async { self.reasserting = value }
    }

    func endSession() {
        DispatchQueue.main.async { self.cancelTunnelWithError(nil) }
    }
}

enum TunnelError: Error { case missingURL, noUtunFD, dupFailed }

/// Binds each provider-created socket to the physical interface (`IP_BOUND_IF`)
/// so its packets bypass the tunnel — the relay dial and direct-upgrade sockets
/// must not route back through the utun we're establishing. This is the ADR D2
/// fallback, now the primary path (macOS doesn't auto-bypass, and excludedRoutes
/// proved unreliable).
final class TunnelProtector: SocketProtectorCallback, @unchecked Sendable {
    private let ifIndex: UInt32
    init(ifIndex: UInt32) { self.ifIndex = ifIndex }
    func protect(fd: Int32) {
        var v4 = ifIndex
        let r4 = setsockopt(fd, IPPROTO_IP, IP_BOUND_IF_OPT, &v4, socklen_t(MemoryLayout<UInt32>.size))
        var v6 = ifIndex
        let r6 = setsockopt(fd, IPPROTO_IPV6, IPV6_BOUND_IF_OPT, &v6, socklen_t(MemoryLayout<UInt32>.size))
        tlog("protect fd=\(fd) if=\(ifIndex) v4=\(r4) v6=\(r6)")
    }
}

/// MTU is discovered via PMTUD; a conservative 1280 is set up front, so we just
/// record the value (re-applying tunnel settings mid-session would churn the fd).
final class TunnelMtuCallback: MtuCallback, @unchecked Sendable {
    func onMtu(mtu: Int32) { tlog("MTU discovered: \(mtu)") }
}

/// Surfaces core lifecycle events to NE status: reconnecting → `reasserting`,
/// session ended → tear the tunnel down (app sees disconnected).
final class TunnelEventCallback: EventCallback, @unchecked Sendable {
    private weak var provider: PacketTunnelProvider?
    init(provider: PacketTunnelProvider) { self.provider = provider }
    func onEvent(event: SporaEvent) {
        switch event {
        case .reconnecting: provider?.setReasserting(true)
        case .reconnected: provider?.setReasserting(false)
        case .sessionEnded: provider?.endSession()
        default: break // relay established, direct upgrade, conn-log degraded
        }
    }
}
