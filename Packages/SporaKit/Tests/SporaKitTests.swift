import XCTest
@testable import SporaKit

/// Relay addresses are checked as spora-core's `RelayEndpoint::from_url_param`
/// reads them (Android parity: `RelayEndpointTest`).
final class RelayEndpointTests: XCTestCase {
    func testUsableAddresses() {
        for ok in ["relay.example.org:443", "1.2.3.4:1", "nz/relay.example.org:443", "tcptls/10.0.0.1:65535",
                   "quic/r:9", "udpquic/r:9", "direct/r:9", "[2001:db8::1]:443", "nz/[::1]:443",
                   "[::ffff:192.0.2.1]:80", "[1:2:3:4:5:6:7:8]:1"] {
            XCTAssertNil(relayEndpointError(ok), ok)
        }
    }

    func testRefusedAddresses() {
        let cases: [(String, RelayEndpointError)] = [
            ("", .format),
            ("relay example:443", .format),
            ("relay.example.org", .format),
            (":443", .format),
            ("ftp/relay:443", .unknownProtocol),
            ("2001:db8::1:443", .ipv6Brackets),
            ("[2001:db8::1]443", .format),
            ("[not-v6]:443", .format),
            ("[1:2:3:4:5:6:7:8:9]:1", .format),
            ("[1::2::3]:1", .format),
            ("relay:0", .port),
            ("relay:65536", .port),
            ("relay:", .port),
            ("relay:44a", .port),
            ("relay:٤٤٣", .port),
            ("relay:443443", .port),
        ]
        for (endpoint, error) in cases {
            XCTAssertEqual(relayEndpointError(endpoint), error, endpoint)
        }
    }

    func testNormalizeUndoesAPastedURLParameter() {
        XCTAssertEqual(normalizeRelayEndpoint("  nz%2Frelay.example.org%3A443 \n"), "nz/relay.example.org:443")
        XCTAssertEqual(normalizeRelayEndpoint("relay:443"), "relay:443")
    }

    func testOwnRelayTokenIsAStaticCredentialAndNeverLogged() {
        let r = OwnRelay(endpoint: "relay:443", token: "s3cret")
        XCTAssertEqual(r.entry.credential, .static(token: Data("s3cret".utf8)))
        XCTAssertEqual(OwnRelay(endpoint: "relay:443").entry.credential, RelayCredential.none)
        XCTAssertFalse(String(describing: r).contains("s3cret"))
    }

    func testSettingsNeedARelay() {
        XCTAssertTrue(RelaySettings().hasRelays, "Spora's relays are on by default")
        XCTAssertFalse(RelaySettings(useSpora: false).hasRelays)
        XCTAssertTrue(RelaySettings(useSpora: false, own: [OwnRelay(endpoint: "r:1")]).hasRelays)
    }
}

final class ServiceTests: XCTestCase {
    /// `SPORA_API` is read as the CLI reads it, and a value set but naming
    /// no address never means production.
    func testApiBases() {
        XCTAssertEqual(ServiceHost.apiBases(nil), [])
        XCTAssertEqual(ServiceHost.apiBases("http://a, http://b ,"), ["http://a", "http://b"])
        XCTAssertEqual(ServiceHost.apiBases(""), [""])
        XCTAssertEqual(ServiceHost.apiBases(" , "), [" , "])
    }

    func testShareErrorsMapToTheUserVocabulary() {
        XCTAssertEqual(SporaError.from(ShareError.IdentityMismatch), .shareLinkLost)
        XCTAssertEqual(SporaError.from(ShareError.NotInitialized), .shareUnavailable)
        XCTAssertEqual(SporaError.from(ShareError.NoRelayAdvice), .noSporaRelays)
        XCTAssertEqual(SporaError.from(ShareError.Generic("x")), .shareFailed)
        XCTAssertEqual(SporaError.from(ConnectError.InvalidUrl), .invalidUrl)
        XCTAssertEqual(SporaError.from(ConnectError.Generic("x")), .connectFailed)
        for e in SporaError.allCases {
            XCTAssertEqual(SporaError(messageKey: e.messageKey), e)
        }
        XCTAssertEqual(SporaError(token: "share_link_lost"), .shareLinkLost)
    }

    /// A blob this build cannot read has no URL and uses no relays (the
    /// harness seeds such shares to exercise the error path).
    func testUnreadableShare() {
        let s = ShareConnection(id: "x", label: "x", share: Data("debug".utf8))
        XCTAssertNil(s.url)
        XCTAssertFalse(s.usesSporaRelays)
    }
}

final class ConnectionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "to.spora.macos.tests.\(UUID().uuidString)"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    /// Shares saved with an identity (before shares were the core's) cannot
    /// be started any more: dropped; use connections carry over.
    func testLegacySharesAreDroppedUsesKept() throws {
        let legacy = """
        {"shares":[{"id":"share-1","label":"Old","createdAt":0}],
         "uses":[{"id":"use-1","label":"Home","url":"https://spora.to/s/abc","createdAt":0}],
         "urls":{"share-1":"https://spora.to/s/old"}}
        """
        defaults.set(Data(legacy.utf8), forKey: "spora.connections.v1")
        let store = ConnectionStore(defaults: defaults,
                                    blobs: SecretStore(service: "to.spora.macos.tests", fileDirName: "tests"))
        let loaded = store.load()
        XCTAssertTrue(loaded.shares.isEmpty)
        XCTAssertEqual(loaded.uses.map(\.id), ["use-1"])
        XCTAssertNil(defaults.data(forKey: "spora.connections.v1"))
        XCTAssertEqual(store.load().uses.map(\.label), ["Home"], "migrated once, then read back")
    }
}
