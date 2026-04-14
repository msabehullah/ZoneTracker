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
        let workouts = lastWeekFillers() + [makeWorkout(daysAgo: 0, avgHR: 160)]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)

        XCTAssertEqual(rec.sessionType, .zone2)
        XCTAssertEqual(rec.adjustmentType, .decreaseIntensity)
    }

    func testIncreasesIntensityWhenHRTooLow() {
        let profile = makeProfile()
        let workouts = lastWeekFillers() + [makeWorkout(daysAgo: 0, avgHR: 120)]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)

        XCTAssertEqual(rec.sessionType, .zone2)
        XCTAssertEqual(rec.adjustmentType, .increaseIntensity)
    }

    func testHoldsSteadyOnSignificantDrift() {
        let profile = makeProfile()
        let workouts = lastWeekFillers() + [makeWorkout(daysAgo: 0, avgHR: 140, drift: 12.0)]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)

        XCTAssertEqual(rec.adjustmentType, .holdSteady)
    }

    func testProgressesWhenInZoneAndStable() {
        let profile = makeProfile()
        let workouts = lastWeekFillers() + [makeWorkout(daysAgo: 0, avgHR: 140, drift: 3.0, duration: 40 * 60)]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)

        // Should increase duration or intensity
        let progressTypes: Set<AdjustmentType> = [.increaseDuration, .increaseIntensity]
        XCTAssertTrue(progressTypes.contains(rec.adjustmentType),
                     "Expected progression, got \(rec.adjustmentType)")
    }

    // MARK: - Phase 1 Always Zone 2

    func testPhase1AlwaysRecommendsZone2() {
        let profile = makeProfile(phase: .phase1)
        let workouts = lastWeekFillers() + (0..<3).map { i in
            makeWorkoutInCurrentWeek(dayOffset: i, avgHR: 140)
        }
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)
        XCTAssertEqual(rec.sessionType, .zone2, "Phase 1 should only have Zone 2 sessions")
    }

    // MARK: - Phase 2 Intervals

    func testPhase2AddsIntervalsAfterZone2Complete() {
        let profile = makeProfile(phase: .phase2)
        // 2 Zone 2 sessions this week + fillers in last week
        let workouts = lastWeekFillers(phase: .phase2) + [
            makeWorkoutInCurrentWeek(dayOffset: 0, sessionType: .zone2, phase: .phase2),
            makeWorkoutInCurrentWeek(dayOffset: 1, sessionType: .zone2, phase: .phase2)
        ]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)
        XCTAssertTrue(rec.sessionType.isInterval, "Should recommend interval after 2 Zone 2 sessions")
    }

    func testPhase2DefersIntervalsOnLegDay() {
        let profile = makeProfile(phase: .phase2)
        profile.legDays = [Date().weekday]
        let workouts = lastWeekFillers(phase: .phase2) + [
            makeWorkoutInCurrentWeek(dayOffset: 0, sessionType: .zone2, phase: .phase2),
            makeWorkoutInCurrentWeek(dayOffset: 1, sessionType: .zone2, phase: .phase2)
        ]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)
        XCTAssertEqual(rec.sessionType, .zone2, "Leg day should defer high-intensity work")
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
        XCTAssertGreaterThan(bikeMetrics["resistance"]!, 1)
        XCTAssertLessThan(bikeMetrics["resistance"]!, 30)
    }

    // MARK: - 48-Hour Spacing

    func testPhase3Enforces48HourSpacing() {
        let profile = makeProfile(phase: .phase3)
        let now = Date()
        // Place 2 Zone 2 + 1 recent interval in current week + fillers in last week
        let workouts = lastWeekFillers(count: 3, phase: .phase3) + [
            makeWorkoutInCurrentWeek(dayOffset: 0, sessionType: .zone2, phase: .phase3),
            makeWorkoutInCurrentWeek(dayOffset: 1, sessionType: .zone2, phase: .phase3),
            makeWorkoutAt(date: now.addingTimeInterval(-3600), sessionType: .interval_30_30, phase: .phase3)
        ]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)
        // Should recommend Zone 2 instead of another interval due to 48h spacing
        XCTAssertEqual(rec.sessionType, .zone2,
                      "Should return Zone 2 when interval was < 48h ago")
    }

    // MARK: - Avoid High Intensity

    func testAvoidHighIntensityBlocksIntervals() {
        let profile = makeProfile(phase: .phase2)
        profile.intensityConstraint = .avoidHighIntensity
        let workouts = lastWeekFillers(phase: .phase2) + [
            makeWorkoutInCurrentWeek(dayOffset: 0, sessionType: .zone2, phase: .phase2),
            makeWorkoutInCurrentWeek(dayOffset: 1, sessionType: .zone2, phase: .phase2)
        ]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: workouts)
        XCTAssertEqual(rec.sessionType, .zone2,
                      "Avoid high intensity constraint should block interval recommendations")
    }

    // MARK: - Low Impact Preference

    func testLowImpactPreferenceInfluencesExerciseType() {
        let profile = makeProfile(phase: .phase1)
        profile.intensityConstraint = .lowImpactPreferred
        profile.preferredModalities = [ExerciseType.treadmill.rawValue, ExerciseType.bike.rawValue]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: [])
        // With low-impact preference and bike in preferred, should choose bike over treadmill
        XCTAssertEqual(rec.exerciseType, .bike,
                      "Low-impact preference should choose bike when available in preferred modalities")
    }

    // MARK: - Preferred Modalities

    func testPreferredModalityUsedForFirstWorkout() {
        let profile = makeProfile(phase: .phase1)
        profile.preferredModalities = [ExerciseType.elliptical.rawValue]
        let rec = RecommendationEngine.recommend(profile: profile, workouts: [])
        XCTAssertEqual(rec.exerciseType, .elliptical,
                      "First workout should use preferred exercise type")
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
        return makeWorkoutAt(date: date, avgHR: avgHR, drift: drift, duration: duration,
                            sessionType: sessionType, phase: phase)
    }

    private func makeWorkoutInCurrentWeek(
        dayOffset: Int = 0,
        avgHR: Int = 140,
        drift: Double = 3.0,
        duration: TimeInterval = 45 * 60,
        sessionType: SessionType = .zone2,
        phase: TrainingPhase = .phase1
    ) -> WorkoutEntry {
        let date = Date().startOfWeek.addingTimeInterval(Double(dayOffset) * 86400 + 43200)
        return makeWorkoutAt(date: date, avgHR: avgHR, drift: drift, duration: duration,
                            sessionType: sessionType, phase: phase)
    }

    private func makeWorkoutAt(
        date: Date,
        avgHR: Int = 140,
        drift: Double = 3.0,
        duration: TimeInterval = 45 * 60,
        sessionType: SessionType = .zone2,
        phase: TrainingPhase = .phase1
    ) -> WorkoutEntry {
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

    /// Creates filler workouts in the previous calendar week to pass the consistency check.
    private func lastWeekFillers(
        count: Int = 3,
        phase: TrainingPhase = .phase1
    ) -> [WorkoutEntry] {
        let calendar = Calendar.current
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: Date().startOfWeek)!
        return (0..<count).map { i in
            let date = lastWeekStart.addingTimeInterval(Double(i + 1) * 86400 + 43200)
            return makeWorkoutAt(date: date, phase: phase)
        }
    }
}
