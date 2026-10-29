import SwiftUI
import SporaKit
import SporaDesign

/// The settings pages: the list, and a page per section (Android parity:
/// `SettingsPage`). They open in the window's detail region, as a stack: the
/// sidebar's SETTINGS (⌘,) opens the list, OPEN SETTINGS under a share
/// error opens Relays alone, so back returns there.
enum SettingsPage: Equatable {
    case list, relays, telemetry

    var titleKey: String {
        switch self {
        case .list: return "settings_title_page"
        case .relays: return "settings_relays_label"
        case .telemetry: return "settings_telemetry_label"
        }
    }

    var crumbKey: String {
        switch self {
        case .list: return "settings_title"
        case .relays: return "settings_relays_header"
        case .telemetry: return "settings_telemetry_header"
        }
    }
}

// While a page is open, the service's background work (renewals, uploads) is
// re-read at this pace.
private let statusPollNanos: UInt64 = 2_000_000_000

/// The settings in the detail region: back + breadcrumb, the page's title,
/// and its content, scrolling.
struct SettingsPane: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var service: ServiceController
    let page: SettingsPage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { controller.popSettings() } label: {
                HStack(spacing: 6) {
                    SporaIcon(.chevronLeft, size: 12).foregroundStyle(SporaColor.textMuted)
                    MicroLabel(breadcrumb)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("settings_back"))

            Text(L(page.titleKey))
                .sporaType(.displayLarge)
                .foregroundStyle(SporaColor.textPrimary)
                .padding(.top, 18)

            ScrollView {
                Group {
                    switch page {
                    case .list: SettingsList()
                    case .relays: RelaySettingsPage()
                    case .telemetry: TelemetrySettingsPage()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
        }
        .padding(EdgeInsets(top: 20, leading: 30, bottom: 0, trailing: 30))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SporaColor.surfaceBg)
        .task {
            while !Task.isCancelled {
                service.refresh()
                try? await Task.sleep(nanoseconds: statusPollNanos)
            }
        }
    }

    private var breadcrumb: String {
        let pages = controller.settingsPages
        return pages.map { L($0.crumbKey) }.joined(separator: " / ")
    }
}

// MARK: - The list

private struct SettingsList: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var service: ServiceController

    var body: some View {
        VStack(spacing: 9) {
            SectionRow(icon: .relays, title: L("settings_relays_label"),
                       summary: relaysSummary, summaryIsError: !service.relaySettings.hasRelays) {
                controller.pushSettings(.relays)
            }
            SectionRow(icon: .pulse, title: L("settings_telemetry_label"), summary: telemetrySummary) {
                controller.pushSettings(.telemetry)
            }
        }
    }

    private var relaysSummary: String {
        let s = service.relaySettings
        if s.useSpora && s.own.isEmpty { return L("settings_relays_summary_spora") }
        if s.useSpora { return Lf("settings_relays_summary_spora_own", s.own.count) }
        if !s.own.isEmpty { return Lf("settings_relays_summary_own", s.own.count) }
        return L("settings_relays_summary_none")
    }

    private var telemetrySummary: String? {
        if let t = service.telemetry { return L(t.uploadEnabled ? "settings_telemetry_on" : "settings_telemetry_off") }
        if service.unavailable { return L("settings_telemetry_unavailable") }
        return nil // the service is still starting
    }
}

/// A section of the settings: its icon, name and state at a glance.
private struct SectionRow: View {
    let icon: SporaIcon.Glyph
    let title: String
    let summary: String?
    var summaryIsError = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SporaIcon(icon, size: 20).foregroundStyle(SporaColor.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(SporaFont.sans(13.5, .semibold)).foregroundStyle(SporaColor.textPrimary)
                    if let summary {
                        Text(summary).sporaType(.bodySmall)
                            .foregroundStyle(summaryIsError ? SporaColor.error : SporaColor.textMuted)
                    }
                }
                Spacer(minLength: 0)
                SporaIcon(.chevronRight, size: 16).foregroundStyle(SporaColor.textMuted)
            }
            .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .sporaCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Relays

