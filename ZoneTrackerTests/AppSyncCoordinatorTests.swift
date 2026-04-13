import XCTest
@testable import ZoneTracker

@MainActor
final class AppSyncCoordinatorTests: XCTestCase {

    func testBackfillIdentityAssignsAccountIdentifierToProfileAndWorkouts() {
        let profile = UserProfile()
        let workout = WorkoutEntry(
            date: Date(),
            exerciseType: .treadmill,
            duration: 30 * 60,
            metrics: [:],
            sessionType: .zone2,
            heartRateData: .empty,
            phase: .phase1,
            weekNumber: 1
        )

        AppSyncCoordinator.shared.backfillIdentity(
            profile: profile,
            workouts: [workout],
            accountIdentifier: "apple-user-123"
        )

        XCTAssertFalse(profile.profileIdentifier.isEmpty)
        XCTAssertEqual(profile.accountIdentifier, "apple-user-123")
        XCTAssertEqual(workout.accountIdentifier, "apple-user-123")
    }

    func testBackfillIdentityRestoresMissingWorkoutSource() {
        let workout = WorkoutEntry(
            date: Date(),
            exerciseType: .treadmill,
            duration: 30 * 60,
            metrics: [:],
            sessionType: .zone2,
            heartRateData: .empty,
            phase: .phase1,
            weekNumber: 1
        )
        workout.sourceRaw = ""

        AppSyncCoordinator.shared.backfillIdentity(
            profile: nil,
            workouts: [workout],
            accountIdentifier: nil
        )

        XCTAssertEqual(workout.source, .manualEntry)
    }
}
