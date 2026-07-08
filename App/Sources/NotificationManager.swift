import Foundation
import AppKit
import UserNotifications
import SporaKit

/// Posts the three notification families from design 1f: sharing started (Stop
/// all), connected, and the persistent connection-lost error (Retry / Close).
/// Only real events (routed through `AppController`) post — the debug harness
/// mutates the model directly, so screenshot runs stay quiet.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private weak var controller: AppController?
    private let center = UNUserNotificationCenter.current()

    private enum ID {
        static let sharing = "sharing"
        static let connected = "connected"
        static func lost(_ useId: String) -> String { "lost.\(useId)" }
    }
    private enum Category {
        static let sharing = "sharing"
        static let connectError = "connect_error"
    }

    func configure(controller: AppController) {
        self.controller = controller
        center.delegate = self
        registerCategories()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func registerCategories() {
        let stopAll = UNNotificationAction(identifier: "STOP_ALL", title: L("notif_stop_all"), options: [.destructive])
        let sharing = UNNotificationCategory(identifier: Category.sharing, actions: [stopAll], intentIdentifiers: [])
        let retry = UNNotificationAction(identifier: "RETRY", title: L("notif_retry"), options: [])
        let close = UNNotificationAction(identifier: "CLOSE", title: L("notif_close"), options: [])
        let error = UNNotificationCategory(identifier: Category.connectError, actions: [retry, close], intentIdentifiers: [])
        center.setNotificationCategories([sharing, error])
    }

    // MARK: - Posts

    /// Reflect the current set of active shares (or clear when none).
    func updateSharing(names: [String]) {
        guard !names.isEmpty else {
            center.removeDeliveredNotifications(withIdentifiers: [ID.sharing]); return
        }
        let c = content(L("notif_sharing_title"), Lf("notif_sharing_body", names.map { "«\($0)»" }.joined(separator: ", ")))
        c.categoryIdentifier = Category.sharing
        post(ID.sharing, c)
    }

    func connected(name: String) {
        post(ID.connected, content(L("notif_connected_title"), Lf("notif_connected_body", "«\(name)»")))
    }

    func connectionLost(useId: String, name: String) {
        let c = content(L("notif_lost_title"), Lf("notif_lost_body", "«\(name)»"))
        c.categoryIdentifier = Category.connectError
        c.userInfo = ["useId": useId]
        post(ID.lost(useId), c) // stable id → persists, replaces a prior one
    }

    private func content(_ title: String, _ body: String) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        return c
    }

    private func post(_ id: String, _ content: UNMutableNotificationContent) {
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: - Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound]) // show even when Spora is frontmost
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler handler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let useId = response.notification.request.content.userInfo["useId"] as? String
        Task { @MainActor in
            switch action {
            case "STOP_ALL": self.controller?.stopAllShares()
            case "RETRY": if let useId { self.controller?.toggleUse(useId) }
            case "CLOSE": break
            case UNNotificationDefaultActionIdentifier: NSApp.activate(ignoringOtherApps: true)
            default: break
            }
            handler()
        }
    }
}
