import Foundation

// MARK: - Exercise Type

enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case treadmill
    case elliptical
    case stairClimber
    case bike
    case rowing
    case outdoorRun
    case rucking

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .treadmill: return "Treadmill"
        case .elliptical: return "Elliptical"
        case .stairClimber: return "Stair Climber"
        case .bike: return "Stationary Bike"
        case .rowing: return "Rowing Machine"
        case .outdoorRun: return "Outdoor Run/Walk"
        case .rucking: return "Rucking"
        }
    }

    var sfSymbol: String {
        switch self {
        case .treadmill: return "figure.run"
        case .elliptical: return "figure.elliptical"
        case .stairClimber: return "figure.stairs"
        case .bike: return "figure.indoor.cycle"
        case .rowing: return "figure.rowing"
        case .outdoorRun: return "figure.run.circle"
        case .rucking: return "figure.hiking"
        }
    }

    var metricDefinitions: [MetricDefinition] {
        switch self {
        case .treadmill:
            return [
                MetricDefinition(key: "speed", name: "Speed", unit: "mph", min: 1.0, max: 12.0, step: 0.1, defaultValue: 3.5),
                MetricDefinition(key: "incline", name: "Incline", unit: "%", min: 0, max: 15, step: 0.5, defaultValue: 3.0)
            ]
        case .elliptical:
            return [
                MetricDefinition(key: "resistance", name: "Resistance", unit: "", min: 1, max: 25, step: 1, defaultValue: 5),
                MetricDefinition(key: "spm", name: "Strides/min", unit: "spm", min: 60, max: 200, step: 1, defaultValue: 130)
            ]
        case .stairClimber:
            return [
                MetricDefinition(key: "stepsPerMin", name: "Steps/min", unit: "spm", min: 20, max: 150, step: 1, defaultValue: 60),
                MetricDefinition(key: "resistance", name: "Resistance", unit: "", min: 1, max: 20, step: 1, defaultValue: 5)
            ]
        case .bike:
            return [
                MetricDefinition(key: "resistance", name: "Resistance", unit: "", min: 1, max: 30, step: 1, defaultValue: 8),
                MetricDefinition(key: "cadence", name: "Cadence", unit: "RPM", min: 40, max: 130, step: 1, defaultValue: 75)
            ]
        case .rowing:
            return [
                MetricDefinition(key: "damper", name: "Damper", unit: "", min: 1, max: 10, step: 1, defaultValue: 5),
                MetricDefinition(key: "strokeRate", name: "Strokes/min", unit: "spm", min: 18, max: 40, step: 1, defaultValue: 24)
            ]
        case .outdoorRun:
            return [
                MetricDefinition(key: "pace", name: "Pace", unit: "min/mi", min: 6, max: 20, step: 0.25, defaultValue: 12.0)
            ]
        case .rucking:
            return [
                MetricDefinition(key: "weight", name: "Weight", unit: "lbs", min: 10, max: 60, step: 5, defaultValue: 20),
                MetricDefinition(key: "pace", name: "Pace", unit: "min/mi", min: 12, max: 25, step: 0.25, defaultValue: 18.0)
            ]
        }
    }
}

// MARK: - Metric Definition

struct MetricDefinition: Identifiable {
    let key: String
    let name: String
    let unit: String
    let min: Double
    let max: Double
    let step: Double
    let defaultValue: Double

    var id: String { key }
}

// MARK: - Session Type

enum SessionType: String, Codable, CaseIterable, Identifiable {
    case zone2
    case interval_30_30
    case interval_tempo
    case interval_hillRepeats
    case interval_4x4
    case interval_tabata
    case interval_longIntervals
    case benchmark_mile

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zone2: return "Zone 2"
        case .interval_30_30: return "30/30 Intervals"
        case .interval_tempo: return "Tempo Run"
        case .interval_hillRepeats: return "Hill Repeats"
        case .interval_4x4: return "4×4 Norwegian"
        case .interval_tabata: return "Tabata"
        case .interval_longIntervals: return "Long Intervals"
        case .benchmark_mile: return "Mile Benchmark"
        }
    }

    var isInterval: Bool {
        switch self {
        case .zone2, .benchmark_mile: return false
        default: return true
        }
    }

    var phaseAvailability: Set<TrainingPhase> {
        switch self {
        case .zone2: return [.phase1, .phase2, .phase3]
        case .interval_30_30, .interval_tempo, .interval_hillRepeats: return [.phase2, .phase3]
        case .interval_4x4, .interval_tabata, .interval_longIntervals: return [.phase3]
        case .benchmark_mile: return [.phase1, .phase2, .phase3]
        }
    }

    var defaultIntervalProtocol: IntervalProtocol? {
        switch self {
        case .interval_30_30:
            return IntervalProtocol(workDuration: 30, restDuration: 30, rounds: 8, targetWorkHRLow: 170, targetWorkHRHigh: 180, targetRestHR: 140)
        case .interval_tempo:
            return IntervalProtocol(workDuration: 600, restDuration: 0, rounds: 1, targetWorkHRLow: 160, targetWorkHRHigh: 170, targetRestHR: nil)
        case .interval_hillRepeats:
            return IntervalProtocol(workDuration: 45, restDuration: 90, rounds: 6, targetWorkHRLow: 170, targetWorkHRHigh: 180, targetRestHR: 140)
        case .interval_4x4:
            return IntervalProtocol(workDuration: 240, restDuration: 180, rounds: 4, targetWorkHRLow: 170, targetWorkHRHigh: 180, targetRestHR: 130)
        case .interval_tabata:
            return IntervalProtocol(workDuration: 20, restDuration: 10, rounds: 8, targetWorkHRLow: 170, targetWorkHRHigh: 189, targetRestHR: nil)
        case .interval_longIntervals:
            return IntervalProtocol(workDuration: 180, restDuration: 120, rounds: 5, targetWorkHRLow: 161, targetWorkHRHigh: 170, targetRestHR: 130)
        default:
            return nil
        }
    }
}

// MARK: - Adjustment Type

enum AdjustmentType: String, Codable {
    case holdSteady
    case increaseIntensity
    case decreaseIntensity
    case increaseDuration
    case addIntervalRounds
    case phaseTransition
}
