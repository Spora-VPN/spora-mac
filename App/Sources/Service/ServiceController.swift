import Foundation
import SporaKit

/// The UI's view of the core's service (`ServiceHost`): the relay settings
/// new links are made with, the device's access to Spora's relays, and the
/// telemetry upload switch. The settings pages read it; the service's
/// background work (renewals, uploads) is re-read by polling while a page is
/// open (`refresh`), since the core pushes nothing.
@MainActor
final class ServiceController: ObservableObject {
    private static let tag = "ServiceController"

    /// The relays new links are made with.
    @Published private(set) var relaySettings: RelaySettings
    /// The device's relay access as last read; nil until the service is up.
    @Published private(set) var relayAccess: RelayAccessStatus?
    /// The last relay fetch failed.
    @Published private(set) var fetchFailed = false
    /// A fetch started from the Relays page is running.
    @Published private(set) var fetching = false
    /// The upload switch as last read; nil until the service is up.
    @Published private(set) var telemetry: TelemetryStatus?
    /// The service failed to start (it is retried on foreground).
    @Published private(set) var unavailable = false

    /// When the harness seeds relay settings, they stay in memory.
    var persistenceSuppressed = false

    private let host: ServiceHost
    private let relayStore: RelaySettingsStore

    init(host: ServiceHost = .shared, relayStore: RelaySettingsStore = RelaySettingsStore()) {
        self.host = host
        self.relayStore = relayStore
        relaySettings = relayStore.load()
        host.onChange = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Start the service (once per process, off the main thread).
    func start() {
        host.start(ServiceHost.Options(
            appVersion: Self.appVersion,
            apiBases: Self.apiBases,
            // Registering the device with Spora's API is for Spora's relays:
            // new links go on them, or a saved link does
            manageRelays: {
                RelaySettingsStore().load().useSpora
                    || ConnectionStore().load().shares.contains(where: \.usesSporaRelays)
            }
        ))
    }

    /// The app came to the foreground.
    func onForeground() {
        host.onForeground()
        refresh()
    }

    /// Re-read the service's state (this process's copy: no I/O).
    func refresh() {
        unavailable = host.isUnavailable
        fetchFailed = host.fetchFailed
        guard host.isReady else { return }
        let status = telemetryStatus()
        if telemetry != status { telemetry = status }
        do {
            let access = try relayAccessStatus()
            if relayAccess != access { relayAccess = access }
        } catch {
            SporaLog.w(Self.tag, "relay access status unavailable", error)
        }
    }

    // MARK: - Relays

    func setUseSpora(_ use: Bool) {
        relaySettings.useSpora = use
        persistRelays()
        SporaLog.i(Self.tag, "Spora's relays \(use ? "on" : "off") for new shares")
    }

    /// Add `relay`, or replace the one at `index`.
    func putRelay(_ relay: OwnRelay, at index: Int?) {
        if let index, relaySettings.own.indices.contains(index) {
            relaySettings.own[index] = relay
        } else {
            relaySettings.own.append(relay)
        }
        persistRelays()
    }

    func removeRelay(at index: Int) {
        guard relaySettings.own.indices.contains(index) else { return }
        relaySettings.own.remove(at: index)
        persistRelays()
    }

    /// Seed the settings for the harness (kept in memory only).
    func seedRelays(_ settings: RelaySettings) {
        persistenceSuppressed = true
        relaySettings = settings
    }

    /// Reload the saved settings (the harness `reset`).
    func reloadRelays() {
        persistenceSuppressed = false
        relaySettings = relayStore.load()
    }

    private func persistRelays() {
        guard !persistenceSuppressed else { return }
        relayStore.save(relaySettings)
    }

    /// Ask the API for relays now (the Relays page, when Spora's relays are on
    /// and were never fetched).
    func fetchRelays() async {
        guard !fetching else { return }
        fetching = true
        _ = await host.fetchRelays()
        fetching = false
        refresh()
    }

    // MARK: - Telemetry

    enum SwitchResult { case ok, required, failed }

    /// Flip the upload switch. `.required`: the account requires uploads,
    /// nothing changed, and the user is owed the force notice.
    func setUploadEnabled(_ enabled: Bool) async -> SwitchResult {
        defer { refresh() }
        do {
            try await offMain { try setTelemetryEnabled(enabled: enabled) }
            SporaLog.i(Self.tag, "uploads switched \(enabled ? "on" : "off") by the user")
            return .ok
        } catch TelemetryError.Required {
            return .required
        } catch {
            SporaLog.e(Self.tag, "cannot switch uploads \(enabled ? "on" : "off")", error)
            return .failed
        }
    }

    /// The user has seen the force notice.
    func acknowledgeNotice() {
        guard telemetry?.requiredNoticePending == true else { return }
        Task {
            try? await offMain { acknowledgeTelemetryNotice() }
            refresh()
        }
    }

    // MARK: - Build

    /// The version the service reports: `-debug` on debug builds, so the
    /// server can tell them from installs.
    nonisolated static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        #if DEBUG
        return v + "-debug"
        #else
        return v
        #endif
    }

    /// Debug builds can be pointed at a test API with `SPORA_API`
    /// (`scripts/dev.sh run` pins it to an address that answers nothing);
    /// release builds always use the built-in production API.
    nonisolated static var apiBases: [String] {
        #if DEBUG
        return ServiceHost.apiBases(ProcessInfo.processInfo.environment["SPORA_API"])
        #else
        return []
        #endif
    }
}
