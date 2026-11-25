#if SPORA_DIRECT
import Foundation
import SystemExtensions
import SporaKit

/// Which version of the tunnel's system extension macOS runs, against the
/// copy inside this app. After an update (Sparkle's, or a newer app dragged
/// into /Applications) they differ until the app asks macOS to replace it.
enum ExtensionVersion {
    private static let tag = "ExtensionVersion"

    /// Whether macOS has the extension `identifier` enabled, that is, the
    /// user allowed it once, at another version than the app's own copy.
    /// `false` when it was never allowed or is switched off: then nothing
    /// may activate it before the user's next connect.
    static func enabledIsOutdated(identifier: String) async -> Bool {
        guard let own = ownCopy(identifier) else {
            SporaLog.w(tag, "no extension inside the app")
            return false
        }
        guard let found = await PropertiesQuery().run(identifier: identifier) else { return false }
        let enabled = found.filter { $0.isEnabled && !$0.isUninstalling }
        guard !enabled.isEmpty else { return false }
        if enabled.contains(where: { $0.bundleVersion == own.build && $0.bundleShortVersion == own.version }) {
            return false
        }
        let running = enabled.map { "\($0.bundleShortVersion) (\($0.bundleVersion))" }.joined(separator: ", ")
        SporaLog.i(tag, "macOS runs \(running), the app has \(own.version) (\(own.build))")
        return true
    }

    private static func ownCopy(_ identifier: String) -> (version: String, build: String)? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions/\(identifier).systemextension")
        guard let info = Bundle(url: url)?.infoDictionary,
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else { return nil }
        return (version, build)
    }
}

/// One `propertiesRequest`: what macOS knows of every version of the
/// extension it has (enabled, waiting for approval, being uninstalled).
/// sysextd answers on the main queue.
private final class PropertiesQuery: NSObject, OSSystemExtensionRequestDelegate {
    private static let tag = "ExtensionVersion"
    private var continuation: CheckedContinuation<[OSSystemExtensionProperties]?, Never>?

    @MainActor
    func run(identifier: String) async -> [OSSystemExtensionProperties]? {
        await withCheckedContinuation { cont in
            continuation = cont
            let request = OSSystemExtensionRequest.propertiesRequest(
                forExtensionWithIdentifier: identifier, queue: .main)
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    private func answer(_ found: [OSSystemExtensionProperties]?) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: found)
    }

    func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        answer(properties)
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        answer(nil) // after foundProperties, if there were any
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        SporaLog.w(Self.tag, "properties request failed (code \((error as NSError).code))", error)
        answer(nil)
    }

    // Never asked of a properties request.
    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .cancel
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {}
}
#endif
