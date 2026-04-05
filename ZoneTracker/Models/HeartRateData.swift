import Foundation

// MARK: - Heart Rate Sample

struct HRSample: Codable, Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let bpm: Int
}

// MARK: - Heart Rate Data

struct HeartRateData: Codable {
    var avgHR: Int
    var maxHR: Int
    var minHR: Int
    var timeInZone2: TimeInterval
    var timeInZone4Plus: TimeInterval
    var hrDrift: Double // percentage increase from first 10 min avg to last 10 min avg
    var recoveryHR: Int? // HR drop 1 min after stopping
    var samples: [HRSample]

    static let empty = HeartRateData(
        avgHR: 0, maxHR: 0, minHR: 0,
        timeInZone2: 0, timeInZone4Plus: 0,
        hrDrift: 0, recoveryHR: nil, samples: []
    )

    var timeInZone2Percentage: Double {
        guard !samples.isEmpty else { return 0 }
        let totalDuration = samples.last!.timestamp.timeIntervalSince(samples.first!.timestamp)
        guard totalDuration > 0 else { return 0 }
        return (timeInZone2 / totalDuration) * 100
    }

    var hasSignificantDrift: Bool {
        hrDrift >= 10.0
    }
}

// MARK: - Interval Protocol

struct IntervalProtocol: Codable, Equatable {
    var workDuration: TimeInterval   // seconds
    var restDuration: TimeInterval   // seconds
    var rounds: Int
    var targetWorkHRLow: Int
    var targetWorkHRHigh: Int
    var targetRestHR: Int?

    var targetWorkHR: ClosedRange<Int> {
        targetWorkHRLow...targetWorkHRHigh
    }

    var totalDuration: TimeInterval {
        Double(rounds) * (workDuration + restDuration)
    }

    var description: String {
        let workSec = Int(workDuration)
        let restSec = Int(restDuration)
        if workDuration >= 60 {
            let workMin = workSec / 60
            let restMin = restSec / 60
            if restDuration >= 60 {
                return "\(rounds)×\(workMin)min / \(restMin)min rest"
            } else {
                return "\(rounds)×\(workMin)min / \(restSec)s rest"
            }
        } else {
            return "\(rounds)×\(workSec)s / \(restSec)s rest"
        }
    }
}
