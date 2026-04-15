import Foundation

// MARK: - Assessment Mode

enum AssessmentMode {
    case initialOnboarding
    case editExisting
}

// MARK: - Assessment Draft

/// A pure value type holding every answer the assessment flow can edit.
///
/// Never mutates a `UserProfile` directly — all commits go through
/// ``apply(to:resetFocus:)`` so there is a single, reviewable mutation point.
struct AssessmentDraft: Equatable {
    // Profile
    var age: Int
    var weight: Double          // lbs
    var heightFeet: Int
    var heightInches: Int
    var biologicalSex: String

    // Goal
    var primaryGoal: CardioGoal
    var targetEvent: String
    var targetEventDate: Date
    var hasEventDate: Bool

    // Fitness routine
    var fitnessLevel: FitnessLevel
    var weeklyCardioFrequency: Int
    var typicalWorkoutMinutes: Int

    // Preferences
    /// Ordered list of preferred modalities. Order is meaningful: the first
    /// element is the user's primary modality and is what the first workout
    /// recommendation will default to.
    var selectedModalities: [ExerciseType]
    var availableTrainingDays: Int
    var intensityConstraint: IntensityConstraint

    /// Toggle a modality, preserving selection order. First-tapped wins the
    /// primary slot. Returns without change if it would leave zero selected.
    mutating func toggleModality(_ type: ExerciseType) {
        if let index = selectedModalities.firstIndex(of: type) {
            guard selectedModalities.count > 1 else { return }
            selectedModalities.remove(at: index)
        } else {
            selectedModalities.append(type)
        }
    }

    /// The primary (first-selected) modality, or treadmill as a safe fallback.
    var primaryModality: ExerciseType {
        selectedModalities.first ?? .treadmill
    }

    // MARK: - Defaults

    /// A sensible empty draft for brand-new profiles before HealthKit pre-fill.
    static var blank: AssessmentDraft {
        AssessmentDraft(
            age: 31,
            weight: 150,
            heightFeet: 5,
            heightInches: 8,
            biologicalSex: "notSet",
            primaryGoal: .generalFitness,
            targetEvent: "",
            targetEventDate: Date(),
            hasEventDate: false,
            fitnessLevel: .occasional,
            weeklyCardioFrequency: 2,
            typicalWorkoutMinutes: 30,
            selectedModalities: [.treadmill],
            availableTrainingDays: 3,
            intensityConstraint: .none
        )
    }

    // MARK: - Factories

    /// Build a draft pre-filled from an existing profile. Used by edit mode.
    static func from(profile: UserProfile) -> AssessmentDraft {
        let totalInches = Int(profile.height)
        let feet = max(4, min(7, totalInches / 12))
        let inches = max(0, min(11, totalInches % 12))

        let modalities = profile.preferredExerciseTypes
        let safeModalities: [ExerciseType] = modalities.isEmpty ? [.treadmill] : modalities

        return AssessmentDraft(
            age: profile.age,
            weight: profile.weight,
            heightFeet: feet,
            heightInches: inches,
            biologicalSex: profile.biologicalSex,
            primaryGoal: profile.primaryGoal,
            targetEvent: profile.targetEvent ?? "",
            targetEventDate: profile.targetEventDate ?? Date(),
            hasEventDate: profile.targetEventDate != nil,
            fitnessLevel: profile.fitnessLevel,
            weeklyCardioFrequency: profile.weeklyCardioFrequency,
            typicalWorkoutMinutes: profile.typicalWorkoutMinutes,
            selectedModalities: safeModalities,
            availableTrainingDays: profile.availableTrainingDays,
            intensityConstraint: profile.intensityConstraint
        )
    }

    // MARK: - Beginner Gating

    /// Beginners don't have an established cardio routine — hide frequency/duration
    /// inputs and fall back to conservative defaults that the recommendation
    /// engine can still consume.
    var isBeginner: Bool { fitnessLevel == .beginner }

    /// Routine answers that should be persisted. Beginners collapse to sane defaults
    /// so downstream code (effectiveStartingDuration, etc.) keeps working.
    var effectiveWeeklyCardioFrequency: Int {
        isBeginner ? 0 : weeklyCardioFrequency
    }

    var effectiveTypicalWorkoutMinutes: Int {
        isBeginner ? 20 : typicalWorkoutMinutes
    }

    // MARK: - Commit

    /// Single point of mutation back into the profile.
    ///
    /// - Parameter resetFocus: When true, also resets `focus` to the new goal's
    ///   initial focus and sets `phaseStartDate = Date()`. Caller is responsible
    ///   for confirming this with the user in edit mode, since it effectively
    ///   restarts the training arc.
    func apply(to profile: UserProfile, resetFocus: Bool) {
        // Profile
        profile.age = age
        profile.maxHR = 220 - age
        profile.weight = weight
        profile.height = Double(heightFeet * 12 + heightInches)
        profile.biologicalSex = biologicalSex

        // Goal
        profile.primaryGoal = primaryGoal
        if primaryGoal == .raceTraining {
            profile.targetEvent = targetEvent.isEmpty ? nil : targetEvent
            profile.targetEventDate = hasEventDate ? targetEventDate : nil
        } else {
            profile.targetEvent = nil
            profile.targetEventDate = nil
        }

        // Fitness routine
        profile.fitnessLevel = fitnessLevel
        profile.weeklyCardioFrequency = effectiveWeeklyCardioFrequency
        profile.typicalWorkoutMinutes = effectiveTypicalWorkoutMinutes

        // Preferences
        profile.preferredModalities = selectedModalities.map(\.rawValue)
        profile.availableTrainingDays = availableTrainingDays
        profile.intensityConstraint = intensityConstraint

        if resetFocus {
            profile.focus = primaryGoal.initialFocus
            profile.phaseStartDate = Date()
        }
    }
}
