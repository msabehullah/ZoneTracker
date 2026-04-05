import XCTest
@testable import ZoneTracker

final class HRZoneCalculatorTests: XCTestCase {

    // MARK: - Zone Classification

    func testZoneClassificationWithDefaults() {
        let calc = HRZoneCalculator(maxHR: 189, zone2Override: 130...150)

        XCTAssertEqual(calc.zone(for: 100), .zone1)
        XCTAssertEqual(calc.zone(for: 129), .zone1)
        XCTAssertEqual(calc.zone(for: 130), .zone2)
        XCTAssertEqual(calc.zone(for: 140), .zone2)
        XCTAssertEqual(calc.zone(for: 150), .zone2)
        XCTAssertEqual(calc.zone(for: 151), .zone3)
        XCTAssertEqual(calc.zone(for: 155), .zone3) // 80% of 189 = 151.2
        XCTAssertEqual(calc.zone(for: 165), .zone4) // > 80% of 189
        XCTAssertEqual(calc.zone(for: 175), .zone5) // > 90% of 189 = 170.1
    }

    func testZoneClassificationWithCustomZone2() {
        let calc = HRZoneCalculator(maxHR: 189, zone2Override: 120...140)

        XCTAssertEqual(calc.zone(for: 119), .zone1)
        XCTAssertEqual(calc.zone(for: 120), .zone2)
        XCTAssertEqual(calc.zone(for: 140), .zone2)
        XCTAssertEqual(calc.zone(for: 141), .zone3)
    }

    // MARK: - Time In Zones

    func testTimeInZonesCalculation() {
        let calc = HRZoneCalculator(maxHR: 189, zone2Override: 130...150)
        let baseDate = Date()

        let samples = [
            HRSample(timestamp: baseDate, bpm: 135),                                    // Zone 2
            HRSample(timestamp: baseDate.addingTimeInterval(60), bpm: 140),              // Zone 2
            HRSample(timestamp: baseDate.addingTimeInterval(120), bpm: 165),             // Zone 4
            HRSample(timestamp: baseDate.addingTimeInterval(180), bpm: 170)              // Zone 4
        ]

        let zoneTime = calc.timeInZones(samples: samples)

        XCTAssertEqual(zoneTime[.zone2], 120, accuracy: 0.1, "Should have 120s in Zone 2")
        XCTAssertEqual(zoneTime[.zone4], 60, accuracy: 0.1, "Should have 60s in Zone 4")
    }

    func testTimeInZonesEmptyForSingleSample() {
        let calc = HRZoneCalculator(maxHR: 189)
        let result = calc.timeInZones(samples: [HRSample(timestamp: Date(), bpm: 140)])
        XCTAssertTrue(result.isEmpty || result.values.allSatisfy { $0 == 0 })
    }

    // MARK: - HR Drift

    func testDriftCalculation() {
        let baseDate = Date()
        var samples: [HRSample] = []

        // First 10 minutes: avg ~135 bpm
        for i in 0..<20 {
            samples.append(HRSample(
                timestamp: baseDate.addingTimeInterval(Double(i) * 30),
                bpm: 135
            ))
        }
        // Last 10 minutes: avg ~150 bpm (drift ≈ 11%)
        for i in 20..<40 {
            samples.append(HRSample(
                timestamp: baseDate.addingTimeInterval(Double(i) * 30),
                bpm: 150
            ))
        }

        let drift = HRZoneCalculator.calculateDrift(samples: samples)
        XCTAssertGreaterThan(drift, 10, "Drift should be > 10%")
        XCTAssertLessThan(drift, 12, "Drift should be < 12%")
    }

    func testDriftReturnsZeroForShortWorkouts() {
        let baseDate = Date()
        let samples = [
            HRSample(timestamp: baseDate, bpm: 140),
            HRSample(timestamp: baseDate.addingTimeInterval(300), bpm: 145)  // only 5 min
        ]
        let drift = HRZoneCalculator.calculateDrift(samples: samples)
        XCTAssertEqual(drift, 0, "Should return 0 for workouts < 10 min")
    }

    // MARK: - Zone Ranges

    func testZoneRangesAreContiguous() {
        let calc = HRZoneCalculator(maxHR: 189, zone2Override: 130...150)

        let z1 = calc.zoneRange(for: .zone1)
        let z2 = calc.zoneRange(for: .zone2)
        let z3 = calc.zoneRange(for: .zone3)
        let z4 = calc.zoneRange(for: .zone4)
        let z5 = calc.zoneRange(for: .zone5)

        XCTAssertEqual(z1.upperBound + 1, z2.lowerBound, "Zone 1 upper should be adjacent to Zone 2 lower")
        XCTAssertEqual(z2.upperBound + 1, z3.lowerBound, "Zone 2 upper should be adjacent to Zone 3 lower")
        XCTAssertEqual(z3.upperBound + 1, z4.lowerBound, "Zone 3 upper should be adjacent to Zone 4 lower")
        XCTAssertEqual(z4.upperBound + 1, z5.lowerBound, "Zone 4 upper should be adjacent to Zone 5 lower")
    }
}
