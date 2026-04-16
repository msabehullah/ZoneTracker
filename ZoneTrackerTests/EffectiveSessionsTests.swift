import XCTest
@testable import ZoneTracker

// MARK: - Effective Session Math
//
// These tests guard the weekly-target contract. The post-pass-4 rule:
//
//   * `weeklyCardioFrequency` is the user's *current* baseline — how many
//     cardio sessions they're already doing when they join.
//   * `availableTrainingDays` is the *ceiling* — how many they could train.
//   * The plan ramps from baseline toward ceiling; ramp size depends on
//     fitness level (experienced gets a bigger jump; beginner/return-to-
//     training gets none) and is always clamped to the ceiling.
//   * `focus` shapes *composition* (interval share), never the total.
//   * `.avoidHighIntensity` keeps intervals at 0, no matter the focus.
//   * target-zone + interval sessions always sum to the planned total.
//
// Anything that reads effective session counts — Dashboard "This Week",
// Progress "Target", PlanOverview snapshot, ProgramExplanation weekly
// structure — flows through these properties, so this is the one place to
// lock the math down.

final class EffectiveSessionsTests: XCTestCase {

    private func makeProfile(
        focus: TrainingFocus = .buildingBase,
        fitnessLevel: FitnessLevel = .occasional,
        goal: CardioGoal = .generalFitness,
        weeklyCardioFrequency: Int = 0,
        availableDays: Int,
        intensityConstraint: IntensityConstraint = .none
    ) -> UserProfile {
        let profile = UserProfile()
        profile.primaryGoal = goal
        profile.fitnessLevel = fitnessLevel
        profile.focus = focus
        profile.weeklyCardioFrequency = weeklyCardioFrequency
        profile.availableTrainingDays = availableDays
        profile.intensityConstraint = intensityConstraint
        return profile
    }

    // MARK: Baseline-to-ceiling ramp

    func testExperiencedUserGetsBiggerRampButStaysUnderCeiling() {
        // Current 2, capacity 7, experienced fitness — we should add 3
        // (not skip straight to 7). That's the whole point of the ramp.
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7
        )
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 5,
                       "Experienced user at 2→7 should start at baseline+3")
        XCTAssertEqual(profile.availableSessionsCeiling, 7)
        XCTAssertTrue(profile.hasHeadroomToBuild,
                      "5 of 7 should leave headroom for UI to surface")
    }

    func testBeginnerUsesConservativeBaselineAndNoRamp() {
        // Beginners don't report a frequency (draft stores 0), so the
        // baseline is a conservative 2 regardless of what comes in.
        let profile = makeProfile(
            fitnessLevel: .beginner,
            weeklyCardioFrequency: 0,
            availableDays: 7
        )
        XCTAssertEqual(profile.baselineSessionsPerWeek, 2,
                       "Beginner baseline hard-coded to 2")
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 2,
                       "Beginner ramp allowance is 0 — stay at baseline")
    }

    func testReturnToTrainingCapsRampAtZero() {
        // Returning users need to restore consistency, not add volume.
        let profile = makeProfile(
            fitnessLevel: .experienced,
            goal: .returnToTraining,
            weeklyCardioFrequency: 2,
            availableDays: 7
        )
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 2,
                       "Return-to-training never ramps above current")
    }

    func testBaselineEqualToCeilingStays() {
        let profile = makeProfile(
            fitnessLevel: .regular,
            weeklyCardioFrequency: 5,
            availableDays: 5
        )
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 5,
                       "If baseline already equals ceiling, stay there")
        XCTAssertFalse(profile.hasHeadroomToBuild)
    }

    func testCeilingClampsLowerThanBaseline() {
        // If the user reports training more than they're available for,
        // the plan respects the ceiling they actually committed to.
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 4,
            availableDays: 3
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

    func testTotalIsIndependentOfFocus() {
        for focus in TrainingFocus.allCases {
            let profile = makeProfile(
                focus: focus,
                fitnessLevel: .regular,
                weeklyCardioFrequency: 3,
                availableDays: 5
            )
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
            availableDays: 7
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
            availableDays: 4
        )
        XCTAssertEqual(profile.effectiveIntervalSessions, 0)
        XCTAssertEqual(profile.effectiveTargetZoneSessions,
                       profile.effectiveSessionsPerWeek)
    }

    func testDevelopingSpeedScalesIntervalsWithinCap() {
        // Roughly one interval per three sessions, capped at 2.
        // experienced + freq 1 + avail 3 → target 3 (baseline 1 + ramp 3,
        // capped to 3) → 1 interval.
        let three = makeProfile(
            focus: .developingSpeed,
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 1,
            availableDays: 3
        )
        XCTAssertEqual(three.effectiveSessionsPerWeek, 3)
        XCTAssertEqual(three.effectiveIntervalSessions, 1)

        // experienced + freq 4 + avail 7 → target 7 → 2 intervals (capped)
        let seven = makeProfile(
            focus: .developingSpeed,
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 4,
            availableDays: 7
        )
        XCTAssertEqual(seven.effectiveSessionsPerWeek, 7)
        XCTAssertEqual(seven.effectiveIntervalSessions, 2,
                       "Cap still holds at the top of the range")
    }

    func testPeakPerformanceScalesIntervalsWithinCap() {
        // Roughly one interval per two sessions, capped at 3.
        let four = makeProfile(
            focus: .peakPerformance,
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 4
        )
        XCTAssertEqual(four.effectiveSessionsPerWeek, 4)
        XCTAssertEqual(four.effectiveIntervalSessions, 2)

        let seven = makeProfile(
            focus: .peakPerformance,
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 4,
            availableDays: 7
        )
        XCTAssertEqual(seven.effectiveSessionsPerWeek, 7)
        XCTAssertEqual(seven.effectiveIntervalSessions, 3,
                       "Interval share is capped at 3")
    }

    func testTargetZonePlusIntervalsAlwaysSumToTotal() {
        // Full matrix — every (focus, fitnessLevel, freq, ceiling) must
        // sum cleanly to the planned total.
        for focus in TrainingFocus.allCases {
            for level in FitnessLevel.allCases {
                for freq in 0...7 {
                    for days in 1...7 {
                        let p = makeProfile(
                            focus: focus,
                            fitnessLevel: level,
                            weeklyCardioFrequency: freq,
                            availableDays: days
                        )
                        XCTAssertEqual(
                            p.effectiveTargetZoneSessions + p.effectiveIntervalSessions,
                            p.effectiveSessionsPerWeek,
                            "\(focus)/\(level)/\(freq)→\(days): target-zone + intervals must equal total"
                        )
                        XCTAssertGreaterThanOrEqual(p.effectiveTargetZoneSessions, 0)
                        XCTAssertGreaterThanOrEqual(p.effectiveIntervalSessions, 0)
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
        // Regression guard — capping intervals must never cap the total.
        let profile = makeProfile(
            focus: .peakPerformance,
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 3,
            availableDays: 6,
            intensityConstraint: .avoidHighIntensity
        )
        // experienced + freq 3 + avail 6 → baseline 3 + ramp 3 = 6, capped 6
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 6)
        XCTAssertEqual(profile.effectiveTargetZoneSessions, 6)
    }

    // MARK: Headroom signal for UI

    func testHasHeadroomOnlyWhenCeilingExceedsCurrent() {
        let room = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7
        )
        XCTAssertTrue(room.hasHeadroomToBuild)

        let atCeiling = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 7,
            availableDays: 7
        )
        XCTAssertFalse(atCeiling.hasHeadroomToBuild,
                       "Baseline already at ceiling — no room to build")
    }
}
