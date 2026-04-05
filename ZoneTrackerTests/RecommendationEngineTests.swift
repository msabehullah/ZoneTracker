import XCTest
@testable import ZoneTracker

final class RecommendationEngineTests: XCTestCase {

    // MARK: - First Workout

    func testDefaultFirstWorkoutForNewUser() {
        let profile = makeProfile()
        let rec = RecommendationEngine.recommend(profile: profile, workouts: [])

        XCTAssertEqual(rec.sessionType, .zone2)
        XCTAssertEqual(rec.exerciseType, .treadmill)
        XCTAssertEqual(rec.targetDurationMinutes, 30)
        XCTAssertEqual(rec.targetHRLow, 130)
        XCTAssertEqual(rec.targetHRHigh, 150)
    }

    // MARK: - Zone 2 Adjustments

    func testReducesIntensityWhenHRTooHigh() {
        let profile = makeProfile()
        let workouts = [makeWorkout(avgHR: 160)]  // well above zone 2 ceiling of 150
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)

        XCTAssertEqual(rec.sessionType, .zone2)
        XCTAssertEqual(rec.adjustmentType, .decreaseIntensity)
    }

    func testIncreasesIntensityWhenHRTooLow() {
        let profile = makeProfile()
        let workouts = [makeWorkout(avgHR: 120)]  // well below zone 2 floor of 130
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)

        XCTAssertEqual(rec.sessionType, .zone2)
        XCTAssertEqual(rec.adjustmentType, .increaseIntensity)
    }

    func testHoldsSteadyOnSignificantDrift() {
        let profile = makeProfile()
        let workouts = [makeWorkout(avgHR: 140, drift: 12.0)]  // drift >= 10%
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)

        XCTAssertEqual(rec.adjustmentType, .holdSteady)
    }

    func testProgressesWhenInZoneAndStable() {
        let profile = makeProfile()
        let workouts = [makeWorkout(avgHR: 140, drift: 3.0, duration: 40 * 60)]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)

        // Should increase duration or intensity
        let progressTypes: Set<AdjustmentType> = [.increaseDuration, .increaseIntensity]
        XCTAssertTrue(progressTypes.contains(rec.adjustmentType),
                     "Expected progression, got \(rec.adjustmentType)")
    }

    // MARK: - Phase 1 Always Zone 2

    func testPhase1AlwaysRecommendsZone2() {
        let profile = makeProfile(phase: .phase1)
        let workouts = (0..<5).map { i in
            makeWorkout(daysAgo: i, avgHR: 140)
        }
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)
        XCTAssertEqual(rec.sessionType, .zone2, "Phase 1 should only have Zone 2 sessions")
    }

    // MARK: - Phase 2 Intervals

    func testPhase2AddsIntervalsAfterZone2Complete() {
        let profile = makeProfile(phase: .phase2)
        // 2 Zone 2 sessions this week
        let workouts = [
            makeWorkout(daysAgo: 0, sessionType: .zone2, phase: .phase2),
            makeWorkout(daysAgo: 1, sessionType: .zone2, phase: .phase2)
        ]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)
        XCTAssertTrue(rec.sessionType.isInterval, "Should recommend interval after 2 Zone 2 sessions")
    }

    // MARK: - Consistency Check

    func testRepeatLastWorkoutWhenMissedSessions() {
        let profile = makeProfile(phase: .phase1)
        // Only 1 workout last week (target is 3) — missed 2+
        let lastWeekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date().startOfWeek)!
        let workout = WorkoutEntry(
            date: lastWeekStart.addingTimeInterval(86400),
            exerciseType: .treadmill,
            duration: 40 * 60,
            metrics: ["speed": 3.5, "incline": 3.0],
            sessionType: .zone2,
            heartRateData: HeartRateData(
                avgHR: 140, maxHR: 155, minHR: 130,
                timeInZone2: 30 * 60, timeInZone4Plus: 0,
                hrDrift: 3.0, recoveryHR: 30, samples: []
            ),
            phase: .phase1,
            weekNumber: 3
        )
        let rec = RecommendationEngine.recommend(profile: profile, workouts: [workout])
        XCTAssertEqual(rec.adjustmentType, .holdSteady)
        XCTAssertTrue(rec.reasoning.contains("Consistency"), "Should mention consistency")
    }

    // MARK: - Metric Translation

    func testTranslateMetricsBetweenExercises() {
        let treadmillMetrics: [String: Double] = ["speed": 6.5, "incline": 3.0]
        let bikeMetrics = RecommendationEngine.translateMetrics(
            from: .treadmill, to: .bike, metrics: treadmillMetrics
        )

        XCTAssertNotNil(bikeMetrics["resistance"])
        XCTAssertNotNil(bikeMetrics["cadence"])
        // Speed 6.5 is 50% into treadmill range (1-12), so bike metrics should be roughly mid-range
        XCTAssertGreaterThan(bikeMetrics["resistance"]!, 1)
        XCTAssertLessThan(bikeMetrics["resistance"]!, 30)
    }

    // MARK: - 48-Hour Spacing

    func testPhase3Enforces48HourSpacing() {
        let profile = makeProfile(phase: .phase3)
        // 2 Zone 2 done + 1 interval done very recently (< 48h ago)
        let workouts = [
            makeWorkout(daysAgo: 0, sessionType: .interval_30_30, phase: .phase3),
            makeWorkout(daysAgo: 1, sessionType: .zone2, phase: .phase3),
            makeWorkout(daysAgo: 2, sessionType: .zone2, phase: .phase3)
        ]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)
        // Should recommend Zone 2 instead of another interval due to 48h spacing
        XCTAssertEqual(rec.sessionType, .zone2,
                      "Should return Zone 2 when interval was < 48h ago")
    }

    // MARK: - Helpers

    private func makeProfile(phase: TrainingPhase = .phase1) -> UserProfile {
        let profile = UserProfile()
        profile.phase = phase
        profile.phaseStartDate = Calendar.current.date(byAdding: .weekOfYear, value: -6, to: Date()) ?? Date()
        return profile
    }

    private func makeWorkout(
        daysAgo: Int = 1,
        avgHR: Int = 140,
        drift: Double = 3.0,
        duration: TimeInterval = 45 * 60,
        sessionType: SessionType = .zone2,
        phase: TrainingPhase = .phase1
    ) -> WorkoutEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let hrData = HeartRateData(
            avgHR: avgHR, maxHR: avgHR + 15, minHR: avgHR - 10,
            timeInZone2: duration * 0.8, timeInZone4Plus: 0,
            hrDrift: drift, recoveryHR: 30, samples: []
        )
        return WorkoutEntry(
            date: date,
            exerciseType: .treadmill,
            duration: duration,
            metrics: ["speed": 3.5, "incline": 3.0],
            sessionType: sessionType,
            heartRateData: hrData,
            phase: phase,
            weekNumber: 4
        )
    }
}
