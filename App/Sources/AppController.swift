import SwiftUI
import AppKit
import SporaKit

/// Owns the app-level actions and UI-flow state that sit above the pure
/// `AppModel` store. Share mode runs **in-process** (ADR D3) via the real Rust
/// `share()` FFI, with connections persisted (`ConnectionStore`). Connect mode
/// still simulates (it needs the tunnel appex, which is signing-blocked per
/// ADR D5).
@MainActor
final class AppController: ObservableObject {
    let model: AppModel
    private let store: ConnectionStore

    /// Presented modal flow (save-connection sheet / create-share handoff).
    @Published var flow: Flow?

    /// The share currently being created (for cancel before the handoff).
    private var creatingShareId: String?

    /// When the harness seeds fake state, suppress persistence so debug data
    /// never reaches disk (real data reloads on `reset`).
    var persistenceSuppressed = false

    enum Flow: Equatable {
        case saveConnection(prefillURL: String?)   // sheet 1g
        case createShare(handoff: ShareDraft?)     // busy 3a → handoff 2c
    }

    /// A freshly created share awaiting copy + naming (design 2c).
    struct ShareDraft: Equatable {
        var id: String
        var url: String
    }

    init(model: AppModel, store: ConnectionStore = ConnectionStore()) {
        self.model = model
        self.store = store
        loadPersisted()
    }

    // MARK: - Persistence

    /// Reload persisted connections into the store (also the harness `reset`,
    /// Android parity: reset drops in-memory/seeded state back to real data).
    func loadPersisted() {
        persistenceSuppressed = false
        let loaded = store.load()
        model.reset()
        model.setConnections(shares: loaded.shares, uses: loaded.uses)
        for (id, url) in loaded.urls { model.registerShareURL(id, url) }
        model.selectedId = loaded.shares.first?.id ?? loaded.uses.first?.id
    }

    private func persist(writeIdentities: Bool = false) {
        guard !persistenceSuppressed else { return }
        store.save(shares: model.shares, uses: model.uses, urls: model.shareURLs,
                   writeIdentities: writeIdentities)
    }

    // MARK: - Share toggles (real, in-process)

    func toggleShare(_ id: String) {
        switch model.shareState(id) {
        case .active, .pending:
            if let handle = model.activeShares[id]?.handle { try? stopShare(handle: handle) }
            model.shareStopped(id)
        default:
            guard let conn = model.shares.first(where: { $0.id == id }) else { return }
            model.shareStarting(id)
            startShareFFI(id, identity: conn.identity, onSuccess: { [weak self] handle, url in
                self?.model.shareStarted(id, handle: handle, url: url)
                self?.persist()
            }, onFailure: { [weak self] error in
                self?.model.shareFailed(id, error: error)
            })
        }
    }

    /// Run the blocking `share()` FFI off the main thread and report back on the
    /// main actor. `share()` returns the (stable, identity-derived) URL fast; the
    /// relay registration proceeds in Rust's background task.
    private func startShareFFI(_ id: String, identity: Data,
                               onSuccess: @escaping (Int32, String) -> Void,
                               onFailure: @escaping (SporaError) -> Void) {
        Task.detached {
            do {
                let result = try share(identityBytes: identity, protector: nil,
                                       connLogDir: nil, connLogRetentionDays: nil,
                                       connLogSessionsOnly: false)
                await MainActor.run { onSuccess(result.handle, result.url) }
            } catch {
                let mapped = SporaError.from(error, defaultCase: .shareFailed)
                await MainActor.run { onFailure(mapped) }
            }
        }
    }

    func toggleUse(_ id: String) {
        // Connect mode needs the tunnel appex (signing-blocked, ADR D5) — still
        // simulated. Real path: connect_utun() from a NEPacketTunnelProvider.
        switch model.useState(id) {
        case .active, .pending:
            model.connectDisconnected()
        default:
            model.connectConnecting(id)
            after(0.5) { [model] in model.connectConnected() }
        }
    }

    // MARK: - Actions

