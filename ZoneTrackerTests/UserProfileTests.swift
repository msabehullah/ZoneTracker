import XCTest
@testable import ZoneTracker

final class UserProfileTests: XCTestCase {

    // MARK: - Default Initialization

    func testDefaultValues() {
        let profile = UserProfile()
        XCTAssertEqual(profile.age, 31)
        XCTAssertEqual(profile.maxHR, 189)
        XCTAssertEqual(profile.weight, 150)
        XCTAssertEqual(profile.height, 68)
        XCTAssertEqual(profile.zone2TargetLow, 130)
        XCTAssertEqual(profile.zone2TargetHigh, 150)
        XCTAssertFalse(profile.hasCompletedOnboarding)
        XCTAssertEqual(profile.phase, .phase1)
        XCTAssertTrue(profile.legDays.isEmpty)
        XCTAssertTrue(profile.coachingHapticsEnabled)
        XCTAssertEqual(profile.coachingAlertCooldownSeconds, 18)
    }

    // MARK: - Max HR Calculation

    func testMaxHRFromAge() {
        let profile = UserProfile(age: 25)
        XCTAssertEqual(profile.maxHR, 195)
    }

    // MARK: - Phase Management

    func testPhaseGetSet() {
        let profile = UserProfile()
        XCTAssertEqual(profile.phase, .phase1)
        profile.phase = .phase2
        XCTAssertEqual(profile.phase, .phase2)
        XCTAssertEqual(profile.currentPhase, "phase2")
    }

    func testAdvancePhase() {
        let profile = UserProfile()
        profile.advancePhase()
        XCTAssertEqual(profile.phase, .phase2)
        profile.advancePhase()
        XCTAssertEqual(profile.phase, .phase3)
        profile.advancePhase()
        XCTAssertEqual(profile.phase, .phase3, "Phase 3 is final — should not advance")
    }

    // MARK: - Week Number

    func testWeekNumberStartsAtOne() {
        let profile = UserProfile()
        profile.phaseStartDate = Date()
        XCTAssertEqual(profile.weekNumber, 1)
    }

    func testWeekNumberAfterSixWeeks() {
        let profile = UserProfile()
        profile.phaseStartDate = Calendar.current.date(byAdding: .weekOfYear, value: -6, to: Date())!
        XCTAssertGreaterThanOrEqual(profile.weekNumber, 6)
    }

    // MARK: - Zone Ranges

    func testZone2Range() {
        let profile = UserProfile(zone2TargetLow: 125, zone2TargetHigh: 145)
        XCTAssertEqual(profile.zone2Range, 125...145)
    }

    func testHRZoneCeilings() {
        let profile = UserProfile(age: 31) // maxHR = 189
        XCTAssertEqual(profile.zone1Ceiling, Int(189 * 0.60)) // 113
        XCTAssertEqual(profile.zone3Ceiling, Int(189 * 0.80)) // 151
        XCTAssertEqual(profile.zone4Ceiling, Int(189 * 0.90)) // 170
    }

    // MARK: - Leg Days

    func testIsLegDay() {
        let profile = UserProfile()
        profile.legDays = [2, 5] // Monday, Thursday
        let monday = nextWeekday(2)
        let tuesday = nextWeekday(3)
        XCTAssertTrue(profile.isLegDay(monday))
        XCTAssertFalse(profile.isLegDay(tuesday))
    }

    func testIsAdjacentToLegDay() {
        let profile = UserProfile()
        profile.legDays = [3] // Tuesday
        // Wednesday (day after Tuesday) — adjacency checks the day BEFORE
        let wednesday = nextWeekday(4)
        XCTAssertTrue(profile.isAdjacentToLegDay(wednesday),
                     "The day after a leg day should be adjacent")

        let monday = nextWeekday(2)
        XCTAssertFalse(profile.isAdjacentToLegDay(monday),
                      "Monday is not the day after Tuesday")
    }

    // MARK: - Training Phase Properties

    func testPhaseMinimumWeeks() {
        XCTAssertEqual(TrainingPhase.phase1.minimumWeeks, 6)
        XCTAssertEqual(TrainingPhase.phase2.minimumWeeks, 6)
        XCTAssertEqual(TrainingPhase.phase3.minimumWeeks, 0)
    }

    func testShouldAvoidHighIntensityOnLegDayAndDayAfter() {
        let profile = UserProfile()
        let tuesday = nextWeekday(3)
        let wednesday = Calendar.current.date(byAdding: .day, value: 1, to: tuesday)!
        profile.legDays = [3]

        XCTAssertTrue(profile.shouldAvoidHighIntensity(on: tuesday))
        XCTAssertTrue(profile.shouldAvoidHighIntensity(on: wednesday))
    }

    func testPhaseTargetSessions() {
        XCTAssertEqual(TrainingPhase.phase1.targetSessionsPerWeek, 3)
        XCTAssertEqual(TrainingPhase.phase2.targetSessionsPerWeek, 3)
        XCTAssertEqual(TrainingPhase.phase3.targetSessionsPerWeek, 4)
    }

    func testPhaseNext() {
        XCTAssertEqual(TrainingPhase.phase1.next, .phase2)
        XCTAssertEqual(TrainingPhase.phase2.next, .phase3)
        XCTAssertNil(TrainingPhase.phase3.next)
    }

    // MARK: - Helpers

    private func nextWeekday(_ weekday: Int) -> Date {
        let calendar = Calendar.current
        var date = Date()
        while calendar.component(.weekday, from: date) != weekday {
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return date
    }
}
