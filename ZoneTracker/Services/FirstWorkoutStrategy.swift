import Foundation

// MARK: - First Workout Strategy

/// Decides the very first workout recommendation for a brand-new user.
///
/// Replaces the old one-size-fits-all `defaultFirstWorkout` with an explicit
/// decision matrix driven by `(primaryGoal, fitnessLevel, intensityConstraint,
/// daysUntilEvent)`. The rules are deliberately visible and testable — no
/// randomness, no hidden heuristics.
///
/// The selected modality is always the user's **primary preference** (the
/// first modality they picked in the assessment), subject to the low-impact
/// filter. Metrics are modality-aware: there is no treadmill bias.
enum FirstWorkoutStrategy {

    // MARK: - Public Entry Point

    /// Build the first workout recommendation for `profile`.
    static func recommend(for profile: UserProfile) -> WorkoutRecommendation {
        let modality = selectModality(for: profile)
        let rawShape = decideShape(for: profile)
        let shape = resolveShape(rawShape, modality: modality)
        return build(profile: profile, modality: modality, shape: shape)
    }

    // MARK: - Shape

    /// The high-level structure of the first session. Each case resolves to
    /// a concrete `SessionType` + duration + reasoning — but captures the
    /// *why* so tests can assert on intent rather than implementation detail.
    enum Shape: Equatable {
        /// Easy confidence-building target-zone session. Short duration.
        case easyTargetZoneIntro
        /// Gentle re-entry target-zone session for returners. Mid-short duration.
        case returnToTargetZone
        /// Standard target-zone baseline. Duration scales with fitness.
        case targetZoneBaseline
        /// Longer aerobic support session for race training.
        case aerobicSupport
        /// Short interval intro session (30/30, reduced rounds).
        case intervalIntro
        /// Benchmark mile assessment to calibrate fitness.
        case benchmarkAssessment
        /// Race-intent tempo starter (shortened tempo block).
        case tempoStarter
    }

    // MARK: - Decision Matrix

    /// Decide the shape of the first workout. This is the decision table.
    /// Read top-to-bottom; the first matching rule wins.
    static func decideShape(for profile: UserProfile) -> Shape {
        let goal = profile.primaryGoal
        let level = profile.fitnessLevel
        let avoidHigh = profile.intensityConstraint == .avoidHighIntensity
        let eventSoon = (profile.daysUntilEvent ?? Int.max) <= 28

        // Beginners always start easy. No exceptions.
        if level == .beginner {
            return .easyTargetZoneIntro
        }

        // Returners get a gentle ramp-in regardless of stated goal.
        if goal == .returnToTraining {
            return .returnToTargetZone
        }

        // Users who asked us to avoid high intensity never get intervals,
        // benchmarks, or tempo on their first session.
        if avoidHigh {
            switch goal {
            case .raceTraining: return .aerobicSupport
            default: return .targetZoneBaseline
            }
        }

        // Casual users need an aerobic baseline before we push.
        if level == .occasional {
            switch goal {
            case .raceTraining: return .aerobicSupport
            default: return .targetZoneBaseline
            }
        }

        // Consistent / experienced users get a goal-specific starter.
        switch goal {
        case .peakCardio:
            return .intervalIntro
        case .raceTraining:
            return eventSoon ? .benchmarkAssessment : .aerobicSupport
        case .aerobicBase, .generalFitness:
            return .targetZoneBaseline
        case .returnToTraining:
            return .returnToTargetZone   // unreachable, guarded above
        }
    }

    // MARK: - Shape × Modality Resolution

    /// Modalities for which "run one all-out mile" is an honest prescription.
    /// Everything else (bike, row, swim, ruck, stair, elliptical) would need a
    /// different test protocol, and we don't have one modeled yet — so we
    /// don't pretend.
    static let runningModalities: Set<ExerciseType> = [.treadmill, .outdoorRun]

    static func isRunningModality(_ modality: ExerciseType) -> Bool {
        runningModalities.contains(modality)
    }

    /// Narrow a decided shape to one that's compatible with the selected
    /// modality. Today the only mismatch we correct is the benchmark mile,
    /// which historically fell through on bike/row/swim users and told them to
    /// run a mile. When the modality isn't running, we fall back to
    /// `.aerobicSupport` — the same shape race-training users get when the
    /// event isn't imminent. It's goal-aware (still targets race fitness) and
    /// modality-honest (target-zone session in the user's actual sport).
    static func resolveShape(_ shape: Shape, modality: ExerciseType) -> Shape {
        switch shape {
        case .benchmarkAssessment where !isRunningModality(modality):
            return .aerobicSupport
        default:
            return shape
        }
    }

