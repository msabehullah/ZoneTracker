import Foundation

// MARK: - Recommendation Engine

struct RecommendationEngine {

    /// Generate the next workout recommendation based on history and profile.
    static func recommend(
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> WorkoutRecommendation {
        let sorted = workouts.sorted { $0.date > $1.date }

        // No history — return default first workout
        guard let lastWorkout = sorted.first else {
            return .defaultFirstWorkout(profile: profile)
        }

        // Check consistency: if user missed 2+ sessions, repeat last week
        if PhaseManager.missedSessionsLastWeek(workouts: workouts, profile: profile) {
            return repeatLastWorkout(lastWorkout, profile: profile,
                reasoning: "Consistency is key. Let's lock in this week before moving forward.")
        }

        // Determine what type of session is next
        let nextSessionType = determineNextSessionType(profile: profile, workouts: sorted)

        // Build recommendation based on session type
        if nextSessionType.isInterval {
            return recommendIntervalSession(
                type: nextSessionType,
                profile: profile,
                workouts: sorted
            )
        } else {
            return recommendZone2Session(
                lastWorkout: lastWorkout,
                profile: profile,
                workouts: sorted
            )
        }
    }

    // MARK: - Session Type Selection

    private static func determineNextSessionType(
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> SessionType {
        let thisWeek = workouts.inCurrentWeek()
        let zone2Count = thisWeek.zone2Sessions().count
        let intervalCount = thisWeek.intervalSessions().count

        switch profile.phase {
        case .phase1:
            return .zone2

        case .phase2:
            // 2x Zone 2, 1x Interval per week
            if zone2Count < 2 { return .zone2 }
            if intervalCount < 1 { return pickIntervalType(for: .phase2, workouts: workouts) }
            return .zone2

        case .phase3:
            // 2x Zone 2, 1-2x High-intensity per week
            if zone2Count < 2 { return .zone2 }
            if intervalCount < 2 {
                // Check 48-hour spacing from last interval
                if let lastInterval = thisWeek.intervalSessions().last {
                    let hoursSince = Date().timeIntervalSince(lastInterval.date) / 3600
                    if hoursSince < 48 { return .zone2 }
                }
                return pickIntervalType(for: .phase3, workouts: workouts)
            }
            return .zone2
        }
    }

    private static func pickIntervalType(
        for phase: TrainingPhase,
        workouts: [WorkoutEntry]
    ) -> SessionType {
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

    // MARK: - Zone 2 Recommendation

    private static func recommendZone2Session(
        lastWorkout: WorkoutEntry,
        profile: UserProfile,
        workouts: [WorkoutEntry]
    ) -> WorkoutRecommendation {
        let lastZ2 = workouts.zone2Sessions().first ?? lastWorkout
        let hrData = lastZ2.heartRateData
        let avgHR = hrData.avgHR

        let zone2Low = profile.zone2TargetLow
        let zone2High = profile.zone2TargetHigh
        let exerciseType = lastZ2.exerciseType
        var metrics = lastZ2.metrics
        var duration = lastZ2.duration
        var reasoning: String
        var adjustment: AdjustmentType

        // Check for leg day conflicts
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let avoidHighIntensity = profile.isAdjacentToLegDay(Date())

        if avgHR == 0 {
            // No HR data — carry forward last settings
            reasoning = "No heart rate data from your last session. Repeating the same settings — make sure your Apple Watch is connected."
            adjustment = .holdSteady
        } else if hrData.hasSignificantDrift {
            // Significant drift — hold steady
            reasoning = "Your heart rate drifted up during the session, which means this intensity is still challenging. Let's repeat this workout before progressing."
            adjustment = .holdSteady
        } else if avgHR > zone2High + 5 {
            // HR too high — reduce intensity
            metrics = adjustMetrics(metrics, for: exerciseType, direction: .decrease)
            reasoning = "Your HR ran high last session (avg \(avgHR) bpm vs target \(zone2Low)–\(zone2High)). Let's dial back the intensity to keep you in Zone 2."
            adjustment = .decreaseIntensity
        } else if avgHR < zone2Low - 5 {
            // HR too low — increase intensity
            metrics = adjustMetrics(metrics, for: exerciseType, direction: .increase)
            reasoning = "You were cruising below your target zone (avg \(avgHR) bpm). Let's bump it up slightly."
            adjustment = .increaseIntensity
        } else {
            // In zone, stable — progress
            let result = progressZone2(
                duration: duration,
                metrics: metrics,
                exerciseType: exerciseType,
                phase: profile.phase
            )
            duration = result.duration
            metrics = result.metrics
            reasoning = "Great session — right in the zone. \(result.progressNote)"
            adjustment = result.adjustment
        }

        return WorkoutRecommendation(
            sessionType: .zone2,
            exerciseType: exerciseType,
            targetDuration: duration,
            targetHRLow: zone2Low,
            targetHRHigh: zone2High,
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
        let exerciseType = lastOfType?.exerciseType ?? lastInterval?.exerciseType ?? .treadmill

        var proto = lastOfType?.intervalProtocol ?? type.defaultIntervalProtocol!
        var metrics = lastOfType?.metrics ?? defaultMetricsForInterval(exerciseType: exerciseType)
        var reasoning: String
        var adjustment: AdjustmentType

        if let last = lastOfType {
            let hrData = last.heartRateData
            let peakHR = hrData.maxHR

            if peakHR > 185 || (last.intervalProtocol.map { hrData.maxHR > $0.targetWorkHRHigh + 5 } ?? false) {
                // Too hard — reduce rounds or extend rest
                if proto.rounds > 4 {
                    proto.rounds -= 1
                    reasoning = "Your peak HR hit \(peakHR) bpm — that's above the target ceiling. Dropping 1 round to keep it sustainable."
                } else {
                    proto.restDuration += 15
                    reasoning = "Your peak HR hit \(peakHR) bpm — adding 15 seconds of rest between intervals."
                }
                adjustment = .decreaseIntensity
            } else if peakHR < (proto.targetWorkHRLow - 5) && peakHR > 0 {
                // Not reaching target — increase intensity
                metrics = adjustMetrics(metrics, for: exerciseType, direction: .increase)
                reasoning = "Your peak HR during intervals didn't reach the target zone (\(peakHR) vs \(proto.targetWorkHRLow)+). Bumping up the intensity for the hard efforts."
                adjustment = .increaseIntensity
            } else {
                // Good — add rounds
                proto.rounds += 1
                reasoning = "Solid interval session! Adding 1 round. You're at \(proto.rounds) rounds now."
                adjustment = .addIntervalRounds
            }
        } else {
            reasoning = "First \(type.displayName) session! Starting with \(proto.description). Target \(proto.targetWorkHRLow)–\(proto.targetWorkHRHigh) bpm during work intervals."
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
            // Prefer adjusting speed first, then incline
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
                // Lower pace = faster, so decrease means lower number
                adjusted["pace"] = max(6, min(20, pace - sign * 0.25))
            }

        case .rucking:
            if let pace = adjusted["pace"] {
                adjusted["pace"] = max(12, min(25, pace - sign * 0.25))
            }
        }

        return adjusted
    }

    // MARK: - Zone 2 Progression

    private struct ProgressionResult {
        var duration: TimeInterval
        var metrics: [String: Double]
        var adjustment: AdjustmentType
        var progressNote: String
    }

    private static func progressZone2(
        duration: TimeInterval,
        metrics: [String: Double],
        exerciseType: ExerciseType,
        phase: TrainingPhase
    ) -> ProgressionResult {
        var newDuration = duration
        var newMetrics = metrics
        var adjustment: AdjustmentType
        var note: String

        switch phase {
        case .phase1:
            if duration < 60 * 60 { // < 60 min
                newDuration += 5 * 60 // +5 minutes
                adjustment = .increaseDuration
                note = "Here's your next step up: \(Int(newDuration / 60)) minutes."
            } else {
                newMetrics = adjustMetrics(metrics, for: exerciseType, direction: .increase)
                adjustment = .increaseIntensity
                note = "You're at 60 min — nudging intensity up slightly."
            }

        case .phase2, .phase3:
            // Zone 2 sessions in later phases maintain duration, can nudge intensity
            if duration < 45 * 60 {
                newDuration = 45 * 60
                adjustment = .increaseDuration
                note = "Bringing your Zone 2 session up to 45 minutes."
            } else {
                newMetrics = adjustMetrics(metrics, for: exerciseType, direction: .increase)
                adjustment = .increaseIntensity
                note = "Slight intensity bump on your Zone 2 session."
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
        WorkoutRecommendation(
            sessionType: workout.sessionType,
            exerciseType: workout.exerciseType,
            targetDuration: workout.duration,
            targetHRLow: profile.zone2TargetLow,
            targetHRHigh: profile.zone2TargetHigh,
            suggestedMetrics: workout.metrics,
            intervalProtocol: workout.intervalProtocol,
            reasoning: reasoning,
            adjustmentType: .holdSteady
        )
    }

    private static func defaultMetricsForInterval(exerciseType: ExerciseType) -> [String: Double] {
        var metrics: [String: Double] = [:]
        for def in exerciseType.metricDefinitions {
            metrics[def.key] = def.defaultValue
        }
        return metrics
    }

    /// Translate intensity from one exercise type to another proportionally.
    /// Maps each metric to its percentage within range, then applies to target exercise.
    static func translateMetrics(
        from sourceType: ExerciseType,
        to targetType: ExerciseType,
        metrics: [String: Double]
    ) -> [String: Double] {
        // Calculate overall intensity as a percentage (0-1) from source metrics
        let sourceDefs = sourceType.metricDefinitions
        var intensityPercent: Double = 0.5

        if let firstMetric = sourceDefs.first, let value = metrics[firstMetric.key] {
            let range = firstMetric.max - firstMetric.min
            if range > 0 {
                intensityPercent = (value - firstMetric.min) / range
            }
        }

        // Apply that intensity percentage to target metrics
        var result: [String: Double] = [:]
        for def in targetType.metricDefinitions {
            let range = def.max - def.min
            let value = def.min + (intensityPercent * range)
            // Round to step
            let stepped = (value / def.step).rounded() * def.step
            result[def.key] = max(def.min, min(def.max, stepped))
        }

        return result
    }
}