/// Settings › Relays: which relays new links are made with. Spora's relays
/// (on by default) and the user's own are independent; a link keeps the
/// relays it was made with, so nothing here changes an existing link.
private struct RelaySettingsPage: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var service: ServiceController

    var body: some View {
        let settings = service.relaySettings
        VStack(alignment: .leading, spacing: 0) {
            Text(L("settings_relays_intro")).sporaType(.body).foregroundStyle(SporaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            sporaCard(settings).padding(.top, 16)

            MicroLabel(L("settings_own_relays_header")).padding(.top, 26)
            Text(L("settings_own_relays_intro")).sporaType(.bodySmall).foregroundStyle(SporaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(spacing: 9) {
                ForEach(Array(settings.own.enumerated()), id: \.offset) { index, relay in
                    OwnRelayRow(relay: relay,
                                onEdit: { controller.sheet = .relayEditor(index: index) },
                                onRemove: { controller.sheet = .removeRelay(index: index) })
                }
                AddRelayButton { controller.sheet = .relayEditor(index: nil) }
            }
            .padding(.top, 14)

            if !settings.hasRelays {
                StatusLine(dot: .error, text: L("settings_no_relays"), color: SporaColor.error, mono: false)
                    .padding(.top, 10)
            }

            Text(L("settings_relays_note")).sporaType(.bodySmall).foregroundStyle(SporaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
        }
        // Spora's relays on and never fetched (a fresh install, or turned on
        // after a start without them): fetch now, so the status says whether
        // they can be reached before the user makes a link. Once per page and
        // switch-on: a failure leaves this true, so it does not loop.
        .task(id: neverFetched) {
            if neverFetched { await service.fetchRelays() }
        }
    }

    private var neverFetched: Bool {
        guard service.relaySettings.useSpora, let access = service.relayAccess else { return false }
        return access.advisedRelays.isEmpty && access.lastSuccessUnixMs == nil
    }

    private func sporaCard(_ settings: RelaySettings) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Text(L("settings_spora_toggle_label")).font(SporaFont.sans(13.5, .semibold))
                    .foregroundStyle(SporaColor.textPrimary)
                Spacer(minLength: 0)
                SporaToggle(on: settings.useSpora, accessibilityLabel: L("settings_spora_toggle_label")) {
                    service.setUseSpora(!settings.useSpora)
                }
            }
            Text(L("settings_spora_toggle_hint")).sporaType(.bodySmall).foregroundStyle(SporaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.trailing, 54)
            if settings.useSpora {
                let status = sporaStatus
                StatusLine(dot: status.dot, text: status.text, color: status.color, mono: false)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .sporaCard()
    }

    /// What the state of Spora's relays tells the user: whether new links
    /// (and running shares) can use them.
    private var sporaStatus: (dot: StatusShape, text: String, color: Color) {
        let pending = (StatusShape.pending, L("settings_spora_status_checking"), SporaColor.pendingText)
        guard let access = service.relayAccess else {
            return service.unavailable
                ? (.error, L("settings_spora_status_unavailable"), SporaColor.error)
                : pending
        }
        if service.fetching { return pending }
        let now = UInt64(Date().timeIntervalSince1970 * 1000)
        let tokenValid = (access.tokenExpiresUnixMs ?? 0) > now
        if tokenValid && !access.advisedRelays.isEmpty {
            return (.active, L("settings_spora_status_ready"), SporaColor.successText)
        }
        if access.lastError != nil || service.fetchFailed {
            return (.error, L("settings_spora_status_unreachable"), SporaColor.error)
        }
        // The API answered, and gave no token (or no relays)
        if access.lastSuccessUnixMs != nil {
            return (.error, L("settings_spora_status_not_available"), SporaColor.error)
        }
        return pending
    }
}

private struct OwnRelayRow: View {
    let relay: OwnRelay
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(relay.endpoint).font(SporaFont.mono(12.5, .medium)).foregroundStyle(SporaColor.textPrimary)
                        .lineLimit(2).truncationMode(.middle)
                    MicroLabel(L(relay.token != nil ? "settings_relay_token_set" : "settings_relay_no_token"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("settings_relay_edit_action"))
            Button(action: onRemove) {
                SporaIcon(.trash, size: 15).foregroundStyle(SporaColor.textMuted)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("settings_relay_remove_content_desc"))
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 11)
        .sporaCard()
    }
}

