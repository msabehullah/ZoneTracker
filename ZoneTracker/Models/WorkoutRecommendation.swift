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
        let lowImpactTypes: Set<ExerciseType> = [.bike, .elliptical, .rowing]
        let preferred = profile.preferredExerciseTypes
        let candidate = preferred.first ?? .treadmill
        let exerciseType: ExerciseType
        if profile.prefersLowImpact && !lowImpactTypes.contains(candidate) {
            exerciseType = preferred.first(where: { lowImpactTypes.contains($0) }) ?? .bike
        } else {
            exerciseType = candidate
        }
        let defaultMetrics: [String: Double]
        switch exerciseType {
        case .treadmill: defaultMetrics = ["speed": 3.5, "incline": 3.0]
        default:
            defaultMetrics = Dictionary(uniqueKeysWithValues:
                exerciseType.metricDefinitions.map { ($0.key, $0.defaultValue) }
            )
        }

        let goalContext: String
        switch profile.primaryGoal {
        case .aerobicBase: goalContext = "Let's build your aerobic base."
        case .peakCardio: goalContext = "Starting with a foundation session before we push intensity."
        case .raceTraining: goalContext = "Building the aerobic engine for race day."
        case .returnToTraining: goalContext = "Welcome back. Starting easy to rebuild your rhythm."
        case .generalFitness: goalContext = "Let's get your first session in."
        }

        let startDuration = profile.effectiveStartingDuration
        let startMinutes = Int(startDuration / 60)

        return WorkoutRecommendation(
            sessionType: .zone2,
            exerciseType: exerciseType,
            targetDuration: startDuration,
            targetHRLow: profile.zone2TargetLow,
            targetHRHigh: profile.zone2TargetHigh,
            suggestedMetrics: defaultMetrics,
            intervalProtocol: nil,
            reasoning: "\(goalContext) Start with a \(startMinutes)-minute \(exerciseType.displayName.lowercased()) session in your target zone (\(profile.zone2TargetLow)–\(profile.zone2TargetHigh) bpm).",
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
