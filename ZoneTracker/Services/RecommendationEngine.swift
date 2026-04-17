import Foundation

// MARK: - Recommendation Engine

struct RecommendationEngine {

    /// Generate the next workout recommendation based on history and profile.
    static func recommend(
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> WorkoutRecommendation {
        let sorted = workouts.sorted { $0.date > $1.date }

        // No history — delegate to the explicit first-workout decision model.
        guard let lastWorkout = sorted.first else {
            return FirstWorkoutStrategy.recommend(for: profile)
        }

        // Resolve targets: current-week for planning, last-week for the consistency gate.
        let weeklyTarget = WeeklyTargetService.currentTarget(profile: profile, workouts: workouts)
        let lastWeekStart = Calendar.current.date(
            byAdding: .weekOfYear, value: -1, to: Date().startOfWeek
        )!
        let lastWeekTarget = WeeklyTargetService.currentTarget(
            profile: profile, workouts: workouts, asOf: lastWeekStart
        )

        // Check consistency: if user missed 2+ sessions relative to LAST week's target
        if PhaseManager.missedSessionsLastWeek(workouts: workouts, target: lastWeekTarget) {
            return repeatLastWorkout(lastWorkout, profile: profile,
                reasoning: "Consistency is key. Let's lock in this week before moving forward.")
        }

        // Determine what type of session is next
        let nextSessionType = determineNextSessionType(profile: profile, workouts: sorted, weeklyTarget: weeklyTarget)

        // Build recommendation based on session type
        if nextSessionType.isInterval {
            return recommendIntervalSession(
                type: nextSessionType,
                profile: profile,
                workouts: sorted
            )
        } else {
            return recommendTargetZoneSession(
                lastWorkout: lastWorkout,
                profile: profile,
                workouts: sorted
            )
        }
    }

    // MARK: - Session Type Selection

    private static func determineNextSessionType(
        profile: UserProfile,
        workouts: [WorkoutEntry],
        weeklyTarget: Int
    ) -> SessionType {
        let focus = profile.focus
        let thisWeek = workouts.inCurrentWeek()
        let zone2Count = thisWeek.zone2Sessions().count
        let intervalCount = thisWeek.intervalSessions().count
        let targetZoneSessions = WeeklyTargetService.targetZoneSessions(total: weeklyTarget, profile: profile)
        let targetIntervalSessions = WeeklyTargetService.intervalSessions(total: weeklyTarget, profile: profile)
        let shouldDeferHighIntensity = profile.shouldAvoidHighIntensity(on: Date())

        switch focus {
        case .buildingBase, .activeRecovery:
            return .zone2

        case .developingSpeed:
            if zone2Count < targetZoneSessions { return .zone2 }
            if targetIntervalSessions > 0 && intervalCount < targetIntervalSessions {
                if shouldDeferHighIntensity { return .zone2 }
                return pickIntervalType(for: focus, workouts: workouts)
            }
            return .zone2

        case .peakPerformance:
            if zone2Count < targetZoneSessions { return .zone2 }
            if targetIntervalSessions > 0 && intervalCount < targetIntervalSessions {
                if shouldDeferHighIntensity { return .zone2 }
                // Check 48-hour spacing from last interval
                if let lastInterval = thisWeek.intervalSessions().sorted(by: { $0.date > $1.date }).first {
                    let hoursSince = Date().timeIntervalSince(lastInterval.date) / 3600
                    if hoursSince < 48 { return .zone2 }
                }
                return pickIntervalType(for: focus, workouts: workouts)
            }
            return .zone2
        }
    }

    private static func pickIntervalType(
        for focus: TrainingFocus,
        workouts: [WorkoutEntry]
    ) -> SessionType {
        let phase = focus.mappedPhase
        let available = SessionType.allCases.filter {
            $0.isInterval && $0.phaseAvailability.contains(phase)
        }

        // Rotate through available interval types — pick whichever was used least recently
        let recentIntervalTypes = workouts.intervalSessions().prefix(10).map(\.sessionType)
        for type in available {
            if !recentIntervalTypes.contains(type) { return type }
        }

        return available.first ?? .interval_30_30
    }

    // MARK: - Target Zone Recommendation

    private static func recommendTargetZoneSession(
        lastWorkout: WorkoutEntry,
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> WorkoutRecommendation {
        let lastZ2 = workouts.zone2Sessions().first ?? lastWorkout
        let hrData = lastZ2.heartRateData
        let avgHR = hrData.avgHR

        let targetLow = profile.zone2TargetLow
        let targetHigh = profile.zone2TargetHigh
        let exerciseType = preferredExerciseType(lastUsed: lastZ2.exerciseType, profile: profile)
        let sourceMetrics = lastZ2.exerciseMetrics.isEmpty
            ? defaultMetricsForInterval(exerciseType: exerciseType)
            : lastZ2.exerciseMetrics
        var metrics = exerciseType != lastZ2.exerciseType
            ? translateMetrics(from: lastZ2.exerciseType, to: exerciseType, metrics: sourceMetrics)
            : sourceMetrics
        var duration = lastZ2.duration
        var reasoning: String
        var adjustment: AdjustmentType

        if avgHR == 0 {
            reasoning = goalAwareReasoning(
                profile: profile,
                base: "No heart rate data from your last session. Repeating the same settings — make sure your Apple Watch is connected."
            )
            adjustment = .holdSteady
        } else if hrData.hasSignificantDrift {
            reasoning = goalAwareReasoning(
                profile: profile,
                base: "Your heart rate drifted during the session, which means this intensity is still challenging. Let's repeat before progressing."
            )
            adjustment = .holdSteady
        } else if avgHR > targetHigh + 5 {
            metrics = adjustMetrics(metrics, for: exerciseType, direction: .decrease)
            reasoning = goalAwareReasoning(
                profile: profile,
                base: "Your HR ran high last session (avg \(avgHR) bpm vs target \(targetLow)–\(targetHigh)). Dialing back to keep you in the target zone."
            )
            adjustment = .decreaseIntensity
        } else if avgHR < targetLow - 5 {
            metrics = adjustMetrics(metrics, for: exerciseType, direction: .increase)
            reasoning = goalAwareReasoning(
                profile: profile,
                base: "You were below your target zone (avg \(avgHR) bpm). Bumping it up slightly."
            )
            adjustment = .increaseIntensity
        } else {
            let result = progressTargetZone(
                duration: duration,
                metrics: metrics,
                exerciseType: exerciseType,
                profile: profile
            )
            duration = result.duration
            metrics = result.metrics
            reasoning = goalAwareReasoning(
                profile: profile,
                base: "Great session — right in the zone. \(result.progressNote)"
            )
            adjustment = result.adjustment
        }

        return WorkoutRecommendation(
            sessionType: .zone2,
            exerciseType: exerciseType,
            targetDuration: duration,
            targetHRLow: targetLow,
            targetHRHigh: targetHigh,
            suggestedMetrics: metrics,
            intervalProtocol: nil,
            reasoning: reasoning,
            adjustmentType: adjustment
        )
    }

    // MARK: - Interval Recommendation

    private static func recommendIntervalSession(
        type: SessionType,
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> WorkoutRecommendation {
        // Find the most recent interval session of this type
        let lastOfType = workouts.first { $0.sessionType == type }
        let lastInterval = workouts.intervalSessions().first
        let fallbackType = lastOfType?.exerciseType ?? lastInterval?.exerciseType ?? .treadmill
        let exerciseType = preferredExerciseType(lastUsed: fallbackType, profile: profile)

        var proto = lastOfType?.intervalProtocol ?? type.defaultIntervalProtocol!
        let sourceMetrics = {
            if let lastOfType, !lastOfType.exerciseMetrics.isEmpty {
                return lastOfType.exerciseMetrics
            }
            return defaultMetricsForInterval(exerciseType: exerciseType)
        }()
        var metrics: [String: Double]
        if let lastType = lastOfType?.exerciseType, lastType != exerciseType {
            metrics = translateMetrics(from: lastType, to: exerciseType, metrics: sourceMetrics)
        } else {
            metrics = sourceMetrics
        }
        var reasoning: String
        var adjustment: AdjustmentType

        if let last = lastOfType {
            let hrData = last.heartRateData
            let peakHR = hrData.maxHR

            if peakHR > 185 || (last.intervalProtocol.map { hrData.maxHR > $0.targetWorkHRHigh + 5 } ?? false) {
                if proto.rounds > 4 {
                    proto.rounds -= 1
                    reasoning = goalAwareReasoning(
                        profile: profile,
                        base: "Your peak HR hit \(peakHR) bpm — above the target ceiling. Dropping 1 round to keep it sustainable."
                    )
                } else {
                    proto.restDuration += 15
                    reasoning = goalAwareReasoning(
                        profile: profile,
                        base: "Your peak HR hit \(peakHR) bpm — adding 15 seconds of rest between intervals."
                    )
                }
                adjustment = .decreaseIntensity
            } else if peakHR < (proto.targetWorkHRLow - 5) && peakHR > 0 {
                metrics = adjustMetrics(metrics, for: exerciseType, direction: .increase)
                reasoning = goalAwareReasoning(
                    profile: profile,
                    base: "Your peak HR during intervals didn't reach the target zone (\(peakHR) vs \(proto.targetWorkHRLow)+). Bumping up intensity for the hard efforts."
                )
                adjustment = .increaseIntensity
            } else {
                proto.rounds += 1
                reasoning = goalAwareReasoning(
                    profile: profile,
                    base: "Solid interval session! Adding 1 round. You're at \(proto.rounds) rounds now."
                )
                adjustment = .addIntervalRounds
            }
        } else {
            reasoning = goalAwareReasoning(
                profile: profile,
                base: "First \(type.displayName) session! Starting with \(proto.description). Target \(proto.targetWorkHRLow)–\(proto.targetWorkHRHigh) bpm during work intervals."
            )
            adjustment = .holdSteady
        }

        // Calculate total duration: warmup + intervals + cooldown
        let warmupCooldown: TimeInterval = 20 * 60 // 10 min warmup + 10 min cooldown
        let totalDuration = proto.totalDuration + warmupCooldown

        return WorkoutRecommendation(
            sessionType: type,
            exerciseType: exerciseType,
            targetDuration: totalDuration,
            targetHRLow: proto.targetWorkHRLow,
            targetHRHigh: proto.targetWorkHRHigh,
            suggestedMetrics: metrics,
            intervalProtocol: proto,
            reasoning: reasoning,
            adjustmentType: adjustment
        )
    }

    // MARK: - Goal-Aware Reasoning

    private static func goalAwareReasoning(profile: UserProfile, base: String) -> String {
        let prefix: String
        switch profile.primaryGoal {
        case .aerobicBase:
            prefix = profile.focus == .buildingBase
                ? "Building your aerobic engine."
                : "Strengthening your foundation."
        case .peakCardio:
            prefix = profile.focus == .peakPerformance
                ? "Pushing your VO2 max ceiling."
                : "Laying the groundwork for peak cardio."
        case .raceTraining:
            if let days = profile.daysUntilEvent, days > 0, let event = profile.targetEvent {
                prefix = "\(days) days to your \(event)."
            } else {
                prefix = "Building race-day fitness."
            }
        case .returnToTraining:
            prefix = "Rebuilding your rhythm."
        case .generalFitness:
            prefix = "Keeping your cardio sharp."
        }
        return "\(prefix) \(base)"
    }

    // MARK: - Metric Adjustments

    private enum AdjustDirection { case increase, decrease }

    private static func adjustMetrics(
        _ metrics: [String: Double],
        for exerciseType: ExerciseType,
        direction: AdjustDirection
    ) -> [String: Double] {
        var adjusted = metrics
        let sign: Double = direction == .increase ? 1 : -1

        switch exerciseType {
        case .treadmill:
            if let speed = adjusted["speed"] {
                adjusted["speed"] = max(1.0, min(12.0, speed + sign * 0.2))
            } else if let incline = adjusted["incline"] {
                adjusted["incline"] = max(0, min(15, incline + sign * 0.5))
            }

        case .elliptical:
            if let resistance = adjusted["resistance"] {
                adjusted["resistance"] = max(1, min(25, resistance + sign * 1))
            }

        case .stairClimber:
            if let spm = adjusted["stepsPerMin"] {
                adjusted["stepsPerMin"] = max(20, min(150, spm + sign * 5))
            }

        case .bike:
            if let resistance = adjusted["resistance"] {
                adjusted["resistance"] = max(1, min(30, resistance + sign * 1))
            }

        case .rowing:
            if let strokeRate = adjusted["strokeRate"] {
                adjusted["strokeRate"] = max(18, min(40, strokeRate + sign * 2))
            }

        case .outdoorRun:
            if let pace = adjusted["pace"] {
                adjusted["pace"] = max(6, min(20, pace - sign * 0.25))
            }

        case .rucking:
            if let pace = adjusted["pace"] {
                adjusted["pace"] = max(12, min(25, pace - sign * 0.25))
            }

        case .swimming:
            if let pace = adjusted["pace"] {
                adjusted["pace"] = max(1.2, min(4.0, pace - sign * 0.05))
            } else if let strokeRate = adjusted["strokeRate"] {
                adjusted["strokeRate"] = max(20, min(80, strokeRate + sign * 2))
            }
        }

        return adjusted
    }

    // MARK: - Target Zone Progression

    private struct ProgressionResult {
        var duration: TimeInterval
        var metrics: [String: Double]
        var adjustment: AdjustmentType
        var progressNote: String
    }

    private static func progressTargetZone(
        duration: TimeInterval,
        metrics: [String: Double],
        exerciseType: ExerciseType,
        profile: UserProfile
    ) -> ProgressionResult {
        var newDuration = duration
        var newMetrics = metrics
        var adjustment: AdjustmentType
        var note: String

        // Fitness level affects progression step size and duration ceiling
        let durationStep: TimeInterval
        let durationCeiling: TimeInterval
        switch profile.fitnessLevel {
        case .beginner:
            durationStep = 2 * 60
            durationCeiling = 40 * 60
        case .occasional:
            durationStep = 5 * 60
            durationCeiling = 60 * 60
        case .regular, .experienced:
            durationStep = 5 * 60
            durationCeiling = 75 * 60
        }

        switch profile.focus {
        case .buildingBase, .activeRecovery:
            if duration < durationCeiling {
                newDuration += durationStep
                adjustment = .increaseDuration
                note = "Next step up: \(Int(newDuration / 60)) minutes."
            } else {
                newMetrics = adjustMetrics(metrics, for: exerciseType, direction: .increase)
                adjustment = .increaseIntensity
                note = "You're at \(Int(duration / 60)) min — nudging intensity up slightly."
            }

        case .developingSpeed, .peakPerformance:
            if duration < 45 * 60 {
                newDuration = 45 * 60
                adjustment = .increaseDuration
                note = "Bringing your target zone session up to 45 minutes."
            } else {
                newMetrics = adjustMetrics(metrics, for: exerciseType, direction: .increase)
                adjustment = .increaseIntensity
                note = "Slight intensity bump on your target zone session."
            }
        }

        return ProgressionResult(
            duration: newDuration, metrics: newMetrics,
            adjustment: adjustment, progressNote: note
        )
    }

    // MARK: - Helpers

    private static func repeatLastWorkout(
        _ workout: WorkoutEntry,
        profile: UserProfile,
        reasoning: String
    ) -> WorkoutRecommendation {
        let targetRange: ClosedRange<Int>
        if let intervalTarget = workout.intervalProtocol?.targetWorkHR {
            targetRange = intervalTarget
        } else {
            targetRange = profile.zone2Range
        }

        return WorkoutRecommendation(
            sessionType: workout.sessionType,
            exerciseType: workout.exerciseType,
            targetDuration: workout.duration,
            targetHRLow: targetRange.lowerBound,
            targetHRHigh: targetRange.upperBound,
            suggestedMetrics: workout.exerciseMetrics.isEmpty
                ? defaultMetricsForInterval(exerciseType: workout.exerciseType)
                : workout.exerciseMetrics,
            intervalProtocol: workout.intervalProtocol,
            reasoning: reasoning,
            adjustmentType: .holdSteady
        )
    }

    /// Choose exercise type: prefer the user's selected modalities, apply low-impact filtering,
    /// fall back to last-used type.
    private static func preferredExerciseType(
        lastUsed: ExerciseType,
        profile: UserProfile
    ) -> ExerciseType {
        let preferred = profile.preferredExerciseTypes
        guard !preferred.isEmpty else {
            return applyLowImpactFilter(lastUsed, profile: profile)
        }

        // If last-used type is in their preferred list, keep it
        if preferred.contains(lastUsed) {
            return applyLowImpactFilter(lastUsed, profile: profile)
        }

        // Otherwise pick first preferred type (with low-impact filter)
        let candidate = preferred.first ?? lastUsed
        return applyLowImpactFilter(candidate, profile: profile)
    }

    private static let lowImpactTypes: Set<ExerciseType> = [.bike, .elliptical, .rowing, .swimming]

    private static func applyLowImpactFilter(_ type: ExerciseType, profile: UserProfile) -> ExerciseType {
        guard profile.prefersLowImpact else { return type }

        // If already low impact, keep it
        if lowImpactTypes.contains(type) { return type }

        // Swap to a low-impact preferred modality if available
        let preferredLowImpact = profile.preferredExerciseTypes.filter { lowImpactTypes.contains($0) }
        if let alternative = preferredLowImpact.first { return alternative }

        // Otherwise swap to bike as default low-impact
        return .bike
    }

    private static func defaultMetricsForInterval(exerciseType: ExerciseType) -> [String: Double] {
        var metrics: [String: Double] = [:]
        for def in exerciseType.metricDefinitions {
            metrics[def.key] = def.defaultValue
        }
        return metrics
    }

    /// Translate intensity from one exercise type to another proportionally.
    static func translateMetrics(
        from sourceType: ExerciseType,
        to targetType: ExerciseType,
        metrics: [String: Double]
    ) -> [String: Double] {
        let sourceDefs = sourceType.metricDefinitions
        var intensityPercent: Double = 0.5

        if let firstMetric = sourceDefs.first, let value = metrics[firstMetric.key] {
            let range = firstMetric.max - firstMetric.min
            if range > 0 {
                intensityPercent = (value - firstMetric.min) / range
            }
        }

        var result: [String: Double] = [:]
        for def in targetType.metricDefinitions {
            let range = def.max - def.min
            let value = def.min + (intensityPercent * range)
            let stepped = (value / def.step).rounded() * def.step
            result[def.key] = max(def.min, min(def.max, stepped))
        }

        return result
    }
}
