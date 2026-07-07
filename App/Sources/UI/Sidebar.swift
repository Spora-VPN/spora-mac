import SwiftUI
import SporaKit
import SporaDesign

/// The 248px master sidebar (committed direction 1b): brand lockup, aggregate
/// status block, both connection lists (shape-coded), and the two primary
/// actions pinned at the foot. The sidebar *is* the connection list — selecting
/// a row drives the detail pane.
struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    var onCreateShare: () -> Void
    var onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Lockup — sits below the window's traffic lights (hidden titlebar).
            SporaLockup(markHeight: 20)
                .padding(.top, 30)
                .padding(.horizontal, 18)

            AggregateStatusBlock()
                .padding(.horizontal, 18)
                .padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section(L("section_my_shares"))
                    if model.shares.isEmpty {
                        emptyPlaceholder
                    } else {
                        ForEach(model.shares) { s in
                            SidebarRow(id: s.id, name: s.label, state: model.shareState(s.id), role: .share)
                        }
                    }
                    section(L("section_connections"))
                    if model.uses.isEmpty {
                        emptyPlaceholder
                    } else {
                        ForEach(model.uses) { u in
                            SidebarRow(id: u.id, name: u.label, state: model.useState(u.id), role: .use)
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            footer
        }
        .frame(width: SporaMetrics.sidebarWidth)
        .background(SporaColor.surfaceCard)
        .overlay(alignment: .trailing) {
            Rectangle().fill(SporaColor.borderHairline).frame(width: 1)
        }
    }

    private func section(_ title: String) -> some View {
        MicroLabel(title)
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private var emptyPlaceholder: some View {
        Text(L("empty_placeholder"))
            .sporaType(.bodySmall)
            .foregroundStyle(SporaColor.textMuted)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            footerAction(L("action_share_internet"), action: onCreateShare)
            footerAction(L("action_connect_friend"), action: onConnect)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 12, trailing: 10))
        .overlay(alignment: .top) {
            Rectangle().fill(SporaColor.borderDivider).frame(height: 1)
        }
    }

    private func footerAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SporaIcon(.plus, size: 14).foregroundStyle(SporaColor.textPrimary)
                Text(title)
                    .font(SporaFont.sans(12.5, .medium))
                    .foregroundStyle(SporaColor.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}

/// A single sidebar connection row: name ellipsizes before the shape (the dot
/// never clips), inactive rows read muted with no dot, selected rows get a
/// filled highlight.
struct SidebarRow: View {
    @EnvironmentObject var model: AppModel
    let id: String
    let name: String
    let state: DisplayState
    let role: Role

    private var isSelected: Bool { model.selectedId == id }
    private var isInactive: Bool { state == .inactive }

    var body: some View {
        Button {
            model.selectedId = id
        } label: {
            HStack(spacing: 10) {
                Text(name)
                    .font(SporaFont.sans(13, isSelected ? .semibold : .medium))
                    .foregroundStyle(isInactive && !isSelected ? SporaColor.textMuted : SporaColor.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if !isInactive {
                    StatusDot(state.shape)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(rowHighlight)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var rowHighlight: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: SporaMetrics.radiusRow)
                .fill(SporaColor.surfaceBg)
                .overlay(
                    RoundedRectangle(cornerRadius: SporaMetrics.radiusRow)
                        .strokeBorder(SporaColor.borderHairline, lineWidth: 1)
                )
        }
    }
}

/// The at-a-glance status inside the window (design 2a/2b): the down (use) line
/// and/or the up (share) line — dual role, no collapse — or АФЛАЙН.
struct AggregateStatusBlock: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let status = model.aggregateStatus
        VStack(alignment: .leading, spacing: 5) {
            if status.isOffline {
                Text(L("status_offline"))
                    .sporaType(.status)
                    .foregroundStyle(SporaColor.textMuted)
            } else {
                if let down = status.down { downLine(down) }
                if let up = status.up { upLine(up) }
            }
        }
    }

    @ViewBuilder private func downLine(_ down: DownStatus) -> some View {
        switch down {
        case .connected:
            StatusLine(dot: .active, text: "↓ " + L("st_connected"), color: SporaColor.successText)
        case .connecting:
            StatusLine(dot: .pending, text: "↓ " + L("st_connecting"), color: SporaColor.pendingText)
        }
    }

    @ViewBuilder private func upLine(_ up: UpStatus) -> some View {
        switch up {
        case let .sharing(names):
            let text = names.count <= 2
                ? Lf("st_sharing_names", names.map(upper).joined(separator: ", "))
                : Lf("st_sharing_count", names.count)
            StatusLine(dot: .active, text: "↑ " + text, color: SporaColor.successText)
        case .starting:
            StatusLine(dot: .pending, text: "↑ " + L("st_starting"), color: SporaColor.pendingText)
        }
    }
}

/// A quiet pressable row (footer actions, popover menu items).
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: SporaMetrics.radiusRow)
                    .fill(configuration.isPressed ? SporaColor.surfaceBg : .clear)
            )
    }
}
