import Foundation

/// SporaKit — the platform-agnostic core of the client: the Rust FFI
/// (UniFFI-generated `connectUtun`/`startShare`/… are re-exported as this
/// module's public API), domain models, persistence, the core's service
/// (device identity, relay access, diagnostics) and status derivation. Shared
/// by the app and the NetworkExtension appex, and reusable for iOS.
public enum SporaKit {
    public static let version = "0.1.0"

    /// Route the Rust core's logging to the unified log and the diagnostic
    /// log file (`SporaPaths.logDir`). Idempotent; call once per process (the
    /// app and the tunnel extension are separate processes).
    public static func initLogging() {
        SporaPaths.initLogging()
    }
}
