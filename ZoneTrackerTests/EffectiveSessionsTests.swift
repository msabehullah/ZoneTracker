import XCTest
@testable import ZoneTracker

// MARK: - Effective Session Math
//
// These tests guard the weekly-target contract. The post-pass-5 rule:
//
//   * `weeklyCardioFrequency` is the user's *current* baseline — how many
//     cardio sessions they're already doing when they join.
//   * `availableTrainingDays` is the *ceiling* — how many they could train.
//   * The plan starts at baseline (week 1) and earns +1 session every
//     `weeksPerRampStep` weeks. Experienced/regular ramp every 2 weeks;
//     occasional every 3; beginner/return-to-training every 4.
//   * `focus` shapes *composition* (interval share), never the total.
//   * `.avoidHighIntensity` keeps intervals at 0, no matter the focus.
//   * target-zone + interval sessions always sum to the planned total.
//
// Consistency gating: when `PhaseManager.missedSessionsLastWeek` fires,
// the recommendation engine falls back to "repeat last week," preventing
// the user from being pushed toward a ramped target they haven't been
// hitting. The target itself is time-based (deterministic from
// `weekNumber`), and the engine gates the user's actual experience.

final class EffectiveSessionsTests: XCTestCase {

    private func makeProfile(
        focus: TrainingFocus = .buildingBase,
        fitnessLevel: FitnessLevel = .occasional,
        goal: CardioGoal = .generalFitness,
        weeklyCardioFrequency: Int = 0,
        availableDays: Int,
        weeksAgo: Int = 0,
        intensityConstraint: IntensityConstraint = .none
    ) -> UserProfile {
        let profile = UserProfile()
        profile.primaryGoal = goal
        profile.fitnessLevel = fitnessLevel
        profile.focus = focus
        profile.weeklyCardioFrequency = weeklyCardioFrequency
        profile.availableTrainingDays = availableDays
        profile.intensityConstraint = intensityConstraint
        if weeksAgo > 0 {
            profile.phaseStartDate = Calendar.current.date(
                byAdding: .weekOfYear, value: -weeksAgo, to: Date()
            ) ?? Date()
        }
        return profile
    }

    // MARK: Week-1 baseline

