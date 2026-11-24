import SwiftUI
import AppKit
import NetworkExtension
import SporaKit

/// Owns the app-level actions and UI-flow state that sit above the pure
/// `AppModel` store. Share mode runs **in-process** (ADR D3): shares are the
/// core's (a blob per link, made by `ShareMaker` on the relays the settings
/// name, under the device identity the core's service keeps) and run through
/// `startShare`; connections are persisted (`ConnectionStore`). Connect mode
/// runs in the tunnel appex and is reconciled from `NEVPNStatus`.
@MainActor
final class AppController: ObservableObject {
    private static let tag = "AppController"

    let model: AppModel
    let service: ServiceController
    private let store: ConnectionStore

    /// The create-share flow, shown in the detail region.
    @Published var flow: Flow?
    /// The modal sheet over the window (one at a time).
    @Published var sheet: Sheet?
    /// The open settings pages, shown in the detail region; the last is
    /// shown, and back drops it. Empty: closed.
    @Published var settingsPages: [SettingsPage] = []

    /// The share the create flow is making and starting (`replacing`: a new
    /// link for a saved share), for cancel and for results that arrive after.
    private var creating: (token: UUID, shareId: String?, replacing: Bool)?

    /// The pending start of each share: a stop while `startShare` is still
    /// blocked drops it, and the session it then returns is stopped.
    private var startTokens: [String: UUID] = [:]

    /// When the harness seeds fake state, suppress persistence so debug data
    /// never reaches disk (real data reloads on `reset`).
    var persistenceSuppressed = false

    private let tunnel = TunnelManager()
    private let notifications = NotificationManager()
    /// The use connection whose tunnel is being (dis)connected — for status
    /// attribution back into the model.
    private var connectingUseId: String?

    enum Flow: Equatable {
        case createShare(CreateStage)   // busy 3a → handoff 2c
    }

    enum CreateStage: Equatable {
        case making
        /// No link could be made (no relays, Spora unreachable, …).
        case failed(SporaError)
        case ready(ShareDraft)
    }

    /// A freshly made share awaiting copy (+ naming, when new) (design 2c).
    struct ShareDraft: Equatable {
        var id: String
        var url: String
        /// A new share (offer to name it), not a new link for a saved one.
        var isNew: Bool
    }

    enum Sheet: Identifiable, Equatable {
        case saveConnection(prefillURL: String?)   // sheet 1g
        case relayEditor(index: Int?)               // nil: add a relay
        case removeRelay(index: Int)
        case feedback
        case telemetryRequired

        var id: String {
            switch self {
            case .saveConnection: return "save"
            case .relayEditor(let i): return "relay-\(i ?? -1)"
            case .removeRelay(let i): return "remove-\(i)"
            case .feedback: return "feedback"
            case .telemetryRequired: return "telemetry-required"
            }
        }
    }

    init(model: AppModel, service: ServiceController, store: ConnectionStore = ConnectionStore()) {
        self.model = model
        self.service = service
        self.store = store
        loadPersisted()
        notifications.configure(controller: self)
        tunnel.onStatus = { [weak self] status in self?.handleTunnelStatus(status) }
        // Reconcile an already-running tunnel (app relaunched while connected).
        Task { [weak self] in
            guard let self,
                  let (status, url) = await self.tunnel.syncExisting(),
                  let use = self.model.uses.first(where: { $0.url == url }) else { return }
            self.connectingUseId = use.id
            self.handleTunnelStatus(status)
        }
    }

    // MARK: - Persistence

    /// Reload persisted connections into the store (also the harness `reset`,
    /// Android parity: reset drops in-memory/seeded state back to real data).
    func loadPersisted() {
        persistenceSuppressed = false
        let loaded = store.load()
        model.reset()
        model.setConnections(shares: loaded.shares, uses: loaded.uses)
        for s in loaded.shares {
            if let url = s.url { model.registerShareURL(s.id, url) }
        }
        model.selectedId = loaded.shares.first?.id ?? loaded.uses.first?.id
    }

    private func persist(writeBlobs: Bool = false) {
        guard !persistenceSuppressed else { return }
        store.save(shares: model.shares, uses: model.uses, writeBlobs: writeBlobs)
    }

    // MARK: - Share toggles (real, in-process)

