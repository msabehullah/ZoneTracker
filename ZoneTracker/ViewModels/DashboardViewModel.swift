import Foundation
import SwiftData
import Combine

// MARK: - Dashboard ViewModel

@MainActor
@Observable
class DashboardViewModel {
    var nextRecommendation: WorkoutRecommendation?
    var sessionsThisWeek: Int = 0
    var targetSessionsThisWeek: Int = 3
    var totalSessions: Int = 0
    var currentStreak: Int = 0
    var bestMileTime: String = "—"
    var restingHRData: [(date: Date, bpm: Int)] = []
    var phaseTransitionMessage: String?

    private let healthKit = HealthKitManager.shared

    func load(profile: UserProfile, workouts: [WorkoutEntry]) {
        // Generate recommendation
        nextRecommendation = RecommendationEngine.recommend(profile: profile, workouts: workouts)

        // Session counts
        sessionsThisWeek = workouts.inCurrentWeek().count
        targetSessionsThisWeek = profile.phase.targetSessionsPerWeek
        totalSessions = workouts.count

        // Streak
        currentStreak = calculateStreak(workouts: workouts)

        // Best mile time
        bestMileTime = findBestMileTime(workouts: workouts)

        // Phase transition check
        phaseTransitionMessage = PhaseManager.evaluatePhaseTransition(
            profile: profile, workouts: workouts
        )
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

        // Check each week backwards — did they have at least 1 session?
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
