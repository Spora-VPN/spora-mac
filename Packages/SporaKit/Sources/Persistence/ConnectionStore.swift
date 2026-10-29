import Foundation

/// Persists connections across launches (Android parity: `SharedConnectionStore`
/// + `UseConnectionStore`). Share **metadata** and use connections live in
/// UserDefaults; share **blobs** (secrets: the share's secret and its relay
/// credentials) live in the Keychain (`SecretStore.shares`). Share URLs are
/// not stored: each is a pure function of its blob (`shareUrl`).
public struct ConnectionStore {
    private let defaults: UserDefaults
    private let blobs: SecretStore
    private let key = "spora.connections.v2"
    /// Before shares were the core's: a per-share identity in the Keychain.
    private let legacyKey = "spora.connections.v1"

    public init(defaults: UserDefaults = .standard, blobs: SecretStore = .shares) {
        self.defaults = defaults
        self.blobs = blobs
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
    }

    public struct Loaded {
        public var shares: [ShareConnection]
        public var uses: [UseConnection]
    }

    /// Load persisted connections. Shares whose blob is missing from the
    /// Keychain are dropped (Android drops undecodable entries).
    public func load() -> Loaded {
        migrateLegacy()
        guard let snap = snapshot() else { return Loaded(shares: [], uses: []) }
        let shares: [ShareConnection] = snap.shares.compactMap { s in
            guard let blob = blobs.load(s.id) else { return nil }
            return ShareConnection(id: s.id, label: s.label, share: blob, createdAt: s.createdAt)
        }
        let uses = snap.uses.map { UseConnection(id: $0.id, label: $0.label, url: $0.url, createdAt: $0.createdAt) }
        return Loaded(shares: shares, uses: uses)
    }

    /// Save the full connection set. Metadata goes to UserDefaults; blobs to
    /// the Keychain only when `writeBlobs` is true (skip it for renames so
    /// the Keychain isn't re-touched on every keystroke). Blobs of removed
    /// shares are always deleted.
    public func save(shares: [ShareConnection], uses: [UseConnection], writeBlobs: Bool = true) {
        let previousShareIds = Set(snapshot()?.shares.map(\.id) ?? [])
        for removed in previousShareIds.subtracting(shares.map(\.id)) {
            blobs.delete(removed)
        }
        if writeBlobs {
            for s in shares where !blobs.save(s.share, for: s.id) {
                SporaLog.e("ConnectionStore", "share \(s.id) not saved")
            }
        }
        let snap = Snapshot(
            shares: shares.map { PersistedShare(id: $0.id, label: $0.label, createdAt: $0.createdAt) },
            uses: uses.map { PersistedUse(id: $0.id, label: $0.label, url: $0.url, createdAt: $0.createdAt) }
        )
        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: key)
        }
    }

    private func snapshot() -> Snapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Shares saved before they were the core's carry an identity instead of
    /// a share and cannot be started any more: drop them (and their
    /// identities). Use connections carry over.
    private func migrateLegacy() {
        struct LegacyShare: Codable { var id: String }
        struct LegacySnapshot: Codable {
            var shares: [LegacyShare]
            var uses: [PersistedUse]
        }
        guard let data = defaults.data(forKey: legacyKey) else { return }
        if let legacy = try? JSONDecoder().decode(LegacySnapshot.self, from: data) {
            for s in legacy.shares { SecretStore.legacyIdentities.delete(s.id) }
            if snapshot() == nil, let new = try? JSONEncoder().encode(Snapshot(shares: [], uses: legacy.uses)) {
                defaults.set(new, forKey: key)
            }
            SporaLog.i("ConnectionStore", "dropped \(legacy.shares.count) shares made before device identities")
        }
        defaults.removeObject(forKey: legacyKey)
    }
}
