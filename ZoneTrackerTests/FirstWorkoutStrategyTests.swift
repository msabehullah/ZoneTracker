import XCTest
@testable import ZoneTracker

final class FirstWorkoutStrategyTests: XCTestCase {

    // MARK: - Decision Matrix: Goal × Fitness Level

    func testBeginnerAlwaysGetsEasyTargetZoneRegardlessOfGoal() {
        for goal in CardioGoal.allCases {
            let profile = makeProfile(goal: goal, level: .beginner)
            let shape = FirstWorkoutStrategy.decideShape(for: profile)
            XCTAssertEqual(shape, .easyTargetZoneIntro,
                           "Beginner should get easyTargetZoneIntro for goal \(goal)")
        }
    }

    func testReturnToTrainingAlwaysReturnsToTargetZone() {
        for level in [FitnessLevel.occasional, .regular, .experienced] {
            let profile = makeProfile(goal: .returnToTraining, level: level)
            let shape = FirstWorkoutStrategy.decideShape(for: profile)
            XCTAssertEqual(shape, .returnToTargetZone,
                           "Return-to-training should always get returnToTargetZone for level \(level)")
        }
    }

    func testOccasionalAerobicBaseGetsTargetZoneBaseline() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        XCTAssertEqual(FirstWorkoutStrategy.decideShape(for: profile), .targetZoneBaseline)
    }

    func testOccasionalRaceTrainingGetsAerobicSupport() {
        let profile = makeProfile(goal: .raceTraining, level: .occasional)
        XCTAssertEqual(FirstWorkoutStrategy.decideShape(for: profile), .aerobicSupport)
    }

    func testOccasionalPeakCardioStillGetsBaselineNotIntervals() {
        let profile = makeProfile(goal: .peakCardio, level: .occasional)
        let shape = FirstWorkoutStrategy.decideShape(for: profile)
        XCTAssertEqual(shape, .targetZoneBaseline,
                       "Casual users should not be thrown into intervals on their first session")
    }

    func testExperiencedPeakCardioGetsIntervalIntro() {
        let profile = makeProfile(goal: .peakCardio, level: .experienced)
        XCTAssertEqual(FirstWorkoutStrategy.decideShape(for: profile), .intervalIntro)
    }

    func testConsistentPeakCardioGetsIntervalIntro() {
        let profile = makeProfile(goal: .peakCardio, level: .regular)
        XCTAssertEqual(FirstWorkoutStrategy.decideShape(for: profile), .intervalIntro)
    }

    func testExperiencedRaceTrainingCloseToEventGetsBenchmark() {
        let profile = makeProfile(goal: .raceTraining, level: .experienced)
        profile.targetEvent = "10K"
        profile.targetEventDate = Calendar.current.date(byAdding: .day, value: 20, to: Date())
        XCTAssertEqual(FirstWorkoutStrategy.decideShape(for: profile), .benchmarkAssessment)
    }

    func testExperiencedRaceTrainingFarFromEventGetsAerobicSupport() {
        let profile = makeProfile(goal: .raceTraining, level: .experienced)
        profile.targetEvent = "Marathon"
        profile.targetEventDate = Calendar.current.date(byAdding: .day, value: 120, to: Date())
        XCTAssertEqual(FirstWorkoutStrategy.decideShape(for: profile), .aerobicSupport)
    }

    func testExperiencedRaceTrainingWithNoDateGetsAerobicSupport() {
        let profile = makeProfile(goal: .raceTraining, level: .experienced)
        XCTAssertEqual(FirstWorkoutStrategy.decideShape(for: profile), .aerobicSupport)
    }

    // MARK: - Decision Matrix: Constraints

    func testAvoidHighIntensityBlocksIntervalIntroForExperienced() {
        let profile = makeProfile(goal: .peakCardio, level: .experienced)
        profile.intensityConstraint = .avoidHighIntensity
        XCTAssertEqual(FirstWorkoutStrategy.decideShape(for: profile), .targetZoneBaseline,
                       "avoidHighIntensity must block interval intro even for experienced users")
    }

    func testAvoidHighIntensityBlocksBenchmarkForExperienced() {
        let profile = makeProfile(goal: .raceTraining, level: .experienced)
        profile.intensityConstraint = .avoidHighIntensity
        profile.targetEventDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())
        XCTAssertEqual(FirstWorkoutStrategy.decideShape(for: profile), .aerobicSupport,
                       "avoidHighIntensity must block the benchmark assessment")
    }

    // MARK: - Modality Selection

    func testFirstSelectedModalityBecomesPrimary() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        profile.preferredModalities = [
            ExerciseType.bike.rawValue,
            ExerciseType.treadmill.rawValue
        ]
        XCTAssertEqual(FirstWorkoutStrategy.selectModality(for: profile), .bike)
    }

    func testSelectionOrderRespectedEvenWhenMultipleLowImpact() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        profile.preferredModalities = [
            ExerciseType.rowing.rawValue,
            ExerciseType.bike.rawValue
        ]
        XCTAssertEqual(FirstWorkoutStrategy.selectModality(for: profile), .rowing)
    }

    func testLowImpactFilterSwapsToFirstLowImpactInPreferences() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        profile.intensityConstraint = .lowImpactPreferred
        profile.preferredModalities = [
            ExerciseType.treadmill.rawValue,   // high impact
            ExerciseType.elliptical.rawValue,  // low impact
            ExerciseType.bike.rawValue
        ]
        XCTAssertEqual(FirstWorkoutStrategy.selectModality(for: profile), .elliptical,
                       "Should pick first low-impact entry from preferences, not fallback to bike")
    }

    func testLowImpactFilterFallsBackToBikeIfNoLowImpactPreferred() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        profile.intensityConstraint = .lowImpactPreferred
        profile.preferredModalities = [
            ExerciseType.treadmill.rawValue,
            ExerciseType.outdoorRun.rawValue
        ]
        XCTAssertEqual(FirstWorkoutStrategy.selectModality(for: profile), .bike)
    }

    func testEmptyPreferencesFallsBackToTreadmill() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        profile.preferredModalities = []
        XCTAssertEqual(FirstWorkoutStrategy.selectModality(for: profile), .treadmill)
    }

    // MARK: - End-to-End Recommendation

    func testBeginnerVsExperiencedProduceDifferentFirstWorkouts() {
        let beginner = makeProfile(goal: .peakCardio, level: .beginner)
        let experienced = makeProfile(goal: .peakCardio, level: .experienced)

        let beginnerRec = FirstWorkoutStrategy.recommend(for: beginner)
        let experiencedRec = FirstWorkoutStrategy.recommend(for: experienced)

        XCTAssertEqual(beginnerRec.sessionType, .zone2)
        XCTAssertEqual(experiencedRec.sessionType, .interval_30_30)
        // The beginner session is target-zone and short; the experienced
        // session has an interval protocol — these must be materially different.
        XCTAssertNil(beginnerRec.intervalProtocol)
        XCTAssertNotNil(experiencedRec.intervalProtocol)
        XCTAssertLessThanOrEqual(beginnerRec.targetDurationMinutes, 25)
    }

    func testRaceTrainingEventInfluencesFirstWorkoutSessionType() {
        let soonRace = makeProfile(goal: .raceTraining, level: .experienced)
        soonRace.targetEvent = "Half Marathon"
        soonRace.targetEventDate = Calendar.current.date(byAdding: .day, value: 21, to: Date())

        let distantRace = makeProfile(goal: .raceTraining, level: .experienced)
        distantRace.targetEvent = "Marathon"
        distantRace.targetEventDate = Calendar.current.date(byAdding: .day, value: 180, to: Date())

        let soonRec = FirstWorkoutStrategy.recommend(for: soonRace)
        let distantRec = FirstWorkoutStrategy.recommend(for: distantRace)

        XCTAssertEqual(soonRec.sessionType, .benchmark_mile,
                       "Close-to-event race training should start with a benchmark")
        XCTAssertEqual(distantRec.sessionType, .zone2,
                       "Far-from-event race training should start with aerobic support")
        XCTAssertTrue(soonRec.reasoning.contains("days to your Half Marathon"),
                      "Reasoning should reference days until the event: \(soonRec.reasoning)")
    }

    // MARK: - Per-Modality Metrics

    func testMetricsAreValidForEachModality() {
        // Every first-workout modality choice should produce metrics matching
        // that modality's own metric definitions — no treadmill bias anywhere.
        for modality in ExerciseType.allCases {
            for intensity: FirstWorkoutStrategy.IntensityLevel in [.easy, .moderate, .confident] {
                let metrics = FirstWorkoutStrategy.starterMetrics(for: modality, intensity: intensity)
                for def in modality.metricDefinitions {
                    guard let value = metrics[def.key] else {
                        XCTFail("Missing metric \(def.key) for \(modality)")
                        continue
                    }
                    XCTAssertGreaterThanOrEqual(value, def.min,
                        "Metric \(def.key) below min for \(modality) at \(intensity)")
                    XCTAssertLessThanOrEqual(value, def.max,
                        "Metric \(def.key) above max for \(modality) at \(intensity)")
                }
                // And no extra keys that don't belong to the modality.
                let validKeys = Set(modality.metricDefinitions.map(\.key))
                XCTAssertEqual(Set(metrics.keys), validKeys,
                               "Metric keys for \(modality) should match modality definitions exactly")
            }
        }
    }

    func testNoTreadmillBiasForNonTreadmillUsers() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        profile.preferredModalities = [ExerciseType.bike.rawValue]
        let rec = FirstWorkoutStrategy.recommend(for: profile)

        XCTAssertEqual(rec.exerciseType, .bike)
        XCTAssertNil(rec.suggestedMetrics["speed"],
                     "Bike recommendation must not contain treadmill-only metrics")
        XCTAssertNil(rec.suggestedMetrics["incline"])
        XCTAssertNotNil(rec.suggestedMetrics["resistance"])
        XCTAssertNotNil(rec.suggestedMetrics["cadence"])
    }

    func testSwimmingGetsPoolAppropriateMetrics() {
        let profile = makeProfile(goal: .aerobicBase, level: .regular)
        profile.preferredModalities = [ExerciseType.swimming.rawValue]
        let rec = FirstWorkoutStrategy.recommend(for: profile)

        XCTAssertEqual(rec.exerciseType, .swimming)
        XCTAssertNotNil(rec.suggestedMetrics["pace"])
        XCTAssertNotNil(rec.suggestedMetrics["strokeRate"])
    }

    // MARK: - Zone Labeling

    func testReasoningUsesZone2LabelWhenCanonical() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        // Canonical Zone 2 for a 31-year-old (maxHR 189) is ~113-132.
        profile.zone2TargetLow = Int((Double(profile.maxHR) * 0.60).rounded())
        profile.zone2TargetHigh = Int((Double(profile.maxHR) * 0.70).rounded())
        let rec = FirstWorkoutStrategy.recommend(for: profile)
        XCTAssertTrue(rec.reasoning.contains("Zone 2"),
                      "Canonical Zone 2 bounds should use the 'Zone 2' label, got: \(rec.reasoning)")
    }

    func testReasoningUsesTargetZoneLabelWhenCustomized() {
        let profile = makeProfile(goal: .aerobicBase, level: .occasional)
        profile.zone2TargetLow = 130
        profile.zone2TargetHigh = 150
        let rec = FirstWorkoutStrategy.recommend(for: profile)
        // Default profile: maxHR=189, canonical Z2 ~113-132 — 130/150 is customized.
        XCTAssertTrue(rec.reasoning.contains("target zone"),
                      "Customized zone bounds should use 'target zone' label, got: \(rec.reasoning)")
    }

    // MARK: - Helpers

    private func makeProfile(goal: CardioGoal, level: FitnessLevel) -> UserProfile {
        let profile = UserProfile()
        profile.primaryGoal = goal
        profile.fitnessLevel = level
        profile.focus = goal.initialFocus
        profile.typicalWorkoutMinutes = 30
        profile.weeklyCardioFrequency = 3
        profile.availableTrainingDays = 3
        profile.preferredModalities = [ExerciseType.treadmill.rawValue]
        profile.intensityConstraint = .none
        return profile
    }
}
