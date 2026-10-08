import Foundation
import UserNotifications

/// Posts a native notification when a transfer finishes. Uses UNUserNotificationCenter,
/// so it respects Focus modes and Do Not Disturb automatically.
final class Notifier {
    static let shared = Notifier()
    private var authorized = false

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.authorized = granted
        }
    }

    func notifyCompleted(_ transfer: Transfer) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Download finished"
            content.body = transfer.name
            content.sound = .default
            let request = UNNotificationRequest(identifier: transfer.id, content: content, trigger: nil)
            center.add(request)
        }
    }
}
