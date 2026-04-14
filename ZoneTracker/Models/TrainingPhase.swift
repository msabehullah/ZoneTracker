import Foundation

// MARK: - Training Phase

enum TrainingPhase: String, Codable, CaseIterable, Identifiable, Sendable {
    case phase1
    case phase2
    case phase3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .phase1: return "Phase 1"
        case .phase2: return "Phase 2"
        case .phase3: return "Phase 3"
        }
    }

    var subtitle: String {
        switch self {
        case .phase1: return "Aerobic Base Building"
        case .phase2: return "Introducing Intervals"
        case .phase3: return "VO2 Max Development"
        }
    }

    var weekRange: String {
        switch self {
        case .phase1: return "Weeks 1–6"
        case .phase2: return "Weeks 7–12"
        case .phase3: return "Week 13+"
        }
    }

    var targetSessionsPerWeek: Int {
        switch self {
        case .phase1: return 3
        case .phase2: return 3
        case .phase3: return 4
        }
    }

    var minimumWeeks: Int {
        switch self {
        case .phase1: return 6
        case .phase2: return 6
        case .phase3: return 0
        }
    }

    var zone2SessionsPerWeek: Int {
        switch self {
        case .phase1: return 3
        case .phase2: return 2
        case .phase3: return 2
        }
    }

    var intervalSessionsPerWeek: Int {
        switch self {
        case .phase1: return 0
        case .phase2: return 1
        case .phase3: return 2
        }
    }

    var startDurationMinutes: Int {
        switch self {
        case .phase1: return 30
        case .phase2: return 45
        case .phase3: return 45
        }
    }

    var targetDurationMinutes: Int {
        switch self {
        case .phase1: return 60
        case .phase2: return 60
        case .phase3: return 60
        }
    }

    var next: TrainingPhase? {
        switch self {
        case .phase1: return .phase2
        case .phase2: return .phase3
        case .phase3: return nil
        }
    }

    var toFocus: TrainingFocus {
        switch self {
        case .phase1: return .buildingBase
        case .phase2: return .developingSpeed
        case .phase3: return .peakPerformance
        }
    }
}

// MARK: - Cardio Goal

enum CardioGoal: String, Codable, CaseIterable, Identifiable, Sendable {
    case aerobicBase
    case peakCardio
    case raceTraining
    case returnToTraining
    case generalFitness

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aerobicBase: return "Build Aerobic Base"
        case .peakCardio: return "Improve VO2 Max"
        case .raceTraining: return "Train for an Event"
        case .returnToTraining: return "Return to Training"
        case .generalFitness: return "General Cardio Fitness"
        }
    }

    var shortName: String {
        switch self {
        case .aerobicBase: return "Aerobic Base"
        case .peakCardio: return "Peak Cardio"
        case .raceTraining: return "Race Training"
        case .returnToTraining: return "Comeback"
        case .generalFitness: return "General Fitness"
        }
    }

    var icon: String {
        switch self {
        case .aerobicBase: return "heart.fill"
        case .peakCardio: return "bolt.heart.fill"
        case .raceTraining: return "flag.checkered"
        case .returnToTraining: return "arrow.counterclockwise.heart"
        case .generalFitness: return "figure.run"
        }
    }

    var tagline: String {
        switch self {
        case .aerobicBase: return "Build a strong aerobic engine"
        case .peakCardio: return "Push your cardio ceiling higher"
        case .raceTraining: return "Prepare for race day"
        case .returnToTraining: return "Rebuild consistency safely"
        case .generalFitness: return "Stay healthy and energized"
        }
    }

    var initialFocus: TrainingFocus {
        switch self {
        case .aerobicBase, .generalFitness: return .buildingBase
        case .peakCardio: return .developingSpeed
        case .raceTraining: return .buildingBase
        case .returnToTraining: return .activeRecovery
        }
    }
}

// MARK: - Fitness Level

enum FitnessLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner
    case occasional
    case regular
    case experienced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: return "New to Cardio"
        case .occasional: return "Occasional (1–2×/week)"
        case .regular: return "Regular (3–4×/week)"
        case .experienced: return "Experienced (5+×/week)"
        }
    }

    var icon: String {
        switch self {
        case .beginner: return "leaf"
        case .occasional: return "figure.walk"
        case .regular: return "figure.run"
        case .experienced: return "flame.fill"
        }
    }
}

// MARK: - Intensity Constraint

enum IntensityConstraint: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case lowImpactPreferred
    case avoidHighIntensity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "No constraints"
        case .lowImpactPreferred: return "Prefer low impact"
        case .avoidHighIntensity: return "Avoid high intensity"
        }
    }

    var icon: String {
        switch self {
        case .none: return "checkmark.circle"
        case .lowImpactPreferred: return "hand.raised"
        case .avoidHighIntensity: return "exclamationmark.shield"
        }
    }
}

// MARK: - Training Focus

enum TrainingFocus: String, Codable, CaseIterable, Identifiable, Sendable {
    case buildingBase
    case developingSpeed
    case peakPerformance
    case activeRecovery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .buildingBase: return "Building Your Base"
        case .developingSpeed: return "Developing Speed"
        case .peakPerformance: return "Peak Performance"
        case .activeRecovery: return "Getting Back on Track"
        }
    }

    var subtitle: String {
        switch self {
        case .buildingBase: return "Strengthening your aerobic foundation"
        case .developingSpeed: return "Adding intensity and variety"
        case .peakPerformance: return "Pushing your cardio ceiling"
        case .activeRecovery: return "Rebuilding consistency"
        }
    }

    var targetSessionsPerWeek: Int {
        switch self {
        case .buildingBase, .activeRecovery: return 3
        case .developingSpeed: return 3
        case .peakPerformance: return 4
        }
    }

    var targetZoneSessionsPerWeek: Int {
        switch self {
        case .buildingBase, .activeRecovery: return 3
        case .developingSpeed: return 2
        case .peakPerformance: return 2
        }
    }

    var intervalSessionsPerWeek: Int {
        switch self {
        case .buildingBase, .activeRecovery: return 0
        case .developingSpeed: return 1
        case .peakPerformance: return 2
        }
    }

    var minimumWeeks: Int {
        switch self {
        case .buildingBase: return 4
        case .developingSpeed: return 4
        case .peakPerformance: return 0
        case .activeRecovery: return 2
        }
    }

    var mappedPhase: TrainingPhase {
        switch self {
        case .buildingBase, .activeRecovery: return .phase1
        case .developingSpeed: return .phase2
        case .peakPerformance: return .phase3
        }
    }

    var next: TrainingFocus? {
        switch self {
        case .activeRecovery: return .buildingBase
        case .buildingBase: return .developingSpeed
        case .developingSpeed: return .peakPerformance
        case .peakPerformance: return nil
        }
    }
}
