import XCTest
import SwiftData
@testable import ZoneTracker

// MARK: - Tests for the second targeted follow-up fix pass
//
// Covers:
//   1. Benchmark shape is narrowed away from non-running modalities so the
//      recommendation never tells a swimmer / cyclist / rower to "run one
//      all-out mile".
//   2. `hasSubmittedAssessment` round-trips through `CloudProfileSnapshot`,
//      survives remote merge/apply without regressing the local state, and
//      decodes safely from records that predate the field (nil → false).
//   3. `OnboardingCommitter` only moves the profile flags forward on a
//      successful save; on save failure it rolls the flag back so the
//      in-memory state never drifts from what's on disk.

// MARK: - Benchmark modality routing

final class BenchmarkModalityRoutingTests: XCTestCase {

    func testBenchmarkShapeKeptForTreadmill() {
        XCTAssertEqual(
            FirstWorkoutStrategy.resolveShape(.benchmarkAssessment, modality: .treadmill),
            .benchmarkAssessment
        )
    }

    func testBenchmarkShapeKeptForOutdoorRun() {
        XCTAssertEqual(
            FirstWorkoutStrategy.resolveShape(.benchmarkAssessment, modality: .outdoorRun),
            .benchmarkAssessment
        )
    }

    func testBenchmarkShapeNarrowedForBikeRowingSwimming() {
        for modality: ExerciseType in [.bike, .rowing, .swimming, .elliptical, .stairClimber, .rucking] {
            XCTAssertEqual(
                FirstWorkoutStrategy.resolveShape(.benchmarkAssessment, modality: modality),
                .aerobicSupport,
                "Non-running modality \(modality) must not resolve to a mile benchmark"
            )
        }
    }

    func testNonBenchmarkShapesUntouched() {
        // Regression guard — the modality narrowing should only touch the
        // benchmark case today.
        let shapes: [FirstWorkoutStrategy.Shape] = [
            .easyTargetZoneIntro, .returnToTargetZone, .targetZoneBaseline,
            .aerobicSupport, .intervalIntro, .tempoStarter
        ]
        for shape in shapes {
            XCTAssertEqual(FirstWorkoutStrategy.resolveShape(shape, modality: .bike), shape)
            XCTAssertEqual(FirstWorkoutStrategy.resolveShape(shape, modality: .treadmill), shape)
        }
    }

    // MARK: End-to-end recommendation

    func testBikeRacerDoesNotGetMileBenchmark() {
        let profile = raceProfile(preferredModalities: [.bike])
        let rec = FirstWorkoutStrategy.recommend(for: profile)

        XCTAssertEqual(rec.exerciseType, .bike)
        XCTAssertEqual(rec.sessionType, .zone2,
                      "Bike race user should fall back to aerobic support, not a mile benchmark")
        XCTAssertFalse(rec.reasoning.localizedCaseInsensitiveContains("mile"),
                      "Reasoning must not mention a mile for a bike session: \(rec.reasoning)")
        XCTAssertFalse(rec.reasoning.localizedCaseInsensitiveContains("all-out"),
                      "Reasoning must not prescribe an all-out run for a bike session")
    }

    func testRowingRacerDoesNotGetMileBenchmark() {
        let profile = raceProfile(preferredModalities: [.rowing])
        let rec = FirstWorkoutStrategy.recommend(for: profile)

        XCTAssertEqual(rec.exerciseType, .rowing)
        XCTAssertEqual(rec.sessionType, .zone2)
        XCTAssertFalse(rec.reasoning.localizedCaseInsensitiveContains("mile"))
    }

    func testSwimmingRacerDoesNotGetMileBenchmark() {
        let profile = raceProfile(preferredModalities: [.swimming])
        let rec = FirstWorkoutStrategy.recommend(for: profile)

        XCTAssertEqual(rec.exerciseType, .swimming)
        XCTAssertEqual(rec.sessionType, .zone2)
        XCTAssertFalse(rec.reasoning.localizedCaseInsensitiveContains("mile"))
    }

