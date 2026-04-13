import XCTest
@testable import ZoneTracker

final class WorkoutPlanningServiceTests: XCTestCase {

    func testIntervalPlanIncludesWarmupWorkRecoveryAndCooldown() {
        let profile = UserProfile()
        profile.phase = .phase2

        let recommendation = WorkoutRecommendation(
            sessionType: .interval_30_30,
            exerciseType: .treadmill,
            targetDuration: 28 * 60,
            targetHRLow: 170,
            targetHRHigh: 180,
            suggestedMetrics: ["speed": 6.0],
            intervalProtocol: SessionType.interval_30_30.defaultIntervalProtocol,
            reasoning: "Interval day",
            adjustmentType: .holdSteady
        )

        let plan = WorkoutPlanningService.plan(
            from: recommendation,
            profile: profile,
            accountIdentifier: "apple-user-123"
        )

        XCTAssertEqual(plan.segments.first?.kind, .warmup)
        XCTAssertEqual(plan.segments.last?.kind, .cooldown)
        XCTAssertTrue(plan.segments.contains(where: { $0.kind == .work }))
        XCTAssertTrue(plan.segments.contains(where: { $0.kind == .recovery }))
    }
}
