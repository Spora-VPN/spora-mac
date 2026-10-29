import Foundation
import os

/// The app's logger (Android parity: `SporaLog`). Use it, never `NSLog` or
/// `print`: a line goes to the unified log (Console.app, `log stream
/// --predicate 'subsystem == "to.spora"'`) and, through the core's
/// `logLine`, into the diagnostic log file, where it sits between the core's
/// own lines in bug reports and uploads. Share-link secrets are redacted on
/// the way into the file.
///
/// The file needs `initLogging(logDir:)` (`SporaPaths.initLogging()`);
/// before it, a line reaches only the unified log. Never log a share blob,
/// a token or an error that may quote one.
public enum SporaLog {
    public static func d(_ tag: String, _ message: String) { log(.debug, tag, message) }
    public static func i(_ tag: String, _ message: String) { log(.info, tag, message) }
    public static func w(_ tag: String, _ message: String, _ error: Error? = nil) { log(.warn, tag, message, error) }
    public static func e(_ tag: String, _ message: String, _ error: Error? = nil) { log(.error, tag, message, error) }

    private static let lock = NSLock()
    private static var loggers: [String: Logger] = [:]

    private static func logger(_ tag: String) -> Logger {
        lock.lock(); defer { lock.unlock() }
        if let l = loggers[tag] { return l }
        let l = Logger(subsystem: "to.spora", category: tag)
        loggers[tag] = l
        return l
    }

    private static func log(_ level: LogLevel, _ tag: String, _ message: String, _ error: Error? = nil) {
        // The FFI errors' descriptions are the core's debug text, as on Android
        let line = error.map { "\(message): \(describe($0))" } ?? message
        let l = logger(tag)
        switch level {
        case .error: l.error("\(line, privacy: .public)")
        case .warn: l.warning("\(line, privacy: .public)")
        case .info: l.info("\(line, privacy: .public)")
        default: l.debug("\(line, privacy: .public)")
        }
        logLine(level: level, tag: tag, message: line)
    }

    /// An error in words: its type and case (the FFI's errors carry the
    /// core's debug text as their payload).
    static func describe(_ error: Error) -> String {
        "\(type(of: error)).\(error)"
    }
}
