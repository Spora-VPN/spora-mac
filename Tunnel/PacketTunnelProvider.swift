import NetworkExtension
import SporaKit
import Darwin

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

    private let tunnelAddress = "10.11.0.2"
    private let tunnelMTU = 1280

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        SporaKit.initLogging()
        NSLog("[spora-tunnel] startTunnel")

        guard let url = resolveURL(options: options), !url.isEmpty else {
            completionHandler(TunnelError.missingURL); return
        }

        setTunnelNetworkSettings(makeSettings()) { [weak self] error in
            guard let self else { return }
            if let error {
                NSLog("[spora-tunnel] setTunnelNetworkSettings failed: \(error)")
                completionHandler(error); return
            }
            guard let fd = self.tunnelFileDescriptor() else {
                NSLog("[spora-tunnel] could not locate utun fd")
                completionHandler(TunnelError.noUtunFD); return
            }
            let dupFd = dup(fd)
            guard dupFd >= 0 else { completionHandler(TunnelError.dupFailed); return }

            let mtuCb = TunnelMtuCallback()
            let eventCb = TunnelEventCallback(provider: self)
            self.mtuCallback = mtuCb
            self.eventCallback = eventCb

            // connect_utun blocks through relay negotiation, then returns a
            // handle and pumps packets in the background — run it off the NE
            // callback thread.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let h = try connectUtun(url: url, tunFd: dupFd, mtuCallback: mtuCb, eventCallback: eventCb)
                    self.handle = h
                    try? setKeepalive(handle: h, intervalSecs: 20) // screen-on default
                    NSLog("[spora-tunnel] connected, handle=\(h)")
                    completionHandler(nil)
                } catch {
                    Darwin.close(dupFd)
                    NSLog("[spora-tunnel] connect_utun failed: \(error)")
                    completionHandler(self.mapError(error))
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        NSLog("[spora-tunnel] stopTunnel reason=\(reason.rawValue)")
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

    private func makeSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.11.0.1")
        let ipv4 = NEIPv4Settings(addresses: [tunnelAddress], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8"])
        settings.mtu = NSNumber(value: tunnelMTU)
        return settings
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

/// MTU is discovered via PMTUD; a conservative 1280 is set up front, so we just
/// record the value (re-applying tunnel settings mid-session would churn the fd).
final class TunnelMtuCallback: MtuCallback, @unchecked Sendable {
    func onMtu(mtu: Int32) { NSLog("[spora-tunnel] MTU discovered: \(mtu)") }
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
