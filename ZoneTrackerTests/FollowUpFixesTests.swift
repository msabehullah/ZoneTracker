import XCTest
import SwiftData
@testable import ZoneTracker

// MARK: - Tests for the targeted follow-up fix pass
//
// Covers:
//   1. `ConnectivityManager` buffers watch completions that arrive before a
//      handler is installed, and dedupes repeated payloads by id.
//   2. `UserProfile.hasSubmittedAssessment` models the intermediate onboarding
//      state so relaunches resume on plan-overview, not the finished app.
//   3. `SessionType.coachingLabel` translates `.zone2` to "Target Zone" while
//      preserving technical labels for intervals/benchmarks.
//   4. `LocalModelContainer` builds a usable local-only SwiftData container
//      (i.e. the architectural decision to opt out of CloudKit mirroring
//      doesn't break the persistence path).

@MainActor
final class ConnectivityManagerQueueTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        ConnectivityManager.shared.debug_reset()
    }

    override func tearDown() async throws {
        ConnectivityManager.shared.debug_reset()
        try await super.tearDown()
    }

    func testPayloadArrivingBeforeHandlerIsBufferedAndFlushed() {
        let manager = ConnectivityManager.shared
        let payload = makePayload(id: "completion-A")

        manager.debug_injectCompletion(payload)
        XCTAssertEqual(manager.debug_pendingCompletionCount, 1,
                       "Payload should buffer when no handler is installed")

        var delivered: [WorkoutCompletionPayload] = []
        manager.setWorkoutCompletionHandler { delivered.append($0) }

        XCTAssertEqual(delivered, [payload], "Installing handler should flush the buffered payload")
        XCTAssertEqual(manager.debug_pendingCompletionCount, 0, "Buffer should drain on flush")
    }

    func testMultiplePendingPayloadsFlushInOrder() {
        let manager = ConnectivityManager.shared
        let a = makePayload(id: "completion-A")
        let b = makePayload(id: "completion-B")
        let c = makePayload(id: "completion-C")

        manager.debug_injectCompletion(a)
        manager.debug_injectCompletion(b)
        manager.debug_injectCompletion(c)

        var delivered: [WorkoutCompletionPayload] = []
        manager.setWorkoutCompletionHandler { delivered.append($0) }

        XCTAssertEqual(delivered, [a, b, c])
        XCTAssertEqual(manager.debug_pendingCompletionCount, 0)
    }

    func testDuplicatePendingPayloadsAreDeduped() {
        let manager = ConnectivityManager.shared
        let payload = makePayload(id: "completion-A")

        // Simulates the sendMessage + transferUserInfo redundancy on the watch side.
        manager.debug_injectCompletion(payload)
        manager.debug_injectCompletion(payload)
        manager.debug_injectCompletion(payload)
        XCTAssertEqual(manager.debug_pendingCompletionCount, 1,
                       "Repeat deliveries with the same completion id should not queue twice")

        var delivered: [WorkoutCompletionPayload] = []
        manager.setWorkoutCompletionHandler { delivered.append($0) }

        XCTAssertEqual(delivered, [payload])
    }

    func testPayloadDeliveredImmediatelyWhenHandlerAlreadyInstalled() {
        let manager = ConnectivityManager.shared
        var delivered: [WorkoutCompletionPayload] = []
        manager.setWorkoutCompletionHandler { delivered.append($0) }

        let payload = makePayload(id: "completion-A")
        manager.debug_injectCompletion(payload)

        XCTAssertEqual(delivered, [payload])
        XCTAssertEqual(manager.debug_pendingCompletionCount, 0,
                       "Synchronous delivery should not buffer the payload")
    }

    // MARK: - Helpers

    private func makePayload(id: String) -> WorkoutCompletionPayload {
        WorkoutCompletionPayload(
            id: id,
            planIdentifier: "plan-1",
            recommendationIdentifier: "rec-1",
            accountIdentifier: "apple-user-1",
            profileIdentifier: "profile-1",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 700),
            sessionType: .zone2,
            exerciseType: .treadmill,
            intervalProtocol: nil,
            calories: 210,
            heartRateData: HeartRateData(
                avgHR: 140,
                maxHR: 155,
                minHR: 128,
                timeInZone2: 420,
                timeInZone4Plus: 0,
                hrDrift: 4.0,
                recoveryHR: nil,
                samples: []
            ),
            completedSegments: 1,
            plannedSegments: 1,
            notes: nil
        )
    }
}

