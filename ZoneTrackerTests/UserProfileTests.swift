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

    // MARK: - Focus / Phase Synchronization

    func testFocusSetterSyncsPhase() {
        let profile = UserProfile()
        profile.focus = .developingSpeed
        XCTAssertEqual(profile.phase, .phase2, "Setting focus should sync phase via mappedPhase")
        XCTAssertEqual(profile.currentPhase, "phase2")
    }

    func testPhaseSetterSyncsFocus() {
        let profile = UserProfile()
        profile.phase = .phase3
        XCTAssertEqual(profile.focus, .peakPerformance, "Setting phase should sync focus via toFocus")
    }

    func testFocusActiveRecoveryMapsToPhase1() {
        let profile = UserProfile()
        profile.focus = .activeRecovery
        XCTAssertEqual(profile.phase, .phase1, "activeRecovery maps to phase1 internally")
        XCTAssertEqual(profile.focus, .activeRecovery, "focus should remain activeRecovery, not buildingBase")
    }

    func testPhaseSetterDoesNotOverwriteMatchingFocus() {
        let profile = UserProfile()
        profile.focus = .developingSpeed // sets phase to .phase2
        profile.phase = .phase2 // should NOT overwrite focus since it already matches
        XCTAssertEqual(profile.focus, .developingSpeed)
    }

    // MARK: - Legacy Migration

    func testLegacyPhase2ProfileMigratesToDevelopingSpeed() {
        let profile = UserProfile()
        // Simulate a legacy profile that has currentPhase set but empty currentFocusRaw
        profile.currentPhase = TrainingPhase.phase2.rawValue
        profile.currentFocusRaw = "" // legacy: no focus was stored
        XCTAssertEqual(profile.focus, .developingSpeed, "Empty focusRaw should fall back to phase.toFocus")
    }

    func testLegacyPhase3ProfileMigratesToPeakPerformance() {
        let profile = UserProfile()
        profile.currentPhase = TrainingPhase.phase3.rawValue
        profile.currentFocusRaw = ""
        XCTAssertEqual(profile.focus, .peakPerformance)
    }

    // MARK: - Focus Progression

    func testFocusNext() {
        XCTAssertEqual(TrainingFocus.activeRecovery.next, .buildingBase)
        XCTAssertEqual(TrainingFocus.buildingBase.next, .developingSpeed)
        XCTAssertEqual(TrainingFocus.developingSpeed.next, .peakPerformance)
        XCTAssertNil(TrainingFocus.peakPerformance.next)
    }

    func testAdvanceFocus() {
        let profile = UserProfile()
        profile.focus = .activeRecovery
        profile.advanceFocus()
        XCTAssertEqual(profile.focus, .buildingBase, "activeRecovery should advance to buildingBase")
        profile.advanceFocus()
        XCTAssertEqual(profile.focus, .developingSpeed)
        profile.advanceFocus()
        XCTAssertEqual(profile.focus, .peakPerformance)
        profile.advanceFocus()
        XCTAssertEqual(profile.focus, .peakPerformance, "peakPerformance is final")
    }

    // MARK: - Effective Session Counts

    func testEffectiveSessionsRampsFromBaselineTowardCeiling() {
        // Post-pass-4: weeklyCardioFrequency is the current baseline,
        // availableTrainingDays is the ceiling the plan grows toward.
        let profile = UserProfile()
        profile.fitnessLevel = .experienced
        profile.focus = .peakPerformance
        profile.weeklyCardioFrequency = 2
        profile.availableTrainingDays = 7
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 5,
                       "Experienced user ramps 3 past baseline, capped at ceiling")
        XCTAssertEqual(profile.availableSessionsCeiling, 7)
        XCTAssertTrue(profile.hasHeadroomToBuild,
                      "5 of 7 leaves headroom for UI to surface 'building toward' copy")

        profile.weeklyCardioFrequency = 7
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 7,
                       "Baseline already at ceiling — stay there")
        XCTAssertFalse(profile.hasHeadroomToBuild)
    }

    func testEffectiveIntervalSessionsBlockedByAvoidHighIntensity() {
        let profile = UserProfile()
        profile.fitnessLevel = .experienced
        profile.focus = .developingSpeed
        profile.weeklyCardioFrequency = 2
        profile.availableTrainingDays = 4
        profile.intensityConstraint = .avoidHighIntensity
        XCTAssertEqual(profile.effectiveSessionsPerWeek, 4,
                       "Ramp still lands at ceiling for experienced users")
        XCTAssertEqual(profile.effectiveIntervalSessions, 0, "Avoid high intensity should block intervals")
        XCTAssertEqual(profile.effectiveTargetZoneSessions, 4,
                       "All sessions become target zone when intervals are blocked")
    }

    func testEffectiveStartingDurationForBeginner() {
        let profile = UserProfile()
        profile.fitnessLevel = .beginner
        profile.typicalWorkoutMinutes = 60 // wants 60 but beginner cap is 30
        XCTAssertEqual(profile.effectiveStartingDuration, 30 * 60, "Beginner should be capped at 30 min")
    }

    func testEffectiveStartingDurationForExperienced() {
        let profile = UserProfile()
        profile.fitnessLevel = .experienced
        profile.typicalWorkoutMinutes = 60
        XCTAssertEqual(profile.effectiveStartingDuration, 60 * 60, "Experienced user should get their requested duration")
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
