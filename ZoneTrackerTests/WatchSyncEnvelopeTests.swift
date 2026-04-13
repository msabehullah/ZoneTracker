import XCTest
@testable import ZoneTracker

final class WatchSyncEnvelopeTests: XCTestCase {

    func testWorkoutPlanEnvelopeRoundTrip() throws {
        let profile = UserProfile()
        let recommendation = WorkoutRecommendation.defaultFirstWorkout(profile: profile)
        let plan = WorkoutPlanningService.plan(
            from: recommendation,
            profile: profile,
            accountIdentifier: "apple-user-123"
        )

        let message = try WatchSyncEnvelope.workoutPlanMessage(plan)
        let decoded = try WatchSyncEnvelope.decodeWorkoutPlan(from: message)

        XCTAssertEqual(decoded, plan)
    }

    func testWorkoutCompletionEnvelopeRoundTrip() throws {
        let payload = WorkoutCompletionPayload(
            id: UUID().uuidString,
            planIdentifier: "plan-1",
            recommendationIdentifier: "rec-1",
            accountIdentifier: "apple-user-123",
            profileIdentifier: "profile-1",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 700),
            sessionType: .zone2,
            exerciseType: .treadmill,
            intervalProtocol: nil,
            calories: 220,
            heartRateData: HeartRateData(
                avgHR: 141,
                maxHR: 156,
                minHR: 128,
                timeInZone2: 420,
                timeInZone4Plus: 0,
                hrDrift: 4.2,
                recoveryHR: nil,
                samples: []
            ),
            completedSegments: 1,
            plannedSegments: 1,
            notes: nil
        )

        let message = try WatchSyncEnvelope.workoutCompletionMessage(payload)
        let decoded = try WatchSyncEnvelope.decodeWorkoutCompletion(from: message)

        XCTAssertEqual(decoded, payload)
    }
}