/// Dashed like an empty list: a place for something to go.
private struct AddRelayButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SporaIcon(.plus, size: 14).foregroundStyle(SporaColor.textPrimary)
                MicroLabel(L("settings_relay_add"), color: SporaColor.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .overlay(
                RoundedRectangle(cornerRadius: SporaMetrics.radiusCard)
                    .strokeBorder(SporaColor.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Telemetry

/// Settings › Telemetry: the upload switch, what it sends and why. A refused
/// switch-off (the account requires uploads) owes the user the force notice,
/// which the controller shows.
private struct TelemetrySettingsPage: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var service: ServiceController
    @State private var switching = false
    @State private var switchFailed = false

    var body: some View {
        let status = service.telemetry
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["diagnostics_modal_what", "diagnostics_modal_why", "diagnostics_modal_off"], id: \.self) {
                    Text(L($0)).sporaType(.body).foregroundStyle(SporaColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 14) {
                Text(L("diagnostics_toggle_label")).font(SporaFont.sans(13.5, .semibold))
                    .foregroundStyle(SporaColor.textPrimary)
                Spacer(minLength: 0)
                SporaToggle(on: status?.uploadEnabled == true, enabled: status != nil,
                            accessibilityLabel: L("diagnostics_toggle_label")) {
                    flip(to: !(status?.uploadEnabled ?? false))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .sporaCard()
            .padding(.top, 24)

            statusLine.padding(.top, 10)

            if let id = status?.deviceId {
                DataField(label: L("diagnostics_device_id_label"), value: id,
                          helper: L("diagnostics_device_id_hint"))
                    .padding(.top, 22)
            }

            if let status, status.uploadEnabled || status.lastUploadUnixMs != nil {
                DataField(label: L("diagnostics_last_upload_label"),
                          value: status.lastUploadUnixMs.map { Fmt.dateTime(unixMs: $0) }
                            ?? L("diagnostics_last_upload_never"))
                    .padding(.top, 18)
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if service.telemetry == nil && service.unavailable {
            StatusLine(dot: .error, text: L("diagnostics_unavailable"), color: SporaColor.error, mono: false)
        } else if switchFailed {
            StatusLine(dot: .error, text: L("diagnostics_switch_failed"), color: SporaColor.error, mono: false)
        } else if let s = service.telemetry, s.uploadEnabled, s.lastError != nil {
            StatusLine(dot: .pending, text: L("diagnostics_upload_failed"), color: SporaColor.pendingText, mono: false)
        }
    }

    private func flip(to enabled: Bool) {
        // The guard absorbs a double click landing before the switch's new
        // state has been read back
        guard !switching else { return }
        switching = true
        Task {
            let result = await service.setUploadEnabled(enabled)
            switchFailed = result == .failed
            if result == .required { controller.showTelemetryRequired() }
            switching = false
        }
    }
}

/// A mono data value (selectable, e.g. to paste into a support mail) under a
/// micro-label.
struct DataField: View {
    let label: String
    let value: String
    var helper: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel(label)
            Text(value).font(SporaFont.mono(12.5, .medium)).foregroundStyle(SporaColor.textPrimary)
                .textSelection(.enabled)
                .padding(.top, 6)
            if let helper {
                Text(helper).sporaType(.bodySmall).foregroundStyle(SporaColor.textMuted).padding(.top, 4)
            }
        }
    }
}

// MARK: - Sheets

/// Add a relay, or edit the one at `index`.
struct RelayEditorSheet: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var service: ServiceController
    let index: Int?
    @State private var endpoint: String
    @State private var token: String
    // Errors show once the user tries to save, not while they type
    @State private var tried = false

    init(index: Int?, current: OwnRelay?) {
        self.index = current == nil ? nil : index
        _endpoint = State(initialValue: current?.endpoint ?? "")
        _token = State(initialValue: current?.token ?? "")
    }

    private var normalized: String { normalizeRelayEndpoint(endpoint) }

    private var error: RelayEndpointError? {
        if let e = relayEndpointError(normalized) { return e }
        // Every relay but the one being edited
        let others = service.relaySettings.own.enumerated().filter { $0.offset != index }.map(\.element.endpoint)
        return others.contains(normalized) ? .duplicate : nil
    }

    var body: some View {
        SheetBody {
            MicroLabel(L(index == nil ? "settings_relay_add_header" : "settings_relay_edit_header"))
            Text(L("settings_relay_modal_title")).sporaType(.display).foregroundStyle(SporaColor.textPrimary)
                .padding(.top, 8)
            InputField(label: L("settings_relay_address_label"), placeholder: L("settings_relay_address_placeholder"),
                       text: $endpoint, helper: L("settings_relay_address_helper"),
                       error: tried ? error.map { L(Self.messageKey($0)) } : nil, mono: true)
                .padding(.top, 20)
            InputField(label: L("settings_relay_token_label"), placeholder: L("settings_relay_token_placeholder"),
                       text: $token, helper: L("settings_relay_token_helper"), mono: true)
                .padding(.top, 20)
            VStack(spacing: 2) {
                SporaButton(L("action_save"), variant: .primary, action: save)
                    .disabled(endpoint.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(endpoint.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                SporaButton(L("cancel"), variant: .text) { controller.sheet = nil }
            }
            .padding(.top, 24)
        }
    }

    private func save() {
        tried = true
        guard error == nil else { return }
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        service.putRelay(OwnRelay(endpoint: normalized, token: t.isEmpty ? nil : t), at: index)
        controller.sheet = nil
    }

    static func messageKey(_ e: RelayEndpointError) -> String {
        switch e {
        case .format: return "settings_relay_error_format"
        case .unknownProtocol: return "settings_relay_error_protocol"
        case .ipv6Brackets: return "settings_relay_error_ipv6"
        case .port: return "settings_relay_error_port"
        case .duplicate: return "settings_relay_error_duplicate"
        }
    }
}

struct RemoveRelaySheet: View {
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var service: ServiceController
    let index: Int

    var body: some View {
        SheetBody {
            MicroLabel(L("settings_relay_remove_header"))
            Text(L("delete_modal_title")).sporaType(.display).foregroundStyle(SporaColor.textPrimary)
                .padding(.top, 8)
            if let relay = service.relaySettings.own[safe: index] {
                Text(relay.endpoint).font(SporaFont.mono(12.5, .medium)).foregroundStyle(SporaColor.textPrimary)
                    .padding(.top, 10)
            }
            Text(L("settings_relay_remove_message")).sporaType(.body).foregroundStyle(SporaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            VStack(spacing: 2) {
                SporaButton(L("action_delete"), variant: .primary) {
                    service.removeRelay(at: index)
                    controller.sheet = nil
                }
                SporaButton(L("cancel"), variant: .text) { controller.sheet = nil }
            }
            .padding(.top, 24)
        }
    }
}

/// The force notice: the account requires uploads, so the switch stays on.
/// Shown when the user tries to switch off, and once when the flag arrives.
struct TelemetryRequiredSheet: View {
    @EnvironmentObject var controller: AppController

    var body: some View {
        SheetBody {
            MicroLabel(L("telemetry_required_header"))
            Text(L("telemetry_required_title")).sporaType(.display).foregroundStyle(SporaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text(L("telemetry_required_message")).sporaType(.body).foregroundStyle(SporaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            VStack(spacing: 2) {
                SporaButton(L("telemetry_required_keep"), variant: .primary) {
                    controller.dismissTelemetryRequired(contactSupport: false)
                }
                SporaButton(L("telemetry_required_contact"), variant: .text) {
                    controller.dismissTelemetryRequired(contactSupport: true)
                }
            }
            .padding(.top, 24)
        }
    }
}

/// The common frame of the window's sheets (design 1g).
struct SheetBody<Content: View>: View {
    var width: CGFloat = 400
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(width: width, alignment: .leading)
            .background(SporaColor.surfaceCard)
            .environment(\.colorScheme, .light)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
