import SwiftUI
import SporaKit
import SporaDesign

@main
struct SporaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    @StateObject private var service: ServiceController
    @StateObject private var controller: AppController

    init() {
        // Before anything logs: the diagnostic log file, and crash capture
        SporaKit.initLogging()
        CrashCapture.install()
        let model = AppModel()
        let service = ServiceController()
        _model = StateObject(wrappedValue: model)
        _service = StateObject(wrappedValue: service)
        _controller = StateObject(wrappedValue: AppController(model: model, service: service))
        // Off the main thread: the device identity, relay access, uploads
        service.start()
        AppDelegate.networkReporter.start()
    }

    var body: some Scene {
        Window("Spora", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(controller)
                .environmentObject(service)
                .onOpenURL { handleURL($0) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    service.onForeground()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands { SporaCommands(controller: controller) }

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
            NSApp.activate(ignoringOtherApps: true)
            controller.handleDeepLink(url)
        default:
            break
        }
    }
}

/// Settings… (⌘,) opens the settings in the window, as the design's menu
/// has it; Send Feedback… sits in Help.
struct SporaCommands: Commands {
    let controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(L("menu_settings")) {
                openMain()
                controller.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .help) {
            Button(L("menu_feedback")) {
                openMain()
                controller.openFeedback()
            }
        }
    }

    private func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Tells the core which network is under the app's shares.
    static let networkReporter = NetworkReporter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        SporaDesign.registerFonts()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // menu-bar presence persists after the window closes
    }
}

/// Uncaught Objective-C exceptions (AppKit's) go to a crash file before the
/// process dies, for the next bug report and upload. The core's own panics
/// have their hook; Swift traps leave a system crash report only.
enum CrashCapture {
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            writeCrash(source: "objc",
                       text: "Uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")\n\(stack)")
        }
    }
}
