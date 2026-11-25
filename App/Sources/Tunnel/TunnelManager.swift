import Foundation
import NetworkExtension
import SporaKit

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

    /// After an update the extension macOS runs is still the previous
    /// version's: replace it with this app's copy now, at launch, before the
    /// tunnel is reconciled (ADR-002 D3: right after the update, not at the
    /// next connect). Only an extension the user already allowed, so someone
    /// who never connected never meets the approval. A tunnel the old
    /// extension runs is stopped first and started again on the new one.
    func replaceOutdatedExtension() async {
        guard await ExtensionVersion.enabledIsOutdated(identifier: providerBundleId) else { return }
        let saved = try? await NETunnelProviderManager.loadAllFromPreferences().first
        let running = saved.map { [.connected, .connecting, .reasserting].contains($0.connection.status) } ?? false
        if running, let saved {
            saved.connection.stopVPNTunnel()
            await waitUntilStopped(saved)
        }
        do {
            try await activator.activate(identifier: providerBundleId) { [activator = self.activator] in
                // Not expected of an extension the user allowed. The guide is
                // for a connect, never for a launch: stop waiting, and the next
                // connect asks again.
                SporaLog.w("TunnelManager", "the replacement waits for the user's approval")
                activator.cancel()
            }
        } catch {
            SporaLog.w("TunnelManager", "extension not replaced", error)
        }
        guard running, let saved,
              let url = (saved.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerConfiguration?["url"] as? String else { return }
        do {
            try saved.connection.startVPNTunnel(options: ["url": url as NSObject])
        } catch {
            SporaLog.w("TunnelManager", "tunnel not restarted after the replacement", error)
        }
    }

    private func waitUntilStopped(_ m: NETunnelProviderManager) async {
        var waited = 0 // up to 10 s
        while m.connection.status != .disconnected, m.connection.status != .invalid, waited < 50 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            waited += 1
        }
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
