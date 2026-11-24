import Foundation

/// The app's side of the core's service (Android parity: `Diagnostics` +
/// `RelayAccess`). The service holds the device identity every share is made
/// under, the device's access to Spora's relays (the relays the API advises
/// for new shares and the relay token running shares present, renewed in the
/// background) and the telemetry upload switch, and it uploads on its own
/// thread while the switch is on.
///
/// It starts off the main thread (`start`): local files and the Keychain
/// only. Every share call needs it, so they wait for it (`awaitReady`). A
/// start that failed is retried when the app comes to the foreground
/// (`onForeground`) and before a share that needs it.
///
/// Only the app runs the service: the tunnel extension writes its records
/// and log lines into the shared directories (`SporaPaths`), and the app's
/// service is what bundles and uploads them. (The direct build's system
/// extension writes into root's, and the app fetches them from it:
/// `DiagnosticsHandover`.)
public final class ServiceHost: @unchecked Sendable {
    public static let shared = ServiceHost()

    private static let tag = "ServiceHost"
    /// The Keychain account of the state key in `SecretStore.serviceKey`.
    private static let stateKeyAccount = "state"
    private static let stateKeyLength = 32

    public struct Options: Sendable {
        /// The version uploads and bug reports carry (`-debug` on debug builds).
        public var appVersion: String
        /// API base URLs (debug builds only); empty is the built-in production API.
        public var apiBases: [String]
        /// Keep the relay access fresh in the background: new shares go on
        /// Spora's relays, or a saved share does. Read at each start attempt.
        public var manageRelays: @Sendable () -> Bool

        public init(appVersion: String, apiBases: [String], manageRelays: @escaping @Sendable () -> Bool) {
            self.appVersion = appVersion
            self.apiBases = apiBases
            self.manageRelays = manageRelays
        }
    }

    /// The API bases from a debug build's `SPORA_API`, read as the CLI reads
    /// it: comma-separated, each trimmed, blanks dropped. Unset (nil) is the
    /// empty list, the built-in production API. A value that is set but names
    /// no address (blank, a stray comma) is passed on as it is, for the
    /// service to refuse as not a URL: a dev setup gone wrong must not
    /// quietly mean production.
    public static func apiBases(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        let bases = raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return bases.isEmpty ? [raw] : bases
    }

    private let queue = DispatchQueue(label: "to.spora.service-host")
    private let lock = NSLock()
    private var options: Options?
    private var ready = false
    private var attempted = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var lastFetchFailed = false

    /// Called on the main queue after each start attempt and relay fetch.
    public var onChange: (@Sendable () -> Void)?

    private init() {}

    /// The service is up: shares can be made and started, the switch read.
    public var isReady: Bool { lock.locked { ready } }

    /// The service failed to start (it is retried on foreground); false
    /// while it is still starting, or up.
    public var isUnavailable: Bool { lock.locked { attempted && !ready } }

    /// The last relay fetch failed. The relay access status says so too,
    /// except where the device has no registration with the API in use to
    /// keep it under.
    public var fetchFailed: Bool { lock.locked { lastFetchFailed } }

    /// Start the service in the background. Once per process; a second call
    /// only retries a failed start.
    public func start(_ options: Options) {
        lock.locked { if self.options == nil { self.options = options } }
        queue.async { self.attempt() }
    }

