import XCTest
@testable import ZoneTracker

// MARK: - Effective Session Math
//
// These tests guard the weekly-target contract. The post-pass-6 rule:
//
//   * `weeklyCardioFrequency` is the user's *current* baseline — how many
//     cardio sessions they're already doing when they join.
//   * `availableTrainingDays` is the *ceiling* — how many they could train.
//   * The plan starts at baseline (week 1) and earns +1 session every
//     `weeksPerRampStep` *consistent* weeks. A week is "consistent" when
//     the user completed at least half the then-current target (min 1).
//     Inconsistent weeks pause growth but don't reset it.
//   * `WeeklyTargetService.currentTarget(profile:workouts:)` is the single
//     source of truth for any consumer that has workout history.
//   * `UserProfile.effectiveSessionsPerWeek` returns the workout-free
//     baseline (for onboarding contexts without history).
//   * `focus` shapes *composition* (interval share), never the total.
//   * `.avoidHighIntensity` keeps intervals at 0, no matter the focus.
//   * target-zone + interval sessions always sum to the planned total.

final class EffectiveSessionsTests: XCTestCase {

    // MARK: - Helpers

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

    /// Build `count` workouts per week for each of the last `weeks` completed
    /// weeks. The workouts land in the previous calendar weeks (not the current
    /// week, which hasn't completed yet).
    private func makeConsistentHistory(
        weeks: Int,
        sessionsPerWeek: Int,
        weeksAgo startWeeksAgo: Int = 0
    ) -> [WorkoutEntry] {
        let calendar = Calendar.current
        let currentWeekStart = Date().startOfWeek
        var workouts: [WorkoutEntry] = []

        // Walk backwards from the most recent completed week
        for w in 0..<weeks {
            let weekOffset = -(w + 1 + startWeeksAgo)
            let weekStart = calendar.date(
                byAdding: .weekOfYear, value: weekOffset, to: currentWeekStart
            )!
            for s in 0..<sessionsPerWeek {
                let day = min(6, s)
                let date = weekStart.addingTimeInterval(Double(day) * 86400 + 43200)
                workouts.append(makeWorkout(date: date))
            }
        }

        return workouts
    }

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

    // MARK: - Profile baseline (workout-free)

