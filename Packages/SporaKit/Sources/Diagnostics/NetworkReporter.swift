import Foundation
import Network

/// Tells the core which network is underneath any tunnel (`setNetworkState`),
/// for the connection records (Android parity: `UnderlyingNetworkReporter`).
/// Not the default route: while our tunnel is up, that IS the tunnel (a utun,
/// interface type `.other`), so the monitor never considers those.
///
/// The core's network feed is per process, so each process that runs
/// tunnels reports: the app for shares, the tunnel extension for its
/// connection. A loss is reported only if nothing replaced the network
/// within 2 s, so a Wi-Fi → Ethernet handover is not recorded as an outage.
public final class NetworkReporter: @unchecked Sendable {
    private static let lossGrace: TimeInterval = 2

    private let monitor = NWPathMonitor(prohibitedInterfaceTypes: [.other])
    private let queue = DispatchQueue(label: "to.spora.network-reporter")
    private var pendingLoss: DispatchWorkItem?
    private var started = false

    public init() {}

    public func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in self?.update(path) }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
        pendingLoss?.cancel()
    }

    // On `queue`.
    private func update(_ path: NWPath) {
        pendingLoss?.cancel()
        pendingLoss = nil
        let kind = Self.kind(of: path)
        guard kind != .none else {
            let loss = DispatchWorkItem { setNetworkState(kind: .none, validated: nil) }
            pendingLoss = loss
            queue.asyncAfter(deadline: .now() + Self.lossGrace, execute: loss)
            return
        }
        // macOS does not say whether a network reaches the internet (no
        // equivalent of Android's VALIDATED): the core records "unknown".
        setNetworkState(kind: kind, validated: nil)
    }

    static func kind(of path: NWPath) -> NetworkKind {
        guard path.status == .satisfied else { return .none }
        if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        return .other
    }
}
