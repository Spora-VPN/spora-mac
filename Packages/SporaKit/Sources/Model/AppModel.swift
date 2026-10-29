import Foundation
import Combine

/// The single source of truth for connection state — the macOS counterpart to
/// Android's `ShareState` + `ConnectState` singletons, merged into one
/// `ObservableObject` (per ADR D3: share mode runs in-process, connect mode
/// reconciles from the tunnel into this same store).
///
/// Transition methods mirror the Android state machines exactly, including the
/// load-bearing details: share errors survive `stopped`/`serviceStopped`;
/// connect errors survive `serviceStopped` but not a fresh `connecting`; only
/// one tunnel is active at a time.
@MainActor
public final class AppModel: ObservableObject {
    // Persisted connections (persistence layer wires these; seeded for now).
    @Published public private(set) var shares: [ShareConnection] = []
    @Published public private(set) var uses: [UseConnection] = []

    // Share live overlays (per-connection; multiple shares run at once).
    @Published public private(set) var activeShares: [String: ActiveShareInfo] = [:]
    @Published public private(set) var startingShares: Set<String> = []
    @Published public private(set) var shareErrors: [String: SporaError] = [:]

    // Use live overlays (one tunnel at a time; scalar flags).
    @Published public private(set) var useActiveId: String?
    @Published public private(set) var useConnecting = false
    @Published public private(set) var useConnected = false
    @Published public private(set) var useError: SporaError?
    @Published public private(set) var useErrorId: String?
    @Published public private(set) var useConnectedAt: Date?

    // Known share URLs (from the share's blob, a live share, or synthesized
    // when seeded) so the detail pane can show the link even for an inactive
    // share.
    @Published public private(set) var shareURLs: [String: String] = [:]

    // Sidebar selection (which connection's detail is shown in the window).
    @Published public var selectedId: String?

    public init() {}

    // MARK: - Derivation

    public func shareState(_ id: String) -> DisplayState {
        if activeShares[id] != nil { return .active }
        if startingShares.contains(id) { return .pending }
        if let e = shareErrors[id] { return .error(e) }
        return .inactive
    }

    public func useState(_ id: String) -> DisplayState {
        if useActiveId == id, useConnected { return .active }
        if useActiveId == id, useConnecting { return .pending }
        if useErrorId == id, let e = useError { return .error(e) }
        return .inactive
    }

    public func state(for selection: Selection) -> DisplayState {
        selection.role == .share ? shareState(selection.id) : useState(selection.id)
    }

    /// Aggregate status — dual-role, no collapse (down line then up line).
    public var aggregateStatus: AggregateStatus {
        var status = AggregateStatus()
        // ↓ use row
        if let id = useActiveId, let label = uses.first(where: { $0.id == id })?.label {
            if useConnected { status.down = .connected(label: label) }
            else if useConnecting { status.down = .connecting(label: label) }
        }
        // ↑ share row
        let activeNames = shares.filter { activeShares[$0.id] != nil }.map(\.label)
        if !activeNames.isEmpty {
            status.up = .sharing(names: activeNames)
        } else if !startingShares.isEmpty {
            status.up = .starting
        }
        return status
    }

    /// Template menu-bar icon state. Precedence: error ◆ > pending ○ > active ●
    /// > offline. (Errors that survive teardown still surface here.)
    public var menuBarState: MenuBarState {
        let states = shares.map { shareState($0.id) } + uses.map { useState($0.id) }
        if states.contains(where: { if case .error = $0 { return true } else { return false } }) { return .error }
        if states.contains(.pending) { return .pending }
        if states.contains(.active) { return .active }
        return .offline
    }

    // MARK: - Lookups

    public var selection: Selection? {
        guard let id = selectedId else { return nil }
        if shares.contains(where: { $0.id == id }) { return Selection(id: id, role: .share) }
        if uses.contains(where: { $0.id == id }) { return Selection(id: id, role: .use) }
        return nil
    }

    public func shareURL(_ id: String) -> String? {
        activeShares[id]?.url ?? shareURLs[id]
    }

    public func label(_ id: String) -> String? {
        shares.first(where: { $0.id == id })?.label ?? uses.first(where: { $0.id == id })?.label
    }

