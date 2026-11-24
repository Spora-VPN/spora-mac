import SwiftUI
import AppKit
import SporaKit
import SporaDesign

/// Send feedback (Android parity: `FeedbackModal`): a subject and a message,
/// sent with a diagnostic report (records, log, crash files of the last few
/// days) through whatever app the user picks. Nothing reaches Spora until
/// the user sends it from there, and the hand-off says so.
struct FeedbackSheet: View {
    @EnvironmentObject var controller: AppController
    @State private var subject = ""
    @State private var message = ""
    @State private var preparing = false
    /// The report written for this message, reused when the picker is
    /// opened again (the reports directory keeps it a day).
    @State private var report: URL?
    /// Once the picker has been shown: whether the report went with it.
    @State private var handedOff: Bool?
    @State private var anchor: NSView?
    @State private var sharer = FeedbackSharer()

    var body: some View {
        SheetBody(width: 440) {
            if let handedOff {
                handoff(reportAttached: handedOff)
            } else {
                form
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel(L("feedback_modal_header"))
            Text(L("feedback_modal_title")).sporaType(.display).foregroundStyle(SporaColor.textPrimary)
                .padding(.top, 8)
            Text(L("feedback_modal_hint")).sporaType(.body).foregroundStyle(SporaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text(L("feedback_modal_report_note")).sporaType(.bodySmall).foregroundStyle(SporaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            InputField(label: L("feedback_subject_label"), placeholder: L("feedback_subject_placeholder"),
                       text: $subject)
                .padding(.top, 20)
            InputField(label: L("feedback_message_label"), placeholder: L("feedback_message_placeholder"),
                       text: $message, multiline: true)
                .padding(.top, 20)
            VStack(spacing: 2) {
                SporaButton(L(preparing ? "feedback_preparing" : "feedback_send"), variant: .primary, action: send)
                    .disabled(preparing)
                    .background(PickerAnchor { anchor = $0 })
                SporaButton(L("cancel"), variant: .text) { controller.sheet = nil }
            }
            .padding(.top, 24)
        }
    }

    // After the picker: nothing has reached us yet, and the copy says so.
    private func handoff(reportAttached: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel(L("feedback_modal_header"))
            Text(L("feedback_handoff_title")).sporaType(.display).foregroundStyle(SporaColor.textPrimary)
                .padding(.top, 8)
            Text(L("feedback_handoff_message")).sporaType(.body).foregroundStyle(SporaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if !reportAttached {
                StatusLine(dot: .error, text: L("feedback_no_report"), color: SporaColor.error, mono: false)
                    .padding(.top, 10)
            }
            DataField(label: L("feedback_support_address_label"), value: BugReport.supportAddress)
                .padding(.top, 20)
            VStack(spacing: 2) {
                SporaButton(L("done"), variant: .primary) { controller.sheet = nil }
                    .background(PickerAnchor { anchor = $0 })
                SporaButton(L("feedback_send_again"), variant: .text, action: send)
                if let report {
                    SporaButton(L("feedback_show_report"), variant: .text) {
                        NSWorkspace.shared.activateFileViewerSelecting([report])
                    }
                }
            }
            .padding(.top, 24)
        }
    }

    // Also from the hand-off: a user who closed the picker can pick an app
    // again without retyping anything.
    private func send() {
        guard !preparing else { return }
        preparing = true
        let s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let existing = report.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            let made: URL?
            if let existing {
                made = existing
            } else {
                made = await BugReport.prepare(note: "\(s)\n\n\(m)")
            }
            report = made
            preparing = false
            guard let anchor else {
                handedOff = made != nil
                return
            }
            sharer.show(subject: s, message: m, report: made, from: anchor) {
                handedOff = made != nil
            }
        }
    }
}
