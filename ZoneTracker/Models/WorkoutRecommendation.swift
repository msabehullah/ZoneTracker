import Foundation

// MARK: - Workout Recommendation

struct WorkoutRecommendation: Identifiable {
    let id = UUID()
    var sessionType: SessionType
    var exerciseType: ExerciseType
    var targetDuration: TimeInterval        // seconds
    var targetHRLow: Int
    var targetHRHigh: Int
    var suggestedMetrics: [String: Double]
    var intervalProtocol: IntervalProtocol?
    var reasoning: String
    var adjustmentType: AdjustmentType

    var targetHRZone: ClosedRange<Int> {
        targetHRLow...targetHRHigh
    }

    var targetDurationMinutes: Int {
        Int(targetDuration / 60)
    }

    // Default first workout for a brand new user
    static func defaultFirstWorkout(profile: UserProfile) -> WorkoutRecommendation {
        WorkoutRecommendation(
            sessionType: .zone2,
            exerciseType: .treadmill,
            targetDuration: 30 * 60, // 30 minutes
            targetHRLow: profile.zone2TargetLow,
            targetHRHigh: profile.zone2TargetHigh,
            suggestedMetrics: ["speed": 3.5, "incline": 3.0],
            intervalProtocol: nil,
            reasoning: "Welcome to Phase 1! Start with a 30-minute treadmill walk to establish your Zone 2 baseline. Keep your heart rate between \(profile.zone2TargetLow)–\(profile.zone2TargetHigh) bpm.",
            adjustmentType: .holdSteady
        )
    }

    var formattedMetrics: String {
        suggestedMetrics.map { key, value in
            let name = metricDisplayName(for: key)
            if key == "pace" {
                return "\(name): \(formatPace(value))"
            }
            if value == value.rounded() {
                return "\(name): \(Int(value))"
            }
            return "\(name): \(String(format: "%.1f", value))"
        }.joined(separator: " · ")
    }

    private func metricDisplayName(for key: String) -> String {
        switch key {
        case "speed": return "Speed"
        case "incline": return "Incline"
        case "resistance": return "Resistance"
        case "cadence": return "Cadence"
        case "spm": return "Strides/min"
        case "stepsPerMin": return "Steps/min"
        case "damper": return "Damper"
        case "strokeRate": return "Strokes/min"
        case "pace": return "Pace"
        case "weight": return "Weight"
        default: return key.capitalized
        }
    }

    private func formatPace(_ minutesPerMile: Double) -> String {
        let totalSeconds = Int(minutesPerMile * 60)
        let min = totalSeconds / 60
        let sec = totalSeconds % 60
        return String(format: "%d:%02d /mi", min, sec)
    }
}
