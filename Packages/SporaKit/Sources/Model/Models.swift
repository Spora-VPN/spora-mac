import Foundation

/// The two roles a device plays. A device can hold both simultaneously (dual
/// role) — the UI never collapses them (CLAUDE.md rule).
public enum Role: Sendable, Equatable {
    case share  // ↑ give: you share your internet
    case use    // ↓ receive: you use a friend's internet
}

/// A share this device offers. `share` is the core's share blob (made by
/// `makeShare` under the device identity the core's service keeps): it holds
/// the share's secret and its relays, and its URL is a pure function of it
/// (`shareUrl`), so the link a friend holds stays valid across restarts and
/// other relays mean a new share. The blob is a secret and lives in the
/// Keychain (see `ConnectionStore`); the URL is never persisted.
public struct ShareConnection: Identifiable, Equatable, Sendable {
    public let id: String
    public var label: String
    public var share: Data
    public var createdAt: Date

    public init(id: String, label: String, share: Data, createdAt: Date = .distantPast) {
        self.id = id
        self.label = label
        self.share = share
        self.createdAt = createdAt
    }

    /// The share's link; nil for a blob this build cannot read.
    public var url: String? { try? shareUrl(shareBlob: share) }

    /// Whether the share presents the device's relay token (Spora's relays).
    public var usesSporaRelays: Bool {
        ((try? shareRelays(shareBlob: share)) ?? []).contains { $0.credential == .spora }
    }
}

/// A friend's connection this device can use. The bearer URL is persisted (not
/// a secret identity).
public struct UseConnection: Identifiable, Equatable, Sendable {
    public let id: String
    public var label: String
    public var url: String
    public var createdAt: Date

    public init(id: String, label: String, url: String, createdAt: Date = .distantPast) {
        self.id = id
        self.label = label
        self.url = url
        self.createdAt = createdAt
    }
}

/// Runtime info for a live share (never persisted).
public struct ActiveShareInfo: Equatable, Sendable {
    public var handle: Int32
    public var url: String
    public var startedAt: Date
    public init(handle: Int32, url: String, startedAt: Date) {
        self.handle = handle
        self.url = url
        self.startedAt = startedAt
    }
}

/// The per-connection state the UI renders, role-independent. The view maps
/// this to a shape (● ○ ◆ ◌) and localized status text; the arrow comes from
/// the connection's `Role`.
public enum DisplayState: Equatable, Sendable {
    case inactive
    case pending                 // starting / connecting
    case active                  // sharing / connected
    case error(SporaError)
    case waiting                 // waiting on a person (roadmap)
}

// MARK: - Aggregate status (dual-role, no collapse)

/// The ↓ (use) status line, if any.
public enum DownStatus: Equatable, Sendable {
    case connected(label: String)
    case connecting(label: String)
}

/// The ↑ (share) status line, if any. `sharing` carries the active names so the
/// view can render "names, then a count past two" (design 3b).
public enum UpStatus: Equatable, Sendable {
    case sharing(names: [String])
    case starting
}

/// The device's aggregate status: up to two lines (down first, then up), or
/// offline. Never collapses a dual role to one line.
public struct AggregateStatus: Equatable, Sendable {
    public var down: DownStatus?
    public var up: UpStatus?
    public var isOffline: Bool { down == nil && up == nil }
    public init(down: DownStatus? = nil, up: UpStatus? = nil) {
        self.down = down
        self.up = up
    }
}

/// Template menu-bar icon state — shape carries state without color. Precedence:
/// error ◆ beats pending ○ beats active ● beats offline (design 2e/1h).
public enum MenuBarState: Sendable, Equatable {
    case offline, active, pending, error
}

/// A selected sidebar entry (which connection's detail is shown).
public struct Selection: Equatable, Sendable {
    public let id: String
    public let role: Role
    public init(id: String, role: Role) {
        self.id = id
        self.role = role
    }
}
