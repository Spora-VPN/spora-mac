import Foundation

// The hand-over of the tunnel's diagnostics in the direct build.
//
// There the tunnel is a system extension: it runs as root, so the connection
// records and the diagnostic log it writes land in root's group container,
// where the app never sees them, and the app is what bundles bug reports and
// uploads. So the app asks the extension for them (`HandoverXPC`) and files
// them into its own record and log directories, under their own names:
//
// - A file is copied by name and offset, only ever appended to: what the app
//   holds is always a prefix of the extension's file. That is all the core's
//   bug report and uploader ask of a file (they cut a growing one back to its
//   last whole line, and keep a cursor per name), so a record still being
//   written and the log of a running extension come over too, and a report
//   made while connected has them.
// - Once a file is finished and the app holds all of it, the app says so and
//   the extension deletes its copy. Nothing is handed over twice, and what is
//   never fetched is trimmed by the core's own retention, as everywhere.
//
// This file is the two ends' file work, with no XPC in it; `HandoverXPC.swift`
// carries one to the other.

/// Which of the two directories a file is in.
public enum HandoverKind: String, Codable, CaseIterable, Sendable {
    /// Connection records (`records/`): one `.jsonl` per run.
    case record
    /// The diagnostic directory (`diag/`): the log (`diag-*.jsonl`) and
    /// crash files (`crash-*.txt`).
    case diag

    /// Whether `name` is a file of this kind, as the core names them. Both
    /// ends check every name with it, which is also what keeps a name inside
    /// its directory: no separators, no leading dot.
    public func accepts(_ name: String) -> Bool {
        guard HandoverName.isPlain(name) else { return false }
        switch self {
        case .record: return name.hasSuffix(".jsonl")
        case .diag: return HandoverName.isLog(name) || HandoverName.isCrash(name)
        }
    }
}

/// The core's file names, as far as the hand-over reads them.
enum HandoverName {
    /// The uploader's rule for a file name: `[A-Za-z0-9][A-Za-z0-9._-]{0,127}`.
    static func isPlain(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        guard let first = bytes.first, bytes.count <= 128, isAlphanumeric(first) else { return false }
        return bytes.allSatisfy { isAlphanumeric($0) || $0 == UInt8(ascii: ".") || $0 == UInt8(ascii: "_") || $0 == UInt8(ascii: "-") }
    }

    private static func isAlphanumeric(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
    }

    /// `diag-<stamp>-<pid>.jsonl` (never `diag-<pid>.lock`, a writer's lock).
    static func isLog(_ name: String) -> Bool { name.hasPrefix("diag-") && name.hasSuffix(".jsonl") }

    /// `crash-<stamp>-<source>.txt`.
    static func isCrash(_ name: String) -> Bool { name.hasPrefix("crash-") && name.hasSuffix(".txt") }

    /// The process that wrote a log file.
    static func logPid(_ name: String) -> Int32? {
        guard isLog(name), let dash = name.dropLast(".jsonl".count).lastIndex(of: "-") else { return nil }
        return Int32(name.dropLast(".jsonl".count)[name.index(after: dash)...])
    }
}

/// A file the extension has, as it was when listed.
public struct HandoverFile: Codable, Equatable, Sendable {
    public var kind: HandoverKind
    public var name: String
    public var size: UInt64
    public var modified: Date
    /// Nothing will be appended to it any more: once the app holds it all,
    /// the extension's copy can go.
    public var finished: Bool

    public init(kind: HandoverKind, name: String, size: UInt64, modified: Date, finished: Bool) {
        self.kind = kind
        self.name = name
        self.size = size
        self.modified = modified
        self.finished = finished
    }
}

/// What `lstat` says about a path; nil when there is nothing there.
struct HandoverStat {
    var size: UInt64
    var modified: Date
    var isRegular: Bool

    init?(_ url: URL) {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        self.init(st)
    }

    init(_ st: stat) {
        size = UInt64(max(0, st.st_size))
        modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)
                        + TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000)
        isRegular = (st.st_mode & S_IFMT) == S_IFREG
    }
}

// MARK: - The extension's end

/// The extension's end: its record and log directories, read for the app.
/// Made once, when the process starts and before it writes anything: every
/// file already there was left by an earlier process, and is finished.
public struct HandoverSource: Sendable {
    /// The most `read` returns at once.
    public static let maxChunk = 1 << 20