    /// Wait for the service, trying once more to start it if it failed.
    /// Whether it is up.
    public func awaitReady() async -> Bool {
        if isReady { return true }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let done = lock.locked { () -> Bool in
                if attempted { return true }
                waiters.append(c)
                return false
            }
            if done { c.resume() }
        }
        if isReady { return true }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async {
                self.attempt()
                c.resume()
            }
        }
        return isReady
    }

    /// The app came to the foreground: a chance to upload, to notice a
    /// changed flag, and to retry a service that failed to start rather than
    /// leave it dead until the process ends.
    public func onForeground() {
        queue.async {
            if self.isUnavailable { self.attempt() }
            if self.isReady { telemetryNudge() }
        }
    }

    /// Ask the API for relays and a relay token now (network, so off the
    /// main thread): registers the device if it is not yet. False when the
    /// service is down or the API could not be reached; the relay access
    /// status says more.
    public func fetchRelays() async -> Bool {
        guard await awaitReady() else {
            setFetchFailed(true)
            return false
        }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    _ = try refreshRelays()
                    self.setFetchFailed(false)
                    c.resume(returning: true)
                } catch {
                    SporaLog.w(Self.tag, "cannot fetch Spora's relays", error)
                    self.setFetchFailed(true)
                    c.resume(returning: false)
                }
            }
        }
    }

    private func setFetchFailed(_ failed: Bool) {
        lock.locked { lastFetchFailed = failed }
        notify()
    }

    // On `queue`: attempts never overlap.
    private func attempt() {
        if let options = lock.locked({ self.options }), !isReady {
            initialize(options)
        }
        let resume = lock.locked { () -> [CheckedContinuation<Void, Never>] in
            attempted = true
            defer { waiters.removeAll() }
            return waiters
        }
        resume.forEach { $0.resume() }
        notify()
    }

    private func initialize(_ options: Options) {
        let manageRelays = options.manageRelays()
        let storedKey = SecretStore.serviceKey.load(Self.stateKeyAccount)
            .flatMap { $0.count == Self.stateKeyLength ? $0 : nil }
        do {
            let result = try initService(config: ServiceConfig(
                stateDir: SporaPaths.stateDir.path,
                recordDir: SporaPaths.recordDir.path,
                logDir: SporaPaths.logDir.path,
                platform: "macos",
                appVersion: options.appVersion,
                apiBases: options.apiBases,
                // The device key, device token and relay token are sealed in
                // service.json with a key only the Keychain holds. None (first
                // run, or the Keychain item is gone): the service mints one,
                // and a state sealed with a lost key opens as a fresh device.
                stateKey: storedKey.map { .provided(key: $0) } ?? .mint,
                manageRelays: manageRelays
            ))
            if let minted = result.mintedStateKey,
               !SecretStore.serviceKey.save(minted, for: Self.stateKeyAccount) {
                SporaLog.e(Self.tag, "state key not saved: the next start will be a fresh device")
            }
            let status = telemetryStatus()
            SporaLog.i(Self.tag, "app \(options.appVersion) started; uploads \(status.uploadEnabled ? "on" : "off")"
                + (status.required ? ", required by the account" : "")
                + "; relay access \(manageRelays ? "kept fresh" : "off")"
                + (result.mintedStateKey != nil ? "; new state key" : ""))
            lock.locked { ready = true }
        } catch {
            SporaLog.e(Self.tag, "service unavailable", error)
        }
    }

    private func notify() {
        guard let onChange else { return }
        DispatchQueue.main.async { onChange() }
    }
}

/// Make a new share (each its own secret and link) on the relays `settings`
/// name: Spora's first, when on, then the user's own (Android: `ShareMaker`).
/// Network only when Spora's relays are wanted and none have been fetched
/// yet (a fresh install, or the API was never reachable); otherwise offline,
/// on the relays last fetched. The blob holds the share's secret: keep it in
/// the Keychain.
public enum ShareMaker {
    private static let tag = "ShareMaker"

    public static func make(settings: RelaySettings,
                            service: ServiceHost = .shared) async -> Result<Data, SporaError> {
        guard settings.hasRelays else { return .failure(.noRelays) }
        guard await service.awaitReady() else { return .failure(.shareUnavailable) }
        do {
            if settings.useSpora, try relayAccessStatus().advisedRelays.isEmpty {
                let fetched = await service.fetchRelays()
                if !fetched { return .failure(.relaysUnreachable) }
            }
            let blob = try await offMain { try makeShare(own: settings.own.map(\.entry), useSpora: settings.useSpora) }
            SporaLog.i(tag, "new share: \(settings.useSpora ? "Spora's relays + " : "")\(settings.own.count) own")
            return .success(blob)
        } catch {
            SporaLog.e(tag, "cannot make a share", error)
            return .failure(SporaError.from(error, defaultCase: .shareFailed))
        }
    }
}

/// Run blocking FFI work (files, network) off the main thread.
public func offMain<T>(_ work: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { c in
        DispatchQueue.global(qos: .userInitiated).async {
            c.resume(with: Result(catching: work))
        }
    }
}

extension NSLock {
    /// `withLock`, which Foundation has only from macOS 14.
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
