import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private(set) var authorized = false

    func requestAuthorization() async {
        switch await Self.authorizationStatus() {
        case .authorized, .provisional: authorized = true
        case .notDetermined:
            authorized = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        default: authorized = false
        }
    }

    /// UNNotificationSettings is not Sendable on older SDKs, so it is read off the main actor and only the status comes back.
    nonisolated private static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func deliver(title: String, body: String, id: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
