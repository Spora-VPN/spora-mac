import SwiftUI
import SporaKit
import SporaDesign

/// The detail pane — the status surface for the selected connection, plus the
/// first-launch empty state. Covers the 2d state matrix for both roles and the
/// unattributed use-error banner (design 2d).
struct DetailPane: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = model.unattributedUseError {
                UnattributedErrorBanner(error: error)
                    .padding(EdgeInsets(top: 20, leading: 30, bottom: 0, trailing: 30))
            }
            if let selection = model.selection {
                ConnectionDetail(selection: selection)
                    .id(selection.id)
            } else {
                EmptyState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SporaColor.surfaceBg)
    }
}

// MARK: - Empty state (2b)

struct EmptyState: View {
    @EnvironmentObject var controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            SporaLogoIcon(height: 46).opacity(0.9)
            Text(L("empty_title"))
                .font(SporaFont.sans(22, .semibold)).tracking(-0.3)
                .foregroundStyle(SporaColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
            Text(L("empty_body"))
                .sporaType(.body)
                .foregroundStyle(SporaColor.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.top, 8)
            VStack(spacing: 12) {
                ActionCard(
                    eyebrow: L("card_share_eyebrow"),
                    title: L("card_share_title"),
                    subtitle: L("card_share_subtitle"),
                    action: controller.beginCreateShare
                )
                ActionCard(
                    eyebrow: L("card_use_eyebrow"),
                    title: L("card_use_title"),
                    subtitle: L("card_use_subtitle"),
                    variant: .secondary,
                    action: controller.beginConnect
                )
            }
            .frame(width: 400)
            .padding(.top, 26)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

// MARK: - Connection detail

struct ConnectionDetail: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var controller: AppController
    let selection: Selection

    private var role: Role { selection.role }
    private var state: DisplayState { model.state(for: selection) }
    private var name: String { model.label(selection.id) ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel(breadcrumb)
            header.padding(.top, 22)
            Text(name)
                .sporaType(.displayLarge)
                .foregroundStyle(SporaColor.textPrimary)
                .padding(.top, 8)

            if case .error(let error) = state {
                RetryRow(title: L(error == .shareLinkLost ? "share_new_link" : "retry")) {
                    controller.retry(selection)
                }
                .padding(.top, 12)
            }
            if isActive {
                Barcode(seed: Fmt.seed(selection.id), bars: 132, height: 26).padding(.top, 16)
            }

            infoCard.padding(.top, 22)
            toggleCard.padding(.top, 22)

            Spacer(minLength: 12)
            footer
        }
        .padding(EdgeInsets(top: 20, leading: 30, bottom: 26, trailing: 30))
    }

    private var isActive: Bool { state == .active }

    private var breadcrumb: String {
        let section = role == .share ? L("section_my_shares") : L("section_connections")
        return "\(section) / \(upper(name))"
    }

    // Status header line, with a ticking session clock when active.
    @ViewBuilder private var header: some View {
        switch (role, state) {
        case (.share, .active):
            DetailStatus(dot: .active, text: "↑ " + L("st_sharing"), color: SporaColor.successText,
                         since: model.activeShares[selection.id]?.startedAt)
        case (.share, .pending):
            DetailStatus(dot: .pending, text: "↑ " + L("st_starting"), color: SporaColor.pendingText)
        case (.use, .active):
            DetailStatus(dot: .active, text: "↓ " + L("st_connected"), color: SporaColor.successText,
                         since: model.useConnectedAt)
        case (.use, .pending):
            DetailStatus(dot: .pending, text: "↓ " + Lf("st_connecting_via", "«\(upper(name))»"), color: SporaColor.pendingText)
        case (_, .error(let e)):
            DetailStatus(dot: .error, text: L(e.messageKey), color: SporaColor.error, mono: false)
        default:
            DetailStatus(dot: nil, text: L("st_inactive"), color: SporaColor.textMuted)
        }
    }

