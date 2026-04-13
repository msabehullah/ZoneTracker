import XCTest
@testable import ZoneTracker

final class WorkoutEntryTests: XCTestCase {

    // MARK: - Initialization

    func testDefaultInitialization() {
        let entry = makeWorkout()
        XCTAssertEqual(entry.exerciseType, .treadmill)
        XCTAssertEqual(entry.sessionType, .zone2)
        XCTAssertEqual(entry.phase, .phase1)
        XCTAssertEqual(entry.duration, 45 * 60)
        XCTAssertEqual(entry.weekNumber, 3)
    }

    // MARK: - Metrics Encoding/Decoding

    func testMetricsRoundTrip() {
        let entry = makeWorkout(metrics: ["speed": 6.5, "incline": 3.0])
        XCTAssertEqual(entry.metrics["speed"], 6.5)
        XCTAssertEqual(entry.metrics["incline"], 3.0)
    }

    func testEmptyMetrics() {
        let entry = WorkoutEntry(
            exerciseType: .treadmill,
            duration: 30 * 60,
            metrics: [:],
            sessionType: .zone2,
            heartRateData: .empty,
            phase: .phase1,
            weekNumber: 1
        )
        XCTAssertTrue(entry.metrics.isEmpty)
    }

    func testMetricsMutation() {
        let entry = makeWorkout(metrics: ["speed": 5.0])
        entry.metrics = ["speed": 6.0, "incline": 2.0]
        XCTAssertEqual(entry.metrics["speed"], 6.0)
        XCTAssertEqual(entry.metrics["incline"], 2.0)
    }

    // MARK: - HeartRateData Encoding/Decoding

    func testHeartRateDataRoundTrip() {
        let hrData = HeartRateData(
            avgHR: 142, maxHR: 160, minHR: 125,
            timeInZone2: 30 * 60, timeInZone4Plus: 5 * 60,
            hrDrift: 4.5, recoveryHR: 35, samples: []
        )
        let entry = WorkoutEntry(
            exerciseType: .treadmill, duration: 45 * 60, metrics: [:],
            sessionType: .zone2, heartRateData: hrData,
            phase: .phase1, weekNumber: 1
        )
        let decoded = entry.heartRateData
        XCTAssertEqual(decoded.avgHR, 142)
        XCTAssertEqual(decoded.maxHR, 160)
        XCTAssertEqual(decoded.minHR, 125)
        XCTAssertEqual(decoded.hrDrift, 4.5)
        XCTAssertEqual(decoded.recoveryHR, 35)
    }

    func testEmptyHeartRateDataFallback() {
        let entry = WorkoutEntry(
            exerciseType: .treadmill, duration: 30 * 60, metrics: [:],
            sessionType: .zone2, heartRateData: .empty,
            phase: .phase1, weekNumber: 1
        )
        let decoded = entry.heartRateData
        XCTAssertEqual(decoded.avgHR, 0)
        XCTAssertNil(decoded.recoveryHR)
    }

    // MARK: - IntervalProtocol Encoding/Decoding

    func testIntervalProtocolRoundTrip() {
        let proto = IntervalProtocol(
            workDuration: 30, restDuration: 30, rounds: 8,
            targetWorkHRLow: 160, targetWorkHRHigh: 175
        )
        let entry = WorkoutEntry(
            exerciseType: .treadmill, duration: 30 * 60, metrics: [:],
            sessionType: .interval_30_30, heartRateData: .empty,
            phase: .phase2, weekNumber: 8,
            intervalProtocol: proto
        )
        let decoded = entry.intervalProtocol
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.rounds, 8)
        XCTAssertEqual(decoded?.workDuration, 30)
        XCTAssertEqual(decoded?.restDuration, 30)
    }

    func testNilIntervalProtocol() {
        let entry = makeWorkout()
        XCTAssertNil(entry.intervalProtocol)
    }

    // MARK: - Computed Properties

    func testDurationMinutes() {
        let entry = makeWorkout(duration: 45 * 60)
        XCTAssertEqual(entry.durationMinutes, 45)
    }

    func testFormattedDurationWholeMinutes() {
        let entry = makeWorkout(duration: 45 * 60)
        XCTAssertEqual(entry.formattedDuration, "45 min")
    }

    func testFormattedDurationWithSeconds() {
        let entry = makeWorkout(duration: 45 * 60 + 30)
        XCTAssertEqual(entry.formattedDuration, "45m 30s")
    }

    func testZoneBadge() {
        XCTAssertEqual(makeWorkout(avgHR: 0).zoneBadge, "—")
        XCTAssertEqual(makeWorkout(avgHR: 100).zoneBadge, "Z1")
        XCTAssertEqual(makeWorkout(avgHR: 140).zoneBadge, "Z2")
        XCTAssertEqual(makeWorkout(avgHR: 151).zoneBadge, "Z3")
        XCTAssertEqual(makeWorkout(avgHR: 160).zoneBadge, "Z4")
        XCTAssertEqual(makeWorkout(avgHR: 170).zoneBadge, "Z4")
        XCTAssertEqual(makeWorkout(avgHR: 175).zoneBadge, "Z5")
        XCTAssertEqual(makeWorkout(avgHR: 185).zoneBadge, "Z5")
    }

    // MARK: - Enum Computed Properties

    func testExerciseTypeMutation() {
        let entry = makeWorkout()
        entry.exerciseType = .bike
        XCTAssertEqual(entry.exerciseType, .bike)
        XCTAssertEqual(entry.exerciseTypeRaw, "bike")
    }

    func testSessionTypeMutation() {
        let entry = makeWorkout()
        entry.sessionType = .interval_30_30
        XCTAssertEqual(entry.sessionType, .interval_30_30)
    }

    func testPhaseMutation() {
        let entry = makeWorkout()
        entry.phase = .phase2
        XCTAssertEqual(entry.phase, .phase2)
        XCTAssertEqual(entry.phaseRaw, "phase2")
    }

    // MARK: - Helpers

    private func makeWorkout(
        duration: TimeInterval = 45 * 60,
        metrics: [String: Double] = ["speed": 3.5, "incline": 3.0],
        avgHR: Int = 140
    ) -> WorkoutEntry {
        WorkoutEntry(
            exerciseType: .treadmill,
            duration: duration,
            metrics: metrics,
            sessionType: .zone2,
            heartRateData: HeartRateData(
                avgHR: avgHR, maxHR: avgHR + 15, minHR: avgHR - 10,
                timeInZone2: 30 * 60, timeInZone4Plus: 0,
                hrDrift: 3.0, recoveryHR: 30, samples: []
            ),
            phase: .phase1,
            weekNumber: 3
        )
    }
}
