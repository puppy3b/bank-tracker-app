import SwiftUI
import UserNotifications

/// Settings → Reminders: whether to notify, at what time, and how much notice to give.
struct ReminderSettingsSection: View {
    @AppStorage(SettingsKey.remindersEnabled) private var enabled = ReminderDefaults.enabled
    @AppStorage(SettingsKey.reminderMinuteOfDay) private var minuteOfDay = ReminderDefaults.minuteOfDay
    @AppStorage(SettingsKey.reminderLeadDays) private var leadDays = ReminderDefaults.leadDays
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationsDenied = false

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                Label("Deadline reminders", systemImage: "bell")
            }
            if enabled {
                DatePicker("Remind me at", selection: time, displayedComponents: .hourAndMinute)
                Stepper(value: $leadDays, in: 0...14) {
                    Text(noticeText)
                }
                if notificationsDenied {
                    Button("Turn On Notifications…", systemImage: "gear") { openURL(Self.notificationSettingsURL) }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text(footer)
        }
        // Checked again on returning to the app, in case notifications were turned on meanwhile.
        .task(id: scenePhase) {
            notificationsDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        }
    }

    private var noticeText: String {
        switch leadDays {
        case 0: "On the day only"
        case 1: "1 day's notice, and on the day"
        default: "\(leadDays) days' notice, and on the day"
        }
    }

    private var footer: String {
        var text = "A notification when a requirement is coming due, when money on hold can come out, when an account can be closed without a penalty, when a bonus is late, and before an offer ends. Reminders whose time has passed are skipped."
        if enabled, notificationsDenied {
            text += " Notifications are turned off for Bank Tracker, so none will show until you turn them on."
        }
        return text
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: .now) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minuteOfDay = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private static var notificationSettingsURL: URL {
        #if os(iOS)
        URL(string: UIApplication.openNotificationSettingsURLString)!
        #else
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        #endif
    }
}