    /// The fully-resolved shape for a profile — the same shape `recommend(for:)`
    /// will hand back, with modality narrowing already applied. Use this
    /// anywhere UI copy needs to describe the first workout (e.g.
    /// ``ProgramExplanation``) so the narrative never disagrees with the
    /// session the user is actually about to see queued up.
    static func resolvedShape(for profile: UserProfile) -> Shape {
        let modality = selectModality(for: profile)
        return resolveShape(decideShape(for: profile), modality: modality)
    }

    // MARK: - Modality Selection

    /// Pick the modality for the first session. Always prefers the user's
    /// *primary* (first-listed) modality, then applies the low-impact filter.
    static func selectModality(for profile: UserProfile) -> ExerciseType {
        let preferred = profile.preferredExerciseTypes
        let primary = preferred.first ?? .treadmill

        guard profile.prefersLowImpact else { return primary }
        if lowImpactTypes.contains(primary) { return primary }

        // Try to find a low-impact modality in their preference list first —
        // we should respect what they actually picked.
        if let lowImpactFromPreferences = preferred.first(where: { lowImpactTypes.contains($0) }) {
            return lowImpactFromPreferences
        }

        // Fall back to bike as universally-available low-impact option.
        return .bike
    }

    private static let lowImpactTypes: Set<ExerciseType> = [.bike, .elliptical, .rowing, .swimming]

    // MARK: - Build

    private static func build(
        profile: UserProfile,
        modality: ExerciseType,
        shape: Shape
    ) -> WorkoutRecommendation {
        switch shape {
        case .easyTargetZoneIntro:
            return targetZoneSession(
                profile: profile,
                modality: modality,
                minutes: 20,
                intensity: .easy,
                shape: shape
            )

        case .returnToTargetZone:
            return targetZoneSession(
                profile: profile,
                modality: modality,
                minutes: min(profile.typicalWorkoutMinutes, 28),
                intensity: .easy,
                shape: shape
            )

        case .targetZoneBaseline:
            let minutes: Int
            switch profile.fitnessLevel {
            case .beginner, .occasional: minutes = min(profile.typicalWorkoutMinutes, 30)
            case .regular: minutes = min(profile.typicalWorkoutMinutes, 40)
            case .experienced: minutes = min(profile.typicalWorkoutMinutes, 45)
            }
            return targetZoneSession(
                profile: profile,
                modality: modality,
                minutes: minutes,
                intensity: intensityForLevel(profile.fitnessLevel),
                shape: shape
            )

        case .aerobicSupport:
            let minutes: Int
            switch profile.fitnessLevel {
            case .beginner: minutes = 25
            case .occasional: minutes = 35
            case .regular: minutes = 45
            case .experienced: minutes = 50
            }
            return targetZoneSession(
                profile: profile,
                modality: modality,
                minutes: minutes,
                intensity: intensityForLevel(profile.fitnessLevel),
                shape: shape
            )

        case .intervalIntro:
            return intervalIntroSession(profile: profile, modality: modality)

        case .benchmarkAssessment:
            return benchmarkSession(profile: profile, modality: modality)

        case .tempoStarter:
            return tempoStarterSession(profile: profile, modality: modality)
        }
    }

    // MARK: - Target Zone Builder

    /// Intensity level used to scale starter metrics. Exposed as `internal`
    /// so tests can assert modality metrics across the full range.
    enum IntensityLevel { case easy, moderate, confident }

    private static func intensityForLevel(_ level: FitnessLevel) -> IntensityLevel {
        switch level {
        case .beginner: return .easy
        case .occasional: return .moderate
        case .regular, .experienced: return .confident
        }
    }

    private static func targetZoneSession(
        profile: UserProfile,
        modality: ExerciseType,
        minutes: Int,
        intensity: IntensityLevel,
        shape: Shape
    ) -> WorkoutRecommendation {
        let metrics = starterMetrics(for: modality, intensity: intensity)
        let reasoning = targetZoneReasoning(
            profile: profile,
            modality: modality,
            minutes: minutes,
            shape: shape
        )

        return WorkoutRecommendation(
            sessionType: .zone2,
            exerciseType: modality,
            targetDuration: TimeInterval(minutes * 60),
            targetHRLow: profile.zone2TargetLow,
            targetHRHigh: profile.zone2TargetHigh,
            suggestedMetrics: metrics,
            intervalProtocol: nil,
            reasoning: reasoning,
            adjustmentType: .holdSteady
        )
    }