    func toggleShare(_ id: String) {
        switch model.shareState(id) {
        case .active, .pending:
            stopShareSession(id)
            refreshSharingNotification()
        default:
            guard let conn = model.shares.first(where: { $0.id == id }) else { return }
            startShareSession(conn, onStarted: { [weak self] in self?.refreshSharingNotification() })
        }
    }

    func stopAllShares() {
        for id in Array(model.activeShares.keys) + Array(model.startingShares) {
            stopShareSession(id)
        }
        refreshSharingNotification()
    }

    private func stopShareSession(_ id: String) {
        startTokens[id] = nil
        if let handle = model.activeShares[id]?.handle {
            Task.detached { try? stopShare(handle: handle) }
        }
        model.shareStopped(id)
    }

    private func refreshSharingNotification() {
        let names = model.shares.filter { model.activeShares[$0.id] != nil }.map(\.label)
        notifications.updateSharing(names: names)
    }

    /// Start a share's session: the blocking `startShare` runs off the main
    /// thread once the service is up, and reports back here. It never touches
    /// the network itself (Spora's relays get the relay token the service has
    /// cached, and every renewal).
    private func startShareSession(_ conn: ShareConnection,
                                   onStarted: (() -> Void)? = nil,
                                   onFailed: ((SporaError) -> Void)? = nil) {
        let id = conn.id
        let token = UUID()
        startTokens[id] = token
        model.shareStarting(id)
        let blob = conn.share
        Task { [weak self] in
            do {
                guard await ServiceHost.shared.awaitReady() else { throw ShareError.NotInitialized }
                let result = try await offMain {
                    // The connection log is a liability record for the sharer,
                    // so it is always on; one directory per share (the core
                    // binds a database to the share that created it). A
                    // deleted share keeps its log, and every running share
                    // sweeps the others' by retention.
                    try startShare(shareBlob: blob, protector: nil,
                                   connLogDir: SporaPaths.connLogDir(shareId: try shareId(shareBlob: blob)).path,
                                   connLogRetentionDays: nil, connLogSessionsOnly: false,
                                   recordDir: SporaPaths.recordDir.path,
                                   connLogSweepSiblings: true)
                }
                guard let self, self.startTokens[id] == token else {
                    // Stopped (or deleted) while startShare was blocked: the
                    // session it just created must be stopped, not surfaced
                    try? await offMain { try stopShare(handle: result.handle) }
                    return
                }
                self.startTokens[id] = nil
                self.model.shareStarted(id, handle: result.handle, url: result.url)
                onStarted?()
            } catch {
                SporaLog.e(Self.tag, "share failed for \(id)", error)
                guard let self, self.startTokens[id] == token else { return }
                self.startTokens[id] = nil
                let mapped = SporaError.from(error, defaultCase: .shareFailed)
                self.model.shareFailed(id, error: mapped)
                onFailed?(mapped)
            }
        }
    }

    // MARK: - Use toggles (tunnel appex)