    func testTreadmillRacerStillGetsMileBenchmark() {
        let profile = raceProfile(preferredModalities: [.treadmill])
        let rec = FirstWorkoutStrategy.recommend(for: profile)

        XCTAssertEqual(rec.exerciseType, .treadmill)
        XCTAssertEqual(rec.sessionType, .benchmark_mile)
        XCTAssertTrue(rec.reasoning.localizedCaseInsensitiveContains("mile benchmark"),
                     "Running users should still see the benchmark framing: \(rec.reasoning)")
    }

    func testOutdoorRunRacerStillGetsMileBenchmark() {
        let profile = raceProfile(preferredModalities: [.outdoorRun])
        let rec = FirstWorkoutStrategy.recommend(for: profile)

        XCTAssertEqual(rec.exerciseType, .outdoorRun)
        XCTAssertEqual(rec.sessionType, .benchmark_mile)
    }

    func testNonRunnerRacerRecommendationIsGoalAware() {
        // Swapped out the mile benchmark — the fallback should still reflect
        // the race goal, not regress to a generic target-zone session.
        let profile = raceProfile(preferredModalities: [.bike])
        profile.targetEvent = "Half Iron"
        let rec = FirstWorkoutStrategy.recommend(for: profile)

        // `aerobicSupport` builder uses the goal-aware prefix, which for race
        // training with a known event includes the countdown.
        XCTAssertTrue(
            rec.reasoning.contains("days to your Half Iron"),
            "Non-runner fallback should still acknowledge the race: \(rec.reasoning)"
        )
        XCTAssertTrue(
            rec.reasoning.localizedCaseInsensitiveContains("aerobic"),
            "Non-runner fallback should describe aerobic support: \(rec.reasoning)"
        )
    }

    // MARK: Helpers

    private func raceProfile(preferredModalities: [ExerciseType]) -> UserProfile {
        let profile = UserProfile()
        profile.primaryGoal = .raceTraining
        profile.fitnessLevel = .experienced
        profile.focus = CardioGoal.raceTraining.initialFocus
        profile.targetEvent = "10K"
        profile.targetEventDate = Calendar.current.date(byAdding: .day, value: 21, to: Date())
        profile.typicalWorkoutMinutes = 45
        profile.availableTrainingDays = 4
        profile.preferredModalities = preferredModalities.map(\.rawValue)
        profile.intensityConstraint = .none
        return profile
    }
}

// MARK: - hasSubmittedAssessment cloud sync integration

@MainActor
final class SubmittedAssessmentSyncTests: XCTestCase {

    // MARK: Snapshot round-trip

    func testSnapshotCarriesSubmittedFlag() {
        let profile = UserProfile()
        profile.hasSubmittedAssessment = true

        let snapshot = CloudProfileSnapshot.from(
            profile: profile,
            accountIdentifier: "apple-user-xyz"
        )
        XCTAssertEqual(snapshot.hasSubmittedAssessment, true)
    }

    func testSnapshotPropagatesFalseWhenNotYetSubmitted() {
        let profile = UserProfile()
        XCTAssertFalse(profile.hasSubmittedAssessment)

        let snapshot = CloudProfileSnapshot.from(
            profile: profile,
            accountIdentifier: "apple-user-xyz"
        )
        XCTAssertEqual(snapshot.hasSubmittedAssessment, false,
                       "A fresh profile should snapshot the flag as false, not nil")
    }

    // MARK: makeProfile (legacy + new)

    func testMakeProfileFromLegacySnapshotDefaultsSubmittedToFalse() {
        // Simulates a record that was written before the field existed: the
        // snapshot decoder leaves hasSubmittedAssessment as nil.
        let legacy = makeSnapshot(
            hasCompletedOnboarding: false,
            hasSubmittedAssessment: nil
        )
        let rebuilt = AppSyncCoordinator.shared.debug_makeProfile(from: legacy)
        XCTAssertFalse(rebuilt.hasSubmittedAssessment,
                      "Missing field must decode as 'not submitted', not skip the assessment")
        XCTAssertFalse(rebuilt.hasCompletedOnboarding)
    }

