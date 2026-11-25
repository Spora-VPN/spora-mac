#if SPORA_DIRECT
import SwiftUI
import Sparkle

/// The direct build's updates (ADR-002 D4): Sparkle 2 against the appcast the
/// Info.plist names (`SUFeedURL`), every update signed with the EdDSA key in
/// `SUPublicEDKey`. It checks daily without asking, and asks before it
/// installs: Sparkle's own window (release notes, Install / Later / Skip).
/// The App Store build has no updater, and does not link Sparkle.
///
/// After an update the relaunched app replaces the system extension macOS
/// still runs (`TunnelManager.replaceOutdatedExtension`).
@MainActor
final class Updater: ObservableObject {
    /// Started at launch (`SporaApp.init`), so the daily check runs whether
    /// or not the window is open.
    static let shared = Updater()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var canCheckForUpdates = false

    private init() {
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// The menu's Check for Updates…: Sparkle's window, whatever it finds.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

#if DEBUG
    /// The harness's `updates?do=accept`: press the default button of
    /// Sparkle's frontmost window (Install Update, then Install and
    /// Relaunch), as the user would. Returns the button's title.
    func pressDefaultButton() -> String? {
        for window in NSApp.orderedWindows where window.isVisible {
            guard let wc = window.windowController,
                  NSStringFromClass(type(of: wc)).hasPrefix("SU") else { continue }
            let buttons = Self.buttons(in: window.contentView).filter { $0.isEnabled && !$0.isHidden }
            guard let button = buttons.first(where: { $0.keyEquivalent == "\r" })
                    ?? (buttons.count == 1 ? buttons.first : nil) else { continue }
            button.performClick(nil)
            return button.title
        }
        return nil
    }

    private static func buttons(in view: NSView?) -> [NSButton] {
        guard let view else { return [] }
        let own = (view as? NSButton).map { [$0] } ?? []
        return own + view.subviews.flatMap { buttons(in: $0) }
    }
#endif
}

/// Check for Updates… in the app menu, after About.
struct UpdateCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton(updater: .shared)
        }
    }
}

private struct CheckForUpdatesButton: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Button(L("menu_check_updates")) { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
#endif
