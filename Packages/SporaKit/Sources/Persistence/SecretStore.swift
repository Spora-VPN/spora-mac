import Foundation
import Security

/// Stores secret bytes (AGENTS.md: "Identity bytes are secrets → Keychain"):
/// each share's blob (its secret and relay credentials), the key the core's
/// service seals its state with, the relay settings (own relays' tokens).
/// One `service` per kind of secret, one account per item.
///
/// Primary backend is the Keychain (generic password, this app's access).
/// An ad-hoc signed build could meet a Keychain access-control prompt that
/// blocks a headless run, so operations pass `kSecUseAuthenticationUI: fail`
/// (a would-be prompt becomes an error) and fall back to a 0600 file under
/// Application Support. Team-signed builds take the Keychain path silently
/// and never use the fallback.
public struct SecretStore {
    private let service: String
    private let fileDir: URL

    /// - Parameters:
    ///   - service: the Keychain service, e.g. `to.spora.mac.share`.
    ///   - fileDirName: the fallback directory under Application Support/Spora.
    public init(service: String, fileDirName: String) {
        self.service = service
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileDir = base.appendingPathComponent("Spora/\(fileDirName)", isDirectory: true)
    }

    /// Shares' blobs, by connection id.
    public static let shares = SecretStore(service: "to.spora.mac.share", fileDirName: "shares")
    /// Before shares were the core's: a per-share identity, by connection id.
    /// Only read to delete what an older version left.
    static let legacyIdentities = SecretStore(service: "to.spora.mac.identity", fileDirName: "identities")
    /// The key the core's service seals `service.json`'s secrets with.
    public static let serviceKey = SecretStore(service: "to.spora.mac.service-key", fileDirName: "service-key")
    /// The relay settings (own relays' tokens are secrets).
    public static let relaySettings = SecretStore(service: "to.spora.mac.relay-settings", fileDirName: "relay-settings")

    /// Whether the bytes are stored (Keychain, else the 0600 file).
    @discardableResult
    public func save(_ data: Data, for id: String) -> Bool {
        if keychainSave(data, account: id) {
            try? FileManager.default.removeItem(at: fileURL(id))
            return true
        }
        return fileSave(data, for: id)
    }

    public func load(_ id: String) -> Data? {
        keychainLoad(account: id) ?? fileLoad(id)
    }

    public func delete(_ id: String) {
        keychainDelete(account: id)
        try? FileManager.default.removeItem(at: fileURL(id))
    }

    // MARK: Keychain

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func keychainSave(_ data: Data, account: String) -> Bool {
        keychainDelete(account: account)
        var add = baseQuery(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private func keychainLoad(account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private func keychainDelete(account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    // MARK: File fallback (0600)

    private func fileURL(_ id: String) -> URL {
        fileDir.appendingPathComponent("\(id).bin")
    }

    private func fileSave(_ data: Data, for id: String) -> Bool {
        try? FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let url = fileURL(id)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }

    private func fileLoad(_ id: String) -> Data? {
        try? Data(contentsOf: fileURL(id))
    }
}
