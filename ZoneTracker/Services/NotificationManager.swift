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

    // MARK: - Phase Celebration

    func sendPhaseCelebration(phase: TrainingPhase) {
        let body: String
        switch phase {
        case .phase1:
            body = "You've started Phase 1 — Aerobic Base Building. Consistency is everything right now."
        case .phase2:
            body = "Phase 2 unlocked! Your aerobic base is solid. Time to introduce intervals."
        case .phase3:
            body = "Welcome to Phase 3 — VO2 Max Development. You've earned this."
        }

        scheduleReminder(
            id: "phase_\(phase.rawValue)",
            title: "Phase Advancement",
            body: body,
            delay: 1 // immediate
        )
    }

    // MARK: - Weekly Summary

    func scheduleWeeklySummary(sessionsCompleted: Int, target: Int) {
        let remaining = target - sessionsCompleted
        guard remaining > 0 else { return }

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

        UNUserNotificationCenter.current().add(request)
    }
}
