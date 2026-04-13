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
}
