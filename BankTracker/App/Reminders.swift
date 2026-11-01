import Foundation
import UserNotifications
import BankTrackerCore

/// Default reminder settings; the user changes them in Settings → Reminders.
enum ReminderDefaults {
    static let enabled = true
    /// 9:00 AM, in minutes after midnight.
    static let minuteOfDay = 9 * 60
    static let leadDays = 3
}

/// The page a tapped reminder opens.
nonisolated enum ReminderTarget: Equatable, Sendable {
    case account(UUID)
    case offer(UUID)
}

/// Keeps the system's scheduled notifications in step with the reminders `ReminderPlanner`
/// works out, and opens the right page when one is tapped.
final class ReminderNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderNotifications()

    /// Sample data lives only in memory, so a demo launch leaves the real reminders alone.
    static var isActiveForThisLaunch: Bool {
        !ProcessInfo.processInfo.arguments.contains("--demo")
    }

    /// Opens a tapped reminder's page. The root view sets it; a tap that arrives first, when a
    /// reminder launches the app, waits until then.
    var open: ((ReminderTarget) -> Void)? {
        didSet {
            if let open, let waiting {
                self.waiting = nil
                open(waiting)
            }
        }
    }
    private var waiting: ReminderTarget?

    /// Call at launch, so a tap that launched the app is delivered here.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Replaces every scheduled reminder with `reminders`; with reminders off, just clears them.
    /// The first time there's something to schedule, it asks for permission to notify.
    func schedule(_ reminders: [Reminder], enabled: Bool, askPermission: Bool = true) async {
        let center = UNUserNotificationCenter.current()
        guard enabled, !reminders.isEmpty else {
            center.removeAllPendingNotificationRequests()
            return
        }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined, askPermission {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        // A newer schedule replaced this one while waiting for permission.
        guard !Task.isCancelled else { return }

        center.removeAllPendingNotificationRequests()
        // The system refuses reminders without permission. If notifications are turned on later,
        // the root view schedules again when the app next becomes active.
        guard status != .denied, status != .notDetermined else { return }
        for reminder in reminders {
            guard !Task.isCancelled else { return }
            try? await center.add(request(for: reminder))
        }
    }

    private func request(for reminder: Reminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        var info: [String: String] = [:]
        if let id = reminder.accountID {
            info["accountID"] = id.uuidString
            content.threadIdentifier = id.uuidString
        }
        if let id = reminder.offerID {
            info["offerID"] = id.uuidString
            content.threadIdentifier = id.uuidString
        }
        content.userInfo = info

        let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }

    private func deliver(_ target: ReminderTarget) {
        if let open {
            open(target)
        } else {
            waiting = target
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shows reminders even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let target: ReminderTarget?
        if let id = (info["accountID"] as? String).flatMap(UUID.init(uuidString:)) {
            target = .account(id)
        } else if let id = (info["offerID"] as? String).flatMap(UUID.init(uuidString:)) {
            target = .offer(id)
        } else {
            target = nil
        }
        guard let target else { return }
        await MainActor.run { ReminderNotifications.shared.deliver(target) }
    }
}
