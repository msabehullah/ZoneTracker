import XCTest
import SwiftData
@testable import ZoneTracker

@MainActor
final class WatchWorkoutIngestionTests: XCTestCase {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        // The production schema is mirrored to CloudKit, which insists that
        // every non-optional attribute carry a default value and that no
        // entity have a unique constraint. For unit tests we flip CloudKit
        // off via `.none` so the in-memory store loads cleanly against the
        // real WorkoutEntry / UserProfile model.
        let schema = Schema([WorkoutEntry.self, UserProfile.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makePayload(
        id: String = UUID().uuidString,
        calories: Double = 245,
        distance: Double = 3200,
        timeInTarget: TimeInterval = 1_500,
        plannedSegments: Int = 3,
        completedSegments: Int = 2
    ) -> WorkoutCompletionPayload {
        WorkoutCompletionPayload(
            id: id,
            planIdentifier: "plan-1",
            recommendationIdentifier: "rec-1",
            accountIdentifier: "apple-123",
            profileIdentifier: "profile-1",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 1_800),
            sessionType: .zone2,
            exerciseType: .treadmill,
            intervalProtocol: nil,
            calories: calories,
            heartRateData: HeartRateData(
                avgHR: 140,
                maxHR: 156,
                minHR: 128,
                timeInZone2: 1_500,
                timeInZone4Plus: 0,
                hrDrift: 3.1,
                recoveryHR: nil,
                samples: []
            ),
            completedSegments: completedSegments,
            plannedSegments: plannedSegments,
            notes: nil,
            distanceMeters: distance,
            timeInTarget: timeInTarget
        )
    }

    // MARK: - Persistence

    func testIngestInsertsWorkoutAndPersists() throws {
        let context = try makeContext()
        let profile = UserProfile()
        context.insert(profile)

        let payload = makePayload()
        let workout = WatchWorkoutIngestionService.ingest(
            completion: payload,
            profile: profile,
            context: context,
            existingWorkouts: []
        )

        XCTAssertNotNil(workout)

        // Fetch in a fresh descriptor to confirm the row is persisted, not
        // just in-memory on the context.
        let fetched = try context.fetch(FetchDescriptor<WorkoutEntry>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.completionIdentifier, payload.id)
    }

    func testIngestSkipsDuplicatesByCompletionIdentifier() throws {
        let context = try makeContext()
        let profile = UserProfile()
        context.insert(profile)

        let payload = makePayload(id: "same-id")
        let first = WatchWorkoutIngestionService.ingest(
            completion: payload,
            profile: profile,
            context: context,
            existingWorkouts: []
        )
        XCTAssertNotNil(first)

        let existing = try context.fetch(FetchDescriptor<WorkoutEntry>())
        let second = WatchWorkoutIngestionService.ingest(
            completion: payload,
            profile: profile,
            context: context,
            existingWorkouts: existing
        )

        XCTAssertNil(second, "Second ingest with same completionIdentifier should return nil")
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutEntry>()).count, 1)
    }

    // MARK: - Metrics

    func testIngestPopulatesMetricsFromPayload() throws {
        let context = try makeContext()
        let profile = UserProfile()
        context.insert(profile)

        let payload = makePayload(
            calories: 321,
            distance: 4200,
            timeInTarget: 1_650,
            plannedSegments: 4,
            completedSegments: 3
        )
        guard let workout = WatchWorkoutIngestionService.ingest(
            completion: payload,
            profile: profile,
            context: context,
            existingWorkouts: []
        ) else {
            XCTFail("ingest returned nil for fresh payload")
            return
        }

        let metrics = workout.metrics
        XCTAssertEqual(metrics["calories"], 321)
        XCTAssertEqual(metrics["distanceMeters"], 4200)
        XCTAssertEqual(metrics["timeInTarget"], 1_650)
        XCTAssertEqual(metrics["plannedSegments"], 4)
        XCTAssertEqual(metrics["completedSegments"], 3)
    }

    // MARK: - Backward-compat decode

    func testCompletionPayloadDecodesLegacyEnvelopeWithoutNewFields() throws {
        // Older watch builds didn't ship distanceMeters / timeInTarget.
        // Decode must default them to 0 rather than throwing.
        let legacyJSON: [String: Any] = [
            "id": "legacy-1",
            "startedAt": 0,
            "endedAt": 1800,
            "sessionType": SessionType.zone2.rawValue,
            "exerciseType": ExerciseType.treadmill.rawValue,
            "calories": 200,
            "heartRateData": [
                "avgHR": 140,
                "maxHR": 150,
                "minHR": 120,
                "timeInZone2": 1500,
                "timeInZone4Plus": 0,
                "hrDrift": 2.0,
                "samples": []
            ],
            "completedSegments": 1,
            "plannedSegments": 1
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyJSON)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorkoutCompletionPayload.self, from: data)

        XCTAssertEqual(decoded.distanceMeters, 0)
        XCTAssertEqual(decoded.timeInTarget, 0)
        XCTAssertEqual(decoded.id, "legacy-1")
    }
}
