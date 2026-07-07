import Foundation
import Security

/// Stores a share's secret identity bytes (CLAUDE.md: "Identity bytes are
/// secrets → Keychain"). Each share has its own identity keyed by connection id.
///
/// Primary backend is the Keychain (generic password, this app's access).
/// Because the current build is **ad-hoc unsigned** (project.yml `CODE_SIGN_IDENTITY
/// "-"`), a Keychain access-control prompt could block a headless run — so
/// operations pass `kSecUseAuthenticationUI: fail` (a would-be prompt becomes an
/// error) and fall back to a 0600 file under Application Support. Once the app is
/// dev-signed with a keychain-access-group, the Keychain path succeeds silently
/// and the file fallback is never used.
public struct IdentityStore {
    private let service = "to.spora.mac.identity"
    private let fileDir: URL

    public init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileDir = base.appendingPathComponent("Spora/identities", isDirectory: true)
    }

    public func save(_ data: Data, for id: String) {
        if keychainSave(data, account: id) { return }
        fileSave(data, for: id)
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

    private func fileSave(_ data: Data, for id: String) {
        try? FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let url = fileURL(id)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func fileLoad(_ id: String) -> Data? {
        try? Data(contentsOf: fileURL(id))
    }
}
