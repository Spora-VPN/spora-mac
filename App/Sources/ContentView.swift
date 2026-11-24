import SwiftUI
import SporaKit
import SporaDesign

/// The master-detail window (committed direction 1b): sidebar (both connection
/// lists + aggregate status + footer actions) on the left, the status detail
/// surface on the right. Hidden title bar — the sidebar runs full height under
/// the traffic lights. The detail region also hosts the settings pages and
/// the create-share flow; modal steps are native sheets.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var controller: AppController
    @EnvironmentObject var service: ServiceController

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(onCreateShare: controller.beginCreateShare, onConnect: controller.beginConnect)
            detailRegion
        }
        .frame(width: SporaMetrics.windowWidth, height: SporaMetrics.windowHeight)
        .background(SporaColor.surfaceBg)
        .environment(\.colorScheme, .light) // design is light-theme only
        .sheet(item: $controller.sheet) { sheet in
            sheetContent(sheet)
                .environmentObject(model)
                .environmentObject(controller)
                .environmentObject(service)
        }
        // The force notice is owed once when the account's flag arrives; it
        // waits for whatever sheet is open
        .onChange(of: noticeDue) { due in
            if due { controller.offerTelemetryNotice() }
        }
        .onChange(of: controller.sheet == nil) { idle in
            if idle && noticeDue { controller.offerTelemetryNotice() }
        }
    }

    private var noticeDue: Bool { service.telemetry?.requiredNoticePending == true }

    @ViewBuilder private var detailRegion: some View {
        if let page = controller.settingsPages.last {
            SettingsPane(page: page)
                .id(page)
        } else if case let .createShare(stage) = controller.flow {
            CreateShareView(stage: stage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SporaColor.surfaceBg)
        } else {
            DetailPane()
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: AppController.Sheet) -> some View {
        switch sheet {
        case .saveConnection(let prefill):
            SaveConnectionSheet(prefillURL: prefill)
        case .relayEditor(let index):
            RelayEditorSheet(index: index, current: index.flatMap { service.relaySettings.own[safe: $0] })
        case .removeRelay(let index):
            RemoveRelaySheet(index: index)
        case .feedback:
            FeedbackSheet()
        case .telemetryRequired:
            TelemetryRequiredSheet()
        case .approveExtension:
            ApproveExtensionSheet()
        }
    }
}
