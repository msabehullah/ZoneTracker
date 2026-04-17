import XCTest
@testable import ZoneTracker

final class PhaseManagerTests: XCTestCase {

    // MARK: - Phase 1 → 2 Transition

    func testBuildingBaseDoesNotAdvanceBeforeMinimumWeeks() {
        let profile = makeProfile(focus: .buildingBase, weeksAgo: 2)
        let workouts = makeQualifyingBaseWorkouts(weeks: 2)
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNil(result, "Should not advance before minimum weeks in focus")
    }

    func testBuildingBaseAdvancesWithQualifyingWorkouts() {
        let profile = makeProfile(focus: .buildingBase, weeksAgo: 5)
        let workouts = makeQualifyingBaseWorkouts(weeks: 2)
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNotNil(result, "Should advance with 2 weeks of qualifying Zone 2 sessions")
        XCTAssertEqual(result?.newFocus, .developingSpeed)
    }

    func testBuildingBaseDoesNotAdvanceWithHighDrift() {
        let profile = makeProfile(focus: .buildingBase, weeksAgo: 5)
        let workouts = [
            makeWorkout(daysAgo: 3, duration: 50 * 60, sessionType: .zone2, phase: .phase1,
                       avgHR: 140, drift: 8.0),  // drift too high
            makeWorkout(daysAgo: 10, duration: 50 * 60, sessionType: .zone2, phase: .phase1,
                       avgHR: 140, drift: 3.0)
        ]
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNil(result, "Should not advance with HR drift >= 5%")
    }

    func testBuildingBaseDoesNotAdvanceWithShortWorkouts() {
        let profile = makeProfile(focus: .buildingBase, weeksAgo: 5)
        let workouts = [
            makeWorkout(daysAgo: 3, duration: 30 * 60, sessionType: .zone2, phase: .phase1,
                       avgHR: 140, drift: 2.0),  // only 30 min
            makeWorkout(daysAgo: 10, duration: 30 * 60, sessionType: .zone2, phase: .phase1,
                       avgHR: 140, drift: 2.0)
        ]
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNil(result, "Should not advance with sessions < 45 minutes")
    }

    func testBuildingBaseDoesNotAdvanceWhenCurrentWeekIsEmpty() {
        let profile = makeProfile(focus: .buildingBase, weeksAgo: 5)
        let workouts = [
            makeWorkout(daysAgo: 7, duration: 50 * 60, sessionType: .zone2, phase: .phase1, avgHR: 140, drift: 3.0),
            makeWorkout(daysAgo: 14, duration: 50 * 60, sessionType: .zone2, phase: .phase1, avgHR: 140, drift: 3.0)
        ]
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNil(result, "Should require qualifying work in the current and previous week, not skip empty weeks")
    }

    // MARK: - Peak Performance (no transition)

    func testPeakPerformanceNeverTransitions() {
        let profile = makeProfile(focus: .peakPerformance, weeksAgo: 20)
        let workouts = makeQualifyingBaseWorkouts(weeks: 2)
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNil(result, "Peak performance is final — should never trigger transition")
    }

    // MARK: - Active Recovery → Building Base

    func testActiveRecoveryAdvancesToBuildingBase() {
        let profile = makeProfile(focus: .activeRecovery, weeksAgo: 3)
        let workouts = [
            makeWorkoutInCurrentWeek(dayOffset: 0),
            makeWorkoutInCurrentWeek(dayOffset: 1)
        ]
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNotNil(result, "Should advance after minimum weeks with 2+ sessions this week")
        XCTAssertEqual(result?.newFocus, .buildingBase, "activeRecovery should advance to buildingBase, not developingSpeed")
    }

    func testActiveRecoveryDoesNotSkipBuildingBase() {
        let profile = makeProfile(focus: .activeRecovery, weeksAgo: 3)
        let workouts = [
            makeWorkoutInCurrentWeek(dayOffset: 0),
            makeWorkoutInCurrentWeek(dayOffset: 1)
        ]
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNotEqual(result?.newFocus, .developingSpeed, "Should not skip buildingBase")
    }

    // MARK: - Transition does not mutate profile

    func testTransitionDoesNotMutateProfile() {
        let profile = makeProfile(focus: .buildingBase, weeksAgo: 5)
        let workouts = makeQualifyingBaseWorkouts(weeks: 2)
        let _ = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertEqual(profile.focus, .buildingBase, "evaluatePhaseTransition should not mutate profile")
    }

    // MARK: - Consistency

    func testSessionsThisWeek() {
        let workouts = [
            makeWorkout(daysAgo: 0),
            makeWorkout(daysAgo: 1),
            makeWorkout(daysAgo: 14)  // 2 weeks ago — should not count
        ]
        let count = PhaseManager.sessionsThisWeek(workouts: workouts)
        XCTAssertGreaterThanOrEqual(count, 1, "Should count at least today's workout")
    }

