import Foundation

enum HeartRateTargetPosition: String, Codable, Equatable, Sendable {
    case belowTarget
    case inTarget
    case aboveTarget
    case unavailable

    var shortLabel: String {
        switch self {
        case .belowTarget: return "Below"
        case .inTarget: return "On Target"
        case .aboveTarget: return "Above"
        case .unavailable: return "No Target"
        }
    }
}

enum HeartRateCoachingAlert: String, Codable, Equatable, Sendable {
    case none
    case belowTarget
    case aboveTarget
    case backInTarget
}

struct TargetHeartRateRange: Codable, Equatable, Hashable, Sendable {
    var low: Int
    var high: Int
    var label: String?

    init(low: Int, high: Int, label: String? = nil) {
        self.low = min(low, high)
        self.high = max(low, high)
        self.label = label
    }

    var closedRange: ClosedRange<Int> {
        low...high
    }

    var displayText: String {
        "\(low)-\(high) bpm"
    }

    func position(for heartRate: Int) -> HeartRateTargetPosition {
        guard heartRate > 0 else { return .unavailable }
        if heartRate < low { return .belowTarget }
        if heartRate > high { return .aboveTarget }
        return .inTarget
    }
}

enum HeartRateZoneBucket: Int, Codable, CaseIterable, Equatable, Sendable {
    case zone1 = 1
    case zone2 = 2
    case zone3 = 3
    case zone4 = 4
    case zone5 = 5

    var badge: String {
        "Z\(rawValue)"
    }
}

struct HeartRateZoneClassifier: Equatable, Sendable {
    let maxHeartRate: Int
    let zone2Range: ClosedRange<Int>

    init(maxHeartRate: Int, zone2Range: ClosedRange<Int>) {
        self.maxHeartRate = maxHeartRate
        self.zone2Range = zone2Range
    }

    var zone1Ceiling: Int {
        max(0, zone2Range.lowerBound - 1)
    }

    var zone3Ceiling: Int {
        max(zone2Range.upperBound, Int(Double(maxHeartRate) * 0.80))
    }

    var zone4Ceiling: Int {
        max(zone3Ceiling, Int(Double(maxHeartRate) * 0.90))
    }

    func zone(for heartRate: Int) -> HeartRateZoneBucket {
        if heartRate < zone2Range.lowerBound { return .zone1 }
        if zone2Range.contains(heartRate) { return .zone2 }
        if heartRate <= zone3Ceiling { return .zone3 }
        if heartRate <= zone4Ceiling { return .zone4 }
        return .zone5
    }

    func zoneRange(for zone: HeartRateZoneBucket) -> ClosedRange<Int> {
        switch zone {
        case .zone1:
            return 0...max(0, zone2Range.lowerBound - 1)
        case .zone2:
            return zone2Range
        case .zone3:
            return (zone2Range.upperBound + 1)...zone3Ceiling
        case .zone4:
            return (zone3Ceiling + 1)...zone4Ceiling
        case .zone5:
            return (zone4Ceiling + 1)...max(maxHeartRate, zone4Ceiling + 1)
        }
    }
}

enum HeartRateDriftCalculator {
    static func calculate(samples: [HRSample]) -> Double {
        guard samples.count > 2,
              let first = samples.first?.timestamp,
              let last = samples.last?.timestamp else { return 0 }

        let totalDuration = last.timeIntervalSince(first)
        guard totalDuration > 600 else { return 0 }

        let tenMinutes: TimeInterval = 600
        let firstSegment = samples.filter { $0.timestamp.timeIntervalSince(first) <= tenMinutes }
        let lastSegment = samples.filter { last.timeIntervalSince($0.timestamp) <= tenMinutes }

        guard !firstSegment.isEmpty, !lastSegment.isEmpty else { return 0 }

        let firstAverage = Double(firstSegment.map(\.bpm).reduce(0, +)) / Double(firstSegment.count)
        let lastAverage = Double(lastSegment.map(\.bpm).reduce(0, +)) / Double(lastSegment.count)

        guard firstAverage > 0 else { return 0 }
        return ((lastAverage - firstAverage) / firstAverage) * 100
    }
}

struct CoachingPreferences: Codable, Equatable, Sendable {
    var hapticsEnabled: Bool
    var outOfRangeCooldown: TimeInterval

    static let `default` = CoachingPreferences(
        hapticsEnabled: true,
        outOfRangeCooldown: 18
    )
}

struct HeartRateCoachingSnapshot: Equatable, Sendable {
    var position: HeartRateTargetPosition
    var alert: HeartRateCoachingAlert
    var targetRange: TargetHeartRateRange?
    var heartRate: Int
}

struct HeartRateCoachingEngine: Equatable, Sendable {
    private(set) var lastPosition: HeartRateTargetPosition = .unavailable
    private(set) var lastAlertAt: Date?
    private(set) var isAlertArmed = true

    mutating func reset() {
        lastPosition = .unavailable
        lastAlertAt = nil
        isAlertArmed = true
    }

    mutating func evaluate(
        heartRate: Int,
        targetRange: TargetHeartRateRange?,
        at date: Date,
        preferences: CoachingPreferences
    ) -> HeartRateCoachingSnapshot {
        let position = targetRange?.position(for: heartRate) ?? .unavailable
        var alert: HeartRateCoachingAlert = .none

        if position == .inTarget {
            if lastPosition != .inTarget,
               lastPosition != .unavailable,
               !isAlertArmed {
                alert = .backInTarget
            }
            isAlertArmed = true
        } else if position == .belowTarget || position == .aboveTarget {
            let enoughTimeElapsed: Bool
            if let lastAlertAt {
                enoughTimeElapsed = date.timeIntervalSince(lastAlertAt) >= preferences.outOfRangeCooldown
            } else {
                enoughTimeElapsed = true
            }

            if isAlertArmed && enoughTimeElapsed {
                alert = position == .belowTarget ? .belowTarget : .aboveTarget
                lastAlertAt = date
                isAlertArmed = false
            }
        }

        lastPosition = position

        return HeartRateCoachingSnapshot(
            position: position,
            alert: alert,
            targetRange: targetRange,
            heartRate: heartRate
        )
    }
}
