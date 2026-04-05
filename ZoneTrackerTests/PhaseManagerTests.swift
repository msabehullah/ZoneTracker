import XCTest
@testable import ZoneTracker

final class PhaseManagerTests: XCTestCase {

    // MARK: - Phase 1 → 2 Transition

    func testPhase1DoesNotAdvanceBefore5Weeks() {
        let profile = makeProfile(phase: .phase1, weeksAgo: 3)
        let workouts = makeQualifyingPhase1Workouts(weeks: 2)
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNil(result, "Should not advance before minimum 5 weeks")
    }

    func testPhase1AdvancesWithQualifyingWorkouts() {
        let profile = makeProfile(phase: .phase1, weeksAgo: 6)
        let workouts = makeQualifyingPhase1Workouts(weeks: 2)
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNotNil(result, "Should advance with 2 weeks of qualifying Zone 2 sessions")
    }

    func testPhase1DoesNotAdvanceWithHighDrift() {
        let profile = makeProfile(phase: .phase1, weeksAgo: 6)
        let workouts = [
            makeWorkout(daysAgo: 3, duration: 50 * 60, sessionType: .zone2, phase: .phase1,
                       avgHR: 140, drift: 8.0),  // drift too high
            makeWorkout(daysAgo: 10, duration: 50 * 60, sessionType: .zone2, phase: .phase1,
                       avgHR: 140, drift: 3.0)
        ]
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNil(result, "Should not advance with HR drift >= 5%")
    }

    func testPhase1DoesNotAdvanceWithShortWorkouts() {
        let profile = makeProfile(phase: .phase1, weeksAgo: 6)
        let workouts = [
            makeWorkout(daysAgo: 3, duration: 30 * 60, sessionType: .zone2, phase: .phase1,
                       avgHR: 140, drift: 2.0),  // only 30 min
            makeWorkout(daysAgo: 10, duration: 30 * 60, sessionType: .zone2, phase: .phase1,
                       avgHR: 140, drift: 2.0)
        ]
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNil(result, "Should not advance with sessions < 45 minutes")
    }

    // MARK: - Phase 3 (no transition)

    func testPhase3NeverTransitions() {
        let profile = makeProfile(phase: .phase3, weeksAgo: 20)
        let workouts = makeQualifyingPhase1Workouts(weeks: 2)
        let result = PhaseManager.evaluatePhaseTransition(profile: profile, workouts: workouts)
        XCTAssertNil(result, "Phase 3 is final — should never trigger transition")
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

    // MARK: - Helpers

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

    private func makeQualifyingPhase1Workouts(weeks: Int) -> [WorkoutEntry] {
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
}