    func testWeekOneStartsAtBaseline() {
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 3,
            availableDays: 7
        )
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 3,
                       "Profile-only API returns baseline for contexts without workouts")
        XCTAssertTrue(profile.hasHeadroomToBuild)
    }

    func testBeginnerBaselineHardCodedToTwo() {
        let profile = makeProfile(
            fitnessLevel: .beginner,
            weeklyCardioFrequency: 0,
            availableDays: 7
        )
        XCTAssertEqual(profile.baselineSessionsPerWeek, 2)
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 2)
    }

    // MARK: - Consistency-aware ramp (WeeklyTargetService)

    func testTargetDoesNotGrowWithoutWorkouts() {
        // Profile started 10 weeks ago but zero workouts → target stays at baseline
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 10
        )
        let target = WeeklyTargetService.currentTarget(profile: profile, workouts: [])
        XCTAssertEqual(target, 2,
                       "Without workouts, no bumps are earned — target stays at baseline")
    }

    func testTargetGrowsWithConsistentWeeks() {
        // Experienced, baseline=2, ceiling=7, step=2.
        // Provide 6 consistent weeks of 3 sessions each.
        // Week 1-2: target=2, threshold=1, consistent → bump earned (bumps=1)
        // Week 3-4: target=3, threshold=2, 3>=2 → consistent → bumps=2
        // Week 5-6: target=4, threshold=2, 3>=2 → consistent → bumps=3
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 7
        )
        let workouts = makeConsistentHistory(weeks: 6, sessionsPerWeek: 3)
        let target = WeeklyTargetService.currentTarget(profile: profile, workouts: workouts)
        XCTAssertEqual(target, 5,
                       "6 consistent weeks earns 3 bumps: baseline 2 + 3 = 5")
    }

    func testTargetDoesNotGrowAfterInconsistentWeeks() {
        // 6 weeks passed, but only 2 weeks had workouts (not enough per threshold)
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 7
        )
        // Only provide workouts for 2 of the 6 weeks
        let workouts = makeConsistentHistory(weeks: 2, sessionsPerWeek: 2)
        let target = WeeklyTargetService.currentTarget(profile: profile, workouts: workouts)
        // Only 2 consistent weeks → bumps = 2/2 = 1
        XCTAssertEqual(target, 3,
                       "Only 2 consistent weeks out of 6 → just 1 bump earned")
    }

    func testTargetDoesNotInstantlyJumpToCeiling() {
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 1
        )
        // Only 1 completed week, even if consistent → 0 bumps (1/2 = 0)
        let workouts = makeConsistentHistory(weeks: 1, sessionsPerWeek: 3)
        let target = WeeklyTargetService.currentTarget(profile: profile, workouts: workouts)
        XCTAssertEqual(target, 2,
                       "1 consistent week earns 0 bumps (need 2 for experienced)")
        XCTAssertNotEqual(target, profile.availableSessionsCeiling)
    }

    func testTargetNeverExceedsCeiling() {
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 5,
            weeksAgo: 52
        )
        let workouts = makeConsistentHistory(weeks: 50, sessionsPerWeek: 5)
        let target = WeeklyTargetService.currentTarget(profile: profile, workouts: workouts)
        XCTAssertEqual(target, 5,
                       "Target caps at ceiling even with many consistent weeks")
    }

    func testTargetNeverBelowOne() {
        let profile = makeProfile(
            fitnessLevel: .occasional,
            weeklyCardioFrequency: 0,
            availableDays: 0
        )
        let target = WeeklyTargetService.currentTarget(profile: profile, workouts: [])
        XCTAssertEqual(target, 1,
                       "Must never drop to 0 — at least one session a week")
    }

    func testReturnToTrainingRampsSlowly() {
        // Return-to-training: step = 4. Baseline = 2, ceiling = 7.
        // Need 4 consistent weeks for first bump.
        let profile = makeProfile(
            fitnessLevel: .experienced,
            goal: .returnToTraining,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 5
        )
        let workouts = makeConsistentHistory(weeks: 4, sessionsPerWeek: 3)
        let target = WeeklyTargetService.currentTarget(profile: profile, workouts: workouts)
        XCTAssertEqual(target, 3,
                       "Return-to-training earns first bump after 4 consistent weeks")

        // Same weeks, non-return user (step=2) earns 2 bumps
        let nonReturn = makeProfile(
            fitnessLevel: .experienced,
            goal: .generalFitness,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 5
        )
        let nonReturnTarget = WeeklyTargetService.currentTarget(
            profile: nonReturn, workouts: workouts
        )
        XCTAssertEqual(nonReturnTarget, 4,
                       "Non-return experienced user ramps faster (step=2)")
    }

    func testBeginnerRampsSlowly() {
        // Beginner: step = 4. Baseline = 2, ceiling = 7.
        let profile = makeProfile(
            fitnessLevel: .beginner,
            weeklyCardioFrequency: 0,
            availableDays: 7,
            weeksAgo: 5
        )
        let workouts = makeConsistentHistory(weeks: 4, sessionsPerWeek: 2)
        let target = WeeklyTargetService.currentTarget(profile: profile, workouts: workouts)
        XCTAssertEqual(target, 3, "Beginner first bump after 4 consistent weeks")
    }

    func testOccasionalRampsEveryThreeWeeks() {
        // Occasional: step = 3. Baseline = 3, ceiling = 6.
        let profile = makeProfile(
            fitnessLevel: .occasional,
            weeklyCardioFrequency: 3,
            availableDays: 6,
            weeksAgo: 4
        )
        let workouts = makeConsistentHistory(weeks: 3, sessionsPerWeek: 3)
        let target = WeeklyTargetService.currentTarget(profile: profile, workouts: workouts)
        XCTAssertEqual(target, 4,
                       "Occasional earns first bump after 3 consistent weeks")
    }

    func testPhaseResetRestartsRamp() {
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 7
        )
        let workouts = makeConsistentHistory(weeks: 6, sessionsPerWeek: 3)
        XCTAssertEqual(
            WeeklyTargetService.currentTarget(profile: profile, workouts: workouts),
            5, "Pre-reset: 3 bumps"
        )

        profile.phaseStartDate = Date() // simulate focus transition
        XCTAssertEqual(
            WeeklyTargetService.currentTarget(profile: profile, workouts: workouts),
            2, "Phase reset drops back to baseline — no completed weeks since new start"
        )
    }

    func testHighFrequencyStillNeedsConsistency() {
        // User says freq=4, avail=7. Baseline=4, ceiling=7.
        // Without workouts, target stays at 4 even after 10 weeks.
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 4,
            availableDays: 7,
            weeksAgo: 10
        )
        let noWorkouts = WeeklyTargetService.currentTarget(profile: profile, workouts: [])
        XCTAssertEqual(noWorkouts, 4,
                       "High-frequency user doesn't earn ramps by time alone")

        // With consistent workouts, they earn bumps
        let workouts = makeConsistentHistory(weeks: 8, sessionsPerWeek: 5)
        let withWorkouts = WeeklyTargetService.currentTarget(
            profile: profile, workouts: workouts
        )
        XCTAssertGreaterThan(withWorkouts, 4,
                             "Consistent high-frequency user earns ramp bumps")
        XCTAssertLessThanOrEqual(withWorkouts, 7, "Never exceeds ceiling")
    }

    func testInconsistentWeeksPauseButDontResetGrowth() {
        // Experienced, baseline=2, ceiling=7, step=2.
        // 6 weeks, but only weeks 1,2,5,6 are consistent (gap in 3,4).
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 7
        )
        // Weeks 1-2 consistent, weeks 3-4 empty, weeks 5-6 consistent → 4 consistent weeks
        let earlyWorkouts = makeConsistentHistory(weeks: 2, sessionsPerWeek: 3, weeksAgo: 4)
        let lateWorkouts = makeConsistentHistory(weeks: 2, sessionsPerWeek: 3, weeksAgo: 0)
        let workouts = earlyWorkouts + lateWorkouts

        let target = WeeklyTargetService.currentTarget(profile: profile, workouts: workouts)
        // 4 consistent weeks / step 2 = 2 bumps → target = 2 + 2 = 4
        XCTAssertEqual(target, 4,
                       "Inconsistent weeks pause growth but prior consistent weeks still count")
    }

    // MARK: - Ceiling and floor clamping

    func testBaselineEqualToCeilingStays() {
        let profile = makeProfile(
            fitnessLevel: .regular,
            weeklyCardioFrequency: 5,
            availableDays: 5,
            weeksAgo: 10
        )
        let workouts = makeConsistentHistory(weeks: 8, sessionsPerWeek: 5)
        let target = WeeklyTargetService.currentTarget(profile: profile, workouts: workouts)
        XCTAssertEqual(target, 5,
                       "Baseline == ceiling → stays there regardless of consistency")
    }

    func testCeilingClampsLowerThanBaseline() {
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 4,
            availableDays: 3
        )
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 3,
                       "Profile-only: baseline clamped to ceiling")
        let target = WeeklyTargetService.currentTarget(profile: profile, workouts: [])
        XCTAssertEqual(target, 3,
                       "Service also clamps baseline to ceiling")
    }

    func testTotalNeverDropsBelowOne() {
        let zero = makeProfile(
            fitnessLevel: .occasional,
            weeklyCardioFrequency: 0,
            availableDays: 0
        )
        XCTAssertEqual(zero.effectiveSessionsPerWeek, 1)
        XCTAssertEqual(WeeklyTargetService.currentTarget(profile: zero, workouts: []), 1)
    }

    func testCeilingClampsAtSeven() {
        let crazy = makeProfile(weeklyCardioFrequency: 0, availableDays: 42)
        XCTAssertEqual(crazy.availableSessionsCeiling, 7, "Max 7 days per week")
    }

    // MARK: - AssessmentDraft baseline preview
    //
    // The onboarding connect step renders the starting target and ceiling
    // before the draft commits to a UserProfile. These properties must
    // stay in lockstep with UserProfile's baseline rules so the connect
    // step, plan overview, and first live dashboard agree on the number.

    func testDraftBaselineMatchesProfileAfterApply() {
        // Sweep realistic combinations of fitness level, freq, and avail days.
        let levels: [FitnessLevel] = [.beginner, .occasional, .regular, .experienced]
        let freqs = [0, 1, 2, 3, 4, 5, 6, 7]
        let avails = [1, 2, 3, 4, 5, 6, 7]
        for level in levels {
            for freq in freqs {
                for avail in avails {
                    var draft = AssessmentDraft.blank
                    draft.fitnessLevel = level
                    draft.weeklyCardioFrequency = freq
                    draft.availableTrainingDays = avail

                    let profile = UserProfile()
                    draft.apply(to: profile, resetFocus: true)

                    XCTAssertEqual(
                        draft.baselineSessionsPerWeek,
                        profile.baselineSessionsPerWeek,
                        "\(level)/freq\(freq)/avail\(avail): baseline drifted"
                    )
                    XCTAssertEqual(
                        draft.availableSessionsCeiling,
                        profile.availableSessionsCeiling,
                        "\(level)/freq\(freq)/avail\(avail): ceiling drifted"
                    )
                    XCTAssertEqual(
                        draft.startingSessionsPerWeek,
                        profile.effectiveSessionsPerWeek,
                        "\(level)/freq\(freq)/avail\(avail): starting target drifted"
                    )
                    XCTAssertEqual(
                        draft.hasHeadroomToBuild,
                        profile.hasHeadroomToBuild,
                        "\(level)/freq\(freq)/avail\(avail): headroom flag drifted"
                    )
                }
            }
        }
    }

    func testDraftBeginnerBaselineHardCodedToTwo() {
        var draft = AssessmentDraft.blank
        draft.fitnessLevel = .beginner
        draft.weeklyCardioFrequency = 5 // beginners ignore this
        draft.availableTrainingDays = 7

        XCTAssertEqual(draft.baselineSessionsPerWeek, 2,
                       "Beginner baseline is 2 regardless of stated frequency")
        XCTAssertEqual(draft.startingSessionsPerWeek, 2)
        XCTAssertTrue(draft.hasHeadroomToBuild)
    }

    func testDraftStartingClampedToCeiling() {
        var draft = AssessmentDraft.blank
        draft.fitnessLevel = .experienced
        draft.weeklyCardioFrequency = 6
        draft.availableTrainingDays = 3

        XCTAssertEqual(draft.availableSessionsCeiling, 3)
        XCTAssertEqual(draft.startingSessionsPerWeek, 3,
                       "Starting target cannot exceed available days")
        XCTAssertFalse(draft.hasHeadroomToBuild,
                       "Baseline >= ceiling collapses headroom")
    }

    func testDraftCeilingAndStartingNeverBelowOne() {
        var draft = AssessmentDraft.blank
        draft.fitnessLevel = .occasional
        draft.weeklyCardioFrequency = 0
        draft.availableTrainingDays = 0

        XCTAssertEqual(draft.availableSessionsCeiling, 1)
        XCTAssertEqual(draft.startingSessionsPerWeek, 1,
                       "Floors at 1 — user always gets at least one session a week")
    }

    func testDraftCeilingClampsAtSeven() {
        var draft = AssessmentDraft.blank
        draft.availableTrainingDays = 42
        XCTAssertEqual(draft.availableSessionsCeiling, 7)
    }

    // MARK: - Focus independence

    func testTotalIsIndependentOfFocus() {
        for focus in TrainingFocus.allCases {
            let profile = makeProfile(
                focus: focus,
                fitnessLevel: .regular,
                weeklyCardioFrequency: 3,
                availableDays: 5,
                weeksAgo: 5
            )
            let workouts = makeConsistentHistory(weeks: 4, sessionsPerWeek: 4)
            let target = WeeklyTargetService.currentTarget(profile: profile, workouts: workouts)
            // regular step=2, 4 consistent weeks → bumps=2, target=min(5, 3+2)=5
            XCTAssertEqual(
                target, 5,
                "focus \(focus) must not override the baseline-ramp total"
            )
        }
    }

    // MARK: - Composition is focus-driven

    func testBuildingBaseGivesZeroIntervals() {
        let total = 7
        let profile = makeProfile(focus: .buildingBase, fitnessLevel: .experienced,
                                  weeklyCardioFrequency: 4, availableDays: 7)
        XCTAssertEqual(WeeklyTargetService.intervalSessions(total: total, profile: profile), 0)
        XCTAssertEqual(WeeklyTargetService.targetZoneSessions(total: total, profile: profile), total)
    }

    func testActiveRecoveryGivesZeroIntervals() {
        let total = 4
        let profile = makeProfile(focus: .activeRecovery, fitnessLevel: .regular,
                                  weeklyCardioFrequency: 2, availableDays: 4)
        XCTAssertEqual(WeeklyTargetService.intervalSessions(total: total, profile: profile), 0)
        XCTAssertEqual(WeeklyTargetService.targetZoneSessions(total: total, profile: profile), total)
    }

    func testDevelopingSpeedScalesIntervalsWithinCap() {
        let profile3 = makeProfile(focus: .developingSpeed, fitnessLevel: .experienced,
                                   weeklyCardioFrequency: 1, availableDays: 3)
        XCTAssertEqual(WeeklyTargetService.intervalSessions(total: 3, profile: profile3), 1)

        let profile7 = makeProfile(focus: .developingSpeed, fitnessLevel: .experienced,
                                   weeklyCardioFrequency: 4, availableDays: 7)
        XCTAssertEqual(WeeklyTargetService.intervalSessions(total: 7, profile: profile7), 2,
                       "Cap still holds at the top of the range")
    }

    func testPeakPerformanceScalesIntervalsWithinCap() {
        let profile4 = makeProfile(focus: .peakPerformance, fitnessLevel: .experienced,
                                   weeklyCardioFrequency: 2, availableDays: 4)
        XCTAssertEqual(WeeklyTargetService.intervalSessions(total: 4, profile: profile4), 2)

        let profile7 = makeProfile(focus: .peakPerformance, fitnessLevel: .experienced,
                                   weeklyCardioFrequency: 4, availableDays: 7)
        XCTAssertEqual(WeeklyTargetService.intervalSessions(total: 7, profile: profile7), 3,
                       "Interval share is capped at 3")
    }

    func testTargetZonePlusIntervalsAlwaysSumToTotal() {
        for focus in TrainingFocus.allCases {
            for level in FitnessLevel.allCases {
                for total in [1, 3, 5, 7] {
                    let p = makeProfile(focus: focus, fitnessLevel: level,
                                        weeklyCardioFrequency: 0, availableDays: total)
                    let intervals = WeeklyTargetService.intervalSessions(total: total, profile: p)
                    let zone = WeeklyTargetService.targetZoneSessions(total: total, profile: p)
                    XCTAssertEqual(
                        zone + intervals, total,
                        "\(focus)/\(level)/total\(total): sum must equal total"
                    )
                    XCTAssertGreaterThanOrEqual(zone, 0)
                    XCTAssertGreaterThanOrEqual(intervals, 0)
                }
            }
        }
    }

    // MARK: - Intensity constraint

    func testAvoidHighIntensityForcesZeroIntervals() {
        for focus in TrainingFocus.allCases {
            let profile = makeProfile(
                focus: focus,
                fitnessLevel: .experienced,
                weeklyCardioFrequency: 4,
                availableDays: 7,
                intensityConstraint: .avoidHighIntensity
            )
            XCTAssertEqual(
                WeeklyTargetService.intervalSessions(total: 7, profile: profile), 0,
                "avoidHighIntensity must block intervals for focus \(focus)"
            )
            XCTAssertEqual(
                WeeklyTargetService.targetZoneSessions(total: 7, profile: profile), 7,
                "All sessions collapse to target zone"
            )
        }
    }

    // MARK: - Headroom

    func testHasHeadroomOnlyWhenCeilingExceedsCurrent() {
        let room = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7
        )
        XCTAssertTrue(room.hasHeadroomToBuild, "Baseline < ceiling → headroom")

        let workouts = makeConsistentHistory(weeks: 20, sessionsPerWeek: 7)
        let full = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 21
        )
        let target = WeeklyTargetService.currentTarget(profile: full, workouts: workouts)
        XCTAssertFalse(
            WeeklyTargetService.hasHeadroomToBuild(
                currentTarget: target,
                ceiling: full.availableSessionsCeiling
            ),
            "After enough consistent weeks the ramp reaches the ceiling"
        )
    }

    // MARK: - Consistency gate integration

    func testConsistencyGateUsesLastWeekTargetNotCurrentWeek() {
        // Experienced, baseline=2, ceiling=7, step=2.
        // 3 consistent weeks (weeks -4, -3, -2) before last week.
        // At start of last week: 3 consistent → bumps = 3/2 = 1 → lastWeekTarget = 3.
        // Last week (week -1): 2 sessions → meets 67% of target 3 → consistent.
        // At start of this week: 4 consistent weeks → bumps = 4/2 = 2 → currentTarget = 4.
        //
        // Gate with currentTarget (4): missed = 4 - 2 = 2, threshold = max(2, ceil(4/2)) = 2 → FIRES (wrong!)
        // Gate with lastWeekTarget (3): missed = 3 - 2 = 1 → guard fails → NO FIRE (correct!)
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 5
        )
        // 3 consistent weeks in weeks -4, -3, -2
        let earlyHistory = makeConsistentHistory(weeks: 3, sessionsPerWeek: 3, weeksAgo: 1)

        // 2 sessions in last week (week -1)
        let calendar = Calendar.current
        let lastWeekStart = calendar.date(
            byAdding: .weekOfYear, value: -1, to: Date().startOfWeek
        )!
        let lastWeekWorkouts = (0..<2).map { i in
            makeWorkout(date: lastWeekStart.addingTimeInterval(Double(i) * 86400 + 43200))
        }
        let allWorkouts = earlyHistory + lastWeekWorkouts

        // Verify the target divergence
        let currentTarget = WeeklyTargetService.currentTarget(
            profile: profile, workouts: allWorkouts
        )
        let lastWeekTarget = WeeklyTargetService.currentTarget(
            profile: profile, workouts: allWorkouts, asOf: lastWeekStart
        )
        XCTAssertEqual(currentTarget, 4,
                       "4 consistent weeks → 2 bumps → baseline 2 + 2 = 4")
        XCTAssertEqual(lastWeekTarget, 3,
                       "3 consistent weeks before last week → 1 bump → baseline 2 + 1 = 3")

        // Gate should NOT fire — user completed 2 of 3 (last week's actual target)
        XCTAssertFalse(
            PhaseManager.missedSessionsLastWeek(workouts: allWorkouts, target: lastWeekTarget),
            "Gate must use last week's target (3), not the bumped current target (4)"
        )
        // Verify the old behavior would have been wrong
        XCTAssertTrue(
            PhaseManager.missedSessionsLastWeek(workouts: allWorkouts, target: currentTarget),
            "Using current target (4) would incorrectly penalize last week"
        )
    }

    func testConsistencyGateFiresWithServiceTarget() {
        // Experienced user, 6 consistent weeks (weeks -7 through -2)
        // → target=5. Then only 1 session in last week → gate should fire.
        let profile = makeProfile(
            fitnessLevel: .experienced,
            weeklyCardioFrequency: 2,
            availableDays: 7,
            weeksAgo: 7
        )
        // Shift history back by 1 so it covers weeks -7 through -2, leaving
        // last week empty. This gives 6 consistent weeks → bumps=3, target=5.
        let consistentHistory = makeConsistentHistory(
            weeks: 6, sessionsPerWeek: 3, weeksAgo: 1
        )
        let target = WeeklyTargetService.currentTarget(
            profile: profile, workouts: consistentHistory
        )
        XCTAssertEqual(target, 5, "Target should be 5 after 6 consistent weeks")

        // Build 1 sparse workout in last week (week -1)
        let calendar = Calendar.current
        let lastWeekStart = calendar.date(
            byAdding: .weekOfYear, value: -1, to: Date().startOfWeek
        )!
        let sparseLastWeek = [makeWorkout(date: lastWeekStart.addingTimeInterval(43200))]
        let allWorkouts = consistentHistory + sparseLastWeek

        XCTAssertTrue(
            PhaseManager.missedSessionsLastWeek(workouts: allWorkouts, profile: profile),
            "Consistency gate must fire when user missed ≥ half of consistency-aware target"
        )
    }
}
