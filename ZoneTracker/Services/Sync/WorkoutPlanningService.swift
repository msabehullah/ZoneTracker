import Foundation

enum WorkoutPlanningService {
    static func companionProfile(
        from profile: UserProfile,
        accountIdentifier: String?
    ) -> WatchCompanionProfile {
        WatchCompanionProfile(
            accountIdentifier: accountIdentifier,
            profileIdentifier: profile.profileIdentifier,
            maxHeartRate: profile.maxHR,
            zone2Low: profile.zone2TargetLow,
            zone2High: profile.zone2TargetHigh,
            phase: profile.phase,
            coachingPreferences: profile.coachingPreferences,
            focusRaw: profile.focus.rawValue,
            goalRaw: profile.primaryGoal.rawValue
        )
    }

    static func plan(
        from recommendation: WorkoutRecommendation,
        profile: UserProfile,
        accountIdentifier: String?
    ) -> WorkoutExecutionPlan {
        let recommendationIdentifier = stableRecommendationIdentifier(
            recommendation: recommendation,
            profile: profile
        )
        let segments = segments(for: recommendation, profile: profile)

        return WorkoutExecutionPlan(
            id: recommendationIdentifier,
            recommendationIdentifier: recommendationIdentifier,
            accountIdentifier: accountIdentifier,
            profileIdentifier: profile.profileIdentifier,
            createdAt: Date(),
            phase: profile.phase,
            sessionType: recommendation.sessionType,
            exerciseType: recommendation.exerciseType,
            targetDuration: recommendation.targetDuration,
            overallTargetRange: TargetHeartRateRange(
                low: recommendation.targetHRLow,
                high: recommendation.targetHRHigh,
                label: recommendation.sessionType.displayName
            ),
            intervalProtocol: recommendation.intervalProtocol,
            suggestedMetrics: recommendation.suggestedMetrics,
            segments: segments,
            coachingPreferences: profile.coachingPreferences,
            rationale: recommendation.reasoning,
            isFreeWorkout: false
        )
    }

    static func freeWorkoutPlan(
        exerciseType: ExerciseType,
        profile: UserProfile,
        accountIdentifier: String?
    ) -> WorkoutExecutionPlan {
        let identifier = [
            "free",
            profile.profileIdentifier,
            exerciseType.rawValue,
            "\(profile.zone2TargetLow)",
            "\(profile.zone2TargetHigh)"
        ].joined(separator: "|")

        let targetRange = TargetHeartRateRange(
            low: profile.zone2TargetLow,
            high: profile.zone2TargetHigh,
            label: "Target Zone"
        )
        let duration: TimeInterval = 30 * 60

        return WorkoutExecutionPlan(
            id: identifier,
            recommendationIdentifier: identifier,
            accountIdentifier: accountIdentifier,
            profileIdentifier: profile.profileIdentifier,
            createdAt: Date(),
            phase: profile.phase,
            sessionType: .zone2,
            exerciseType: exerciseType,
            targetDuration: duration,
            overallTargetRange: targetRange,
            intervalProtocol: nil,
            suggestedMetrics: defaultMetrics(for: exerciseType),
            segments: [
                WorkoutPlanSegment(
                    id: "free-steady",
                    title: "Free Workout",
                    kind: .steady,
                    startOffset: 0,
                    duration: duration,
                    targetRange: targetRange,
                    cue: "Stay relaxed and hold your target pace."
                )
            ],
            coachingPreferences: profile.coachingPreferences,
            rationale: "Free workout using your current target zone settings.",
            isFreeWorkout: true
        )
    }

