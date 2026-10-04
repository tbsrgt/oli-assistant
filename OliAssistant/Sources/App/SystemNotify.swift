import Foundation
import UserNotifications

// MARK: - Notifications macOS (secours)
// When a reminder has no mini Oli on screen (pill not active), it goes to the Notification Center
// instead of being dropped. macOS asks the user once for permission.

enum SystemNotify {
    static func post(title: String, body: String, id: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                appendAppLog("oli.log", "Notification non affichée (refusée dans Réglages Système) : \(title)")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}