    private let recordDir: URL
    private let logDir: URL
    /// This process: the newest log file of its own is the one it writes.
    private let pid: Int32
    /// How long a log or crash file must have been left alone to count as
    /// finished (a log file just rotated away is still being flushed).
    private let settle: TimeInterval
    /// What earlier processes left, by directory.
    private let inherited: [HandoverKind: Set<String>]

    public init(recordDir: URL, logDir: URL, pid: Int32 = getpid(), settle: TimeInterval = 2) {
        self.recordDir = recordDir
        self.logDir = logDir
        self.pid = pid
        self.settle = settle
        var inherited: [HandoverKind: Set<String>] = [:]
        for kind in HandoverKind.allCases {
            let dir = kind == .record ? recordDir : logDir
            inherited[kind] = Set(Self.names(in: dir, kind))
        }
        self.inherited = inherited
    }

    private func dir(_ kind: HandoverKind) -> URL { kind == .record ? recordDir : logDir }

    /// The kind's file names in `dir`, sorted (a process's log files sort in
    /// the order they were written).
    private static func names(in dir: URL, _ kind: HandoverKind) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter(kind.accepts).sorted()
    }

    /// Every record, log and crash file there is now.
    public func list(now: Date = Date()) -> [HandoverFile] {
        var files: [HandoverFile] = []
        for kind in HandoverKind.allCases {
            let names = Self.names(in: dir(kind), kind)
            for name in names {
                guard let st = HandoverStat(dir(kind).appendingPathComponent(name)), st.isRegular else { continue }
                files.append(HandoverFile(kind: kind, name: name, size: st.size, modified: st.modified,
                                          finished: isFinished(kind, name, st, among: names, now: now)))
            }
        }
        return files
    }

    /// Up to `length` bytes of a file from `offset` (empty at its end); nil
    /// for a name that is not a file of that kind here.
    public func read(_ kind: HandoverKind, name: String, offset: UInt64, length: Int) -> Data? {
        guard kind.accepts(name), length > 0, offset <= UInt64(Int64.max) else { return nil }
        // Only the regular file itself: never through a link, never a FIFO
        let fd = open(dir(kind).appendingPathComponent(name).path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, HandoverStat(st).isRegular else { return nil }
        var data = Data(count: min(length, Self.maxChunk))
        let n = data.withUnsafeMutableBytes { pread(fd, $0.baseAddress, $0.count, off_t(offset)) }
        guard n >= 0 else { return nil }
        data.count = n
        return data
    }

    /// Delete a file the app holds all `size` bytes of. Refused unless it is
    /// finished and still that size: whether it can go is judged here, never
    /// taken from the caller.
    public func remove(_ kind: HandoverKind, name: String, size: UInt64, now: Date = Date()) -> Bool {
        guard kind.accepts(name) else { return false }
        let url = dir(kind).appendingPathComponent(name)
        guard let st = HandoverStat(url), st.isRegular, st.size == size,
              isFinished(kind, name, st, among: Self.names(in: dir(kind), kind), now: now) else { return false }
        return unlink(url.path) == 0
    }

    private func isFinished(_ kind: HandoverKind, _ name: String, _ st: HandoverStat,
                            among names: [String], now: Date) -> Bool {
        // Left by an earlier process: nobody writes it any more
        let left = inherited[kind]?.contains(name) == true
        let settled = now.timeIntervalSince(st.modified) >= settle
        switch kind {
        case .record:
            // The core writes nothing after a record's close (one left
            // without an ending is that of a process that died)
            return left || Self.endsWithClose(dir(kind).appendingPathComponent(name))
        case .diag:
            guard let writer = HandoverName.logPid(name) else { return left || settled } // a crash file
            // Another process's log that appeared since this one started:
            // that process may be alive
            if writer != pid { return left }
            // This process's log: all but the file it writes now, the newest
            // (by its number, so also an earlier process's that had it)
            return name != names.last(where: { HandoverName.logPid($0) == pid }) && (left || settled)
        }
    }

    /// Whether a record file's last line is its close entry (`"t":"close"`).
    static func endsWithClose(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let window: UInt64 = 64 * 1024
        guard let size = try? handle.seekToEnd(), size > 0,
              (try? handle.seek(toOffset: size > window ? size - window : 0)) != nil,
              let tail = try? handle.readToEnd(), tail.last == UInt8(ascii: "\n") else { return false }
        let line: Data
        if let previous = tail.dropLast().lastIndex(of: UInt8(ascii: "\n")) {
            line = tail[tail.index(after: previous)...]
        } else if size <= window {
            line = tail
        } else {
            return false // a last line longer than the window is no close entry
        }
        let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        return entry?["t"] as? String == "close"
    }
}

