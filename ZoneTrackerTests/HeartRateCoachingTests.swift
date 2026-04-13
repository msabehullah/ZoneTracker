import XCTest
@testable import ZoneTracker

final class HeartRateCoachingTests: XCTestCase {

    func testAlertsWhenHeartRateFallsBelowTarget() {
        var engine = HeartRateCoachingEngine()
        let snapshot = engine.evaluate(
            heartRate: 120,
            targetRange: TargetHeartRateRange(low: 130, high: 150),
            at: Date(),
            preferences: .default
        )

        XCTAssertEqual(snapshot.position, .belowTarget)
        XCTAssertEqual(snapshot.alert, .belowTarget)
    }

    func testCooldownPreventsRepeatedOutOfRangeAlertsUntilRearmed() {
        var engine = HeartRateCoachingEngine()
        let range = TargetHeartRateRange(low: 130, high: 150)
        let start = Date()

        let first = engine.evaluate(
            heartRate: 121,
            targetRange: range,
            at: start,
            preferences: .default
        )
        let second = engine.evaluate(
            heartRate: 122,
            targetRange: range,
            at: start.addingTimeInterval(5),
            preferences: .default
        )

        XCTAssertEqual(first.alert, .belowTarget)
        XCTAssertEqual(second.alert, .none)
    }

    func testReturningToTargetRearmsAndAllowsFutureAlert() {
        var engine = HeartRateCoachingEngine()
        let range = TargetHeartRateRange(low: 130, high: 150)
        let start = Date()

        _ = engine.evaluate(
            heartRate: 121,
            targetRange: range,
            at: start,
            preferences: .default
        )
        let backInRange = engine.evaluate(
            heartRate: 140,
            targetRange: range,
            at: start.addingTimeInterval(8),
            preferences: .default
        )
        let aboveTarget = engine.evaluate(
            heartRate: 160,
            targetRange: range,
            at: start.addingTimeInterval(26),
            preferences: .default
        )

        XCTAssertEqual(backInRange.alert, .backInTarget)
        XCTAssertEqual(aboveTarget.alert, .aboveTarget)
    }
}
