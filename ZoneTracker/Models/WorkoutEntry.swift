import Foundation
import SwiftData

// MARK: - Workout Entry

@Model
final class WorkoutEntry {
    @Attribute(.unique) var id: UUID
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

    var zoneBadge: String {
        let avg = heartRateData.avgHR
        if avg == 0 { return "—" }
        if avg < 113 { return "Z1" }
        if avg <= 150 { return "Z2" }
        if avg <= 170 { return "Z3" }
        if avg <= 180 { return "Z4" }
        return "Z5"
    }
}
