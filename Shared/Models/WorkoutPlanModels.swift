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
    var focusRaw: String?
    var goalRaw: String?

    var focus: TrainingFocus {
        focusRaw.flatMap { TrainingFocus(rawValue: $0) } ?? phase.toFocus
    }

    var goal: CardioGoal {
        goalRaw.flatMap { CardioGoal(rawValue: $0) } ?? .generalFitness
    }

    var targetZoneRange: TargetHeartRateRange {
        TargetHeartRateRange(low: zone2Low, high: zone2High, label: "Target Zone")
    }

    // Keep backward compatibility
    var zone2TargetRange: TargetHeartRateRange {
        targetZoneRange
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
    /// Total distance covered (meters). 0 for modalities that don't yield
    /// HealthKit distance (e.g. stationary bike without cadence sensor).
    var distanceMeters: Double
    /// Wall-clock seconds spent with heart rate inside the target zone.
    /// Drives plan-adherence UI and progression gating on the phone.
    var timeInTarget: TimeInterval

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    // MARK: - Codable (backward-compatible defaults)
    //
    // Older watch builds sent payloads without distance / timeInTarget. Decode
    // those as 0 rather than failing the ingest — a completion with missing
    // metrics is still better than a dropped workout.

    private enum CodingKeys: String, CodingKey {
        case id, planIdentifier, recommendationIdentifier, accountIdentifier,
             profileIdentifier, startedAt, endedAt, sessionType, exerciseType,
             intervalProtocol, calories, heartRateData, completedSegments,
             plannedSegments, notes, distanceMeters, timeInTarget
    }

    init(
        id: String,
        planIdentifier: String? = nil,
        recommendationIdentifier: String? = nil,
        accountIdentifier: String? = nil,
        profileIdentifier: String? = nil,
        startedAt: Date,
        endedAt: Date,
        sessionType: SessionType,
        exerciseType: ExerciseType,
        intervalProtocol: IntervalProtocol? = nil,
        calories: Double,
        heartRateData: HeartRateData,
        completedSegments: Int,
        plannedSegments: Int,
        notes: String? = nil,
        distanceMeters: Double = 0,
        timeInTarget: TimeInterval = 0
    ) {
        self.id = id
        self.planIdentifier = planIdentifier
        self.recommendationIdentifier = recommendationIdentifier
        self.accountIdentifier = accountIdentifier
        self.profileIdentifier = profileIdentifier
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sessionType = sessionType
        self.exerciseType = exerciseType
        self.intervalProtocol = intervalProtocol
        self.calories = calories
        self.heartRateData = heartRateData
        self.completedSegments = completedSegments
        self.plannedSegments = plannedSegments
        self.notes = notes
        self.distanceMeters = distanceMeters
        self.timeInTarget = timeInTarget
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.planIdentifier = try c.decodeIfPresent(String.self, forKey: .planIdentifier)
        self.recommendationIdentifier = try c.decodeIfPresent(String.self, forKey: .recommendationIdentifier)
        self.accountIdentifier = try c.decodeIfPresent(String.self, forKey: .accountIdentifier)
        self.profileIdentifier = try c.decodeIfPresent(String.self, forKey: .profileIdentifier)
        self.startedAt = try c.decode(Date.self, forKey: .startedAt)
        self.endedAt = try c.decode(Date.self, forKey: .endedAt)
        self.sessionType = try c.decode(SessionType.self, forKey: .sessionType)
        self.exerciseType = try c.decode(ExerciseType.self, forKey: .exerciseType)
        self.intervalProtocol = try c.decodeIfPresent(IntervalProtocol.self, forKey: .intervalProtocol)
        self.calories = try c.decode(Double.self, forKey: .calories)
        self.heartRateData = try c.decode(HeartRateData.self, forKey: .heartRateData)
        self.completedSegments = try c.decode(Int.self, forKey: .completedSegments)
        self.plannedSegments = try c.decode(Int.self, forKey: .plannedSegments)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.distanceMeters = try c.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 0
        self.timeInTarget = try c.decodeIfPresent(TimeInterval.self, forKey: .timeInTarget) ?? 0
    }
}
