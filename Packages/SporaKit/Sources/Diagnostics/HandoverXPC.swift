#if os(macOS)
import Foundation
import Security

/// The hand-over (`Handover.swift`) between the app and the tunnel's system
/// extension, over the Mach service the extension declares
/// (`NEMachServiceName`). launchd starts the extension for a caller, so the
/// app gets its files whether or not a tunnel is up. Each end takes only the
/// other one, signed by the team that signed itself (`CodeSigning`).
@objc public protocol HandoverXPC {
    /// Every file there is: a JSON array of `HandoverFile`.
    func list(reply: @escaping (Data?) -> Void)
    /// Up to `length` bytes of a file from `offset`; nil when refused.
    func read(kind: String, name: String, offset: UInt64, length: Int, reply: @escaping (Data?) -> Void)
    /// The caller holds all `size` bytes of a file: delete it, if finished.
    func remove(kind: String, name: String, size: UInt64, reply: @escaping (Bool) -> Void)
}

public enum DiagnosticsHandover {
    private static let tag = "Handover"
    static let appBundleId = "to.spora.macos"
    static let tunnelBundleId = "to.spora.macos.tunnel"

    /// The extension's Mach service, as its Info.plist names it: the app
    /// group, then `.tunnel`. None in a build without a team.
    public static var machServiceName: String? { SporaPaths.appGroup.map { $0 + ".tunnel" } }

    /// Kept for the life of the process.
    private static var listener: HandoverListener?

    /// The extension's end, the system extension only: answer the app from
    /// this process's record and log directories. Once, when the process
    /// starts and before it writes anything (`HandoverSource`). A build
    /// nobody signed serves nothing: there is no team to tell the app by.
    public static func serve() {
        guard listener == nil else { return }
        guard let name = machServiceName, let team = CodeSigning.ownTeam(),
              let requirement = CodeSigning.requirement(identifier: appBundleId, team: team) else {
            SporaLog.w(tag, "no hand-over: this build has no team")
            return
        }
        let mach = NSXPCListener(machServiceName: name)
        mach.setConnectionCodeSigningRequirement(requirement)
        let source = HandoverSource(recordDir: SporaPaths.recordDir, logDir: SporaPaths.logDir)
        let serving = HandoverListener(mach, source: source)
        serving.resume()
        listener = serving
    }

    /// The app's end: a connection to the extension, or nil in a build
    /// without a team. Where no extension is installed, the first call
    /// fails. `invalidate()` it when done.
    public static func connect() -> HandoverClient? {
        guard let name = machServiceName, let team = CodeSigning.ownTeam(),
              let requirement = CodeSigning.requirement(identifier: tunnelBundleId, team: team) else { return nil }
        let connection = NSXPCConnection(machServiceName: name, options: [])
        connection.setCodeSigningRequirement(requirement)
        return HandoverClient(connection)
    }
}

/// The extension's end of the connection: a listener answering from a
/// `HandoverSource`.
public final class HandoverListener: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener
    private let service: HandoverService

    public init(_ listener: NSXPCListener, source: HandoverSource) {
        self.listener = listener
        service = HandoverService(source)
        super.init()
        listener.delegate = self
    }

    public var endpoint: NSXPCListenerEndpoint { listener.endpoint }
    public func resume() { listener.resume() }
    public func invalidate() { listener.invalidate() }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HandoverXPC.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

/// Answers nothing but what `HandoverSource` allows; it logs nothing, so
/// that being asked never adds to the log it hands over.
private final class HandoverService: NSObject, HandoverXPC {
    private let source: HandoverSource

    init(_ source: HandoverSource) { self.source = source }

    func list(reply: @escaping (Data?) -> Void) {
        reply(try? JSONEncoder().encode(source.list()))
    }

    func read(kind: String, name: String, offset: UInt64, length: Int, reply: @escaping (Data?) -> Void) {
        reply(HandoverKind(rawValue: kind).flatMap { source.read($0, name: name, offset: offset, length: length) })
    }

    func remove(kind: String, name: String, size: UInt64, reply: @escaping (Bool) -> Void) {
        reply(HandoverKind(rawValue: kind).map { source.remove($0, name: name, size: size) } ?? false)
    }
}

/// The app's end of the connection.
public final class HandoverClient: HandoverPeer, @unchecked Sendable {
    private let connection: NSXPCConnection

    public init(_ connection: NSXPCConnection) {
        self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: HandoverXPC.self)
        connection.resume()
    }

    /// Close the connection; calls still waiting for an answer fail.
    public func invalidate() { connection.invalidate() }

    public func list() async throws -> [HandoverFile] {
        let data: Data? = try await call { $0.list(reply: $1) }
        guard let data else { throw HandoverError.noListing }
        return try JSONDecoder().decode([HandoverFile].self, from: data)
    }

    public func read(_ file: HandoverFile, offset: UInt64, length: Int) async throws -> Data? {
        try await call {
            $0.read(kind: file.kind.rawValue, name: file.name, offset: offset, length: length, reply: $1)
        }
    }

    public func remove(_ file: HandoverFile) async throws -> Bool {
        try await call { $0.remove(kind: file.kind.rawValue, name: file.name, size: file.size, reply: $1) }
    }

    /// One call: its answer, or the connection's error (no extension, not
    /// the one expected, invalidated).
    private func call<T>(_ send: (HandoverXPC, @escaping (T) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let answer = Once(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { answer.resume(.failure($0)) }
            guard let remote = proxy as? HandoverXPC else {
                answer.resume(.failure(HandoverError.noListing))
                return
            }
            send(remote) { answer.resume(.success($0)) }
        }
    }
}

public enum HandoverError: Error {
    /// The extension answered, but with no listing.
    case noListing
}

/// A continuation resumed by whichever comes first, the answer or the
/// connection's error.
private final class Once<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }

    func resume(_ result: Result<T, Error>) {
        let waiting = lock.locked { () -> CheckedContinuation<T, Error>? in
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(with: result)
    }
}

/// Who signed this process, and the requirement its peer must meet. The
/// team comes from the process's own signature, so no build names one.
enum CodeSigning {
    /// The team that signed this process; nil when nobody did (an unsigned
    /// or ad-hoc build).
    static func ownTeam() -> String? {
        var running: SecCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running else { return nil }
        var onDisk: SecStaticCode?
        guard SecCodeCopyStaticCode(running, [], &onDisk) == errSecSuccess, let onDisk else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(onDisk, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String else { return nil }
        return team
    }

    /// Code with this identifier, signed by `team` with a certificate Apple
    /// issued; nil unless `team` reads as a team ID.
    static func requirement(identifier: String, team: String) -> String? {
        let isTeam = team.utf8.count == 10 && team.utf8.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A)
        }
        guard isTeam else { return nil }
        let text = "anchor apple generic and identifier \"\(identifier)\" "
            + "and certificate leaf[subject.OU] = \"\(team)\""
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &parsed) == errSecSuccess else { return nil }
        return text
    }
}
#endif
