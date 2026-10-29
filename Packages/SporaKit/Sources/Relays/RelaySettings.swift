import Foundation

/// A relay the user runs (or trusts), as they typed it. `endpoint` is in the
/// share URL's `?r=` form; `token` is what the relay wants, as pasted
/// (trimmed), or nil for an open relay. The token goes into the share, never
/// into its URL.
public struct OwnRelay: Codable, Equatable, Sendable, CustomStringConvertible {
    public var endpoint: String
    public var token: String?

    public init(endpoint: String, token: String? = nil) {
        self.endpoint = endpoint
        self.token = token
    }

    public var entry: RelayEntry {
        RelayEntry(endpoint: endpoint,
                   credential: token.map { .static(token: Data($0.utf8)) } ?? .none)
    }

    // The token is a secret: never in a log
    public var description: String { "OwnRelay(\(endpoint), token=\(token != nil ? "set" : "none"))" }
}

/// The relays new shares are made with: Spora's (on by default) and the
/// user's own, independently. A share keeps the relays it was made with (they
/// are part of its URL), so these apply to new shares only.
public struct RelaySettings: Codable, Equatable, Sendable {
    public var useSpora: Bool
    public var own: [OwnRelay]

    public init(useSpora: Bool = true, own: [OwnRelay] = []) {
        self.useSpora = useSpora
        self.own = own
    }

    /// A share needs at least one relay.
    public var hasRelays: Bool { useSpora || !own.isEmpty }
}

/// Keeps the relay settings in the Keychain (own relays' tokens are secrets).
public struct RelaySettingsStore {
    private let secrets: SecretStore
    private let account = "settings"

    public init(secrets: SecretStore = .relaySettings) {
        self.secrets = secrets
    }

    /// The saved settings; the defaults when none were saved or they cannot
    /// be read.
    public func load() -> RelaySettings {
        guard let data = secrets.load(account) else { return RelaySettings() }
        do {
            return try JSONDecoder().decode(RelaySettings.self, from: data)
        } catch {
            // The type only: a decoding error can quote the JSON, tokens and all
            SporaLog.e("RelaySettings", "unreadable relay settings (\(type(of: error))); using the defaults")
            return RelaySettings()
        }
    }

    public func save(_ settings: RelaySettings) {
        guard let data = try? JSONEncoder().encode(settings), secrets.save(data, for: account) else {
            SporaLog.e("RelaySettings", "relay settings not saved")
            return
        }
    }
}

/// Why a relay address cannot be used.
public enum RelayEndpointError: Equatable, Sendable {
    case format, unknownProtocol, ipv6Brackets, port, duplicate
}

/// Normalize a relay address as typed: trimmed, a pasted `?r=` value's
/// percent-encoding undone. The result is what is stored and checked.
public func normalizeRelayEndpoint(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.contains("%") else { return trimmed }
    return trimmed.removingPercentEncoding ?? trimmed
}

private let relayProtocolTags: Set<String> = ["quic", "udpquic", "direct", "tcptls", "nz"]

/// Check `endpoint` (already normalized) the way spora-core's
/// `RelayEndpoint::from_url_param` reads it: an optional protocol tag
/// (`quic/`, `udpquic/`, `nz/`, `tcptls/`, `direct/`), then `host:port`, an
/// IPv6 literal bracketed. Nil when it is usable.
public func relayEndpointError(_ endpoint: String) -> RelayEndpointError? {
    if endpoint.isEmpty || endpoint.contains(where: { $0.isWhitespace }) { return .format }
    var address = Substring(endpoint)
    if let slash = endpoint.firstIndex(of: "/") {
        guard relayProtocolTags.contains(String(endpoint[..<slash])) else { return .unknownProtocol }
        address = endpoint[endpoint.index(after: slash)...]
    }
    let host: Substring
    let port: Substring
    if address.hasPrefix("[") {
        guard let close = address.range(of: "]:") else { return .format }
        host = address[address.index(after: address.startIndex)..<close.lowerBound]
        port = address[close.upperBound...]
        if !isIPv6Literal(host) { return .format }
    } else {
        guard let colon = address.lastIndex(of: ":") else { return .format }
        host = address[..<colon]
        port = address[address.index(after: colon)...]
        if host.contains(":") { return .ipv6Brackets }
        if host.isEmpty || host.contains("/") { return .format }
    }
    // ASCII digits only: Int() would not take other scripts' digits, but say so
    guard !port.isEmpty, port.count <= 5, port.allSatisfy({ ("0"..."9").contains($0) }),
          let n = Int(port), (1...65535).contains(n) else { return .port }
    return nil
}

/// By hand rather than through `inet_pton`'s looser reading, matching the
/// Android client's check.
func isIPv6Literal(_ s: Substring) -> Bool {
    let halves = s.components(separatedBy: "::")
    if halves.count > 2 { return false }
    // Groups in one half; an IPv4 tail counts two and only ends the address
    func groups(_ part: String, last: Bool) -> Int? {
        if part.isEmpty { return 0 }
        let gs = part.split(separator: ":", omittingEmptySubsequences: false)
        var n = 0
        for (i, g) in gs.enumerated() {
            if g.contains(".") {
                if !last || i != gs.count - 1 || !isIPv4Literal(g) { return nil }
                n += 2
            } else {
                guard (1...4).contains(g.count), g.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
                n += 1
            }
        }
        return n
    }
    if halves.count == 1 { return groups(halves[0], last: true) == 8 }
    guard let head = groups(halves[0], last: false), let tail = groups(halves[1], last: true) else { return false }
    return head + tail <= 7
}

private func isIPv4Literal(_ s: Substring) -> Bool {
    let octets = s.split(separator: ".", omittingEmptySubsequences: false)
    return octets.count == 4 && octets.allSatisfy { o in
        (1...3).contains(o.count) && o.allSatisfy({ ("0"..."9").contains($0) })
            && (o == "0" || !o.hasPrefix("0")) && (Int(o) ?? 256) <= 255
    }
}