    func testMakeProfileFromCompletedLegacySnapshotBackfillsSubmitted() {
        // Old record says onboarding was completed but didn't record the
        // submission step. Invariant: completed implies submitted.
        let legacy = makeSnapshot(
            hasCompletedOnboarding: true,
            hasSubmittedAssessment: nil
        )
        let rebuilt = AppSyncCoordinator.shared.debug_makeProfile(from: legacy)
        XCTAssertTrue(rebuilt.hasCompletedOnboarding)
        XCTAssertTrue(rebuilt.hasSubmittedAssessment,
                     "Completion implies submission — backfill must set both flags")
    }

    func testMakeProfileFromSubmittedSnapshotRoutesToPlanOverview() {
        // New record with intermediate state set.
        let snapshot = makeSnapshot(
            hasCompletedOnboarding: false,
            hasSubmittedAssessment: true
        )
        let rebuilt = AppSyncCoordinator.shared.debug_makeProfile(from: snapshot)
        XCTAssertFalse(rebuilt.hasCompletedOnboarding)
        XCTAssertTrue(rebuilt.hasSubmittedAssessment,
                     "Restoring a submitted-but-not-finished profile should still route to plan overview")
    }

    // MARK: apply (onto an existing local profile)

    func testApplyPreservesSubmittedFlagWhenRemoteIsLegacy() {
        // Local already submitted; remote is a legacy record with nil. Apply
        // must not regress the local flag.
        let local = UserProfile()
        local.hasSubmittedAssessment = true

        let legacy = makeSnapshot(
            hasCompletedOnboarding: false,
            hasSubmittedAssessment: nil
        )
        AppSyncCoordinator.shared.debug_applyRemote(legacy, to: local)
        XCTAssertTrue(local.hasSubmittedAssessment,
                     "Legacy remote record must not overwrite local submission state")
    }

    func testApplyBackfillsSubmittedWhenRemoteIsCompleted() {
        let local = UserProfile()
        let snapshot = makeSnapshot(
            hasCompletedOnboarding: true,
            hasSubmittedAssessment: nil
        )
        AppSyncCoordinator.shared.debug_applyRemote(snapshot, to: local)
        XCTAssertTrue(local.hasCompletedOnboarding)
        XCTAssertTrue(local.hasSubmittedAssessment,
                     "After apply, completion invariant must hold even from legacy records")
    }

    // MARK: merge progression (via the onboarding-progress comparator)

    func testMergeAppliesRemoteWhenRemoteIsMoreProgressed() {
        let local = UserProfile()
        let remoteSubmitted = makeSnapshot(
            hasCompletedOnboarding: false,
            hasSubmittedAssessment: true
        )
        XCTAssertTrue(
            AppSyncCoordinator.shared.debug_shouldApplyRemote(remoteSubmitted, overLocal: local),
            "Fresh local vs. submitted remote: remote should win"
        )
    }

    func testMergeDoesNotRegressLocalCompletionFromRemoteSubmission() {
        let local = UserProfile()
        local.hasSubmittedAssessment = true
        local.hasCompletedOnboarding = true

        let remoteSubmitted = makeSnapshot(
            hasCompletedOnboarding: false,
            hasSubmittedAssessment: true
        )
        XCTAssertFalse(
            AppSyncCoordinator.shared.debug_shouldApplyRemote(remoteSubmitted, overLocal: local),
            "A completed local profile must never regress to merely submitted"
        )
    }

    func testMergeDoesNotRegressLocalSubmissionFromFreshRemote() {
        let local = UserProfile()
        local.hasSubmittedAssessment = true

        let freshRemote = makeSnapshot(
            hasCompletedOnboarding: false,
            hasSubmittedAssessment: false
        )
        XCTAssertFalse(
            AppSyncCoordinator.shared.debug_shouldApplyRemote(freshRemote, overLocal: local),
            "Fresh remote must not overwrite local submitted state"
        )
    }