// MARK: - Onboarding state flag

final class OnboardingStateTests: XCTestCase {

    func testDefaultsForFreshProfile() {
        let profile = UserProfile()
        XCTAssertFalse(profile.hasSubmittedAssessment,
                      "A fresh profile should not be marked as having submitted the assessment")
        XCTAssertFalse(profile.hasCompletedOnboarding,
                      "A fresh profile should not be marked as onboarded")
    }

    func testIntermediateStateDoesNotImplyCompletion() {
        let profile = UserProfile()
        profile.hasSubmittedAssessment = true
        XCTAssertFalse(profile.hasCompletedOnboarding,
                      "Submitting the assessment must not auto-complete onboarding — " +
                      "'Start Coaching' is the real completion moment")
    }

    func testCompletionImpliesSubmission() {
        // Forward path: user moves from submission → completion. Submission
        // stays set so relaunch routing remains coherent.
        let profile = UserProfile()
        profile.hasSubmittedAssessment = true
        profile.hasCompletedOnboarding = true
        XCTAssertTrue(profile.hasSubmittedAssessment)
        XCTAssertTrue(profile.hasCompletedOnboarding)
    }
}

// MARK: - Coaching label helper

final class CoachingLabelTests: XCTestCase {

    func testZone2UsesTargetZoneLabel() {
        XCTAssertEqual(SessionType.zone2.coachingLabel, "Target Zone",
                      "Zone 2 should surface as 'Target Zone' on coaching UI")
    }

    func testIntervalLabelsPreservedVerbatim() {
        XCTAssertEqual(SessionType.interval_30_30.coachingLabel, "30/30 Intervals")
        XCTAssertEqual(SessionType.interval_tempo.coachingLabel, "Tempo Run")
        XCTAssertEqual(SessionType.interval_hillRepeats.coachingLabel, "Hill Repeats")
        XCTAssertEqual(SessionType.interval_4x4.coachingLabel, "4×4 Norwegian")
        XCTAssertEqual(SessionType.interval_tabata.coachingLabel, "Tabata")
        XCTAssertEqual(SessionType.interval_longIntervals.coachingLabel, "Long Intervals")
    }

    func testBenchmarkKeepsTechnicalDisplayName() {
        XCTAssertEqual(SessionType.benchmark_mile.coachingLabel,
                       SessionType.benchmark_mile.displayName,
                       "Benchmark names are already user-friendly and should not be rewritten")
    }

    func testDisplayNameIsUntouchedForHistoryAndExport() {
        // The helper split protects the technical name so history/export/debug
        // surfaces still say "Zone 2" unambiguously.
        XCTAssertEqual(SessionType.zone2.displayName, "Zone 2")
    }
}

// MARK: - Local model container smoke test

@MainActor
final class LocalModelContainerTests: XCTestCase {

    func testContainerBuildsAndPersistsModels() throws {
        // We can't assert `cloudKitDatabase == .none` via the public API, so the
        // structural test is: the factory returns a working container, the
        // expected entities round-trip, and nothing throws.
        let container = LocalModelContainer.make()
        let context = ModelContext(container)

        let profile = UserProfile(accountIdentifier: "local-test")
        context.insert(profile)
        try context.save()

        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        XCTAssertTrue(profiles.contains(where: { $0.accountIdentifier == "local-test" }))

        // Clean up so repeated test runs don't accumulate profiles on disk.
        context.delete(profile)
        try context.save()
    }
}
