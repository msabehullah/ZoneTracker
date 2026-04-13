import Foundation

struct WatchWorkoutTelemetry {
    private let zoneClassifier: HeartRateZoneClassifier
    private let minimumSampleInterval: TimeInterval = 5

    private(set) var startDate: Date?
    private(set) var lastObservedAt: Date?
    private(set) var lastObservedHeartRate: Int?
    private(set) var recordedSamples: [HRSample] = []
    private(set) var allHeartRates: [Int] = []
    private(set) var timeInZone2: TimeInterval = 0
    private(set) var timeInZone4Plus: TimeInterval = 0
    private(set) var timeInTarget: TimeInterval = 0

    init(zoneClassifier: HeartRateZoneClassifier) {
        self.zoneClassifier = zoneClassifier
    }

    mutating func reset(startDate: Date) {
        self.startDate = startDate
        lastObservedAt = nil
        lastObservedHeartRate = nil
        recordedSamples = []
        allHeartRates = []
        timeInZone2 = 0
        timeInZone4Plus = 0
        timeInTarget = 0
    }

    mutating func update(
        heartRate: Int,
        at date: Date,
        targetRange: TargetHeartRateRange?
    ) {
        accumulateUntil(date: date, targetRange: targetRange)

        lastObservedAt = date
        lastObservedHeartRate = heartRate
        allHeartRates.append(heartRate)

        if shouldRecordSample(at: date, heartRate: heartRate) {
            recordedSamples.append(HRSample(timestamp: date, bpm: heartRate))
        }
    }

    mutating func finalize(at endDate: Date, targetRange: TargetHeartRateRange?) {
        accumulateUntil(date: endDate, targetRange: targetRange)
    }

    mutating func advance(to date: Date, targetRange: TargetHeartRateRange?) {
        accumulateUntil(date: date, targetRange: targetRange)
        lastObservedAt = date
    }

    var averageHeartRate: Int {
        guard !allHeartRates.isEmpty else { return 0 }
        return allHeartRates.reduce(0, +) / allHeartRates.count
    }

    var maximumHeartRate: Int {
        allHeartRates.max() ?? 0
    }

    var minimumHeartRate: Int {
        allHeartRates.min() ?? 0
    }

    func makeHeartRateData() -> HeartRateData {
        HeartRateData(
            avgHR: averageHeartRate,
            maxHR: maximumHeartRate,
            minHR: minimumHeartRate,
            timeInZone2: timeInZone2,
            timeInZone4Plus: timeInZone4Plus,
            hrDrift: HeartRateDriftCalculator.calculate(samples: recordedSamples),
            recoveryHR: nil,
            samples: recordedSamples
        )
    }

    private mutating func accumulateUntil(
        date: Date,
        targetRange: TargetHeartRateRange?
    ) {
        guard let lastObservedAt,
              let lastObservedHeartRate else { return }

        let delta = max(0, date.timeIntervalSince(lastObservedAt))
        guard delta > 0 else { return }

        let zone = zoneClassifier.zone(for: lastObservedHeartRate)
        if zone == .zone2 {
            timeInZone2 += delta
        }
        if zone == .zone4 || zone == .zone5 {
            timeInZone4Plus += delta
        }
        if targetRange?.closedRange.contains(lastObservedHeartRate) == true {
            timeInTarget += delta
        }
    }

    private func shouldRecordSample(at date: Date, heartRate: Int) -> Bool {
        guard let lastSample = recordedSamples.last else { return true }
        return date.timeIntervalSince(lastSample.timestamp) >= minimumSampleInterval ||
            abs(lastSample.bpm - heartRate) >= 3
    }
}
