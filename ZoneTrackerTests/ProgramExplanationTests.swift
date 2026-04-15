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
