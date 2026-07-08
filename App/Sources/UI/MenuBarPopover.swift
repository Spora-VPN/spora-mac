import SwiftUI
import AppKit
import SporaKit
import SporaDesign

/// The menu-bar template icon (design 1h/2e). Mono shapes carry state without
/// color: ● active · ○ pending · ◆ error · nothing = offline. Precedence is
/// resolved by `AppModel.menuBarState`.
///
/// Rendered as a fixed-size template `NSImage`: `MenuBarExtra` sizes a `View`
/// label to the image's *intrinsic* dimensions (ignoring `.frame()`), which
/// blows the tall mark up several ×. `Image(nsImage:)` with an explicitly-sized
/// template image renders at exactly that size and tints for light/dark.
struct MenuBarLabel: View {
    let state: MenuBarState
    var body: some View {
        Image(nsImage: MenuBarLabel.icon(for: state))
    }

    /// Height of the menu-bar icon in points (fits the ~22pt system menu bar).
    private static let iconHeight: CGFloat = 16

    static func icon(for state: MenuBarState) -> NSImage {
        let h = iconHeight
        let markH = h - 3
        let mark = NSImage(named: "LogoMonoInk")
        let aspect = mark.map { $0.size.width / max($0.size.height, 1) } ?? 0.72
        let markW = (markH * aspect).rounded()
        let gap: CGFloat = 3
        let glyphSize: CGFloat = state == .offline ? 0 : 7
        let width = markW + (glyphSize > 0 ? gap + glyphSize : 0)

        let image = NSImage(size: NSSize(width: width, height: h))
        image.lockFocus()
        mark?.draw(in: NSRect(x: 0, y: (h - markH) / 2, width: markW, height: markH))

        if glyphSize > 0 {
            NSColor.black.setFill(); NSColor.black.setStroke()
            let gx = markW + gap
            let cy = h / 2
            switch state {
            case .active:
                NSBezierPath(ovalIn: NSRect(x: gx, y: cy - 3, width: 6, height: 6)).fill()
            case .pending:
                let ring = NSBezierPath(ovalIn: NSRect(x: gx + 0.75, y: cy - 3.25, width: 6.5, height: 6.5))
                ring.lineWidth = 1.5; ring.stroke()
            case .error:
                let r: CGFloat = 3.5, cx = gx + 3.5
                let d = NSBezierPath()
                d.move(to: NSPoint(x: cx, y: cy + r))
                d.line(to: NSPoint(x: cx + r, y: cy))
                d.line(to: NSPoint(x: cx, y: cy - r))
                d.line(to: NSPoint(x: cx - r, y: cy))
                d.close(); d.fill()
            case .offline:
                break
            }
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
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