    // MARK: - Interval Intro

    private static func intervalIntroSession(
        profile: UserProfile,
        modality: ExerciseType
    ) -> WorkoutRecommendation {
        // Shortened 30/30 intro — 4 rounds instead of 8 — plus warmup/cooldown.
        guard var proto = SessionType.interval_30_30.defaultIntervalProtocol else {
            // Should never happen; fall back to target zone.
            return targetZoneSession(
                profile: profile,
                modality: modality,
                minutes: 40,
                intensity: .confident,
                shape: .targetZoneBaseline
            )
        }
        proto.rounds = 4

        let warmupCooldown: TimeInterval = 20 * 60
        let duration = proto.totalDuration + warmupCooldown
        let metrics = starterMetrics(for: modality, intensity: .confident)
        let reasoning = goalAwarePrefix(profile: profile) +
            " Starting with a short \(modality.displayName.lowercased()) interval intro: 4 rounds of 30 seconds hard / 30 seconds easy after a 10-minute warmup. This calibrates what \"hard\" feels like before we commit to a longer interval day."

        return WorkoutRecommendation(
            sessionType: .interval_30_30,
            exerciseType: modality,
            targetDuration: duration,
            targetHRLow: proto.targetWorkHRLow,
            targetHRHigh: proto.targetWorkHRHigh,
            suggestedMetrics: metrics,
            intervalProtocol: proto,
            reasoning: reasoning,
            adjustmentType: .holdSteady
        )
    }

    // MARK: - Benchmark

    private static func benchmarkSession(
        profile: UserProfile,
        modality: ExerciseType
    ) -> WorkoutRecommendation {
        let duration: TimeInterval = 30 * 60  // 10 warmup + mile + cooldown
        let metrics = starterMetrics(for: modality, intensity: .confident)

        let daysString: String
        if let days = profile.daysUntilEvent, let event = profile.targetEvent, !event.isEmpty {
            daysString = " with \(days) days to your \(event)"
        } else {
            daysString = ""
        }

        let reasoning = "Starting with a mile benchmark\(daysString). This gives us a clean baseline to build race-specific work from — warm up for 10 minutes, run one all-out mile, cool down."

        return WorkoutRecommendation(
            sessionType: .benchmark_mile,
            exerciseType: modality,
            targetDuration: duration,
            targetHRLow: profile.zone2TargetLow,
            targetHRHigh: profile.maxHR,
            suggestedMetrics: metrics,
            intervalProtocol: nil,
            reasoning: reasoning,
            adjustmentType: .holdSteady
        )
    }

    // MARK: - Tempo Starter (reserved for future use)

    private static func tempoStarterSession(
        profile: UserProfile,
        modality: ExerciseType
    ) -> WorkoutRecommendation {
        guard var proto = SessionType.interval_tempo.defaultIntervalProtocol else {
            return targetZoneSession(
                profile: profile,
                modality: modality,
                minutes: 45,
                intensity: .confident,
                shape: .aerobicSupport
            )
        }
        // Shorten the tempo block for a first session.
        proto.workDuration = 6 * 60

        let warmupCooldown: TimeInterval = 20 * 60
        let duration = proto.totalDuration + warmupCooldown
        let metrics = starterMetrics(for: modality, intensity: .confident)
        let reasoning = goalAwarePrefix(profile: profile) +
            " Starting with a 6-minute tempo block inside a 26-minute \(modality.displayName.lowercased()) session. We'll extend it once we see how your legs respond."

        return WorkoutRecommendation(
            sessionType: .interval_tempo,
            exerciseType: modality,
            targetDuration: duration,
            targetHRLow: proto.targetWorkHRLow,
            targetHRHigh: proto.targetWorkHRHigh,
            suggestedMetrics: metrics,
            intervalProtocol: proto,
            reasoning: reasoning,
            adjustmentType: .holdSteady
        )
    }

    // MARK: - Per-Modality Starter Metrics

    /// Build modality-appropriate starter metrics at the requested intensity.
    ///
    /// Rather than hardcoding treadmill-centric values, this maps each intensity
    /// level to a fraction of each metric's defined range. The values are
    /// chosen so that "moderate" matches the modality's `defaultValue`.
    static func starterMetrics(for modality: ExerciseType, intensity: IntensityLevel) -> [String: Double] {
        var result: [String: Double] = [:]
        for def in modality.metricDefinitions {
            let value = starterValue(def: def, modality: modality, intensity: intensity)
            result[def.key] = value
        }
        return result
    }