    func toggleUse(_ id: String) {
        switch model.useState(id) {
        case .active, .pending:
            tunnel.disconnect() // NEVPNStatus observer drives .disconnected
        default:
            guard let use = model.uses.first(where: { $0.id == id }) else { return }
            connectingUseId = id
            model.connectConnecting(id) // optimistic; the status observer confirms
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.tunnel.connect(url: use.url)
                } catch {
                    // Most commonly the user declined the VPN-approval dialog.
                    SporaLog.w(Self.tag, "tunnel not started", error)
                    self.model.connectFailed(.vpnPermissionDenied, id: id)
                    self.connectingUseId = nil
                }
            }
        }
    }

    /// Reconcile the authoritative NEVPNStatus into the model (ADR D3).
    private func handleTunnelStatus(_ status: NEVPNStatus) {
        switch status {
        case .connecting, .reasserting:
            if let id = connectingUseId { model.connectConnecting(id) }
        case .connected:
            model.connectConnected()
            if let id = connectingUseId, let name = model.label(id) { notifications.connected(name: name) }
        case .disconnecting:
            break
        case .disconnected, .invalid:
            Task { [weak self] in
                guard let self else { return }
                let key = await self.tunnel.lastErrorKey()
                if let key {
                    let attributedId = self.connectingUseId
                    self.model.connectFailed(SporaError(messageKey: key), id: attributedId)
                    if let id = attributedId, let name = self.model.label(id) {
                        self.notifications.connectionLost(useId: id, name: name)
                    }
                } else if self.model.useConnected || self.model.useConnecting || self.model.useActiveId != nil {
                    self.model.connectDisconnected()
                }
                self.connectingUseId = nil
            }
        @unknown default:
            break
        }
    }

    // MARK: - Making shares

    /// Create a new share: make it on the relays the settings name, persist
    /// it, and start it — the busy moment (3a) resolves into the link handoff
    /// (2c) with its URL, into the share's error state, or (no link could be
    /// made) into the reason, with the way to fix it.
    func beginCreateShare() {
        settingsPages = []
        make(replacing: nil)
    }

    /// The share was made under a device identity this Mac no longer has:
    /// give it a new share (a new link, to send again) on the relays the
    /// settings name now. Name and place in the list stay.
    func makeNewLink(_ id: String) {
        guard model.shares.contains(where: { $0.id == id }) else { return }
        settingsPages = []
        model.selectedId = id
        make(replacing: id)
    }

    /// The create flow is giving a saved share a new link (not a new share).
    var isRemaking: Bool { creating?.replacing == true }

    /// Try again after no link could be made.
    func retryCreateShare() {
        make(replacing: creating?.replacing == true ? creating?.shareId : nil)
    }

    private func make(replacing replaceId: String?) {
        let token = UUID()
        creating = (token, replaceId, replaceId != nil)
        flow = .createShare(.making)
        let settings = service.relaySettings
        Task { [weak self] in
            let made = await ShareMaker.make(settings: settings)
            guard let self, self.creating?.token == token else { return }
            switch made {
            case .failure(let error):
                self.flow = .createShare(.failed(error))
            case .success(let blob):
                self.made(blob, replacing: replaceId, token: token)
            }
        }
    }

    private func made(_ blob: Data, replacing replaceId: String?, token: UUID) {
        guard let url = try? shareUrl(shareBlob: blob) else {
            flow = .createShare(.failed(.shareFailed))
            return
        }
        let id: String
        if let replaceId {
            id = replaceId
            model.replaceShare(id, share: blob, url: url)
        } else {
            id = "share-\(UUID().uuidString.lowercased())"
            let n = model.shares.count + 1
            let conn = ShareConnection(id: id, label: Lf("share_default_label", n), share: blob, createdAt: Date())
            model.setConnections(shares: model.shares + [conn], uses: model.uses)
            model.registerShareURL(id, url)
        }
        model.selectedId = id
        creating = (token, id, replaceId != nil)
        persist(writeBlobs: true) // the share holds its secret: saved before it runs
        guard let conn = model.shares.first(where: { $0.id == id }) else { return }
        startShareSession(conn, onStarted: { [weak self] in
            guard let self, self.creating?.token == token else { return }
            self.flow = .createShare(.ready(ShareDraft(id: id, url: url, isNew: replaceId == nil)))
            self.refreshSharingNotification()
        }, onFailed: { [weak self] _ in
            guard let self, self.creating?.token == token else { return }
            self.creating = nil
            self.flow = nil // dismiss busy → detail shows the share in error
        })
    }

    /// Cancel share creation before the link is ready. A share being made is
    /// dropped; a new one being started is removed (it was never sent); a
    /// saved share given a new link keeps it, stopped.
    func cancelCreateShare() {
        if let creating, let id = creating.shareId, model.shares.contains(where: { $0.id == id }) {
            stopShareSession(id)
            if !creating.replacing { model.removeShare(id) }
            persist()
        }
        creating = nil
        flow = nil
    }

    func rename(shareId: String, to label: String) {
        model.rename(shareId: shareId, to: label)
        persist()
    }

    func dismissFlow() { creating = nil; flow = nil }

    // MARK: - Use connections

    func beginConnect() {
        settingsPages = []
        sheet = .saveConnection(prefillURL: nil)
    }

    /// Save (and connect) a use connection from the sheet.
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
        sheet = nil
        persist()
        toggleUse(id)
    }

    private var lastDeepLink: (url: String, at: Date)?

    /// Handle an incoming share link (universal link `https://spora.to/s/…` or
    /// the `spora://s/…` custom scheme). Android dispatch parity: known+active →
    /// no-op; known → switch/connect; unknown → prefilled save sheet. Repeated
    /// open-URL events for the same link are deduped.
    func handleDeepLink(_ url: URL) {
        guard let shareURL = Self.canonicalShareURL(from: url), Self.isValidShareURL(shareURL) else { return }
        if let last = lastDeepLink, last.url == shareURL, Date().timeIntervalSince(last.at) < 3 { return }
        lastDeepLink = (shareURL, Date())
        // The link opens on its connection, not behind the settings
        settingsPages = []

        if let existing = model.uses.first(where: { $0.url == shareURL }) {
            model.selectedId = existing.id
            if model.useActiveId == existing.id, model.useConnected || model.useConnecting {
                return // already connected/connecting to this exact link
            }
            if let active = model.useActiveId, active != existing.id { tunnel.disconnect() }
            toggleUse(existing.id)
        } else {
            sheet = .saveConnection(prefillURL: shareURL)
        }
    }

    /// Normalize a share link to its canonical `https://spora.to/s/<token>` form
    /// (preserving the `?r=` relay hints). Returns nil for anything else.
    static func canonicalShareURL(from url: URL) -> String? {
        switch url.scheme {
        case "https":
            return (url.host == "spora.to" && url.path.hasPrefix("/s/")) ? url.absoluteString : nil
        case "spora":
            guard url.host == "s" else { return nil }
            var c = URLComponents()
            c.scheme = "https"; c.host = "spora.to"; c.path = "/s" + url.path
            c.percentEncodedQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
            return c.url?.absoluteString
        default:
            return nil
        }
    }

    /// Connect to a URL directly (deep links + debug harness): ensure a use
    /// connection exists for it, select it, and start the tunnel.
    func connectToURL(_ rawURL: String, label: String = "Test") {
        let url = Self.normalizeURL(rawURL)
        let id = "use-\(Int(Fmt.seed(url)))"
        if !model.uses.contains(where: { $0.id == id }) {
            let conn = UseConnection(id: id, label: label, url: url, createdAt: Date())
            model.setConnections(shares: model.shares, uses: model.uses + [conn])
        }
        model.selectedId = id
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

    // MARK: - Navigation

    /// Show a connection's detail (closing the settings).
    func select(_ id: String) {
        settingsPages = []
        model.selectedId = id
    }

    /// The settings list (the sidebar's SETTINGS, ⌘,).
    func openSettings() {
        settingsPages = [.list]
    }

    /// The Relays page alone, from an error it fixes: back returns there.
    func openRelaySettings() {
        settingsPages = [.relays]
    }

    func pushSettings(_ page: SettingsPage) { settingsPages.append(page) }
    func popSettings() { _ = settingsPages.popLast() }

    func openFeedback() { sheet = .feedback }

    /// The force notice: the account requires uploads. One owner, so the two
    /// triggers (the flag arriving, a refused switch-off) never stack.
    func showTelemetryRequired() {
        if sheet != .telemetryRequired { sheet = .telemetryRequired }
    }

    /// The account's flag arrived: the notice is owed once, when no other
    /// sheet is up.
    func offerTelemetryNotice() {
        guard !telemetryNoticeOffered, sheet == nil else { return }
        telemetryNoticeOffered = true
        sheet = .telemetryRequired
    }
    private var telemetryNoticeOffered = false

    func dismissTelemetryRequired(contactSupport: Bool) {
        service.acknowledgeNotice()
        sheet = contactSupport ? .feedback : nil
    }

    // MARK: - Actions

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// The action an error offers: a new link for a share under a lost
    /// identity, otherwise another try.
    func retry(_ selection: Selection) {
        switch (selection.role, model.state(for: selection)) {
        case (.share, .error(.shareLinkLost)): makeNewLink(selection.id)
        case (.share, _): toggleShare(selection.id)
        case (.use, _): toggleUse(selection.id)
        }
    }

    func deleteSelected() {
        guard let sel = model.selection else { return }
        switch sel.role {
        case .share:
            stopShareSession(sel.id)
            model.removeShare(sel.id)
        case .use:
            model.removeUse(sel.id)
        }
        persist() // deletes the removed share's blob from the Keychain
    }

    // MARK: - Helpers

    /// Deterministic spora.to token from an id — used only by the debug harness
    /// to synthesize plausible URLs for seeded shares.
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