    // MARK: Missed-session gate scales with plan volume
    //
    // The gate fires when the user missed at least half their planned target
    // (minimum absolute floor of 2). Tests use the `target:` parameter
    // overload to test gate logic independently from target computation.
    // WeeklyTargetService tests cover the consistency-aware target itself.

    func testSevenDayPlanNotPenalizedAtFiveOfSeven() {
        // target=7, completed 5 → missed 2 → threshold max(2, ceil(7/2)=4)=4 → no trigger.
        let workouts = lastWeekWorkouts(count: 5)
        XCTAssertFalse(
            PhaseManager.missedSessionsLastWeek(workouts: workouts, target: 7),
            "A 5-of-7 week is still a great week — must not be flagged as missed"
        )
    }

    func testSevenDayPlanTriggersOnClearDropOff() {
        // target=7, completed 3 → missed 4 → threshold=4 → triggers.
        let workouts = lastWeekWorkouts(count: 3)
        XCTAssertTrue(
            PhaseManager.missedSessionsLastWeek(workouts: workouts, target: 7),
            "3-of-7 is a real drop-off — should trigger the 'repeat' fallback"
        )
    }

    func testLowFrequencyPlanStillGatedOnTwoMisses() {
        // target=3, completed 1 → missed 2 → threshold max(2, ceil(3/2)=2)=2 → triggers.
        let workouts = lastWeekWorkouts(count: 1)
        XCTAssertTrue(
            PhaseManager.missedSessionsLastWeek(workouts: workouts, target: 3),
            "1-of-3 is a real slip on a small plan — must still trigger"
        )
    }

    func testFiveDayPlanNotPenalizedAtThreeOfFive() {
        // target=5, completed 3 → missed 2 → threshold max(2, ceil(5/2)=3)=3 → no trigger.
        let workouts = lastWeekWorkouts(count: 3)
        XCTAssertFalse(
            PhaseManager.missedSessionsLastWeek(workouts: workouts, target: 5),
            "3-of-5 shouldn't trigger fallback — 40% miss rate on a mid-volume plan"
        )
    }

    // MARK: - Helpers

    private func makeProfile(focus: TrainingFocus, weeksAgo: Int) -> UserProfile {
        let profile = UserProfile()
        profile.focus = focus
        profile.phaseStartDate = Calendar.current.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date()) ?? Date()
        return profile
    }

    // Keep legacy helper for tests that need specific phase values on workouts
    private func makeProfile(phase: TrainingPhase, weeksAgo: Int) -> UserProfile {
        let profile = UserProfile()
        profile.phase = phase
        profile.phaseStartDate = Calendar.current.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date()) ?? Date()
        return profile
    }

    private func makeWorkout(
        daysAgo: Int,
        duration: TimeInterval = 45 * 60,
        sessionType: SessionType = .zone2,
        phase: TrainingPhase = .phase1,
        avgHR: Int = 140,
        drift: Double = 2.0
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

    private func makeQualifyingBaseWorkouts(weeks: Int) -> [WorkoutEntry] {
        var workouts: [WorkoutEntry] = []
        for week in 0..<weeks {
            // Use week * 7 so week 0 = today (current week) and week 1 = 7 days ago (previous week)
            workouts.append(
                makeWorkout(daysAgo: week * 7, duration: 50 * 60, sessionType: .zone2,
                           phase: .phase1, avgHR: 140, drift: 3.0)
            )
        }
        return workouts
    }

    /// Build `count` workouts dated inside the previous calendar week —
    /// used by `missedSessionsLastWeek` gating tests.
    private func lastWeekWorkouts(count: Int) -> [WorkoutEntry] {
        let calendar = Calendar.current
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: Date().startOfWeek)!
        var workouts: [WorkoutEntry] = []
        for i in 0..<count {
            // Spread the sessions across last week so they all land in the
            // same weekly window regardless of which weekday "today" is.
            let dayOffset = min(6, i)
            let date = lastWeekStart.addingTimeInterval(
                Double(dayOffset) * 86400 + 43200
            )
            workouts.append(makeWorkout(date: date))
        }
        return workouts
    }

    private func makeWorkoutInCurrentWeek(
        dayOffset: Int = 0,
        sessionType: SessionType = .zone2,
        phase: TrainingPhase = .phase1
    ) -> WorkoutEntry {
        let date = Date().startOfWeek.addingTimeInterval(Double(dayOffset) * 86400 + 43200)
        return makeWorkout(date: date, sessionType: sessionType, phase: phase)
    }

    private func makeWorkout(
        date: Date,
        duration: TimeInterval = 45 * 60,
        sessionType: SessionType = .zone2,
        phase: TrainingPhase = .phase1,
        avgHR: Int = 140,
        drift: Double = 2.0
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
}
