import Foundation
import NetworkExtension

/// App-side wrapper over `NETunnelProviderManager` for the connect/use side.
/// Owns the saved VPN configuration, starts/stops the tunnel, and reports the
/// authoritative `NEVPNStatus` back to `AppController` (which reconciles it into
/// `AppModel`, ADR D3). The provider is the embedded appex, or in the direct
/// build (`SPORA_DIRECT`) the system extension, activated before each connect.
@MainActor
final class TunnelManager {
    private let providerBundleId = "to.spora.macos.tunnel"
    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    /// Reports tunnel state transitions from `NEVPNStatus`.
    var onStatus: ((NEVPNStatus) -> Void)?

#if SPORA_DIRECT
    private let activator = ExtensionActivator()
    /// `true`: macOS waits for the user to allow the system extension (the
    /// first connect), so show them how; `false`: it no longer waits.
    var onAwaitingApproval: ((Bool) -> Void)?

    /// Stop waiting for the user to allow the extension: the pending
    /// `connect` throws `ExtensionActivator.Failure.notAllowed`.
    func cancelApproval() {
        activator.cancel()
    }
#endif

    /// Adopt an already-saved/running tunnel at launch. Returns the current
    /// status and the configured URL (so the caller can attribute it to a saved
    /// connection).
    func syncExisting() async -> (status: NEVPNStatus, url: String?)? {
        guard let managers = try? await NETunnelProviderManager.loadAllFromPreferences(),
              let m = managers.first else { return nil }
        adopt(m)
        let url = (m.protocolConfiguration as? NETunnelProviderProtocol)?
            .providerConfiguration?["url"] as? String
        return (m.connection.status, url)
    }

    /// Save the config (first time → the OS VPN-approval dialog) and start the
    /// tunnel with the share URL. The direct build first activates the
    /// system extension (first time → the user allows it in System Settings).
    func connect(url: String) async throws {
#if SPORA_DIRECT
        do {
            try await activator.activate(identifier: providerBundleId) { [weak self] in
                self?.onAwaitingApproval?(true)
            }
        } catch {
            onAwaitingApproval?(false)
            throw error
        }
        onAwaitingApproval?(false)
#endif
        let m = try await loadOrCreate()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = providerBundleId
        proto.serverAddress = "spora.to"
        proto.providerConfiguration = ["url": url]
        m.protocolConfiguration = proto
        m.localizedDescription = "Spora"
        m.isEnabled = true
        try await m.saveToPreferences()
        try await m.loadFromPreferences() // reload so the connection is valid
        adopt(m)
        try m.connection.startVPNTunnel(options: ["url": url as NSObject])
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    /// The `sporaError` message key the provider reported on its last failure.
    func lastErrorKey() async -> String? {
        guard let conn = manager?.connection else { return nil }
        return await withCheckedContinuation { cont in
            conn.fetchLastDisconnectError { error in
                cont.resume(returning: (error as NSError?)?.userInfo["sporaError"] as? String)
            }
        }
    }

    // MARK: - Private

    private func loadOrCreate() async throws -> NETunnelProviderManager {
        if let m = manager { return m }
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        return managers.first ?? NETunnelProviderManager()
    }

    private func adopt(_ m: NETunnelProviderManager) {
        if manager === m { return }
        if let obs = statusObserver { NotificationCenter.default.removeObserver(obs) }
        manager = m
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: m.connection, queue: .main
        ) { [weak self] _ in
            self?.onStatus?(m.connection.status)
        }
    }
}