    private static func starterValue(
        def: MetricDefinition,
        modality: ExerciseType,
        intensity: IntensityLevel
    ) -> Double {
        // Special-case pace metrics: lower pace = harder, so the curve is inverted.
        if def.key == "pace" {
            // Beginner slower, experienced faster.
            let offset: Double
            switch intensity {
            case .easy: offset = +1.5
            case .moderate: offset = 0
            case .confident: offset = -1.0
            }
            let adjusted = def.defaultValue + offset
            let stepped = (adjusted / def.step).rounded() * def.step
            return max(def.min, min(def.max, stepped))
        }

        // "weight" on rucking: keep beginners lighter.
        if def.key == "weight" {
            switch intensity {
            case .easy: return max(def.min, def.defaultValue - 10)
            case .moderate: return def.defaultValue
            case .confident: return def.defaultValue
            }
        }

        // Default: ease off the metric default for beginners, match for
        // moderate, nudge above for confident.
        let delta: Double
        switch intensity {
        case .easy: delta = -(def.defaultValue - def.min) * 0.30
        case .moderate: delta = 0
        case .confident: delta = (def.max - def.defaultValue) * 0.20
        }
        _ = modality  // reserved for future per-modality tweaks
        let raw = def.defaultValue + delta
        let stepped = (raw / def.step).rounded() * def.step
        return max(def.min, min(def.max, stepped))
    }

    // MARK: - Reasoning

    /// One-line prefix that matches the coach voice from the ongoing
    /// recommendation engine. Keeps the onboarding reasoning consistent
    /// with what the user sees after the first workout lands.
    private static func goalAwarePrefix(profile: UserProfile) -> String {
        switch profile.primaryGoal {
        case .aerobicBase:
            return "Building your aerobic engine."
        case .peakCardio:
            return "Laying the groundwork for peak cardio."
        case .raceTraining:
            if let days = profile.daysUntilEvent, days > 0, let event = profile.targetEvent, !event.isEmpty {
                return "\(days) days to your \(event)."
            }
            return "Building race-day fitness."
        case .returnToTraining:
            return "Welcome back — rebuilding your rhythm."
        case .generalFitness:
            return "Let's get your first session in."
        }
    }

    /// Label to use for the training zone in copy. Reserves "Zone 2" for users
    /// who kept the canonical 60–70% maxHR band; anyone who customized gets the
    /// neutral "target zone" label.
    private static func zoneLabel(for profile: UserProfile) -> String {
        let canonicalLow = Int((Double(profile.maxHR) * 0.60).rounded())
        let canonicalHigh = Int((Double(profile.maxHR) * 0.70).rounded())
        if abs(profile.zone2TargetLow - canonicalLow) <= 3 &&
           abs(profile.zone2TargetHigh - canonicalHigh) <= 3 {
            return "Zone 2"
        }
        return "target zone"
    }

    private static func targetZoneReasoning(
        profile: UserProfile,
        modality: ExerciseType,
        minutes: Int,
        shape: Shape
    ) -> String {
        let prefix = goalAwarePrefix(profile: profile)
        let zone = zoneLabel(for: profile)
        let hr = "\(profile.zone2TargetLow)–\(profile.zone2TargetHigh) bpm"
        let modalityName = modality.displayName.lowercased()

        switch shape {
        case .easyTargetZoneIntro:
            return "\(prefix) Starting with a confidence-building \(minutes)-minute \(modalityName) session in your \(zone) (\(hr)). If you can still talk, you're doing it right — we'll build from here."

        case .returnToTargetZone:
            return "\(prefix) Easing in with a \(minutes)-minute \(modalityName) session in your \(zone) (\(hr)). The goal today is just to reconnect — don't push."

        case .targetZoneBaseline:
            return "\(prefix) Kicking off with a \(minutes)-minute \(modalityName) session in your \(zone) (\(hr)). This is the foundation everything else gets built on."

        case .aerobicSupport:
            return "\(prefix) Starting with a \(minutes)-minute aerobic \(modalityName) session in your \(zone) (\(hr)). Race fitness sits on top of deep aerobic capacity — today we're investing in that base."

        case .intervalIntro, .benchmarkAssessment, .tempoStarter:
            // Not reached from target-zone path, but included for exhaustiveness.
            return "\(prefix) \(minutes)-minute \(modalityName) session in your \(zone) (\(hr))."
        }
    }
}
