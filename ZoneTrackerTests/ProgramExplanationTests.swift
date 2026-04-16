import XCTest
@testable import ZoneTracker

final class ProgramExplanationTests: XCTestCase {

    // MARK: - Section Composition

    func testAlwaysProducesAllFiveSectionsInOrder() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        let explanation = ProgramExplanation.build(
            profile: profile,
            firstWorkout: WorkoutRecommendation.defaultFirstWorkout(profile: profile)
        )

        XCTAssertEqual(explanation.sections.map(\.id), [
            "goal",
            "weeklyStructure",
            "firstWorkout",
            "progression",
            "watchCoaching"
        ])
    }

    // MARK: - Headline / Subhead

    func testHeadlineIsGoalSpecific() {
        let aerobic = makeProfile(goal: .aerobicBase, level: .occasional)
        let comeback = makeProfile(goal: .returnToTraining, level: .occasional)

        XCTAssertTrue(buildExplanation(aerobic).headline.lowercased().contains("aerobic"))
        XCTAssertTrue(buildExplanation(comeback).headline.lowercased().contains("comeback"))
    }

    func testRaceTrainingHeadlineUsesEventNameWhenSet() {
        let profile = makeProfile(goal: .raceTraining, level: .experienced)
        profile.targetEvent = "Half Marathon"
        XCTAssertTrue(buildExplanation(profile).headline.contains("Half Marathon"))
    }

    func testRaceSubheadReferencesDaysWhenEventDateSet() {
        let profile = makeProfile(goal: .raceTraining, level: .experienced)
        profile.targetEvent = "10K"
        profile.targetEventDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        XCTAssertTrue(buildExplanation(profile).subhead.contains("days out"),
                      "Race subhead should reference days when event date is set")
    }

    // MARK: - Goal Section Tone Differs by Fitness Level

    func testBeginnerGoalSectionMentionsConfidenceBuilding() {
        let profile = makeProfile(goal: .peakCardio, level: .beginner)
        let goal = section(buildExplanation(profile), id: "goal")
        XCTAssertTrue(goal.body.lowercased().contains("easy") ||
                      goal.body.lowercased().contains("confidence"),
                      "Beginner copy must signal an easy ramp-in: \(goal.body)")
    }

    func testExperiencedGoalSectionMentionsAggressiveStructure() {
        let profile = makeProfile(goal: .peakCardio, level: .experienced)
        let goal = section(buildExplanation(profile), id: "goal")
        XCTAssertTrue(goal.body.lowercased().contains("aggressive") ||
                      goal.body.lowercased().contains("zones"),
                      "Experienced copy should reflect they can move faster: \(goal.body)")
    }

    // MARK: - Weekly Structure Reflects Plan Math

    func testWeeklyStructureMentionsZeroIntervalsForBaseFocus() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        let structure = section(buildExplanation(profile), id: "weeklyStructure")
        XCTAssertTrue(structure.body.lowercased().contains("target heart-rate") ||
                      structure.body.lowercased().contains("target zone"),
                      "Aerobic-base structure should center on target zone work: \(structure.body)")
        // No intervals → no "interval days" pill
        XCTAssertFalse(structure.bullets.contains(where: { $0.lowercased().contains("interval day") }))
    }

    func testWeeklyStructureMentionsIntervalsWhenIntervalSessionsPresent() {
        let profile = makeProfile(goal: .peakCardio, level: .experienced)
        let structure = section(buildExplanation(profile), id: "weeklyStructure")
        XCTAssertTrue(structure.bullets.contains(where: { $0.lowercased().contains("interval") }),
                      "Peak-cardio plan should call out interval days: \(structure.bullets)")
    }

    func testAvoidHighIntensityCallsOutNoIntervalsExplicitly() {
        let profile = makeProfile(goal: .peakCardio, level: .experienced)
        profile.intensityConstraint = .avoidHighIntensity
        let structure = section(buildExplanation(profile), id: "weeklyStructure")
        XCTAssertTrue(structure.bullets.contains(where: { $0.lowercased().contains("by your request") }),
                      "Constraint should be surfaced in bullets, got: \(structure.bullets)")
    }

    // MARK: - First Workout Section Matches Recommendation

    func testFirstWorkoutSectionMentionsModalityAndDuration() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        profile.preferredModalities = [ExerciseType.bike.rawValue]
        let rec = WorkoutRecommendation.defaultFirstWorkout(profile: profile)
        let first = section(
            ProgramExplanation.build(profile: profile, firstWorkout: rec),
            id: "firstWorkout"
        )
        XCTAssertTrue(first.body.lowercased().contains("bike"),
                      "First workout copy should reference the chosen modality: \(first.body)")
        XCTAssertTrue(first.bullets.contains("\(rec.targetDurationMinutes) minutes"),
                      "First workout bullets should expose the duration: \(first.bullets)")
    }

    func testFirstWorkoutSectionFlagsIntervalsWhenIntervalIntroChosen() {
        let profile = makeProfile(goal: .peakCardio, level: .experienced)
        let rec = WorkoutRecommendation.defaultFirstWorkout(profile: profile)
        let first = section(
            ProgramExplanation.build(profile: profile, firstWorkout: rec),
            id: "firstWorkout"
        )
        XCTAssertTrue(first.bullets.contains("Intervals included"),
                      "Interval intro should be flagged in bullets: \(first.bullets)")
    }

    // MARK: Modality-resolved shape in copy
    //
    // ProgramExplanation has to narrate the *same* first workout the user is
    // about to see. Pre-fix it called `decideShape`, so a race-training bike
    // user would land on an aerobic-support session but read "a mile benchmark"
    // in the explanation. Now it uses `resolvedShape`, so the copy and the
    // recommendation stay in lockstep.

    func testRaceTrainingBikeUserDoesNotSeeMileBenchmarkCopy() {
        let profile = makeProfile(goal: .raceTraining, level: .experienced)
        profile.targetEvent = "Half Iron"
        profile.targetEventDate = Calendar.current.date(byAdding: .day, value: 21, to: Date())
        profile.preferredModalities = [ExerciseType.bike.rawValue]

        let rec = WorkoutRecommendation.defaultFirstWorkout(profile: profile)
        let explanation = ProgramExplanation.build(profile: profile, firstWorkout: rec)
        let first = section(explanation, id: "firstWorkout")

        XCTAssertFalse(first.body.localizedCaseInsensitiveContains("mile benchmark"),
                       "Non-running race user must never see mile-benchmark copy: \(first.body)")
        XCTAssertFalse(first.body.localizedCaseInsensitiveContains("all-out mile"))
        XCTAssertTrue(first.body.localizedCaseInsensitiveContains("aerobic"),
                      "Non-runner fallback copy should describe aerobic support: \(first.body)")
    }

    func testRaceTrainingRunningUserStillSeesBenchmarkCopy() {
        // Regression guard — the modality narrowing must not accidentally
        // strip benchmark copy from running users who *should* see it.
        let profile = makeProfile(goal: .raceTraining, level: .experienced)
        profile.targetEvent = "10K"
        profile.targetEventDate = Calendar.current.date(byAdding: .day, value: 21, to: Date())
        profile.preferredModalities = [ExerciseType.treadmill.rawValue]

        let rec = WorkoutRecommendation.defaultFirstWorkout(profile: profile)
        let explanation = ProgramExplanation.build(profile: profile, firstWorkout: rec)
        let first = section(explanation, id: "firstWorkout")

        XCTAssertTrue(first.body.localizedCaseInsensitiveContains("mile"),
                      "Running race user should still see mile-benchmark framing: \(first.body)")
    }

    // MARK: Weekly structure reflects user-selected training days

    func testWeeklyStructureSurfacesBothStartingAndCeiling() {
        // Regular user currently doing 3/week, wants up to 7 — the plan
        // should start in the middle of that range and tell the user so.
        let profile = makeProfile(goal: .generalFitness, level: .regular)
        profile.weeklyCardioFrequency = 3
        profile.availableTrainingDays = 7
        let structure = section(buildExplanation(profile), id: "weeklyStructure")

        // Regular gets +2 ramp → start 5, ceiling 7.
        XCTAssertTrue(structure.bullets.contains("Starting at 5 sessions a week"),
                      "Should expose starting volume, not just the ceiling: \(structure.bullets)")
        XCTAssertTrue(structure.bullets.contains("Building toward 7 days a week"),
                      "Headroom copy must reassure users we'll grow toward their ceiling: \(structure.bullets)")
    }

    func testWeeklyStructureOmitsBuildingCopyWhenAtCeiling() {
        let profile = makeProfile(goal: .generalFitness, level: .regular)
        profile.weeklyCardioFrequency = 5
        profile.availableTrainingDays = 5
        let structure = section(buildExplanation(profile), id: "weeklyStructure")

        XCTAssertTrue(structure.bullets.contains("Starting at 5 sessions a week"))
        XCTAssertFalse(structure.bullets.contains(where: { $0.lowercased().contains("building toward") }),
                       "No headroom → no 'building toward' bullet: \(structure.bullets)")
    }

    func testWeeklyStructureRespectsAvoidHighIntensityWithHeadroom() {
        let profile = makeProfile(goal: .peakCardio, level: .experienced)
        profile.weeklyCardioFrequency = 3
        profile.availableTrainingDays = 7
        profile.intensityConstraint = .avoidHighIntensity
        let structure = section(buildExplanation(profile), id: "weeklyStructure")

        // Experienced ramps +3 → start 6, ceiling 7.
        XCTAssertTrue(structure.bullets.contains("Starting at 6 sessions a week"))
        XCTAssertFalse(structure.bullets.contains(where: { $0.lowercased().contains("interval day") }),
                       "Constraint must suppress interval bullets even with ample days: \(structure.bullets)")
    }

    // MARK: - First Workout Copy Derives From Passed Recommendation
    //
    // The explanation must narrate the *actual* first workout the user is
    // about to see, not re-derive intent from the profile. These tests
    // build a profile that *would* otherwise land on a different shape and
    // hand in a rec that forces a specific shape, then assert the copy
    // matches the rec.

    func testFirstWorkoutSectionFollowsPassedBenchmark() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        let rec = WorkoutRecommendation(
            sessionType: .benchmark_mile,
            exerciseType: .outdoorRun,
            targetDuration: 30 * 60,
            targetHRLow: 130,
            targetHRHigh: 170,
            suggestedMetrics: [:],
            intervalProtocol: nil,
            reasoning: "",
            adjustmentType: .holdSteady
        )
        let explanation = ProgramExplanation.build(profile: profile, firstWorkout: rec)
        let first = section(explanation, id: "firstWorkout")

        XCTAssertTrue(first.body.localizedCaseInsensitiveContains("mile benchmark"),
                      "Passed benchmark_mile must drive benchmark copy regardless of goal: \(first.body)")
    }

    func testFirstWorkoutSectionFollowsPassedIntervalWithProtocolDetails() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        let proto = IntervalProtocol(
            workDuration: 45,
            restDuration: 75,
            rounds: 5,
            targetWorkHRLow: 170,
            targetWorkHRHigh: 180,
            targetRestHR: 140
        )
        let rec = WorkoutRecommendation(
            sessionType: .interval_30_30,
            exerciseType: .treadmill,
            targetDuration: 25 * 60,
            targetHRLow: 130,
            targetHRHigh: 180,
            suggestedMetrics: [:],
            intervalProtocol: proto,
            reasoning: "",
            adjustmentType: .holdSteady
        )
        let explanation = ProgramExplanation.build(profile: profile, firstWorkout: rec)
        let first = section(explanation, id: "firstWorkout")

        XCTAssertTrue(first.body.lowercased().contains("5 rounds"),
                      "Interval copy must reflect the passed rec's round count, not a hardcoded default: \(first.body)")
        XCTAssertTrue(first.body.contains("45 seconds") || first.body.contains("45 "),
                      "Interval copy must reflect the passed work duration: \(first.body)")
        XCTAssertTrue(first.bullets.contains("Intervals included"))
    }

    func testFirstWorkoutSectionFollowsPassedZone2ForReturnToTraining() {
        let profile = makeProfile(goal: .returnToTraining, level: .occasional)
        let rec = WorkoutRecommendation(
            sessionType: .zone2,
            exerciseType: .bike,
            targetDuration: 40 * 60,
            targetHRLow: 120,
            targetHRHigh: 150,
            suggestedMetrics: [:],
            intervalProtocol: nil,
            reasoning: "",
            adjustmentType: .holdSteady
        )
        let explanation = ProgramExplanation.build(profile: profile, firstWorkout: rec)
        let first = section(explanation, id: "firstWorkout")

        XCTAssertTrue(first.body.lowercased().contains("gentle"),
                      "Return-to-training zone2 body should lead with 'gentle' framing: \(first.body)")
        XCTAssertTrue(first.body.lowercased().contains("bike"))
        XCTAssertTrue(first.bullets.contains("Steady target zone"))
    }

    // MARK: - Progression Section Differentiates by Goal/Level

    func testReturnToTrainingProgressionMentionsConsistencyBeforeIntensity() {
        let profile = makeProfile(goal: .returnToTraining, level: .occasional)
        let progression = section(buildExplanation(profile), id: "progression")
        XCTAssertTrue(progression.body.lowercased().contains("consistency"),
                      "Return-to-training progression should lead with consistency: \(progression.body)")
    }

    func testRaceTrainingNearEventProgressionMentionsTaper() {
        let profile = makeProfile(goal: .raceTraining, level: .experienced)
        profile.targetEventDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())
        let progression = section(buildExplanation(profile), id: "progression")
        XCTAssertTrue(progression.body.lowercased().contains("taper"),
                      "Near-event race plan should reference tapering: \(progression.body)")
    }

    func testProgressionAlwaysMentionsCurrentFocus() {
        for goal in CardioGoal.allCases {
            let profile = makeProfile(goal: goal, level: .occasional)
            let progression = section(buildExplanation(profile), id: "progression")
            XCTAssertTrue(progression.bullets.contains(where: { $0.contains(profile.focus.displayName) }),
                          "Progression bullets should always include current focus for goal \(goal): \(progression.bullets)")
        }
    }

    // MARK: - Watch Coaching Reflects Haptic Setting

    func testWatchSectionMentionsHapticsWhenEnabled() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        profile.coachingHapticsEnabled = true
        let watch = section(buildExplanation(profile), id: "watchCoaching")
        XCTAssertTrue(watch.body.lowercased().contains("haptic"),
                      "Watch copy should describe haptic alerts when enabled: \(watch.body)")
        XCTAssertTrue(watch.bullets.contains("Haptic alerts on"))
    }

    func testWatchSectionAcknowledgesHapticsOff() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        profile.coachingHapticsEnabled = false
        let watch = section(buildExplanation(profile), id: "watchCoaching")
        XCTAssertTrue(watch.bullets.contains("Haptic alerts off"))
    }

    // MARK: - Helpers

    private func makeProfile(goal: CardioGoal, level: FitnessLevel) -> UserProfile {
        let profile = UserProfile()
        profile.primaryGoal = goal
        profile.fitnessLevel = level
        profile.focus = goal.initialFocus
        profile.typicalWorkoutMinutes = 30
        profile.weeklyCardioFrequency = 3
        profile.availableTrainingDays = 3
        profile.preferredModalities = [ExerciseType.treadmill.rawValue]
        profile.intensityConstraint = .none
        return profile
    }

    private func buildExplanation(_ profile: UserProfile) -> ProgramExplanation {
        ProgramExplanation.build(
            profile: profile,
            firstWorkout: WorkoutRecommendation.defaultFirstWorkout(profile: profile)
        )
    }

    private func section(_ explanation: ProgramExplanation, id: String) -> ProgramExplanation.Section {
        guard let s = explanation.sections.first(where: { $0.id == id }) else {
            XCTFail("Missing section \(id)")
            return ProgramExplanation.Section(id: id, icon: "", title: "", body: "", bullets: [])
        }
        return s
    }
}
