import Foundation

/// User-facing error vocabulary (Android parity: `UserError`). Raw Rust error
/// strings are English debug text — never shown. Each case maps to a localized
/// string via `messageKey`, resolved by the UI layer (which owns the String
/// Catalog). Errors are snapshotted per connection at failure time and survive
/// service teardown (see `AppModel`).
public enum SporaError: Error, Equatable, Sendable, Codable {
    case invalidUrl
    case connectFailed
    case shareFailed
    case vpnPermissionDenied
    case vpnUnavailable
    case generic

    /// String Catalog key for the localized message.
    public var messageKey: String {
        switch self {
        case .invalidUrl: return "error_invalid_url"
        case .connectFailed: return "error_connect_failed"
        case .shareFailed: return "error_share_failed"
        case .vpnPermissionDenied: return "error_vpn_permission"
        case .vpnUnavailable: return "error_vpn_unavailable"
        case .generic: return "error_generic"
        }
    }

    /// Parse the harness `err=` token (Android `UserError.valueOf`).
    public init(token: String?) {
        switch token?.uppercased() {
        case "INVALID_URL": self = .invalidUrl
        case "CONNECT_FAILED": self = .connectFailed
        case "SHARE_FAILED": self = .shareFailed
        case "VPN_PERMISSION_DENIED", "VPN_PERMISSION": self = .vpnPermissionDenied
        case "VPN_UNAVAILABLE": self = .vpnUnavailable
        default: self = .generic
        }
    }

    /// Map a raw FFI error into the user vocabulary (Android `toUserError`).
    /// `ConnectError.InvalidUrl` → invalid link; other connect errors →
    /// couldn't-connect; share errors → couldn't-start-sharing.
    public static func from(_ error: Error, defaultCase: SporaError = .generic) -> SporaError {
        switch error {
        case ConnectError.InvalidUrl:
            return .invalidUrl
        case is ConnectError:
            return .connectFailed
        case is ShareError:
            return .shareFailed
        default:
            return defaultCase
        }
    }
}
