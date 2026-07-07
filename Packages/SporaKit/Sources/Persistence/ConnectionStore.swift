import Foundation

/// Persists connections across launches (Android parity: `SharedConnectionStore`
/// + `UseConnectionStore`). Share **metadata** and use connections live in
/// UserDefaults; share **identities** (secrets) live in the `IdentityStore`
/// (Keychain). Share URLs are cached so the detail pane can show a stable link
/// even before `share()` runs — the URL is deterministic from the identity, so
/// a cached URL stays valid (see spora-core `share()`).
public struct ConnectionStore {
    private let defaults: UserDefaults
    private let identities = IdentityStore()
    private let key = "spora.connections.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private struct PersistedShare: Codable {
        var id: String
        var label: String
        var createdAt: Date
    }
    private struct PersistedUse: Codable {
        var id: String
        var label: String
        var url: String
        var createdAt: Date
    }
    private struct Snapshot: Codable {
        var shares: [PersistedShare]
        var uses: [PersistedUse]
        var urls: [String: String]
    }

    public struct Loaded {
        public var shares: [ShareConnection]
        public var uses: [UseConnection]
        public var urls: [String: String]
    }

    /// Load persisted connections. Shares whose identity is missing from the
    /// keychain/file are dropped (Android drops undecodable entries).
    public func load() -> Loaded {
        guard let data = defaults.data(forKey: key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Loaded(shares: [], uses: [], urls: [:])
        }
        let shares: [ShareConnection] = snap.shares.compactMap { s in
            guard let identity = identities.load(s.id) else { return nil }
            return ShareConnection(id: s.id, label: s.label, identity: identity, createdAt: s.createdAt)
        }
        let uses = snap.uses.map { UseConnection(id: $0.id, label: $0.label, url: $0.url, createdAt: $0.createdAt) }
        return Loaded(shares: shares, uses: uses, urls: snap.urls)
    }

    /// Save the full connection set. Metadata + URLs go to UserDefaults;
    /// identities to the identity store only when `writeIdentities` is true
    /// (skip it for renames / URL-cache updates so the Keychain isn't re-touched
    /// on every keystroke). Identities for removed shares are always pruned.
    public func save(shares: [ShareConnection], uses: [UseConnection], urls: [String: String],
                     writeIdentities: Bool = true) {
        let previous = (try? JSONDecoder().decode(Snapshot.self, from: defaults.data(forKey: key) ?? Data()))
        let previousShareIds = Set(previous?.shares.map(\.id) ?? [])
        let currentShareIds = Set(shares.map(\.id))
        for removed in previousShareIds.subtracting(currentShareIds) {
            identities.delete(removed)
        }
        if writeIdentities {
            for s in shares {
                identities.save(s.identity, for: s.id)
            }
        }
        let snap = Snapshot(
            shares: shares.map { PersistedShare(id: $0.id, label: $0.label, createdAt: $0.createdAt) },
            uses: uses.map { PersistedUse(id: $0.id, label: $0.label, url: $0.url, createdAt: $0.createdAt) },
            urls: urls
        )
        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: key)
        }
    }

    public func deleteIdentity(_ id: String) {
        identities.delete(id)
    }
}
