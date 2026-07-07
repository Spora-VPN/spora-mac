import SwiftUI
import SporaKit
import SporaDesign

@main
struct SporaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    @StateObject private var controller: AppController

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        _controller = StateObject(wrappedValue: AppController(model: model))
    }

    var body: some Scene {
        Window("Spora", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(controller)
                .onOpenURL { handleURL($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarPopover()
                .environmentObject(model)
                .environmentObject(controller)
        } label: {
            MenuBarLabel(state: model.menuBarState)
        }
        .menuBarExtraStyle(.window)
    }

    private func handleURL(_ url: URL) {
        switch url.scheme {
        case "spora-debug":
            #if DEBUG
            DebugController.handle(url, model: model, controller: controller)
            #endif
        case "spora", "https":
            // Deep link (spora://s/<token> or universal link) — wired in the
            // deep-link phase.
            NSLog("[spora] open url: \(url)")
        default:
            break
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SporaDesign.registerFonts()
        SporaKit.initLogging()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // menu-bar presence persists after the window closes
    }
}
