import SwiftUI
import SporaKit
import SporaDesign

/// The master-detail window (committed direction 1b): sidebar (both connection
/// lists + aggregate status + footer actions) on the left, the status detail
/// surface on the right. Hidden title bar — the sidebar runs full height under
/// the traffic lights.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var controller: AppController

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(onCreateShare: controller.beginCreateShare, onConnect: controller.beginConnect)
            detailRegion
        }
        .frame(width: SporaMetrics.windowWidth, height: SporaMetrics.windowHeight)
        .background(SporaColor.surfaceBg)
        .environment(\.colorScheme, .light) // design is light-theme only
        .sheet(isPresented: saveSheetPresented) {
            if case let .saveConnection(prefill) = controller.flow {
                SaveConnectionSheet(prefillURL: prefill)
            }
        }
    }

    @ViewBuilder private var detailRegion: some View {
        if case let .createShare(handoff) = controller.flow {
            CreateShareView(handoff: handoff)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SporaColor.surfaceBg)
        } else {
            DetailPane()
        }
    }

    private var saveSheetPresented: Binding<Bool> {
        Binding(
            get: { if case .saveConnection = controller.flow { return true } else { return false } },
            set: { presented in if !presented { controller.dismissFlow() } }
        )
    }
}