    private static func stableRecommendationIdentifier(
        recommendation: WorkoutRecommendation,
        profile: UserProfile
    ) -> String {
        let metricsSignature = recommendation.suggestedMetrics
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(String(format: "%.2f", $0.value))" }
            .joined(separator: ",")
        let intervalSignature: String
        if let interval = recommendation.intervalProtocol {
            intervalSignature = [
                "\(Int(interval.workDuration))",
                "\(Int(interval.restDuration))",
                "\(interval.rounds)",
                "\(interval.targetWorkHRLow)",
                "\(interval.targetWorkHRHigh)",
                "\(interval.targetRestHR ?? 0)"
            ].joined(separator: ":")
        } else {
            intervalSignature = "steady"
        }

        return [
            profile.profileIdentifier,
            profile.phase.rawValue,
            recommendation.sessionType.rawValue,
            recommendation.exerciseType.rawValue,
            "\(Int(recommendation.targetDuration))",
            "\(recommendation.targetHRLow)",
            "\(recommendation.targetHRHigh)",
            metricsSignature,
            intervalSignature
        ].joined(separator: "|")
    }

    private static func segments(
        for recommendation: WorkoutRecommendation,
        profile: UserProfile
    ) -> [WorkoutPlanSegment] {
        let defaultTarget = TargetHeartRateRange(
            low: recommendation.targetHRLow,
            high: recommendation.targetHRHigh,
            label: recommendation.sessionType.displayName
        )

        guard recommendation.sessionType.isInterval,
              let interval = recommendation.intervalProtocol else {
            return [
                WorkoutPlanSegment(
                    id: "steady",
                    title: recommendation.sessionType.displayName,
                    kind: .steady,
                    startOffset: 0,
                    duration: recommendation.targetDuration,
                    targetRange: defaultTarget,
                    cue: recommendation.reasoning
                )
            ]
        }

        let warmupDuration: TimeInterval = 10 * 60
        let cooldownDuration: TimeInterval = 10 * 60
        var segments: [WorkoutPlanSegment] = [
            WorkoutPlanSegment(
                id: "warmup",
                title: "Warmup",
                kind: .warmup,
                startOffset: 0,
                duration: warmupDuration,
                targetRange: TargetHeartRateRange(
                    low: profile.zone2TargetLow,
                    high: profile.zone2TargetHigh,
                    label: "Warmup"
                ),
                cue: "Ease into the workout and settle into control."
            )
        ]

        var offset = warmupDuration
        let recoveryRange = TargetHeartRateRange(
            low: max(90, (interval.targetRestHR ?? profile.zone2TargetLow) - 10),
            high: interval.targetRestHR ?? profile.zone2TargetHigh,
            label: "Recovery"
        )
        let workRange = TargetHeartRateRange(
            low: interval.targetWorkHRLow,
            high: interval.targetWorkHRHigh,
            label: "Work"
        )

        for round in 1...interval.rounds {
            segments.append(
                WorkoutPlanSegment(
                    id: "work-\(round)",
                    title: "Work \(round)",
                    kind: .work,
                    startOffset: offset,
                    duration: interval.workDuration,
                    targetRange: workRange,
                    cue: "Push into the work range."
                )
            )
            offset += interval.workDuration

            if interval.restDuration > 0 {
                segments.append(
                    WorkoutPlanSegment(
                        id: "recover-\(round)",
                        title: "Recover \(round)",
                        kind: .recovery,
                        startOffset: offset,
                        duration: interval.restDuration,
                        targetRange: recoveryRange,
                        cue: "Let your heart rate settle before the next round."
                    )
                )
                offset += interval.restDuration
            }
        }

        segments.append(
            WorkoutPlanSegment(
                id: "cooldown",
                title: "Cooldown",
                kind: .cooldown,
                startOffset: offset,
                duration: cooldownDuration,
                targetRange: TargetHeartRateRange(
                    low: profile.zone2TargetLow,
                    high: profile.zone2TargetHigh,
                    label: "Cooldown"
                ),
                cue: "Bring the effort back down and finish in control."
            )
        )
        return segments
    }

    private static func defaultMetrics(for exerciseType: ExerciseType) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: exerciseType.metricDefinitions.map {
            ($0.key, $0.defaultValue)
        })
    }
}