    func testWeekOneStartsAtBaseline() {
        // Week 1: no bumps earned yet, regardless of fitness level.
        let experienced = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 3,
            availableDays: 7
        )
        XCTAssertEqual(experienced.effectiveSessionsPerWeek, 3,
                       "Week 1 should start at baseline — no instant jump")
        XCTAssertTrue(experienced.hasHeadroomToBuild)
    }

    func testBeginnerBaselineHardCodedToTwo() {
        let profile = makeProfile(
            fitnessLevel: .beginner,
            weeklyCardioFrequency: 0,
            availableDays: 7
        )
        XCTAssertEqual(profile.baselineSessionsPerWeek, 2,
                       "Beginner baseline hard-coded to 2")
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 2,
                       "Week 1 beginner stays at baseline")
    }

    // MARK: Time-based ramp

    func testTargetGrowsOverTimeTowardCeiling() {
        // Experienced user, freq=2, avail=7. Step = 2 weeks.
        // Week 1: 2, Week 3: 3, Week 5: 4, Week 7: 5, Week 9: 6, Week 11: 7
        let w1 = makeProfile(fitnessLevel: .experienced, weeklyCardioFrequency: 2, availableDays: 7, weeksAgo: 0)
        XCTAssertEqual(w1.effectiveSessionsPerWeek, 2, "Week 1 = baseline")

        let w3 = makeProfile(fitnessLevel: .experienced, weeklyCardioFrequency: 2, availableDays: 7, weeksAgo: 2)
        XCTAssertEqual(w3.effectiveSessionsPerWeek, 3, "Week 3 earns first bump")

        let w7 = makeProfile(fitnessLevel: .experienced, weeklyCardioFrequency: 2, availableDays: 7, weeksAgo: 6)
        XCTAssertEqual(w7.effectiveSessionsPerWeek, 5, "Week 7 earns 3 bumps")

        let w11 = makeProfile(fitnessLevel: .experienced, weeklyCardioFrequency: 2, availableDays: 7, weeksAgo: 10)
        XCTAssertEqual(w11.effectiveSessionsPerWeek, 7, "Week 11 reaches ceiling")
    }

    func testTargetDoesNotInstantlyJumpToCeiling() {
        // Even with a large gap between baseline and ceiling, week 1 = baseline.
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7
        )
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 2,
                       "Must not jump from 2 to 7 on day one")
        XCTAssertNotEqual(profile.effectiveSessionsPerWeek,
                          profile.availableSessionsCeiling)
    }

    func testTargetNeverExceedsCeiling() {
        // Far enough out that bumps would overshoot if uncapped.
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 5,
            weeksAgo: 52
        )
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 5,
                       "Target must cap at ceiling even after many weeks")
    }

    func testReturnToTrainingRampsSlowly() {
        // Return-to-training: step = 4 weeks. Baseline = 2, ceiling = 7.
        let w1 = makeProfile(fitnessLevel: .experienced, goal: .returnToTraining,
                             weeklyCardioFrequency: 2, availableDays: 7, weeksAgo: 0)
        XCTAssertEqual(w1.effectiveSessionsPerWeek, 2, "Week 1 at baseline")

        let w5 = makeProfile(fitnessLevel: .experienced, goal: .returnToTraining,
                             weeklyCardioFrequency: 2, availableDays: 7, weeksAgo: 4)
        XCTAssertEqual(w5.effectiveSessionsPerWeek, 3,
                       "Return-to-training earns first bump only at week 5")

        // At the same week, a non-return experienced user would be further ahead.
        let nonReturn = makeProfile(fitnessLevel: .experienced, goal: .generalFitness,
                                    weeklyCardioFrequency: 2, availableDays: 7, weeksAgo: 4)
        XCTAssertEqual(nonReturn.effectiveSessionsPerWeek, 4,
                       "Non-return user ramps faster (step=2)")
    }

    func testBeginnerRampsSlowly() {
        // Beginner: step = 4. Baseline = 2, ceiling = 7.
        let w1 = makeProfile(fitnessLevel: .beginner, weeklyCardioFrequency: 0,
                             availableDays: 7, weeksAgo: 0)
        XCTAssertEqual(w1.effectiveSessionsPerWeek, 2)

        let w5 = makeProfile(fitnessLevel: .beginner, weeklyCardioFrequency: 0,
                             availableDays: 7, weeksAgo: 4)
        XCTAssertEqual(w5.effectiveSessionsPerWeek, 3, "Beginner first bump at week 5")
    }

    func testOccasionalRampsEveryThreeWeeks() {
        // Occasional: step = 3. Baseline = 3, ceiling = 6.
        let w1 = makeProfile(fitnessLevel: .occasional, weeklyCardioFrequency: 3,
                             availableDays: 6, weeksAgo: 0)
        XCTAssertEqual(w1.effectiveSessionsPerWeek, 3)

        let w4 = makeProfile(fitnessLevel: .occasional, weeklyCardioFrequency: 3,
                             availableDays: 6, weeksAgo: 3)
        XCTAssertEqual(w4.effectiveSessionsPerWeek, 4)
    }

    func testPhaseResetRestartsRamp() {
        // weekNumber resets when phaseStartDate resets (e.g., focus transition).
        // A user at week 7 with 3 bumps drops back to 0 bumps after reset.
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 6
        )
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 5, "Pre-reset: 3 bumps")

        profile.phaseStartDate = Date() // simulate focus transition
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 2,
                       "Phase reset drops weekNumber to 1 → back to baseline")
    }

    // MARK: Ceiling and floor clamping

    func testBaselineEqualToCeilingStays() {
        let profile = makeProfile(
            fitnessLevel: .regular,
            weeklyCardioFrequency: 5,
            availableDays: 5,
            weeksAgo: 10
        )
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 5,
                       "If baseline already equals ceiling, stay there regardless of week")
        XCTAssertFalse(profile.hasHeadroomToBuild)
    }

    func testCeilingClampsLowerThanBaseline() {
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 4,
            availableDays: 3,
            weeksAgo: 10
        )
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 3,
                       "Plan may not exceed the user-selected ceiling")
    }

    func testTotalNeverDropsBelowOne() {
        let zero = makeProfile(
            fitnessLevel: .occasional,
            weeklyCardioFrequency: 0,
            availableDays: 0
        )
        XCTAssertEqual(zero.effectiveSessionsPerWeek, 1,
                       "Must never drop to 0 — at least one session a week")

        let negativeCeiling = makeProfile(
            weeklyCardioFrequency: 0,
            availableDays: -3
        )
        XCTAssertEqual(negativeCeiling.effectiveSessionsPerWeek, 1)
    }

    func testCeilingClampsAtSeven() {
        let crazy = makeProfile(weeklyCardioFrequency: 0, availableDays: 42)
        XCTAssertEqual(crazy.availableSessionsCeiling, 7, "Max 7 days per week")
    }

    // MARK: Focus independence

    func testTotalIsIndependentOfFocus() {
        for focus in TrainingFocus.allCases {
            let profile = makeProfile(
                focus: focus,
                fitnessLevel: .regular,
                weeklyCardioFrequency: 3,
                availableDays: 5,
                weeksAgo: 4
            )
            // regular step=2, weekNumber=5, earned=(5-1)/2=2, target=min(5, 3+2)=5
            XCTAssertEqual(
                profile.effectiveSessionsPerWeek, 5,
                "focus \(focus) must not override the baseline-ramp total"
            )
        }
    }

    // MARK: Composition is focus-driven

    func testBuildingBaseGivesZeroIntervals() {
        let profile = makeProfile(
            focus: .buildingBase,
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 4,
            availableDays: 7,
            weeksAgo: 10
        )
        XCTAssertEqual(profile.effectiveIntervalSessions, 0)
        XCTAssertEqual(profile.effectiveTargetZoneSessions,
                       profile.effectiveSessionsPerWeek,
                       "All sessions are target zone when focus is base-building")
    }

    func testActiveRecoveryGivesZeroIntervals() {
        let profile = makeProfile(
            focus: .activeRecovery,
            fitnessLevel: .regular,
            weeklyCardioFrequency: 2,
            availableDays: 4,
            weeksAgo: 6
        )
        XCTAssertEqual(profile.effectiveIntervalSessions, 0)
        XCTAssertEqual(profile.effectiveTargetZoneSessions,
                       profile.effectiveSessionsPerWeek)
    }

    func testDevelopingSpeedScalesIntervalsWithinCap() {
        // experienced freq=1 avail=3 weeksAgo=4 → weekNumber=5, step=2,
        // earned=2, target=min(3, 1+2)=3 → 1 interval
        let three = makeProfile(
            focus: .developingSpeed,
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 1,
            availableDays: 3,
            weeksAgo: 4
        )
        XCTAssertEqual(three.effectiveSessionsPerWeek, 3)
        XCTAssertEqual(three.effectiveIntervalSessions, 1)

        // experienced freq=4 avail=7 weeksAgo=10 → weekNumber=11, step=2,
        // earned=5, target=min(7, 4+5)=7 → 2 intervals (capped)
        let seven = makeProfile(
            focus: .developingSpeed,
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 4,
            availableDays: 7,
            weeksAgo: 10
        )
        XCTAssertEqual(seven.effectiveSessionsPerWeek, 7)
        XCTAssertEqual(seven.effectiveIntervalSessions, 2,
                       "Cap still holds at the top of the range")
    }

    func testPeakPerformanceScalesIntervalsWithinCap() {
        // experienced freq=2 avail=4 weeksAgo=4 → weekNumber=5, step=2,
        // earned=2, target=min(4, 2+2)=4 → 2 intervals
        let four = makeProfile(
            focus: .peakPerformance,
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 4,
            weeksAgo: 4
        )
        XCTAssertEqual(four.effectiveSessionsPerWeek, 4)
        XCTAssertEqual(four.effectiveIntervalSessions, 2)

        // experienced freq=4 avail=7 weeksAgo=10 → target=7 → 3 intervals
        let seven = makeProfile(
            focus: .peakPerformance,
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 4,
            availableDays: 7,
            weeksAgo: 10
        )
        XCTAssertEqual(seven.effectiveSessionsPerWeek, 7)
        XCTAssertEqual(seven.effectiveIntervalSessions, 3,
                       "Interval share is capped at 3")
    }

    func testTargetZonePlusIntervalsAlwaysSumToTotal() {
        // Full matrix across focuses and fitness levels, at various week numbers.
        for focus in TrainingFocus.allCases {
            for level in FitnessLevel.allCases {
                for freq in [0, 2, 4, 7] {
                    for days in [1, 3, 5, 7] {
                        for weeksAgo in [0, 4, 10] {
                            let p = makeProfile(
                                focus: focus,
                                fitnessLevel: level,
                                weeklyCardioFrequency: freq,
                                availableDays: days,
                                weeksAgo: weeksAgo
                            )
                            XCTAssertEqual(
                                p.effectiveTargetZoneSessions + p.effectiveIntervalSessions,
                                p.effectiveSessionsPerWeek,
                                "\(focus)/\(level)/freq\(freq)/avail\(days)/w\(weeksAgo): sum must equal total"
                            )
                            XCTAssertGreaterThanOrEqual(p.effectiveTargetZoneSessions, 0)
                            XCTAssertGreaterThanOrEqual(p.effectiveIntervalSessions, 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: Intensity constraint

    func testAvoidHighIntensityForcesZeroIntervals() {
        for focus in TrainingFocus.allCases {
            let profile = makeProfile(
                focus: focus,
                fitnessLevel: .experienced,
                weeklyCardioFrequency: 4,
                availableDays: 7,
                weeksAgo: 10,
                intensityConstraint: .avoidHighIntensity
            )
            XCTAssertEqual(profile.effectiveIntervalSessions, 0,
                           "avoidHighIntensity must block intervals for focus \(focus)")
            XCTAssertEqual(profile.effectiveTargetZoneSessions,
                           profile.effectiveSessionsPerWeek,
                           "All sessions collapse to target zone when high intensity is off the table")
        }
    }

    func testAvoidHighIntensityStillHonorsPlannedTotal() {
        let profile = makeProfile(
            focus: .peakPerformance,
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 3,
            availableDays: 6,
            weeksAgo: 10,
            intensityConstraint: .avoidHighIntensity
        )
        // experienced step=2, weekNumber=11, earned=5, target=min(6, 3+5)=6
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 6)
        XCTAssertEqual(profile.effectiveTargetZoneSessions, 6)
    }

    // MARK: Headroom signal for UI

    func testHasHeadroomOnlyWhenCeilingExceedsCurrent() {
        // Week 1: experienced freq=2 avail=7 → target=2, ceiling=7 → headroom
        let room = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7
        )
        XCTAssertTrue(room.hasHeadroomToBuild)

        // Far in the future: target should have reached ceiling → no headroom
        let atCeiling = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 20
        )
        XCTAssertFalse(atCeiling.hasHeadroomToBuild,
                       "After enough weeks the ramp reaches the ceiling")
    }

    // MARK: Consistency gating via recommendation engine

    func testMissedSessionsGateBlocksRampedVolumeExperience() {
        // An experienced user at week 7 has a target of 5 (baseline 2 + 3 bumps).
        // If they only logged 1 session last week, PhaseManager triggers the
        // "repeat last week" fallback — they never actually *experience* the
        // ramped target. This test proves the consistency gate fires.
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 6
        )
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 5,
                       "Target has ramped to 5 by week 7")

        // Build 1 workout in last week — 4 missed out of 5
        let calendar = Calendar.current
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: Date().startOfWeek)!
        let sparse = [makeWorkout(date: lastWeekStart.addingTimeInterval(43200))]

        XCTAssertTrue(
            PhaseManager.missedSessionsLastWeek(workouts: sparse, profile: profile),
            "Consistency gate must fire when user missed ≥ half of ramped target"
        )
    }

    // MARK: - Helpers

    private func makeWorkout(date: Date) -> WorkoutEntry {
        let hrData = HeartRateData(
            avgHR: 140, maxHR: 155, minHR: 130,
            timeInZone2: 30 * 60, timeInZone4Plus: 0,
            hrDrift: 2.0, recoveryHR: 30, samples: []
        )
        return WorkoutEntry(
            date: date,
            exerciseType: .treadmill,
            duration: 45 * 60,
            metrics: ["speed": 3.5, "incline": 3.0],
            sessionType: .zone2,
            heartRateData: hrData,
            phase: .phase1,
            weekNumber: 4
        )
    }
}
