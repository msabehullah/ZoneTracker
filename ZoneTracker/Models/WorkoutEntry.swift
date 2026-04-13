import Foundation
import SwiftData

// MARK: - Workout Entry

enum WorkoutSource: String, Codable, CaseIterable, Sendable {
    case manualEntry
    case healthKitImport
    case watchPlanned
    case watchFreeWorkout
    case cloudImport
}

@Model
final class WorkoutEntry {
    @Attribute(.unique) var id: UUID
    var accountIdentifier: String?
    var completionIdentifier: String?
    var planIdentifier: String?
    var recommendationIdentifier: String?
    var sourceRaw: String = WorkoutSource.manualEntry.rawValue
    var date: Date
    var exerciseTypeRaw: String    // ExerciseType rawValue
    var duration: TimeInterval     // seconds
    var metricsData: Data?         // JSON-encoded [String: Double]
    var sessionTypeRaw: String     // SessionType rawValue
    var heartRateDataEncoded: Data? // JSON-encoded HeartRateData
    var phaseRaw: String           // TrainingPhase rawValue
    var weekNumber: Int
    var rpe: Int?
    var notes: String?
    var intervalProtocolData: Data? // JSON-encoded IntervalProtocol

    init(
        accountIdentifier: String? = nil,
        completionIdentifier: String? = nil,
        planIdentifier: String? = nil,
        recommendationIdentifier: String? = nil,
        source: WorkoutSource = .manualEntry,
        date: Date = Date(),
        exerciseType: ExerciseType,
        duration: TimeInterval,
        metrics: [String: Double],
        sessionType: SessionType,
        heartRateData: HeartRateData,
        phase: TrainingPhase,
        weekNumber: Int,
        rpe: Int? = nil,
        notes: String? = nil,
        intervalProtocol: IntervalProtocol? = nil
    ) {
        self.id = UUID()
        self.accountIdentifier = accountIdentifier
        self.completionIdentifier = completionIdentifier
        self.planIdentifier = planIdentifier
        self.recommendationIdentifier = recommendationIdentifier
        self.sourceRaw = source.rawValue
        self.date = date
        self.exerciseTypeRaw = exerciseType.rawValue
        self.duration = duration
        self.metricsData = try? JSONEncoder().encode(metrics)
        self.sessionTypeRaw = sessionType.rawValue
        self.heartRateDataEncoded = try? JSONEncoder().encode(heartRateData)
        self.phaseRaw = phase.rawValue
        self.weekNumber = weekNumber
        self.rpe = rpe
        self.notes = notes
        self.intervalProtocolData = try? JSONEncoder().encode(intervalProtocol)
    }

    // MARK: - Computed Properties

    var exerciseType: ExerciseType {
        get { ExerciseType(rawValue: exerciseTypeRaw) ?? .treadmill }
        set { exerciseTypeRaw = newValue.rawValue }
    }

    var sessionType: SessionType {
        get { SessionType(rawValue: sessionTypeRaw) ?? .zone2 }
        set { sessionTypeRaw = newValue.rawValue }
    }

    var phase: TrainingPhase {
        get { TrainingPhase(rawValue: phaseRaw) ?? .phase1 }
        set { phaseRaw = newValue.rawValue }
    }

    var metrics: [String: Double] {
        get {
            guard let data = metricsData else { return [:] }
            return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
        }
        set { metricsData = try? JSONEncoder().encode(newValue) }
    }

    var heartRateData: HeartRateData {
        get {
            guard let data = heartRateDataEncoded else { return .empty }
            return (try? JSONDecoder().decode(HeartRateData.self, from: data)) ?? .empty
        }
        set { heartRateDataEncoded = try? JSONEncoder().encode(newValue) }
    }

    var intervalProtocol: IntervalProtocol? {
        get {
            guard let data = intervalProtocolData else { return nil }
            return try? JSONDecoder().decode(IntervalProtocol.self, from: data)
        }
        set { intervalProtocolData = try? JSONEncoder().encode(newValue) }
    }

    // MARK: - Convenience

    var durationMinutes: Int {
        Int(duration / 60)
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if seconds == 0 {
            return "\(minutes) min"
        }
        return "\(minutes)m \(seconds)s"
    }

    var source: WorkoutSource {
        get { WorkoutSource(rawValue: sourceRaw) ?? .manualEntry }
        set { sourceRaw = newValue.rawValue }
    }

    var zoneBadge: String {
        let avg = heartRateData.avgHR
        if avg == 0 { return "—" }
        let classifier = HeartRateZoneClassifier(maxHeartRate: 189, zone2Range: 130...150)
        return classifier.zone(for: avg).badge
    }
}