// MARK: - The app's end

/// The extension, as the app's end reaches it (`HandoverClient` over XPC).
public protocol HandoverPeer {
    func list() async throws -> [HandoverFile]
    /// Up to `length` bytes of `file` from `offset`; empty when there are
    /// none, nil when the extension will not read that file.
    func read(_ file: HandoverFile, offset: UInt64, length: Int) async throws -> Data?
    /// The app holds all of `file`: delete it. Whether it was deleted.
    func remove(_ file: HandoverFile) async throws -> Bool
}

/// What one `HandoverSink.pull` did.
public struct HandoverSummary: Equatable, Sendable {
    /// Files that arrived or grew.
    public var files = 0
    public var bytes: UInt64 = 0
    /// Files the extension deleted, now that the app holds them.
    public var removed = 0
    /// Files that could not be taken this time.
    public var failed = 0

    public init() {}

    public var isEmpty: Bool { self == HandoverSummary() }
}

/// The app's end: files what the extension has into the app's own record
/// and log directories, where the bug report and the uploader read.
public struct HandoverSink: Sendable {
    /// Asked for per read.
    static let chunk = 512 * 1024
    /// Past these a listing is not what the core writes, and is not taken.
    static let maxFileBytes: UInt64 = 64 << 20
    static let maxFiles = 2000

    private let recordDir: URL
    private let logDir: URL

    public init(recordDir: URL, logDir: URL) {
        self.recordDir = recordDir
        self.logDir = logDir
    }

    /// Bring every listed file up to the length it was listed with, and have
    /// the finished ones deleted over there. Throws when the extension cannot
    /// be asked at all, or stops answering; a file that cannot be taken is
    /// counted and left for the next pull.
    public func pull(from peer: HandoverPeer) async throws -> HandoverSummary {
        var summary = HandoverSummary()
        for file in try await peer.list().prefix(Self.maxFiles) {
            guard file.kind.accepts(file.name), file.size <= Self.maxFileBytes else {
                summary.failed += 1
                continue
            }
            let url = (file.kind == .record ? recordDir : logDir).appendingPathComponent(file.name)
            let existing = HandoverStat(url)
            if let existing, !existing.isRegular {
                summary.failed += 1
                continue
            }
            let have = existing?.size ?? 0
            // Longer here than there: not the file this one was copied from.
            // Left alone on both sides (retention trims each).
            guard have <= file.size else {
                summary.failed += 1
                continue
            }
            var at = have
            if at < file.size {
                do {
                    at = try await append(file, from: peer, at: have, to: url)
                } catch let error as HandoverFileError {
                    at = error.reached
                    summary.failed += 1
                }
                if at > have {
                    summary.files += 1
                    summary.bytes += at - have
                }
            }
            if at == file.size, file.finished, try await peer.remove(file) {
                summary.removed += 1
            }
        }
        return summary
    }

    /// Append `file`'s bytes from `start` up to its listed size; where it got
    /// to. The file is made when its first bytes are here, not before.
    private func append(_ file: HandoverFile, from peer: HandoverPeer, at start: UInt64, to url: URL) async throws -> UInt64 {
        var handle: FileHandle?
        defer {
            if let handle {
                try? handle.close()
                // The file's own time, however far this got: the report's
                // window and the record sweep go by it
                try? FileManager.default.setAttributes([.modificationDate: file.modified], ofItemAtPath: url.path)
            }
        }
        var at = start
        while at < file.size {
            let want = Int(min(UInt64(Self.chunk), file.size - at))
            guard let read = try await peer.read(file, offset: at, length: want) else {
                throw HandoverFileError(reached: at)
            }
            // Never more than asked for, whatever comes back
            let data = read.prefix(want)
            if data.isEmpty { break } // shorter than listed: gone, or replaced
            if handle == nil {
                let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600)
                guard fd >= 0 else { throw HandoverFileError(reached: at) }
                handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            }
            do {
                try handle?.write(contentsOf: data)
            } catch {
                // What a failed write left is unknown: the next pull reads the size
                throw HandoverFileError(reached: HandoverStat(url)?.size ?? at)
            }
            at += UInt64(data.count)
        }
        return at
    }
}

/// A file could not be taken further: the extension refused it, or the
/// app's copy could not be written (the disk, permissions).
private struct HandoverFileError: Error {
    var reached: UInt64
}
