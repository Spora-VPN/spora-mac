import Foundation

/// Where the diagnostics and the core's service state live.
///
/// The connection records and the diagnostic log are written by two
/// processes, the app (shares) and the tunnel extension (connections), and
/// read by the app's service (bug reports, uploads), so they live in the app
/// group container both belong to (Info.plist `SporaAppGroup`). The service
/// state and the connection logs are the app's alone. None of it is backed
/// up: a restored device token would clone a device, and logs and records
/// describe the machine they were made on.
public enum SporaPaths {
    /// The app group shared with the tunnel extension, if the build has one.
    /// A build without a team has none (an empty or unprefixed
    /// `.to.spora.mac`), and no entitlement for one either.
    public static var appGroup: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "SporaAppGroup") as? String,
              !id.isEmpty, !id.hasPrefix("$("), !id.hasPrefix(".") else { return nil }
        return id
    }

    /// Shared with the tunnel extension: the group container; without one
    /// (a build without the entitlement), this process's Application Support.
    public static let shared: URL = {
        if let group = appGroup,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            return url
        }
        return appSupport
    }()

    /// The app's own: Application Support/Spora (the app's container once
    /// sandboxed).
    public static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Spora", isDirectory: true)
    }()

    /// Connection records, passed to every `connectUtun` and `startShare`.
    public static var recordDir: URL { privateDir(shared.appendingPathComponent("records", isDirectory: true)) }

    /// The diagnostic log and crash files (`initLogging`).
    public static var logDir: URL { privateDir(shared.appendingPathComponent("diag", isDirectory: true)) }

    /// The core's service state (`service.json`: the device identity, the
    /// upload switch, the device and relay tokens).
    public static var stateDir: URL { privateDir(appSupport.appendingPathComponent("service", isDirectory: true)) }

    /// The connection logs' root: one directory per share and nothing else,
    /// so a running share may sweep the others' logs
    /// (`startShare(…, connLogSweepSiblings: true)`).
    static let connLogRoot = appSupport.appendingPathComponent("connlog", isDirectory: true)

    /// A share's connection log: one directory per share, because the core
    /// binds a connection-log database to the share that created it.
    public static func connLogDir(shareId: String) -> URL {
        privateDir(privateDir(connLogRoot).appendingPathComponent(shareId, isDirectory: true))
    }

    /// Deletes what is past its retention from every share's connection log,
    /// deleted shares' too, as a running share does for the others: at app
    /// start no share may be running to do it. A deleted share keeps its log
    /// (the sharer's record of what it was used for), but not past its
    /// retention. Blocking (SQLite): off the main thread.
    public static func sweepConnectionLogs() {
        guard FileManager.default.fileExists(atPath: connLogRoot.path) else { return }
        let deleted = sweepConnLogs(connLogRoot: connLogRoot.path)
        if deleted > 0 {
            SporaLog.i("SporaPaths", "connection logs: deleted \(deleted) records past retention")
        }
    }

    /// Bug reports on their way to the user's mail (pruned after a day).
    public static var reportsDir: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return privateDir(caches.appendingPathComponent("to.spora.mac/reports", isDirectory: true))
    }

    /// Route the core's logging to the unified log and the diagnostic log
    /// file. Idempotent; once per process (the app and the tunnel extension
    /// each call it), before anything is logged that a bug report needs.
    public static func initLogging() {
        ffiInitLogging(logDir.path)
    }

    /// Created 0700 if missing, and kept out of Time Machine.
    @discardableResult
    static func privateDir(_ url: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            var u = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? u.setResourceValues(values)
        }
        return url
    }
}

// At file scope, where no member named `initLogging` shadows the FFI's.
private func ffiInitLogging(_ dir: String) {
    initLogging(logDir: dir)
}
