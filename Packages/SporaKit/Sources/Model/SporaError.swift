import Foundation

/// User-facing error vocabulary (Android parity: `UserError`). Raw Rust error
/// strings are English debug text — never shown. Each case maps to a localized
/// string via `messageKey`, resolved by the UI layer (which owns the String
/// Catalog). Errors are snapshotted per connection at failure time and survive
/// service teardown (see `AppModel`).
public enum SporaError: Error, Equatable, Sendable, Codable, CaseIterable {
    case invalidUrl
    case connectFailed
    case shareFailed
    /// The service that holds the device identity is not up.
    case shareUnavailable
    /// The share was made under a device identity this Mac no longer has (its
    /// service state was lost): only a new share (a new link) helps.
    case shareLinkLost
    /// Spora's relays off and none of the user's own: no share can be made.
    case noRelays
    /// Spora's relays asked for, and the API could not be reached.
    case relaysUnreachable
    /// The API answered with no relays.
    case noSporaRelays
    case vpnPermissionDenied
    case vpnUnavailable
    case generic

    /// String Catalog key for the localized message.
    public var messageKey: String {
        switch self {
        case .invalidUrl: return "error_invalid_url"
        case .connectFailed: return "error_connect_failed"
        case .shareFailed: return "error_share_failed"
        case .shareUnavailable: return "error_share_unavailable"
        case .shareLinkLost: return "error_share_link_lost"
        case .noRelays: return "error_no_relays"
        case .relaysUnreachable: return "error_relays_unreachable"
        case .noSporaRelays: return "error_no_spora_relays"
        case .vpnPermissionDenied: return "error_vpn_permission"
        case .vpnUnavailable: return "error_vpn_unavailable"
        case .generic: return "error_generic"
        }
    }

    /// The relay settings are the fix: the error offers to open them.
    public var opensRelaySettings: Bool { self == .noRelays || self == .noSporaRelays }

    /// Reverse-lookup from a `messageKey` (used to decode an error carried
    /// across the app ↔ tunnel-appex boundary).
    public init(messageKey: String?) {
        self = SporaError.allCases.first { $0.messageKey == messageKey } ?? .generic
    }

    /// Parse the harness `err=` token (Android `UserError.valueOf`).
    public init(token: String?) {
        switch token?.uppercased() {
        case "INVALID_URL": self = .invalidUrl
        case "CONNECT_FAILED": self = .connectFailed
        case "SHARE_FAILED": self = .shareFailed
        case "SHARE_UNAVAILABLE": self = .shareUnavailable
        case "SHARE_LINK_LOST": self = .shareLinkLost
        case "NO_RELAYS": self = .noRelays
        case "RELAYS_UNREACHABLE": self = .relaysUnreachable
        case "NO_SPORA_RELAYS": self = .noSporaRelays
        case "VPN_PERMISSION_DENIED", "VPN_PERMISSION": self = .vpnPermissionDenied
        case "VPN_UNAVAILABLE": self = .vpnUnavailable
        default: self = .generic
        }
    }

    /// Map a raw FFI error into the user vocabulary (Android `toUserError`).
    /// `ConnectError.InvalidUrl` → invalid link; other connect errors →
    /// couldn't-connect; a share under a lost identity → make a new link; the
    /// service down → unavailable; no relay advice → no Spora relays; other
    /// share errors → couldn't-start-sharing.
    public static func from(_ error: Error, defaultCase: SporaError = .generic) -> SporaError {
        switch error {
        case ConnectError.InvalidUrl:
            return .invalidUrl
        case is ConnectError:
            return .connectFailed
        case ShareError.IdentityMismatch:
            return .shareLinkLost
        case ShareError.NotInitialized:
            return .shareUnavailable
        case ShareError.NoRelayAdvice:
            return .noSporaRelays
        case is ShareError:
            return .shareFailed
        default:
            return defaultCase
        }
    }
}
