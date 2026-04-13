import Foundation
import SwiftUI

// MARK: - HR Zone

enum HRZone: Int, CaseIterable, Comparable {
    case zone1 = 1
    case zone2 = 2
    case zone3 = 3
    case zone4 = 4
    case zone5 = 5

    static func < (lhs: HRZone, rhs: HRZone) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String { "Zone \(rawValue)" }

    var color: Color {
        switch self {
        case .zone1: return .gray
        case .zone2: return .green
        case .zone3: return .yellow
        case .zone4: return .orange
        case .zone5: return .red
        }
    }

    var description: String {
        switch self {
        case .zone1: return "Recovery"
        case .zone2: return "Aerobic Base"
        case .zone3: return "Tempo"
        case .zone4: return "Threshold"
        case .zone5: return "VO2 Max"
        }
    }
}

// MARK: - HR Zone Calculator

struct HRZoneCalculator {
    let maxHR: Int
    let zone2Override: ClosedRange<Int>?

    private var classifier: HeartRateZoneClassifier {
        HeartRateZoneClassifier(
            maxHeartRate: maxHR,
            zone2Range: zone2Override ?? Int(Double(maxHR) * 0.60)...Int(Double(maxHR) * 0.70)
        )
    }

    init(maxHR: Int, zone2Override: ClosedRange<Int>? = nil) {
        self.maxHR = maxHR
        self.zone2Override = zone2Override
    }

    init(profile: UserProfile) {
        self.maxHR = profile.maxHR
        self.zone2Override = profile.zone2Range
    }

    // Standard zone boundaries (percentage of max HR)
    var zone1Ceiling: Int { classifier.zone1Ceiling }
    var zone2Floor: Int { classifier.zone2Range.lowerBound }
    var zone2Ceiling: Int { classifier.zone2Range.upperBound }
    var zone3Ceiling: Int { classifier.zone3Ceiling }
    var zone4Ceiling: Int { classifier.zone4Ceiling }

    func zone(for hr: Int) -> HRZone {
        switch classifier.zone(for: hr) {
        case .zone1: return .zone1
        case .zone2: return .zone2
        case .zone3: return .zone3
        case .zone4: return .zone4
        case .zone5: return .zone5
        }
    }

    func zoneRange(for zone: HRZone) -> ClosedRange<Int> {
        switch zone {
        case .zone1: return classifier.zoneRange(for: .zone1)
        case .zone2: return classifier.zoneRange(for: .zone2)
        case .zone3: return classifier.zoneRange(for: .zone3)
        case .zone4: return classifier.zoneRange(for: .zone4)
        case .zone5: return classifier.zoneRange(for: .zone5)
        }
    }

    func color(for hr: Int) -> Color {
        zone(for: hr).color
    }

    /// Calculate time spent in each zone from HR samples
    func timeInZones(samples: [HRSample]) -> [HRZone: TimeInterval] {
        guard samples.count > 1 else { return [:] }

        var result: [HRZone: TimeInterval] = [:]
        for z in HRZone.allCases { result[z] = 0 }

        for i in 0..<samples.count - 1 {
            let duration = samples[i + 1].timestamp.timeIntervalSince(samples[i].timestamp)
            let z = zone(for: samples[i].bpm)
            result[z, default: 0] += duration
        }

        return result
    }

    /// Calculate HR drift from samples (first 10 min avg vs last 10 min avg)
    static func calculateDrift(samples: [HRSample]) -> Double {
        HeartRateDriftCalculator.calculate(samples: samples)
    }
}