    /// Create a new share: mint a fresh identity, persist it, and start a real
    /// in-process share — the busy moment (3a) resolves into the link handoff
    /// (2c) with the real, stable URL, or into the share's error state.
    func beginCreateShare() {
        let n = model.shares.count + 1
        let id = "share-\(UUID().uuidString.lowercased())"
        let identity = makeIdentity()
        let conn = ShareConnection(id: id, label: Lf("share_default_label", n),
                                   identity: identity, createdAt: Date())
        model.setConnections(shares: model.shares + [conn], uses: model.uses)
        model.shareStarting(id)
        model.selectedId = id
        creatingShareId = id
        flow = .createShare(handoff: nil)
        persist(writeIdentities: true) // persist the connection + identity now

        startShareFFI(id, identity: identity, onSuccess: { [weak self] handle, url in
            guard let self, self.creatingShareId == id else { return }
            self.model.shareStarted(id, handle: handle, url: url)
            self.persist()
            self.flow = .createShare(handoff: ShareDraft(id: id, url: url))
        }, onFailure: { [weak self] error in
            guard let self, self.creatingShareId == id else { return }
            self.model.shareFailed(id, error: error)
            self.creatingShareId = nil
            self.flow = nil // dismiss busy → detail shows the share in error
        })
    }

    /// Cancel share creation before the link is ready — remove the draft.
    func cancelCreateShare() {
        if let id = creatingShareId {
            if let handle = model.activeShares[id]?.handle { try? stopShare(handle: handle) }
            model.removeShare(id)
            store.deleteIdentity(id)
            persist()
        }
        creatingShareId = nil
        flow = nil
    }

    func rename(shareId: String, to label: String) {
        model.rename(shareId: shareId, to: label)
        persist()
    }

    func beginConnect() { flow = .saveConnection(prefillURL: nil) }
    func dismissFlow() { creatingShareId = nil; flow = nil }

    /// Save (and connect) a use connection from the sheet. Returns the
    /// validation error key, or nil on success.
    func saveConnection(url rawURL: String, label rawLabel: String) {
        let url = Self.normalizeURL(rawURL)
        let id = "use-\(Int(Fmt.seed(url)))"
        let label = rawLabel.trimmingCharacters(in: .whitespaces)
        let name = label.isEmpty ? L("use_default_label") : label
        let conn = UseConnection(id: id, label: name, url: url, createdAt: Date())
        if !model.uses.contains(where: { $0.id == id }) {
            model.setConnections(shares: model.shares, uses: model.uses + [conn])
        }
        model.selectedId = id
        flow = nil
        persist()
        toggleUse(id)
    }

    /// URL validation (Android `isValidShareUrl`): https · spora.to · /s/ prefix.
    static func isValidShareURL(_ raw: String) -> Bool {
        guard let comps = URLComponents(string: normalizeURL(raw)) else { return false }
        return comps.scheme == "https"
            && comps.host == "spora.to"
            && comps.path.hasPrefix("/s/")
            && comps.path.count > "/s/".count
    }

    static func normalizeURL(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://") { return t }
        return "https://\(t)"
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func retry(_ selection: Selection) {
        switch selection.role {
        case .share: toggleShare(selection.id)
        case .use: toggleUse(selection.id)
        }
    }

    func deleteSelected() {
        guard let sel = model.selection else { return }
        switch sel.role {
        case .share:
            if let handle = model.activeShares[sel.id]?.handle { try? stopShare(handle: handle) }
            model.removeShare(sel.id)
        case .use:
            model.removeUse(sel.id)
        }
        persist() // prunes the removed share's identity from the store
    }

    // MARK: - Helpers

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    static func syntheticHandle(_ id: String) -> Int32 {
        Int32(truncatingIfNeeded: Fmt.seed(id))
    }

    /// Deterministic spora.to token from an id (placeholder for a real share URL).
    static func syntheticURL(_ id: String) -> String {
        let alphabet = Array("0123456789abcdefghijkmnpqrstuvwxyz")
        var s = Fmt.seed(id)
        var token = ""
        for _ in 0..<10 {
            token.append(alphabet[Int(s % UInt32(alphabet.count))])
            s = s &* 1664525 &+ 1013904223
        }
        return "https://spora.to/s/\(token)"
    }
}
