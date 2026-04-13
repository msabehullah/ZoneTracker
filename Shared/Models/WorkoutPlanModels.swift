import Foundation

enum WorkoutSegmentKind: String, Codable, Equatable, Sendable {
    case steady
    case warmup
    case work
    case recovery
    case cooldown
}

struct WorkoutPlanSegment: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var kind: WorkoutSegmentKind
    var startOffset: TimeInterval
    var duration: TimeInterval
    var targetRange: TargetHeartRateRange?
    var cue: String?

    var endOffset: TimeInterval {
        startOffset + duration
    }
}

struct WatchCompanionProfile: Codable, Equatable, Sendable {
    var accountIdentifier: String?
    var profileIdentifier: String?
    var maxHeartRate: Int
    var zone2Low: Int
    var zone2High: Int
    var phase: TrainingPhase
    var coachingPreferences: CoachingPreferences

    var zone2TargetRange: TargetHeartRateRange {
        TargetHeartRateRange(low: zone2Low, high: zone2High, label: "Zone 2")
    }
}

struct WorkoutExecutionPlan: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var recommendationIdentifier: String
    var accountIdentifier: String?
    var profileIdentifier: String?
    var createdAt: Date
    var phase: TrainingPhase
    var sessionType: SessionType
    var exerciseType: ExerciseType
    var targetDuration: TimeInterval
    var overallTargetRange: TargetHeartRateRange
    var intervalProtocol: IntervalProtocol?
    var suggestedMetrics: [String: Double]
    var segments: [WorkoutPlanSegment]
    var coachingPreferences: CoachingPreferences
    var rationale: String
    var isFreeWorkout: Bool

    var targetDurationMinutes: Int {
        Int(targetDuration / 60)
    }

    var activeSegmentFallback: WorkoutPlanSegment {
        segments.last ?? WorkoutPlanSegment(
            id: "steady",
            title: sessionType.displayName,
            kind: .steady,
            startOffset: 0,
            duration: targetDuration,
            targetRange: overallTargetRange,
            cue: nil
        )
    }

    func activeSegment(at elapsedTime: TimeInterval) -> WorkoutPlanSegment {
        if let segment = segments.first(where: { elapsedTime >= $0.startOffset && elapsedTime < $0.endOffset }) {
            return segment
        }
        return activeSegmentFallback
    }
}

struct WorkoutCompletionPayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var planIdentifier: String?
    var recommendationIdentifier: String?
    var accountIdentifier: String?
    var profileIdentifier: String?
    var startedAt: Date
    var endedAt: Date
    var sessionType: SessionType
    var exerciseType: ExerciseType
    var intervalProtocol: IntervalProtocol?
    var calories: Double
    var heartRateData: HeartRateData
    var completedSegments: Int
    var plannedSegments: Int
    var notes: String?

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}
