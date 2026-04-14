import Foundation
import UserNotifications

// MARK: - Notification Manager

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    @Published var isAuthorized = false

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            print("Notification auth failed: \(error)")
        }
    }

    // MARK: - Workout Reminders

    /// Schedule a reminder if the user hasn't worked out in `days` days.
    func scheduleInactivityReminder(lastWorkoutDate: Date?, daysThreshold: Int = 3) {
        guard let last = lastWorkoutDate else {
            scheduleReminder(
                id: "inactivity",
                title: "Time to start training!",
                body: "Open ZoneTracker and log your first workout.",
                delay: 24 * 3600
            )
            return
        }

        let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        guard daysSince >= daysThreshold else {
            // Not inactive yet — cancel any pending reminder
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["inactivity"])
            return
        }

        scheduleReminder(
            id: "inactivity",
            title: "Missing your workouts",
            body: "It's been \(daysSince) days since your last session. A quick Zone 2 walk keeps the momentum going.",
            delay: 3600 // 1 hour from now
        )
    }

    // MARK: - Focus Celebration

    func sendPhaseCelebration(phase: TrainingPhase) {
        let focus = phase.toFocus
        let body: String
        switch focus {
        case .activeRecovery:
            body = "Welcome back! Let's rebuild your rhythm together."
        case .buildingBase:
            body = "Building your aerobic base. Consistency is everything right now."
        case .developingSpeed:
            body = "Your base is solid — time to add speed work and intervals."
        case .peakPerformance:
            body = "Peak performance unlocked. You've earned this."
        }

        scheduleReminder(
            id: "focus_\(focus.rawValue)",
            title: "Training Focus Advanced",
            body: body,
            delay: 1 // immediate
        )
    }

    // MARK: - Weekly Summary

    func scheduleWeeklySummary(sessionsCompleted: Int, target: Int) {
        let remaining = target - sessionsCompleted
        guard remaining > 0 else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["weekly_summary"])
            return
        }

        // Schedule for Sunday at 10am
        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour = 10

        let content = UNMutableNotificationContent()
        content.title = "Weekly Check-in"
        content.body = "\(sessionsCompleted)/\(target) sessions done this week. \(remaining) more to hit your target!"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "weekly_summary", content: content, trigger: trigger)

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["weekly_summary"])
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private func scheduleReminder(id: String, title: String, body: String, delay: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().add(request)
    }
}
