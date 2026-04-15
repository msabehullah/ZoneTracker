import Foundation
import SwiftData
import Combine
import WidgetKit

// MARK: - Dashboard ViewModel

@MainActor
@Observable
class DashboardViewModel {
    var nextRecommendation: WorkoutRecommendation?
    var currentPlan: WorkoutExecutionPlan?
    var sessionsThisWeek: Int = 0
    var targetSessionsThisWeek: Int = 3
    var totalSessions: Int = 0
    var currentStreak: Int = 0
    var bestMileTime: String = "—"
    var restingHRData: [(date: Date, bpm: Int)] = []
    var focusTransitionMessage: String?

    private let healthKit = HealthKitManager.shared

    func load(profile: UserProfile, workouts: [WorkoutEntry]) {
        // Check for focus transition first (does not mutate profile)
        if let transition = PhaseManager.evaluatePhaseTransition(
            profile: profile, workouts: workouts
        ) {
            PhaseManager.applyTransition(transition, to: profile)
            focusTransitionMessage = transition.message
        } else {
            focusTransitionMessage = nil
        }

        // Generate recommendation (now reflects any transition that just occurred)
        nextRecommendation = RecommendationEngine.recommend(profile: profile, workouts: workouts)
        currentPlan = nextRecommendation.map {
            WorkoutPlanningService.plan(
                from: $0,
                profile: profile,
                accountIdentifier: profile.accountIdentifier
            )
        }

        // Session counts
        sessionsThisWeek = workouts.inCurrentWeek().count
        targetSessionsThisWeek = profile.effectiveSessionsPerWeek
        totalSessions = workouts.count

        // Streak
        currentStreak = calculateStreak(workouts: workouts)

        // Best mile time
        bestMileTime = findBestMileTime(workouts: workouts)

        // Update widget data
        updateWidgetData(profile: profile)

        let companionProfile = WorkoutPlanningService.companionProfile(
            from: profile,
            accountIdentifier: profile.accountIdentifier
        )
        if let currentPlan {
            ConnectivityManager.shared.sendWorkoutPlan(currentPlan, profile: companionProfile)
        } else {
            ConnectivityManager.shared.sendCompanionProfile(companionProfile)
        }

        // Update notification reminders
        NotificationManager.shared.scheduleInactivityReminder(
            lastWorkoutDate: workouts.first?.date
        )
        NotificationManager.shared.scheduleWeeklySummary(
            sessionsCompleted: sessionsThisWeek,
            target: targetSessionsThisWeek
        )
    }

    func sendPlanToWatch(profile: UserProfile) {
        guard let currentPlan else { return }
        ConnectivityManager.shared.sendWorkoutPlan(
            currentPlan,
            profile: WorkoutPlanningService.companionProfile(
                from: profile,
                accountIdentifier: profile.accountIdentifier
            )
        )
    }

    private func updateWidgetData(profile: UserProfile) {
        let defaults = UserDefaults(suiteName: "group.com.zonetracker.app")
        defaults?.set(profile.focus.displayName, forKey: "widget_phase")
        defaults?.set(profile.weekNumber, forKey: "widget_weekNumber")
        defaults?.set(sessionsThisWeek, forKey: "widget_sessionsThisWeek")
        defaults?.set(targetSessionsThisWeek, forKey: "widget_targetSessions")
        defaults?.set(nextRecommendation?.sessionType.coachingLabel ?? "Target Zone", forKey: "widget_nextSessionType")
        defaults?.set(nextRecommendation?.targetDurationMinutes ?? 30, forKey: "widget_nextDuration")
        WidgetCenter.shared.reloadAllTimelines()
    }

    func loadRestingHR() async {
        do {
            restingHRData = try await healthKit.fetchRestingHeartRate(days: 60)
        } catch {
            // Silently fail — resting HR is supplementary
        }
    }

    private func calculateStreak(workouts: [WorkoutEntry]) -> Int {
        let calendar = Calendar.current
        let sorted = workouts.sorted { $0.date > $1.date }
        guard !sorted.isEmpty else { return 0 }

        var streak = 0
        var checkDate = Date().startOfWeek

        while true {
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: checkDate) ?? checkDate
            let hasWorkout = sorted.contains { $0.date >= checkDate && $0.date < weekEnd }
            if hasWorkout {
                streak += 1
                checkDate = calendar.date(byAdding: .weekOfYear, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }

        return streak
    }

    private func findBestMileTime(workouts: [WorkoutEntry]) -> String {
        let benchmarks = workouts.filter { $0.sessionType == .benchmark_mile }
        guard let best = benchmarks.min(by: { $0.duration < $1.duration }) else { return "—" }
        let minutes = Int(best.duration) / 60
        let seconds = Int(best.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
