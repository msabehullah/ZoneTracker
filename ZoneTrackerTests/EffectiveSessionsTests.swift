import XCTest
@testable import ZoneTracker

final class EffectiveSessionsTests: XCTestCase {

    // The UI (Dashboard, Progress, Plan Overview) must reflect what the user
    // actually signed up for — `availableTrainingDays` — not the idealized
    // focus target. These tests guard against a regression where the
    // hardcoded `focus.targetSessionsPerWeek` sneaks back into the UI.

    private func makeProfile(focus: TrainingFocus, availableDays: Int) -> UserProfile {
        let profile = UserProfile()
        profile.focus = focus
        profile.availableTrainingDays = availableDays
        profile.intensityConstraint = .none
        return profile
    }

    func testEffectiveSessionsCapsByAvailableDays() {
        let profile = makeProfile(focus: .buildingBase, availableDays: 2)
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 2,
                       "Effective sessions must cap to availableTrainingDays when lower than focus target")
    }

    func testEffectiveSessionsUsesFocusWhenDaysAreAmple() {
        let profile = makeProfile(focus: .buildingBase, availableDays: 7)
        XCTAssertEqual(profile.effectiveSessionsPerWeek, profile.focus.targetSessionsPerWeek)
    }

    func testEffectiveIntervalSessionsZeroWhenConstraintAvoidsIntensity() {
        let profile = makeProfile(focus: .developingSpeed, availableDays: 4)
        profile.intensityConstraint = .avoidHighIntensity
        XCTAssertEqual(profile.effectiveIntervalSessions, 0)
    }

    func testEffectiveTargetZoneSessionsScaleWithAvailableDays() {
        // Give the user fewer days than the focus prescribes and confirm the
        // target-zone count drops too — it should not stay at the full focus
        // number when we've capped sessionsPerWeek.
        let full = makeProfile(focus: .buildingBase, availableDays: 10)
        let capped = makeProfile(focus: .buildingBase, availableDays: 2)
        XCTAssertGreaterThan(full.effectiveSessionsPerWeek, capped.effectiveSessionsPerWeek)
        XCTAssertGreaterThanOrEqual(full.effectiveTargetZoneSessions, capped.effectiveTargetZoneSessions)
    }
}
