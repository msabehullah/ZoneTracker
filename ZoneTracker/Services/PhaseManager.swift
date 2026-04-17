import Foundation

// MARK: - Phase Manager

struct FocusTransition {
    let newFocus: TrainingFocus
    let message: String
}

struct PhaseManager {

    /// Evaluate whether the user should transition to the next focus.
    /// Returns a transition result if criteria are met, nil otherwise.
    /// Does NOT mutate the profile — callers must apply the transition.
    static func evaluatePhaseTransition(
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> FocusTransition? {
        switch profile.focus {
        case .activeRecovery:
            return evaluateRecoveryToBase(profile: profile, workouts: workouts)
        case .buildingBase:
            return evaluateBaseToSpeed(profile: profile, workouts: workouts)
        case .developingSpeed:
            return evaluateSpeedToPeak(profile: profile, workouts: workouts)
        case .peakPerformance:
            return nil
        }
    }

    /// Apply a transition to a profile. Single point of mutation.
    static func applyTransition(_ transition: FocusTransition, to profile: UserProfile) {
        profile.focus = transition.newFocus
        profile.phaseStartDate = Date()
    }

    // MARK: - Recovery → Building Base

    private static func evaluateRecoveryToBase(
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> FocusTransition? {
        guard profile.weekNumber >= profile.focus.minimumWeeks else { return nil }

        let recentWorkouts = workouts.inCurrentWeek()
        guard recentWorkouts.count >= 2 else { return nil }

        return FocusTransition(
            newFocus: .buildingBase,
            message: """
            You've rebuilt a consistent rhythm — great work. \
            Your focus is shifting to building a stronger aerobic base. \
            Keep showing up and your engine will grow.
            """
        )
    }

    // MARK: - Building Base → Developing Speed

    /// Criteria: sustain 45+ min in target zone with stable HR (drift <5%) for 2 consecutive weeks,
    /// AND at least the minimum weeks in this focus (reduced if event date is approaching).
    private static func evaluateBaseToSpeed(
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> FocusTransition? {
        let minWeeks = effectiveMinWeeks(for: profile)
        guard profile.weekNumber >= minWeeks else { return nil }

        let baseWorkouts = workouts.zone2Sessions()
        let recentWeeks = lastNWeeks(2, from: baseWorkouts)

        guard recentWeeks.count == 2 else { return nil }

        for weekWorkouts in recentWeeks {
            let qualifying = weekWorkouts.filter { workout in
                workout.duration >= 45 * 60 &&
                workout.heartRateData.hrDrift < 5.0
            }
            guard !qualifying.isEmpty else { return nil }
        }

        let goalContext: String
        switch profile.primaryGoal {
        case .aerobicBase:
            goalContext = "Your aerobic base is solid."
        case .peakCardio:
            goalContext = "Base work is done — time to start pushing your ceiling."
        case .raceTraining:
            if let days = profile.daysUntilEvent, days > 0 {
                goalContext = "With \(days) days until race day, it's time to add speed work."
            } else {
                goalContext = "Your base is ready for race-specific training."
            }
        case .returnToTraining, .generalFitness:
            goalContext = "You've built a strong foundation."
        }

        return FocusTransition(
            newFocus: .developingSpeed,
            message: """
            \(goalContext) You've sustained 45+ minutes in your target zone with stable \
            heart rate for 2 consecutive weeks. Your focus is shifting to developing speed — \
            interval workouts will be added to your plan.
            """
        )
    }

    // MARK: - Developing Speed → Peak Performance

    /// Criteria: complete 12+ interval rounds at target HR AND target zone pace improvement
    /// AND at least the minimum weeks in this focus (reduced if event date is approaching).
    private static func evaluateSpeedToPeak(
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> FocusTransition? {
        let minWeeks = effectiveMinWeeks(for: profile)
        guard profile.weekNumber >= minWeeks else { return nil }

        // Scope to current focus window — only consider workouts since phaseStartDate
        let focusWorkouts = workouts.filter { $0.date >= profile.phaseStartDate }

        let intervalWorkouts = focusWorkouts.intervalSessions()

        let hasHighRoundCount = intervalWorkouts.contains { workout in
            guard let proto = workout.intervalProtocol else { return false }
            return proto.rounds >= 12
        }

        guard hasHighRoundCount else { return nil }

        let treadmillZ2 = focusWorkouts.zone2Sessions()
            .filter { $0.exerciseType == .treadmill }
            .sorted { $0.date < $1.date }

        if treadmillZ2.count >= 4 {
            let earlySpeed = treadmillZ2.prefix(2).compactMap { $0.metrics["speed"] }.reduce(0, +) / 2
            let lateSpeed = treadmillZ2.suffix(2).compactMap { $0.metrics["speed"] }.reduce(0, +) / 2
            guard lateSpeed > earlySpeed else { return nil }
        }

        let goalContext: String
        switch profile.primaryGoal {
        case .peakCardio:
            goalContext = "Time to push your VO2 max to its limit."
        case .raceTraining:
            goalContext = "Your speed work has paid off — time for peak race preparation."
        default:
            goalContext = "Your interval capacity has grown significantly."
        }

        return FocusTransition(
            newFocus: .peakPerformance,
            message: """
            \(goalContext) You've completed 12+ rounds at target heart rate and your aerobic \
            base continues to improve. Peak performance training unlocks advanced intervals: \
            Norwegian 4×4s, Tabata, and long intervals.
            """
        )
    }

    // MARK: - Consistency Check

    static func sessionsThisWeek(workouts: [WorkoutEntry]) -> Int {
        workouts.inCurrentWeek().count
    }

    /// Core gate: checks whether the user missed enough sessions last week
    /// relative to a given target. Trigger when the user missed at least
    /// half their planned target (minimum absolute floor of 2).
    static func missedSessionsLastWeek(
        workouts: [WorkoutEntry],
        target: Int
    ) -> Bool {
        let calendar = Calendar.current
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: Date().startOfWeek) ?? Date()
        let lastWeekEnd = Date().startOfWeek

        let lastWeekWorkouts = workouts.filter {
            $0.date >= lastWeekStart && $0.date < lastWeekEnd
        }

        let completed = lastWeekWorkouts.count
        let missed = target - completed
        guard missed >= 2 else { return false }
        let softThreshold = Int(ceil(Double(target) / 2.0))
        return missed >= max(2, softThreshold)
    }

    /// Convenience overload: computes last week's actual target from
    /// profile + workouts, then checks the gate. Uses the target that
    /// was in effect during last week — not the current (potentially
    /// bumped) target — so a week that met its actual target is never
    /// retroactively penalized by a bump it just earned.
    static func missedSessionsLastWeek(
        workouts: [WorkoutEntry],
        profile: UserProfile
    ) -> Bool {
        let lastWeekStart = Calendar.current.date(
            byAdding: .weekOfYear, value: -1, to: Date().startOfWeek
        )!
        let target = WeeklyTargetService.currentTarget(
            profile: profile, workouts: workouts, asOf: lastWeekStart
        )
        return missedSessionsLastWeek(workouts: workouts, target: target)
    }

    // MARK: - Helpers

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

    /// Reduce minimum weeks in a focus if the user has a race date approaching.
    /// If <8 weeks remain, allow transition after 2 weeks instead of the default minimum.
    private static func effectiveMinWeeks(for profile: UserProfile) -> Int {
        let base = profile.focus.minimumWeeks
        guard profile.primaryGoal == .raceTraining,
              let days = profile.daysUntilEvent,
              days > 0, days < 56 else {
            return base
        }
        return min(base, 2)
    }
}