    /// An unattributed use error (a failed ad-hoc URL not matching any saved
    /// connection) — rendered as a banner above the detail, never orange.
    public var unattributedUseError: SporaError? {
        guard let e = useError, let id = useErrorId else { return nil }
        return uses.contains(where: { $0.id == id }) ? nil : e
    }

    // MARK: - Share transitions (Android ShareState parity)

    public func shareStarting(_ id: String) {
        startingShares.insert(id)
        shareErrors[id] = nil
    }

    public func shareStarted(_ id: String, handle: Int32, url: String) {
        startingShares.remove(id)
        activeShares[id] = ActiveShareInfo(handle: handle, url: url, startedAt: Date())
        shareURLs[id] = url
    }

    public func shareFailed(_ id: String, error: SporaError) {
        startingShares.remove(id)
        shareErrors[id] = error
    }

    public func shareStopped(_ id: String) {
        activeShares[id] = nil
        startingShares.remove(id)
        // errors intentionally left in place (survive teardown)
    }

    public func shareServiceStopped() {
        activeShares.removeAll()
        startingShares.removeAll()
        // errors kept
    }

    // MARK: - Use transitions (Android ConnectState parity)

    public func connectConnecting(_ id: String?) {
        useConnecting = true
        useConnected = false
        useConnectedAt = nil
        useError = nil
        useErrorId = nil
        useActiveId = id
    }

    public func connectConnected() {
        useConnected = true
        useConnecting = false
        useConnectedAt = Date()
        // activeConnectionId kept
    }

    /// Attribute the error to the active connection (or an explicit id) at
    /// failure time, then null the active tunnel. Error survives teardown.
    public func connectFailed(_ error: SporaError, id: String? = nil) {
        useError = error
        useErrorId = id ?? useActiveId
        useConnecting = false
        useConnected = false
        useConnectedAt = nil
        useActiveId = nil
    }

    public func connectServiceStopped() {
        useConnecting = false
        useConnected = false
        useConnectedAt = nil
        useActiveId = nil
        // error kept
    }

    public func connectDisconnected() {
        useConnecting = false
        useConnected = false
        useConnectedAt = nil
        useActiveId = nil
        useError = nil
        useErrorId = nil
    }

    // MARK: - Mutations

    public func setConnections(shares: [ShareConnection], uses: [UseConnection]) {
        self.shares = shares
        self.uses = uses
    }

    /// Clear all connections and live state (harness `reset`; also the seam
    /// where real persisted data would reload).
    public func reset() {
        shares = []
        uses = []
        activeShares = [:]
        startingShares = []
        shareErrors = [:]
        shareURLs = [:]
        useActiveId = nil
        useConnecting = false
        useConnected = false
        useConnectedAt = nil
        useError = nil
        useErrorId = nil
        selectedId = nil
    }

    /// Record a share's URL without marking it active (a persisted share's
    /// URL at launch, read from its blob; seeded shares).
    public func registerShareURL(_ id: String, _ url: String) {
        shareURLs[id] = url
    }

    /// Give a share a new blob (a new link, same name and place): the old one
    /// was made under a device identity this Mac no longer has.
    public func replaceShare(_ id: String, share: Data, url: String) {
        guard let i = shares.firstIndex(where: { $0.id == id }) else { return }
        shares[i].share = share
        shareURLs[id] = url
        shareErrors[id] = nil
    }

    public func rename(shareId: String, to label: String) {
        guard let i = shares.firstIndex(where: { $0.id == shareId }) else { return }
        shares[i].label = label
    }

    public func removeShare(_ id: String) {
        shares.removeAll { $0.id == id }
        activeShares[id] = nil
        startingShares.remove(id)
        shareErrors[id] = nil
        shareURLs[id] = nil
        if selectedId == id { selectedId = shares.first?.id ?? uses.first?.id }
    }

    public func removeUse(_ id: String) {
        uses.removeAll { $0.id == id }
        if useActiveId == id { connectDisconnected() }
        if useErrorId == id { useError = nil; useErrorId = nil }
        if selectedId == id { selectedId = shares.first?.id ?? uses.first?.id }
    }
}
