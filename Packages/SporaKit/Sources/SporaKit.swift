import Foundation

/// SporaKit — the platform-agnostic core of the client: the Rust FFI
/// (UniFFI-generated `connectUtun`/`share`/… are re-exported as this module's
/// public API), domain models, persistence, and status derivation. Shared by
/// the app and (later) the NetworkExtension appex, and reusable for iOS.
public enum SporaKit {
    public static let version = "0.1.0"

    /// Initialize unified-logging for the Rust core. Idempotent; call once per
    /// process (the app and the tunnel extension are separate processes).
    public static func initLogging() {
        initAppleLogging()
    }
}
