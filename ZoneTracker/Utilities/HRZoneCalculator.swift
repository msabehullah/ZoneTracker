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

    init(maxHR: Int, zone2Override: ClosedRange<Int>? = nil) {
        self.maxHR = maxHR
        self.zone2Override = zone2Override
    }

    init(profile: UserProfile) {
        self.maxHR = profile.maxHR
        self.zone2Override = profile.zone2Range
    }

    // Standard zone boundaries (percentage of max HR)
    var zone1Ceiling: Int { Int(Double(maxHR) * 0.60) }
    var zone2Floor: Int { zone2Override?.lowerBound ?? Int(Double(maxHR) * 0.60) }
    var zone2Ceiling: Int { zone2Override?.upperBound ?? Int(Double(maxHR) * 0.70) }
    var zone3Ceiling: Int { Int(Double(maxHR) * 0.80) }
    var zone4Ceiling: Int { Int(Double(maxHR) * 0.90) }

    func zone(for hr: Int) -> HRZone {
        // Use custom Zone 2 range if set
        if let override = zone2Override {
            if hr < override.lowerBound { return .zone1 }
            if hr <= override.upperBound { return .zone2 }
            if hr <= zone3Ceiling { return .zone3 }
            if hr <= zone4Ceiling { return .zone4 }
            return .zone5
        }

        // Standard percentage-based zones
        if hr < zone1Ceiling { return .zone1 }
        if hr <= Int(Double(maxHR) * 0.70) { return .zone2 }
        if hr <= zone3Ceiling { return .zone3 }
        if hr <= zone4Ceiling { return .zone4 }
        return .zone5
    }

    func zoneRange(for zone: HRZone) -> ClosedRange<Int> {
        switch zone {
        case .zone1: return 0...zone2Floor - 1
        case .zone2: return zone2Floor...zone2Ceiling
        case .zone3: return zone2Ceiling + 1...zone3Ceiling
        case .zone4: return zone3Ceiling + 1...zone4Ceiling
        case .zone5: return zone4Ceiling + 1...maxHR
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
        guard samples.count > 2,
              let first = samples.first?.timestamp,
              let last = samples.last?.timestamp else { return 0 }

        let totalDuration = last.timeIntervalSince(first)
        guard totalDuration > 600 else { return 0 } // Need at least 10 min

        let tenMinutes: TimeInterval = 600

        let firstSegment = samples.filter {
            $0.timestamp.timeIntervalSince(first) <= tenMinutes
        }
        let lastSegment = samples.filter {
            last.timeIntervalSince($0.timestamp) <= tenMinutes
        }

        guard !firstSegment.isEmpty, !lastSegment.isEmpty else { return 0 }

        let firstAvg = Double(firstSegment.map(\.bpm).reduce(0, +)) / Double(firstSegment.count)
        let lastAvg = Double(lastSegment.map(\.bpm).reduce(0, +)) / Double(lastSegment.count)

        guard firstAvg > 0 else { return 0 }
        return ((lastAvg - firstAvg) / firstAvg) * 100
    }
}
