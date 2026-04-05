import Foundation
import SwiftData

// MARK: - User Profile

@Model
final class UserProfile {
    var age: Int
    var maxHR: Int
    var weight: Double       // lbs
    var height: Double       // inches
    var currentPhase: String // TrainingPhase rawValue
    var phaseStartDate: Date
    var hasCompletedOnboarding: Bool
    var zone2TargetLow: Int  // customizable Zone 2 floor
    var zone2TargetHigh: Int // customizable Zone 2 ceiling
    var legDays: [Int]       // weekday indices (1=Sun, 2=Mon, ..., 7=Sat) for heavy leg days

    init(
        age: Int = 31,
        weight: Double = 150,
        height: Double = 68,
        zone2TargetLow: Int = 130,
        zone2TargetHigh: Int = 150
    ) {
        self.age = age
        self.maxHR = 220 - age
        self.weight = weight
        self.height = height
        self.currentPhase = TrainingPhase.phase1.rawValue
        self.phaseStartDate = Date()
        self.hasCompletedOnboarding = false
        self.zone2TargetLow = zone2TargetLow
        self.zone2TargetHigh = zone2TargetHigh
        self.legDays = []
    }

    // MARK: - Computed Properties

    var phase: TrainingPhase {
        get { TrainingPhase(rawValue: currentPhase) ?? .phase1 }
        set { currentPhase = newValue.rawValue }
    }

    var weekNumber: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekOfYear], from: phaseStartDate, to: Date())
        return max(1, (components.weekOfYear ?? 0) + 1)
    }

    var zone2Range: ClosedRange<Int> {
        zone2TargetLow...zone2TargetHigh
    }

    // HR zones based on maxHR
    var zone1Ceiling: Int { Int(Double(maxHR) * 0.60) }
    var zone3Ceiling: Int { Int(Double(maxHR) * 0.80) }
    var zone4Ceiling: Int { Int(Double(maxHR) * 0.90) }

    func advancePhase() {
        guard let next = phase.next else { return }
        self.phase = next
        self.phaseStartDate = Date()
    }

    func isLegDay(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return legDays.contains(weekday)
    }

    func isAdjacentToLegDay(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: date)!
        return isLegDay(dayBefore)
    }
}
