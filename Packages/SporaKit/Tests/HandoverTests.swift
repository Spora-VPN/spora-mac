import XCTest
@testable import SporaKit

/// The hand-over of the tunnel's records and log from the system extension
/// to the app: the extension's end (`HandoverSource`), the app's
/// (`HandoverSink`), and the two over a real XPC connection.
final class HandoverTests: XCTestCase {
    private var root: URL!
    /// The extension's directories, and the app's.
    private var ext: (records: URL, diag: URL)!
    private var app: (records: URL, diag: URL)!

    private let open = #"{"t":"open","v":1,"id":"20d4d39e5f38993a","role":"client"}"# + "\n"
    private let step = #"{"t":"step","seq":1,"kind":"relay_dial","outcome":"ok"}"# + "\n"
    private let close = #"{"t":"close","id":"20d4d39e5f38993a","outcome":"closed_locally"}"# + "\n"

    private let closedRecord = "20261124T142903Z-client-20d4d39e.jsonl"
    private let openRecord = "20261124T143022Z-client-f922e89c.jsonl"
    private let oldLog = "diag-20261124T120000000Z-111.jsonl"
    private let rotatedLog = "diag-20261124T142902759Z-222.jsonl"
    private let currentLog = "diag-20261124T150000000Z-222.jsonl"
    private let crash = "crash-20261124T143100000Z-rust.txt"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("handover-\(UUID().uuidString)")
        ext = (root.appendingPathComponent("ext/records"), root.appendingPathComponent("ext/diag"))
        app = (root.appendingPathComponent("app/records"), root.appendingPathComponent("app/diag"))
        for dir in [ext.records, ext.diag, app.records, app.diag] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ dir: URL, _ name: String, _ text: String) throws {
        try Data(text.utf8).write(to: dir.appendingPathComponent(name))
    }

    private func append(_ dir: URL, _ name: String, _ text: String) throws {
        let handle = try FileHandle(forWritingTo: dir.appendingPathComponent(name))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func text(_ dir: URL, _ name: String) -> String? {
        (try? Data(contentsOf: dir.appendingPathComponent(name))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func names(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    /// The extension as process 222, its log and crash files settled at once.
    private func makeSource() -> HandoverSource {
        HandoverSource(recordDir: ext.records, logDir: ext.diag, pid: 222, settle: 0)
    }

    private var sink: HandoverSink { HandoverSink(recordDir: app.records, logDir: app.diag) }

    /// A running extension: an earlier process's log, then this one's files.
    private func runningExtension() throws -> HandoverSource {
        try write(ext.diag, oldLog, "old\n")
        let source = makeSource()
        try write(ext.records, closedRecord, open + step + close)
        try write(ext.records, openRecord, open + step)
        try write(ext.diag, rotatedLog, "first\n")
        try write(ext.diag, currentLog, "second\n")
        try write(ext.diag, crash, "{}\npanicked\n")
        return source
    }

    // MARK: - Names

    func testOnlyTheCoresFileNamesAreTaken() {
        XCTAssertTrue(HandoverKind.record.accepts(closedRecord))
        XCTAssertTrue(HandoverKind.diag.accepts(currentLog))
        XCTAssertTrue(HandoverKind.diag.accepts(crash))
        for bad in ["", "../x.jsonl", "a/b.jsonl", ".hidden.jsonl", "-x.jsonl", "x.txt", "x.jsonl ",
                    "é.jsonl", String(repeating: "a", count: 123) + ".jsonl"] {
            XCTAssertFalse(HandoverKind.record.accepts(bad), bad)
        }
        // A writer's lock, another stream's file, a path
        for bad in ["diag-222.lock", closedRecord, "crash-x.jsonl", "diag-../x.jsonl", "../diag-1-2.jsonl"] {
            XCTAssertFalse(HandoverKind.diag.accepts(bad), bad)
        }
        XCTAssertEqual(HandoverName.logPid(currentLog), 222)
        XCTAssertNil(HandoverName.logPid("diag-.jsonl"))
        XCTAssertNil(HandoverName.logPid(crash))
    }

    // MARK: - The extension's end

    func testWhatIsFinished() throws {
        // Left by a process that died: a record with no ending, and its log
        try write(ext.records, "20261123T101010Z-client-0a0b0c0d.jsonl", open + step)
        try write(ext.diag, oldLog, "old\n")
        let source = HandoverSource(recordDir: ext.records, logDir: ext.diag, pid: 222, settle: 2)
        try write(ext.records, closedRecord, open + step + close)
        try write(ext.records, openRecord, open + step)
        try write(ext.diag, rotatedLog, "first\n")
        try write(ext.diag, currentLog, "second\n")
        try write(ext.diag, crash, "{}\npanicked\n")
        // Another process writing since this one started
        try write(ext.diag, "diag-20261124T150500000Z-333.jsonl", "other\n")
        // Never listed: a lock, a directory, a link out of the directory
        try write(ext.diag, "diag-222.lock", "")
        try FileManager.default.createDirectory(at: ext.records.appendingPathComponent("dir.jsonl"),
                                                withIntermediateDirectories: false)
        try write(root, "outside.jsonl", open + close)
        try FileManager.default.createSymbolicLink(at: ext.records.appendingPathComponent("link.jsonl"),
                                                   withDestinationURL: root.appendingPathComponent("outside.jsonl"))

        func finished(_ files: [HandoverFile]) -> [String: Bool] {
            Dictionary(uniqueKeysWithValues: files.map { ($0.name, $0.finished) })
        }
        let settled = finished(source.list(now: Date().addingTimeInterval(60)))
        XCTAssertEqual(settled, [
            "20261123T101010Z-client-0a0b0c0d.jsonl": true,
            oldLog: true,
            closedRecord: true,
            openRecord: false,
            rotatedLog: true,
            currentLog: false,
            crash: true,
            "diag-20261124T150500000Z-333.jsonl": false,
        ])
        // Just written: a rotated log may still be flushed, a crash file written
        let fresh = finished(source.list())
        XCTAssertEqual(fresh[rotatedLog], false)
        XCTAssertEqual(fresh[crash], false)
        XCTAssertEqual(fresh[closedRecord], true)
        XCTAssertEqual(fresh[oldLog], true)
    }

    func testTheLogBeingWrittenIsNeverFinished() throws {
        // A process number comes around again: an earlier process's log
        // under this one's is taken for the one being written
        try write(ext.diag, rotatedLog, "first\n")
        let source = makeSource()
        XCTAssertEqual(source.list().map(\.finished), [false])
        XCTAssertFalse(source.remove(.diag, name: rotatedLog, size: UInt64("first\n".utf8.count)))
        // Until this process has a newer one
        try write(ext.diag, currentLog, "second\n")
        XCTAssertEqual(source.list().map(\.finished), [true, false])
        XCTAssertFalse(source.remove(.diag, name: currentLog, size: UInt64("second\n".utf8.count)))
        XCTAssertTrue(source.remove(.diag, name: rotatedLog, size: UInt64("first\n".utf8.count)))
    }

    func testARecordIsFinishedByItsCloseEntryAlone() throws {
        let file = ext.records.appendingPathComponent(openRecord)
        try write(ext.records, openRecord, "")
        XCTAssertFalse(HandoverSource.endsWithClose(file))
        try write(ext.records, openRecord, open + step)
        XCTAssertFalse(HandoverSource.endsWithClose(file))
        // Half an ending is none: the process may still be writing it
        try write(ext.records, openRecord, open + step + String(close.dropLast()))
        XCTAssertFalse(HandoverSource.endsWithClose(file))
        try write(ext.records, openRecord, open + step + close)
        XCTAssertTrue(HandoverSource.endsWithClose(file))
        // A long record: the ending is found without reading it all
        try write(ext.records, openRecord, open + String(repeating: step, count: 4000) + close)
        XCTAssertTrue(HandoverSource.endsWithClose(file))
        try write(ext.records, openRecord, open + close + String(repeating: step, count: 4000))
        XCTAssertFalse(HandoverSource.endsWithClose(file))
    }

    func testReadsAndRemovesOnlyItsOwnFiles() throws {
        let source = try runningExtension()
        try write(root, "outside.jsonl", "secret\n")
        try FileManager.default.createSymbolicLink(at: ext.records.appendingPathComponent("link.jsonl"),
                                                   withDestinationURL: root.appendingPathComponent("outside.jsonl"))

        XCTAssertEqual(source.read(.record, name: closedRecord, offset: 0, length: 4), Data(open.utf8.prefix(4)))
        XCTAssertEqual(source.read(.record, name: closedRecord, offset: UInt64(open.utf8.count), length: 1 << 30),
                       Data((step + close).utf8))
        XCTAssertEqual(source.read(.record, name: closedRecord, offset: 10_000, length: 4), Data())
        XCTAssertNil(source.read(.record, name: "../outside.jsonl", offset: 0, length: 4))
        XCTAssertNil(source.read(.record, name: "link.jsonl", offset: 0, length: 4))
        XCTAssertNil(source.read(.record, name: "missing.jsonl", offset: 0, length: 4))
        XCTAssertNil(source.read(.diag, name: closedRecord, offset: 0, length: 4))
        XCTAssertNil(source.read(.diag, name: "diag-222.lock", offset: 0, length: 4))

        let size = UInt64((open + step + close).utf8.count)
        // Not while it may still grow, not at another length, not by a path
        XCTAssertFalse(source.remove(.record, name: openRecord, size: UInt64((open + step).utf8.count)))
        XCTAssertFalse(source.remove(.diag, name: currentLog, size: UInt64("second\n".utf8.count)))
        XCTAssertFalse(source.remove(.record, name: closedRecord, size: size - 1))
        XCTAssertFalse(source.remove(.record, name: "../outside.jsonl", size: 7))
        XCTAssertFalse(source.remove(.record, name: "link.jsonl", size: 7))
        XCTAssertEqual(names(ext.records), [closedRecord, openRecord, "link.jsonl"].sorted())
        XCTAssertTrue(source.remove(.record, name: closedRecord, size: size))
        XCTAssertTrue(source.remove(.diag, name: rotatedLog, size: UInt64("first\n".utf8.count)))
        XCTAssertEqual(names(ext.records), [openRecord, "link.jsonl"].sorted())
        XCTAssertEqual(text(root, "outside.jsonl"), "secret\n")
    }

    // MARK: - The app's end

    func testAPullFilesEverythingAndTakesTheFinishedOffTheExtension() async throws {
        let source = try runningExtension()
        let recorded = Date(timeIntervalSince1970: 1_795_530_000)
        try FileManager.default.setAttributes([.modificationDate: recorded],
                                              ofItemAtPath: ext.records.appendingPathComponent(closedRecord).path)
        let peer = LocalPeer(source: source)

        var summary = try await sink.pull(from: peer)
        XCTAssertEqual(summary.files, 6)
        XCTAssertEqual(summary.removed, 4)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(text(app.records, closedRecord), open + step + close)
        XCTAssertEqual(text(app.records, openRecord), open + step)
        XCTAssertEqual(text(app.diag, oldLog), "old\n")
        XCTAssertEqual(text(app.diag, rotatedLog), "first\n")
        XCTAssertEqual(text(app.diag, currentLog), "second\n")
        XCTAssertEqual(text(app.diag, crash), "{}\npanicked\n")
        // The record's own time, not the time it was fetched
        let modified = try XCTUnwrap(HandoverStat(app.records.appendingPathComponent(closedRecord))?.modified)
        XCTAssertEqual(modified.timeIntervalSince1970, recorded.timeIntervalSince1970, accuracy: 0.01)
        // What is still being written stays over there
        XCTAssertEqual(names(ext.records), [openRecord])
        XCTAssertEqual(names(ext.diag), [currentLog])

        // The run goes on, then ends: only what is new comes over
        try append(ext.records, openRecord, step + close)
        try append(ext.diag, currentLog, "third\n")
        summary = try await sink.pull(from: peer)
        XCTAssertEqual(summary.files, 2)
        XCTAssertEqual(summary.bytes, UInt64((step + close + "third\n").utf8.count))
        XCTAssertEqual(summary.removed, 1)
        XCTAssertEqual(peer.bytesRead, summary.bytes + UInt64((open + step + close + open + step
                                                              + "old\nfirst\nsecond\n{}\npanicked\n").utf8.count))
        XCTAssertEqual(text(app.records, openRecord), open + step + step + close)
        XCTAssertEqual(text(app.diag, currentLog), "second\nthird\n")
        XCTAssertEqual(names(ext.records), [])
        XCTAssertEqual(names(ext.diag), [currentLog])

        // Nothing new: nothing done
        summary = try await sink.pull(from: peer)
        XCTAssertTrue(summary.isEmpty)
    }

    func testAPullInterruptedBeforeTheExtensionDeletedIsFinishedByTheNext() async throws {
        try write(ext.records, closedRecord, open + step + close)
        let source = makeSource()
        // The app has it all already; the extension never heard
        try write(app.records, closedRecord, open + step + close)
        let summary = try await sink.pull(from: LocalPeer(source: source))
        XCTAssertEqual(summary.files, 0)
        XCTAssertEqual(summary.removed, 1)
        XCTAssertEqual(names(ext.records), [])
        XCTAssertEqual(text(app.records, closedRecord), open + step + close)
    }

    func testAPullOnlyAppends() async throws {
        let source = makeSource()
        try write(ext.records, closedRecord, open + step + close)
        try write(ext.records, openRecord, open + step)
        // The app's copies: one a prefix by length, one longer than there
        try write(app.records, closedRecord, String(repeating: "x", count: open.utf8.count))
        try write(app.records, openRecord, open + step + step + close)

        let summary = try await sink.pull(from: LocalPeer(source: source))
        XCTAssertEqual(summary.files, 1)
        XCTAssertEqual(summary.failed, 1)
        // What the app had is kept as it was, with the rest after it
        XCTAssertEqual(text(app.records, closedRecord), String(repeating: "x", count: open.utf8.count) + step + close)
        XCTAssertEqual(text(app.records, openRecord), open + step + step + close)
        // Never deleted over there for a copy the app does not hold
        XCTAssertEqual(names(ext.records), [openRecord])
    }

    func testAPullTakesNothingItDidNotAskFor() async throws {
        let peer = LyingPeer(files: [
            HandoverFile(kind: .record, name: "../../escaped.jsonl", size: 4, modified: Date(), finished: true),
            HandoverFile(kind: .diag, name: closedRecord, size: 4, modified: Date(), finished: true),
            HandoverFile(kind: .record, name: closedRecord, size: 4, modified: Date(), finished: true),
            HandoverFile(kind: .record, name: openRecord, size: 1 << 40, modified: Date(), finished: true),
        ])
        let summary = try await sink.pull(from: peer)
        XCTAssertEqual(summary.failed, 3)
        XCTAssertEqual(summary.files, 1)
        // Listed as 4 bytes: 4 bytes, however many came back
        XCTAssertEqual(text(app.records, closedRecord), "AAAA")
        XCTAssertEqual(names(app.records), [closedRecord])
        XCTAssertEqual(names(app.diag), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.jsonl").path))
        XCTAssertEqual(peer.removed, [closedRecord])
    }

    func testAFileTheExtensionRefusesIsLeftForTheNextPull() async throws {
        let source = try runningExtension()
        let peer = LocalPeer(source: source, refusing: closedRecord)
        let summary = try await sink.pull(from: peer)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.files, 5)
        XCTAssertEqual(names(ext.records), [closedRecord, openRecord])
        XCTAssertNil(text(app.records, closedRecord))
        // The others were not held up by it
        XCTAssertEqual(text(app.diag, crash), "{}\npanicked\n")
    }

    // MARK: - Over XPC

    func testTheTwoEndsOverXPC() async throws {
        let source = try runningExtension()
        // More than one read's worth
        let long = String(repeating: step, count: 3 * HandoverSink.chunk / step.utf8.count)
        try write(ext.records, closedRecord, open + long + close)
        let listener = HandoverListener(NSXPCListener.anonymous(), source: source)
        listener.resume()
        let client = HandoverClient(NSXPCConnection(listenerEndpoint: listener.endpoint))
        defer {
            client.invalidate()
            listener.invalidate()
        }

        let summary = try await sink.pull(from: client)
        XCTAssertEqual(summary.files, 6)
        XCTAssertEqual(summary.removed, 4)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(text(app.records, closedRecord), open + long + close)
        XCTAssertEqual(text(app.records, openRecord), open + step)
        XCTAssertEqual(text(app.diag, currentLog), "second\n")
        XCTAssertEqual(names(ext.records), [openRecord])
        XCTAssertEqual(names(ext.diag), [currentLog])

        // What the service refuses reaches the caller as a refusal
        let outside = HandoverFile(kind: .record, name: "../x.jsonl", size: 1, modified: Date(), finished: true)
        let refusedRead = try await client.read(outside, offset: 0, length: 1)
        XCTAssertNil(refusedRead)
        let refusedRemove = try await client.remove(outside)
        XCTAssertFalse(refusedRemove)
    }

    func testACallOnADeadConnectionFailsInsteadOfWaiting() async throws {
        let listener = HandoverListener(NSXPCListener.anonymous(), source: makeSource())
        listener.resume()
        let client = HandoverClient(NSXPCConnection(listenerEndpoint: listener.endpoint))
        _ = try await client.list()
        client.invalidate()
        listener.invalidate()
        do {
            _ = try await client.list()
            XCTFail("a call on an invalidated connection answered")
        } catch {}
        do {
            _ = try await sink.pull(from: client)
            XCTFail("a pull on an invalidated connection finished")
        } catch {}
    }

    // MARK: - Who may connect

    func testThePeerIsNamedByIdentifierAndTeam() {
        let requirement = CodeSigning.requirement(identifier: "to.spora.macos", team: "ABCDE12345")
        XCTAssertEqual(requirement, "anchor apple generic and identifier \"to.spora.macos\" "
            + "and certificate leaf[subject.OU] = \"ABCDE12345\"")
        // Nothing that is not a team ID gets into a requirement
        for bad in ["", "abcde12345", "ABCDE1234", "ABCDE123456", "ABCDE\"or 1", "ABCDE 2345"] {
            XCTAssertNil(CodeSigning.requirement(identifier: "to.spora.macos", team: bad), bad)
        }
    }
}

/// The extension's end without a connection in between.
private final class LocalPeer: HandoverPeer {
    private let source: HandoverSource
    private let refusing: String?
    private(set) var bytesRead: UInt64 = 0

    init(source: HandoverSource, refusing: String? = nil) {
        self.source = source
        self.refusing = refusing
    }

    func list() async throws -> [HandoverFile] { source.list() }

    func read(_ file: HandoverFile, offset: UInt64, length: Int) async throws -> Data? {
        if file.name == refusing { return nil }
        let data = source.read(file.kind, name: file.name, offset: offset, length: length)
        bytesRead += UInt64(data?.count ?? 0)
        return data
    }

    func remove(_ file: HandoverFile) async throws -> Bool {
        source.remove(file.kind, name: file.name, size: file.size)
    }
}

/// An extension that lists what it likes and answers every read with more
/// than was asked for.
private final class LyingPeer: HandoverPeer {
    private let files: [HandoverFile]
    private(set) var removed: [String] = []

    init(files: [HandoverFile]) { self.files = files }

    func list() async throws -> [HandoverFile] { files }

    func read(_ file: HandoverFile, offset: UInt64, length: Int) async throws -> Data? {
        Data(repeating: UInt8(ascii: "A"), count: length + 100)
    }

    func remove(_ file: HandoverFile) async throws -> Bool {
        removed.append(file.name)
        return true
    }
}