    // MARK: Info card

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow(L("label_link")) {
                HStack(spacing: 8) {
                    Text(url).sporaType(.data).foregroundStyle(SporaColor.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                    Button { controller.copy(url) } label: {
                        SporaIcon(.copy, size: 14).foregroundStyle(SporaColor.textMuted)
                    }.buttonStyle(.plain)
                }
            }
            Divider().overlay(SporaColor.borderDivider)
            infoRow(L("label_created")) {
                Text(Fmt.date(createdAt)).sporaType(.data).foregroundStyle(SporaColor.textPrimary)
            }
            if isActive {
                Divider().overlay(SporaColor.borderDivider)
                infoRow(L("label_last_activity")) {
                    Text(Fmt.date(createdAt)).sporaType(.data).foregroundStyle(SporaColor.textPrimary)
                }
            }
        }
        .sporaCard()
    }

    private func infoRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            MicroLabel(label)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var url: String {
        if role == .share { return model.shareURL(selection.id) ?? "spora.to/s/··········" }
        return model.uses.first(where: { $0.id == selection.id })?.url ?? ""
    }

    private var createdAt: Date {
        if role == .share { return model.shares.first(where: { $0.id == selection.id })?.createdAt ?? .distantPast }
        return model.uses.first(where: { $0.id == selection.id })?.createdAt ?? .distantPast
    }

    // MARK: Toggle card

    private var toggleCard: some View {
        HStack(spacing: 14) {
            SporaToggle(on: toggleOn, enabled: true) {
                if role == .share { controller.toggleShare(selection.id) }
                else { controller.toggleUse(selection.id) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(toggleTitle).font(SporaFont.sans(13.5, .semibold)).foregroundStyle(SporaColor.textPrimary)
                Text(toggleBody).sporaType(.bodySmall).foregroundStyle(SporaColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .sporaCard()
    }

    private var toggleOn: Bool {
        switch state { case .active, .pending: return true; default: return false }
    }

    private var toggleTitle: String {
        switch (role, toggleOn) {
        case (.share, true): return L("share_toggle_on_title")
        case (.share, false): return L("share_toggle_off_title")
        case (.use, true): return L("use_connected_title")
        case (.use, false): return L("use_off_title")
        }
    }

    private var toggleBody: String {
        switch (role, toggleOn) {
        case (.share, true): return L("share_toggle_on_body")
        case (.share, false): return L("share_toggle_off_body")
        case (.use, true): return Lf("use_connected_body", "«\(name)»")
        case (.use, false): return L("use_off_body")
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        switch role {
        case .share:
            if isActive {
                HStack {
                    Button { controller.copy(url) } label: {
                        HStack(spacing: 8) {
                            SporaIcon(.upload, size: 14).foregroundStyle(SporaColor.textPrimary)
                            MicroLabel(L("share_share_again"), color: SporaColor.textPrimary)
                        }
                    }.buttonStyle(.plain)
                    Spacer()
                    Text(L("share_delete_hint")).sporaType(.bodySmall).foregroundStyle(SporaColor.textMuted)
                }
            } else {
                DeleteFooter(enabled: true, label: L("share_delete")) { controller.deleteSelected() }
            }
        case .use:
            if isActive {
                DeleteFooter(enabled: false, label: L("use_delete"), hint: L("use_delete_hint")) {}
            } else {
                DeleteFooter(enabled: true, label: L("use_delete")) { controller.deleteSelected() }
            }
        }
    }
}

// MARK: - Small detail components

/// Status header with an optional ticking session clock (HH:MM:SS).
struct DetailStatus: View {
    let dot: StatusShape?
    let text: String
    let color: Color
    var since: Date? = nil
    var mono: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            if let dot { StatusDot(dot) }
            if mono {
                Text(text).sporaType(.status).foregroundStyle(color)
            } else {
                Text(text).font(SporaFont.sans(11.5)).foregroundStyle(color)
            }
            if let since {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Fmt.elapsed(since: since, now: ctx.date))
                        .sporaType(.data).foregroundStyle(SporaColor.textMuted)
                        .padding(.leading, 6)
                }
            }
        }
    }
}

/// The action an error offers (RETRY, or MAKE A NEW LINK for a share under
/// a lost device identity).
struct RetryRow: View {
    var title = L("retry")
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            MicroLabel(title + " →", color: SporaColor.textPrimary)
        }.buttonStyle(.plain)
    }
}

struct DeleteFooter: View {
    let enabled: Bool
    let label: String
    var hint: String? = nil
    let action: () -> Void
    var body: some View {
        HStack {
            Button(action: action) {
                MicroLabel(label, color: SporaColor.error).opacity(enabled ? 0.85 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            Spacer()
            if let hint {
                Text(hint).sporaType(.bodySmall).foregroundStyle(SporaColor.textMuted)
            }
        }
    }
}

/// Unattributed use error — a banner above the detail content. Error-tinted,
/// never orange (design 2d).
struct UnattributedErrorBanner: View {
    @EnvironmentObject var model: AppModel
    let error: SporaError
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                StatusDot(.error, box: 7)
                Text(L(error.messageKey))
                    .font(SporaFont.sans(12.5)).foregroundStyle(SporaColor.errorStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { model.connectDisconnected() } label: {
                MicroLabel(L("banner_dismiss"))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(SporaColor.surfaceErrorTint, in: RoundedRectangle(cornerRadius: SporaMetrics.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: SporaMetrics.radiusCard).strokeBorder(SporaColor.borderError, lineWidth: 1))
    }
}
