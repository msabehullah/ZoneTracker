import Foundation

// MARK: - Phase Manager

struct PhaseManager {

    /// Evaluate whether the user should transition to the next phase.
    /// Returns a message if a transition is triggered, nil otherwise.
    static func evaluatePhaseTransition(
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> String? {
        switch profile.phase {
        case .phase1:
            return evaluatePhase1to2(profile: profile, workouts: workouts)
        case .phase2:
            return evaluatePhase2to3(profile: profile, workouts: workouts)
        case .phase3:
            return nil // Final phase
        }
    }

    // MARK: - Phase 1 → Phase 2

    /// Criteria: sustain 45+ min Zone 2 with stable HR (drift <5%) for 2 consecutive weeks,
    /// AND at least 6 weeks in Phase 1.
    private static func evaluatePhase1to2(
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> String? {
        guard profile.weekNumber >= profile.phase.minimumWeeks else { return nil }

        let phase1Workouts = workouts.inPhase(.phase1).zone2Sessions()
        let recentWeeks = lastNWeeks(2, from: phase1Workouts)

        // Need qualifying sessions in both of the last 2 weeks
        guard recentWeeks.count == 2 else { return nil }

        for weekWorkouts in recentWeeks {
            let qualifying = weekWorkouts.filter { workout in
                workout.duration >= 45 * 60 && // 45+ minutes
                workout.heartRateData.hrDrift < 5.0 // Stable HR
            }
            guard !qualifying.isEmpty else { return nil }
        }

        return """
        🎉 Phase 1 Complete! You've built a solid aerobic base — sustaining 45+ minutes \
        in Zone 2 with stable heart rate for 2 consecutive weeks. Time to introduce \
        intervals! Phase 2 keeps your Zone 2 sessions and adds one interval workout per week.
        """
    }

    // MARK: - Phase 2 → Phase 3

    /// Criteria: complete 12+ interval rounds at target HR AND Zone 2 pace improvement
    /// AND at least 6 weeks in Phase 2.
    private static func evaluatePhase2to3(
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> String? {
        guard profile.weekNumber >= profile.phase.minimumWeeks else { return nil }

        let phase2Workouts = workouts.inPhase(.phase2)
        let intervalWorkouts = phase2Workouts.intervalSessions()

        // Check if any interval session hit 12+ rounds
        let hasHighRoundCount = intervalWorkouts.contains { workout in
            guard let proto = workout.intervalProtocol else { return false }
            return proto.rounds >= 12
        }

        guard hasHighRoundCount else { return nil }

        // Check Zone 2 pace improvement: compare earliest vs latest treadmill Z2 sessions
        let treadmillZ2 = phase2Workouts.zone2Sessions()
            .filter { $0.exerciseType == .treadmill }
            .sorted { $0.date < $1.date }

        if treadmillZ2.count >= 4 {
            let earlySpeed = treadmillZ2.prefix(2).compactMap { $0.metrics["speed"] }.reduce(0, +) / 2
            let lateSpeed = treadmillZ2.suffix(2).compactMap { $0.metrics["speed"] }.reduce(0, +) / 2
            guard lateSpeed > earlySpeed else { return nil }
        }

        return """
        🔥 Phase 2 Complete! Your interval capacity has grown significantly — 12+ rounds \
        at target heart rate — and your aerobic base continues to improve. Phase 3 unlocks \
        VO2 max training: Norwegian 4×4s, Tabata, and long intervals. Get ready to push \
        your ceiling!
        """
    }

    // MARK: - Consistency Check

    /// Returns the number of sessions completed in the current week
    static func sessionsThisWeek(workouts: [WorkoutEntry]) -> Int {
        workouts.inCurrentWeek().count
    }

    /// Returns true if user missed 2+ sessions last week relative to target
    static func missedSessionsLastWeek(
        workouts: [WorkoutEntry],
        profile: UserProfile
    ) -> Bool {
        let calendar = Calendar.current
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: Date().startOfWeek) ?? Date()
        let lastWeekEnd = Date().startOfWeek

        let lastWeekWorkouts = workouts.filter {
            $0.date >= lastWeekStart && $0.date < lastWeekEnd
        }

        let target = profile.phase.targetSessionsPerWeek
        let completed = lastWeekWorkouts.count
        return (target - completed) >= 2
    }

    // MARK: - Helpers

    /// Group workouts into the last N weeks, returning an array of arrays
    private static func lastNWeeks(_ n: Int, from workouts: [WorkoutEntry]) -> [[WorkoutEntry]] {
        let calendar = Calendar.current
        var result: [[WorkoutEntry]] = []

        for i in 0..<n {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -(i), to: Date().startOfWeek) ?? Date()
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? Date()
            let weekWorkouts = workouts.filter { $0.date >= weekStart && $0.date < weekEnd }
            result.append(weekWorkouts)
        }

        return result
    }
}