    func testMergeAppliesCompletionOverSubmittedLocal() {
        let local = UserProfile()
        local.hasSubmittedAssessment = true

        let remoteCompleted = makeSnapshot(
            hasCompletedOnboarding: true,
            hasSubmittedAssessment: true
        )
        XCTAssertTrue(
            AppSyncCoordinator.shared.debug_shouldApplyRemote(remoteCompleted, overLocal: local),
            "Remote completion should win over local submitted"
        )
    }

    // MARK: Helpers

    private func makeSnapshot(
        hasCompletedOnboarding: Bool,
        hasSubmittedAssessment: Bool?
    ) -> CloudProfileSnapshot {
        CloudProfileSnapshot(
            accountIdentifier: "apple-user-xyz",
            profileIdentifier: UUID().uuidString,
            age: 31,
            maxHeartRate: 189,
            weight: 150,
            height: 68,
            currentPhase: TrainingPhase.phase1.rawValue,
            phaseStartDate: Date(),
            hasCompletedOnboarding: hasCompletedOnboarding,
            hasSubmittedAssessment: hasSubmittedAssessment,
            zone2Low: 130,
            zone2High: 150,
            legDays: [],
            coachingHapticsEnabled: true,
            coachingAlertCooldownSeconds: 18,
            primaryGoalRaw: CardioGoal.generalFitness.rawValue,
            targetEvent: nil,
            targetEventDate: nil,
            fitnessLevelRaw: FitnessLevel.occasional.rawValue,
            weeklyCardioFrequency: 2,
            typicalWorkoutMinutes: 30,
            preferredModalities: [],
            availableTrainingDays: 3,
            intensityConstraintRaw: IntensityConstraint.none.rawValue,
            currentFocusRaw: ""
        )
    }
}

// MARK: - Onboarding save-failure guards

final class OnboardingCommitterTests: XCTestCase {

    struct SimulatedSaveError: Error {}

    func testCommitAssessmentSetsFlagOnSuccessfulSave() throws {
        let profile = UserProfile()
        let draft = AssessmentDraft.blank

        try OnboardingCommitter.commitAssessment(
            draft: draft,
            profile: profile,
            accountIdentifier: "apple-user-1",
            save: { /* succeeds */ }
        )

        XCTAssertTrue(profile.hasSubmittedAssessment,
                     "Successful save should leave the submitted flag set")
        XCTAssertFalse(profile.hasCompletedOnboarding,
                      "Commit step must not also mark onboarding complete")
        XCTAssertEqual(profile.accountIdentifier, "apple-user-1")
    }

    func testCommitAssessmentRollsBackFlagOnSaveFailure() {
        let profile = UserProfile()
        XCTAssertFalse(profile.hasSubmittedAssessment)

        XCTAssertThrowsError(
            try OnboardingCommitter.commitAssessment(
                draft: AssessmentDraft.blank,
                profile: profile,
                accountIdentifier: "apple-user-1",
                save: { throw SimulatedSaveError() }
            )
        )

        XCTAssertFalse(profile.hasSubmittedAssessment,
                      "Save failure must roll hasSubmittedAssessment back to false")
    }

    func testFinalizeOnboardingSetsFlagOnSuccessfulSave() throws {
        let profile = UserProfile()
        profile.hasSubmittedAssessment = true

        try OnboardingCommitter.finalizeOnboarding(
            profile: profile,
            save: { /* succeeds */ }
        )

        XCTAssertTrue(profile.hasCompletedOnboarding)
        XCTAssertTrue(profile.hasSubmittedAssessment,
                     "Finalize must not clear the submitted flag")
    }

    func testFinalizeOnboardingRollsBackFlagOnSaveFailure() {
        let profile = UserProfile()
        profile.hasSubmittedAssessment = true
        XCTAssertFalse(profile.hasCompletedOnboarding)

        XCTAssertThrowsError(
            try OnboardingCommitter.finalizeOnboarding(
                profile: profile,
                save: { throw SimulatedSaveError() }
            )
        )

        XCTAssertFalse(profile.hasCompletedOnboarding,
                      "Save failure must not leave hasCompletedOnboarding set to true")
        XCTAssertTrue(profile.hasSubmittedAssessment,
                     "Submitted flag must survive a failed finalize — only completion rolls back")
    }
}
