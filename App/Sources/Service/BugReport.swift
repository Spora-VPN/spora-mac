import AppKit
import SwiftUI
import SporaKit

/// Bug reports (Android parity: `BugReport`): the core bundles this Mac's
/// recent connection records, diagnostic log and crash files into a zip, and
/// the user sends it through whatever app they choose (Mail, Messages, …).
/// No Spora server is involved, so reporting works exactly when spora.to is
/// unreachable and with uploads off.
enum BugReport {
    private static let tag = "BugReport"
    static let supportAddress = "support@spora.to"

    // A mail app may read the attachment well after the picker closes (an
    // outbox that sends later), so a report outlives its own send by a day
    private static let maxAge: TimeInterval = 24 * 60 * 60

    /// A fresh report, with what the tunnel has recorded up to now (the
    /// direct build fetches it from the system extension first); nil when it
    /// could not be made.
    static func prepare(note: String?) async -> URL? {
        await TunnelDiagnostics.fetch()
        return try? await offMain { export(note: note) }
    }

    /// Write a fresh report from what is in the app's directories and return
    /// it, or nil when it could not be made. Blocking file work, seconds at
    /// worst: call it off the main thread.
    static func export(note: String?) -> URL? {
        let dir = SporaPaths.reportsDir
        prune(dir)
        let stamp = ISO8601DateFormatter.string(
            from: Date(), timeZone: TimeZone(identifier: "UTC")!,
            formatOptions: [.withYear, .withMonth, .withDay, .withTime, .withTimeZone])
        let out = dir.appendingPathComponent("spora-report-\(stamp).zip")
        do {
            let summary = try exportBugReport(outPath: out.path, note: note, platformInfo: platformInfo())
            SporaLog.i(tag, "report \(out.lastPathComponent): \(summary.includedFiles) files, "
                + "\(summary.omittedFiles) left out, \(summary.bytes) bytes")
            return out
        } catch {
            SporaLog.e(tag, "cannot write a report", error)
            return nil
        }
    }

    private static func prune(_ dir: URL) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for f in files {
            let modified = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, Date().timeIntervalSince(modified) > maxAge { try? fm.removeItem(at: f) }
        }
    }

    static func platformInfo() -> [String: String] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let info = Bundle.main.infoDictionary ?? [:]
        return [
            "model": sysctlString("hw.model") ?? "unknown",
            "macos": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "arch": sysctlString("hw.machine") ?? "unknown",
            "app_version": ServiceController.appVersion,
            "app_build": info["CFBundleVersion"] as? String ?? "unknown",
        ]
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}

/// Opens the system share picker for a message to support, the report
/// attached when there is one. Mail is the intent (its compose window gets
/// the support address and the subject), but any app may take it (a
/// messenger when mail is blocked). Main thread only, as AppKit calls its
/// delegate.
final class FeedbackSharer: NSObject, NSSharingServicePickerDelegate {
    private var subject = ""
    private var onClose: (() -> Void)?

    func show(subject: String, message: String, report: URL?, from view: NSView, onClose: @escaping () -> Void) {
        self.subject = subject
        self.onClose = onClose
        var items: [Any] = []
        if !message.isEmpty { items.append(message) }
        if let report { items.append(report) }
        if items.isEmpty { items.append(subject) }
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker,
                              sharingServicesForItems items: [Any],
                              proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
        // NSSharingService exposes no name: Mail is the one titled as the
        // compose-email service is
        let mail = NSSharingService(named: .composeEmail)?.title
        for service in proposed where service.title == mail {
            service.recipients = [BugReport.supportAddress]
            service.subject = subject
        }
        return proposed
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        onClose?()
        onClose = nil
    }
}

/// The NSView the share picker is anchored to, for SwiftUI.
struct PickerAnchor: NSViewRepresentable {
    let onView: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onView(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
