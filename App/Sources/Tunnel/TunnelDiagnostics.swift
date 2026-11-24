import Foundation
import SporaKit

/// The tunnel's connection records and log, where the app's bug reports and
/// uploads find them.
///
/// The app extension writes them into the group container it shares with the
/// app, and there is nothing to do. The direct build's system extension is
/// root and writes into root's: there the app fetches them (`fetch`) into its
/// own directories, over the extension's Mach service (SporaKit's
/// `DiagnosticsHandover`). It asks when something may be new or is about to
/// be read: at launch, when the app comes to the foreground, after a
/// disconnect, and before a bug report. Asking starts the extension's
/// process if it is installed, and never installs or activates it.
enum TunnelDiagnostics {
#if SPORA_DIRECT
    private static let tag = "TunnelDiagnostics"
    /// How long one fetch may take: a stuck extension must not hold up a
    /// bug report. What a cut-off fetch brought stays, and the next goes on.
    private static let deadline: TimeInterval = 8
    private static let fetcher = Fetcher()

    /// Bring over what the extension has; returns once it is here (or the
    /// extension cannot be asked). Fetches never overlap: a call during one
    /// waits for that one.
    static func fetch() async {
        await fetcher.fetch()
    }

    /// After a disconnect: the record gets its ending a moment later.
    static func fetchAfterDisconnect() {
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await fetch()
        }
    }

    private actor Fetcher {
        private var running: Task<Void, Never>?
        /// Whether the extension answered last time (logged when it changes).
        private var answered: Bool?

        func fetch() async {
            if let running {
                await running.value
                return
            }
            let task = Task.detached(priority: .utility) { [weak self] in
                let result = await TunnelDiagnostics.pull()
                await self?.finished(answered: result)
            }
            running = task
            await task.value
            running = nil
        }

        private func finished(answered now: Bool) {
            if answered != now {
                SporaLog.d(TunnelDiagnostics.tag, now ? "the tunnel extension answers" : "no tunnel extension to ask")
            }
            answered = now
        }
    }

    /// One fetch; whether the extension answered.
    private static func pull() async -> Bool {
        guard let client = DiagnosticsHandover.connect() else { return false }
        let watchdog = Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
            if !Task.isCancelled { client.invalidate() }
        }
        defer {
            watchdog.cancel()
            client.invalidate()
        }
        let sink = HandoverSink(recordDir: SporaPaths.recordDir, logDir: SporaPaths.logDir)
        do {
            let summary = try await sink.pull(from: client)
            if !summary.isEmpty {
                SporaLog.i(tag, "from the tunnel extension: \(summary.files) files, \(summary.bytes) bytes; "
                    + "\(summary.removed) finished, \(summary.failed) not taken")
            }
            // New records and log lines are something to upload (at launch
            // the service may still be starting)
            if summary.bytes > 0, await ServiceHost.shared.awaitReady() { telemetryNudge() }
            return true
        } catch {
            return false
        }
    }
#else
    static func fetch() async {}
    static func fetchAfterDisconnect() {}
#endif
}
