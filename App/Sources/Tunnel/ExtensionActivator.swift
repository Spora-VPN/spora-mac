#if SPORA_DIRECT
import Foundation
import SystemExtensions
import SporaKit

/// Activates the tunnel's system extension (the direct build, ADR-002 D3).
///
/// Every connect submits an activation request before the tunnel starts,
/// never the app's launch, so share-only users never meet the approval:
/// - the first time, macOS blocks the extension until the user allows it in
///   System Settings (`onNeedsApproval`), and the request finishes then;
/// - after an update, sysextd offers to replace the running extension with
///   the app's copy, and we always do;
/// - otherwise it is already active and the request finishes at once.
///
/// A request macOS is holding for approval cannot be withdrawn: `cancel()`
/// only stops waiting for it. If the user allows the extension later, the
/// next connect finds it active.
@MainActor
final class ExtensionActivator: NSObject {
    private static let tag = "ExtensionActivator"

    enum Failure: Error {
        /// The user dismissed the approval guide, or a newer request took over.
        case notAllowed
        /// The app is not in /Applications, where macOS activates extensions.
        case notInApplications
        /// Anything else sysextd reported.
        case failed(Error)
        /// Activated, but only after a restart.
        case needsReboot
    }

    private var continuation: CheckedContinuation<Void, Error>?
    /// The request being waited for; callbacks for older ones are ignored.
    private var current: ObjectIdentifier?
    private var onNeedsApproval: (() -> Void)?

    /// Activate the extension `identifier` (the app's own copy) and return
    /// once it is active. `onNeedsApproval` runs when macOS waits for the
    /// user; the call keeps waiting until they allow it or `cancel()`.
    func activate(identifier: String, onNeedsApproval: @escaping () -> Void) async throws {
        finish(.failure(Failure.notAllowed)) // a request still waiting is superseded
        self.onNeedsApproval = onNeedsApproval
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            continuation = cont
            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: identifier, queue: .main)
            request.delegate = self
            current = ObjectIdentifier(request)
            SporaLog.i(Self.tag, "activation requested")
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    /// Stop waiting for the user's approval.
    func cancel() {
        finish(.failure(Failure.notAllowed))
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        current = nil
        onNeedsApproval = nil
        cont.resume(with: result)
    }

    private func needsApproval(_ request: ObjectIdentifier) {
        guard request == current else { return }
        SporaLog.i(Self.tag, "waiting for the user's approval")
        onNeedsApproval?()
    }

    private func finished(_ request: ObjectIdentifier, _ result: OSSystemExtensionRequest.Result) {
        guard request == current else { return }
        switch result {
        case .completed:
            SporaLog.i(Self.tag, "extension active")
            finish(.success(()))
        case .willCompleteAfterReboot:
            SporaLog.w(Self.tag, "extension active after a restart")
            finish(.failure(Failure.needsReboot))
        @unknown default:
            finish(.failure(Failure.failed(NSError(domain: OSSystemExtensionErrorDomain,
                                                   code: OSSystemExtensionError.unknown.rawValue))))
        }
    }

    private func failed(_ request: ObjectIdentifier, _ error: Error) {
        guard request == current else { return }
        let nsError = error as NSError
        SporaLog.e(Self.tag, "activation failed (code \(nsError.code))", error)
        if nsError.domain == OSSystemExtensionErrorDomain,
           nsError.code == OSSystemExtensionError.unsupportedParentBundleLocation.rawValue {
            finish(.failure(Failure.notInApplications))
        } else {
            finish(.failure(Failure.failed(error)))
        }
    }
}

// sysextd calls back on the queue the request names: the main queue.
extension ExtensionActivator: OSSystemExtensionRequestDelegate {
    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        SporaLog.i(Self.tag, "replacing \(existing.bundleShortVersion) (\(existing.bundleVersion)) "
                   + "with \(ext.bundleShortVersion) (\(ext.bundleVersion))")
        return .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        let id = ObjectIdentifier(request)
        Task { @MainActor in self.needsApproval(id) }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let id = ObjectIdentifier(request)
        Task { @MainActor in self.finished(id, result) }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let id = ObjectIdentifier(request)
        Task { @MainActor in self.failed(id, error) }
    }
}
#endif
