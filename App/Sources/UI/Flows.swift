import SwiftUI
import SporaKit
import SporaDesign

/// The create-share handoff: the busy moment (design 3a) resolves into the
/// link-ready handoff (design 2c). Copy is THE action (ember); naming happens in
/// place — no modal (the Android share-sheet → rename moment, reimagined).
struct CreateShareView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var controller: AppController
    let handoff: AppController.ShareDraft?
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let draft = handoff { handoffContent(draft) } else { busyContent }
        }
        .padding(EdgeInsets(top: 20, leading: 30, bottom: 26, trailing: 30))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // 3a — creating the link
    private var busyContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel(L("busy_eyebrow"))
            DetailStatus(dot: .pending, text: "↑ " + L("busy_status"), color: SporaColor.pendingText)
                .padding(.top, 20)
            Text(L("busy_title")).sporaType(.display).foregroundStyle(SporaColor.textPrimary).padding(.top, 8)
            Text(L("busy_body")).sporaType(.bodySmall).foregroundStyle(SporaColor.textMuted)
                .frame(maxWidth: 340, alignment: .leading).padding(.top, 6)
            HStack {
                Text("spora.to/s/··········").font(SporaFont.mono(15, .medium)).foregroundStyle(SporaColor.textMuted)
                Spacer()
                SporaIcon(.copy, size: 16).foregroundStyle(SporaColor.textMuted)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .sporaCard()
            .opacity(0.55)
            .padding(.top, 20)
            HStack {
                Spacer()
                Button { controller.cancelCreateShare() } label: { MicroLabel(L("cancel")) }
                    .buttonStyle(.plain).padding(.vertical, 10)
            }
            .padding(.top, 6)
            Spacer()
        }
    }

    // 2c — link ready, sharing; copy + name in place
    private func handoffContent(_ draft: AppController.ShareDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel(L("new_share_eyebrow"))
            DetailStatus(dot: .active, text: "↑ " + L("st_sharing"), color: SporaColor.successText,
                         since: model.activeShares[draft.id]?.startedAt)
                .padding(.top, 22)
            Text(model.label(draft.id) ?? "").sporaType(.displayLarge)
                .foregroundStyle(SporaColor.textPrimary).padding(.top, 8)

            HStack {
                Text(draft.url).font(SporaFont.mono(15, .medium)).foregroundStyle(SporaColor.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                SporaIcon(.copy, size: 16).foregroundStyle(SporaColor.textMuted)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .sporaCard()
            .padding(.top, 22)

            SporaButton(L("copy_link"), variant: .action) { controller.copy(draft.url) }
                .padding(.top, 14)
            Text(L("copy_link_hint")).sporaType(.bodySmall).foregroundStyle(SporaColor.textMuted).padding(.top, 10)

            InputField(label: L("name_label"), placeholder: L("name_placeholder"),
                       text: $name, helper: L("name_helper"))
                .frame(maxWidth: 400)
                .padding(.top, 26)
                .onChange(of: name) { new in
                    if !new.trimmingCharacters(in: .whitespaces).isEmpty {
                        controller.rename(shareId: draft.id, to: new)
                    }
                }

            Spacer()
            HStack {
                Spacer()
                Button { controller.dismissFlow() } label: {
                    MicroLabel(L("done"), color: SporaColor.textPrimary)
                }.buttonStyle(.plain).padding(.vertical, 12)
            }
        }
    }
}

/// The save-connection sheet (design 1g): Android's full-screen modal becomes a
/// native sheet. Underline inputs; the URL field shows the validation error.
struct SaveConnectionSheet: View {
    @EnvironmentObject var controller: AppController
    let prefillURL: String?
    @State private var url: String
    @State private var label: String = ""
    @State private var showError = false

    init(prefillURL: String?) {
        self.prefillURL = prefillURL
        _url = State(initialValue: prefillURL ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel(L("sheet_new_connection"))
            InputField(label: L("sheet_url_label"), placeholder: L("use_modal_url_placeholder"),
                       text: $url, error: showError ? L("sheet_url_error") : nil)
                .padding(.top, 18)
            InputField(label: L("sheet_name_label"), placeholder: L("sheet_name_placeholder"),
                       text: $label, helper: L("sheet_name_helper"))
                .padding(.top, 20)
            VStack(spacing: 2) {
                SporaButton(L("sheet_save"), variant: .primary, action: save)
                SporaButton(L("cancel"), variant: .text, action: controller.dismissFlow)
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .frame(width: 400)
        .background(SporaColor.surfaceCard)
    }

    private func save() {
        guard AppController.isValidShareURL(url) else { showError = true; return }
        controller.saveConnection(url: url, label: label)
    }
}
