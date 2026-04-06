import XCTest
@testable import ZoneTracker

final class ExtensionsTests: XCTestCase {

    // MARK: - Date Extensions

    func testStartOfWeekIsBeforeOrEqualToDate() {
        let now = Date()
        XCTAssertLessThanOrEqual(now.startOfWeek, now)
    }

    func testStartOfWeekIsSunday() {
        let weekday = Calendar.current.component(.weekday, from: Date().startOfWeek)
        XCTAssertEqual(weekday, 1, "startOfWeek should be Sunday (weekday=1)")
    }

    func testDaysAgo() {
        let now = Date()
        let threeDaysAgo = now.daysAgo(3)
        let diff = Calendar.current.dateComponents([.day], from: threeDaysAgo, to: now).day!
        XCTAssertEqual(diff, 3)
    }

    func testWeeksAgo() {
        let now = Date()
        let twoWeeksAgo = now.weeksAgo(2)
        let diff = Calendar.current.dateComponents([.weekOfYear], from: twoWeeksAgo, to: now).weekOfYear!
        XCTAssertEqual(diff, 2)
    }

    func testRelativeDescriptionToday() {
        XCTAssertEqual(Date().relativeDescription, "Today")
    }

    func testRelativeDescriptionYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertEqual(yesterday.relativeDescription, "Yesterday")
    }

    // MARK: - TimeInterval Extensions

    func testMinutesAndSeconds() {
        XCTAssertEqual(TimeInterval(90).minutesAndSeconds, "1:30")
        XCTAssertEqual(TimeInterval(3600).minutesAndSeconds, "60:00")
        XCTAssertEqual(TimeInterval(0).minutesAndSeconds, "0:00")
    }

    func testFormattedDurationMinutesOnly() {
        XCTAssertEqual(TimeInterval(45 * 60).formattedDuration, "45 min")
    }

    func testFormattedDurationWithHours() {
        XCTAssertEqual(TimeInterval(90 * 60).formattedDuration, "1h 30m")
    }

    // MARK: - Int Extensions

    func testBpmFormatted() {
        XCTAssertEqual(140.bpmFormatted, "140 bpm")
    }

    // MARK: - Array<WorkoutEntry> Extensions

    func testZone2SessionsFilter() {
        let workouts = [
            makeWorkout(sessionType: .zone2),
            makeWorkout(sessionType: .interval_30_30),
            makeWorkout(sessionType: .zone2)
        ]
        XCTAssertEqual(workouts.zone2Sessions().count, 2)
    }

    func testIntervalSessionsFilter() {
        let workouts = [
            makeWorkout(sessionType: .zone2),
            makeWorkout(sessionType: .interval_30_30),
            makeWorkout(sessionType: .zone2)
        ]
        XCTAssertEqual(workouts.intervalSessions().count, 1)
    }

    func testInPhaseFilter() {
        let workouts = [
            makeWorkout(phase: .phase1),
            makeWorkout(phase: .phase2),
            makeWorkout(phase: .phase1)
        ]
        XCTAssertEqual(workouts.inPhase(.phase1).count, 2)
        XCTAssertEqual(workouts.inPhase(.phase2).count, 1)
    }

    func testSortedByDateDescending() {
        let old = makeWorkout(daysAgo: 5)
        let mid = makeWorkout(daysAgo: 2)
        let recent = makeWorkout(daysAgo: 0)
        let sorted = [mid, old, recent].sortedByDate()
        XCTAssertEqual(sorted.first?.date.timeIntervalSince1970 ?? 0,
                       recent.date.timeIntervalSince1970, accuracy: 1)
    }

    func testGroupedByWeek() {
        let thisWeek = makeWorkout(daysAgo: 0)
        let lastWeek = makeWorkout(daysAgo: 8)
        let groups = [thisWeek, lastWeek].groupedByWeek()
        XCTAssertGreaterThanOrEqual(groups.count, 1)
    }

    func testInCurrentWeekFiltersOldWorkouts() {
        let today = makeWorkout(daysAgo: 0)
        let twoWeeksAgo = makeWorkout(daysAgo: 14)
        let result = [today, twoWeeksAgo].inCurrentWeek()
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - HeartRateData

    func testHasSignificantDrift() {
        let low = HeartRateData(avgHR: 140, maxHR: 155, minHR: 130,
                                timeInZone2: 30 * 60, timeInZone4Plus: 0,
                                hrDrift: 5.0, recoveryHR: nil, samples: [])
        XCTAssertFalse(low.hasSignificantDrift)

        let high = HeartRateData(avgHR: 140, maxHR: 155, minHR: 130,
                                 timeInZone2: 30 * 60, timeInZone4Plus: 0,
                                 hrDrift: 10.0, recoveryHR: nil, samples: [])
        XCTAssertTrue(high.hasSignificantDrift)
    }

    func testIntervalProtocolDescription() {
        let short = IntervalProtocol(workDuration: 30, restDuration: 30, rounds: 8,
                                     targetWorkHRLow: 160, targetWorkHRHigh: 175)
        XCTAssertTrue(short.description.contains("8"))
        XCTAssertTrue(short.description.contains("30s"))

        let long = IntervalProtocol(workDuration: 240, restDuration: 240, rounds: 4,
                                    targetWorkHRLow: 170, targetWorkHRHigh: 185)
        XCTAssertTrue(long.description.contains("4min"))
    }

    func testIntervalProtocolTotalDuration() {
        let proto = IntervalProtocol(workDuration: 30, restDuration: 30, rounds: 10,
                                     targetWorkHRLow: 160, targetWorkHRHigh: 175)
        XCTAssertEqual(proto.totalDuration, 600) // 10 * (30+30)
    }

    // MARK: - Helpers

    private func makeWorkout(
        daysAgo: Int = 0,
        sessionType: SessionType = .zone2,
        phase: TrainingPhase = .phase1
    ) -> WorkoutEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return WorkoutEntry(
            date: date,
            exerciseType: .treadmill,
            duration: 45 * 60,
            metrics: ["speed": 3.5],
            sessionType: sessionType,
            heartRateData: .empty,
            phase: phase,
            weekNumber: 1
        )
    }
}
