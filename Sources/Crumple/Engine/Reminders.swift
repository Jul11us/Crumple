import Foundation
import UserNotifications

/// Gentle reminders: when the disk is nearly full, and (if the user wants) once a week to clean up.
/// They are only checked while Crumple is running, e.g. from the menu bar.
@MainActor
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    /// Called when a reminder is clicked.
    var onOpen: (() -> Void)?

    private var task: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    /// Notifications only work from inside an app bundle; a bare development binary would crash.
    private var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func start(check: @escaping @MainActor () -> Void) {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().delegate = self
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(90))
            while !Task.isCancelled {
                check()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    /// Asks macOS for permission the first time a reminder is switched on.
    func requestPermission() async -> Bool {
        guard isAvailable else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isDenied() async -> Bool {
        guard isAvailable else { return false }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Posts at most once per `every` seconds for each kind of reminder.
    func post(_ kind: String, title: String, body: String, every interval: TimeInterval) {
        guard isAvailable else { return }
        let key = "lastReminder.\(kind)"
        if let last = defaults.object(forKey: key) as? Date, Date().timeIntervalSince(last) < interval { return }
        defaults.set(Date(), forKey: key)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: kind, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { onOpen?() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
