import SwiftUI
import SporaKit
import SporaDesign

/// The menu-bar template icon (design 1h/2e). Mono shapes carry state without
/// color: ● active · ○ pending · ◆ error · nothing = offline. Precedence is
/// resolved by `AppModel.menuBarState`. Drawn in `.primary` so it templates to
/// the menu bar's light/dark content color.
struct MenuBarLabel: View {
    let state: MenuBarState

    var body: some View {
        HStack(spacing: 3) {
            Image("LogoMonoInk")
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(height: 15)
            stateGlyph
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder private var stateGlyph: some View {
        switch state {
        case .offline:
            EmptyView()
        case .active:
            Circle().frame(width: 6, height: 6)
        case .pending:
            Circle().strokeBorder(lineWidth: 1.6).frame(width: 7, height: 7)
        case .error:
            RoundedRectangle(cornerRadius: 1).frame(width: 6, height: 6).rotationEffect(.degrees(45))
        }
    }
}

/// The list-first popover (committed direction 1d): every connection and its
/// toggle on one dense surface, aggregate status in the header, primary actions
/// at the foot.
struct MenuBarPopover: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.uses.isEmpty {
                sectionLabel(L("section_connections"))
                ForEach(model.uses) { u in
                    PopoverRow(id: u.id, name: u.label, state: model.useState(u.id), role: .use)
                }
            }
            if !model.shares.isEmpty {
                sectionLabel(L("section_my_shares"), topBorder: !model.uses.isEmpty)
                ForEach(model.shares) { s in
                    PopoverRow(id: s.id, name: s.label, state: model.shareState(s.id), role: .share)
                }
            }
            footer
        }
        .frame(width: SporaMetrics.popoverWidth)
        .environment(\.colorScheme, .light)
        .background(SporaColor.surfaceCard)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 8) {
                SporaMark(.ink, height: 16)
                Text("SPORA").font(SporaFont.sans(11, .bold)).tracking(2.2).foregroundStyle(SporaColor.textPrimary)
            }
            Spacer(minLength: 0)
            CompactAggregateStatus()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(SporaColor.borderDivider).frame(height: 1) }
    }

    private func sectionLabel(_ title: String, topBorder: Bool = false) -> some View {
        MicroLabel(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, topBorder ? 12 : 12).padding(.bottom, 4)
            .overlay(alignment: .top) {
                if topBorder { Rectangle().fill(SporaColor.borderDivider).frame(height: 1) }
            }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            popoverAction(L("popover_create_share"), icon: .plus) { activateAndRun(controller.beginCreateShare) }
            popoverAction(L("popover_connect_link"), icon: .plus) { activateAndRun(controller.beginConnect) }
            popoverAction(L("popover_open"), icon: .external) { activateAndRun {} }
        }
        .padding(.horizontal, 14).padding(.top, 5).padding(.bottom, 9)
        .overlay(alignment: .top) { Rectangle().fill(SporaColor.borderDivider).frame(height: 1) }
    }

    private func popoverAction(_ title: String, icon: SporaIcon.Glyph, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SporaIcon(icon, size: 13).foregroundStyle(SporaColor.textMuted)
                Text(title).font(SporaFont.sans(12.5, .medium)).foregroundStyle(SporaColor.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func activateAndRun(_ action: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
        action()
    }
}

/// Compact aggregate status for the popover header (status words only,
/// right-aligned, no names — design 2e).
struct CompactAggregateStatus: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let s = model.aggregateStatus
        VStack(alignment: .trailing, spacing: 4) {
            if s.isOffline {
                Text(L("status_offline")).sporaType(.status).foregroundStyle(SporaColor.textMuted)
            } else {
                if let down = s.down {
                    switch down {
                    case .connected: statusText("↓ " + L("st_connected"), SporaColor.successText)
                    case .connecting: statusText("↓ " + L("st_connecting"), SporaColor.pendingText)
                    }
                }
                if let up = s.up {
                    switch up {
                    case .sharing: statusText("↑ " + L("st_sharing"), SporaColor.successText)
                    case .starting: statusText("↑ " + L("st_starting"), SporaColor.pendingText)
                    }
                }
            }
        }
    }
    private func statusText(_ t: String, _ c: Color) -> some View {
        Text(t).sporaType(.status).foregroundStyle(c)
    }
}

/// A popover connection row: dot (or aligned gap) + name + status subline, with
/// a toggle on the right. Errors expand to show the sentence + retry (2e).
struct PopoverRow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var controller: AppController
    let id: String
    let name: String
    let state: DisplayState
    let role: Role

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leadingDot.padding(.top, isError ? 3 : 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(SporaFont.sans(13, .medium))
                    .foregroundStyle(state == .inactive ? SporaColor.textMuted : SporaColor.textPrimary)
                subline
            }
            Spacer(minLength: 0)
            SporaToggle(on: toggleOn) {
                if role == .share { controller.toggleShare(id) } else { controller.toggleUse(id) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var isError: Bool { if case .error = state { return true } else { return false } }
    private var toggleOn: Bool { switch state { case .active, .pending: return true; default: return false } }

    @ViewBuilder private var leadingDot: some View {
        if state == .inactive { Color.clear.frame(width: 8, height: 8) }
        else { StatusDot(state.shape, box: 7) }
    }

    @ViewBuilder private var subline: some View {
        switch (role, state) {
        case (_, .inactive):
            EmptyView()
        case (.share, .active):
            Text("↑ " + L("st_sharing")).sporaType(.status).foregroundStyle(SporaColor.successText)
        case (.share, .pending):
            Text(L("st_starting")).sporaType(.status).foregroundStyle(SporaColor.pendingText)
        case (.use, .active):
            Text("↓ " + L("st_connected")).sporaType(.status).foregroundStyle(SporaColor.successText)
        case (.use, .pending):
            Text(L("st_connecting")).sporaType(.status).foregroundStyle(SporaColor.pendingText)
        case (_, .error(let e)):
            VStack(alignment: .leading, spacing: 6) {
                Text(L(e.messageKey)).font(SporaFont.sans(11.5)).foregroundStyle(SporaColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                Button { controller.retry(Selection(id: id, role: role)) } label: {
                    MicroLabel(L("retry") + " →", color: SporaColor.textPrimary)
                }.buttonStyle(.plain)
            }
        case (_, .waiting):
            EmptyView()
        }
    }
}
