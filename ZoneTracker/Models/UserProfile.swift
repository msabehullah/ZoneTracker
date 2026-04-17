import Foundation
import SwiftData

// MARK: - User Profile

@Model
final class UserProfile {
    var profileIdentifier: String = ""
    var accountIdentifier: String?
    var age: Int = 31
    var maxHR: Int = 189
    var weight: Double = 150       // lbs
    var height: Double = 68        // inches
    var currentPhase: String = TrainingPhase.phase1.rawValue // TrainingPhase rawValue
    var phaseStartDate: Date = Date()
    var hasCompletedOnboarding: Bool = false
    /// True once the user has committed their assessment answers but *before*
    /// they tap "Start Coaching" on the plan-overview handoff. Lets the app
    /// reopen into the plan-overview screen if the user closes the app between
    /// assessment submission and the final handoff, instead of either
    /// restarting the assessment or skipping the handoff entirely.
    var hasSubmittedAssessment: Bool = false
    var zone2TargetLow: Int = 130  // customizable target zone floor
    var zone2TargetHigh: Int = 150 // customizable target zone ceiling
    var legDays: [Int] = []        // weekday indices (1=Sun, 2=Mon, ..., 7=Sat) for heavy leg days
    var biologicalSex: String = "notSet" // "male", "female", "other", "notSet"
    var coachingHapticsEnabled: Bool = true
    var coachingAlertCooldownSeconds: Int = 18

    // Goal-driven fields
    var primaryGoalRaw: String = CardioGoal.generalFitness.rawValue
    var targetEvent: String? = nil
    var targetEventDate: Date? = nil
    var fitnessLevelRaw: String = FitnessLevel.occasional.rawValue
    var weeklyCardioFrequency: Int = 2
    var typicalWorkoutMinutes: Int = 30
    var preferredModalities: [String] = []
    var availableTrainingDays: Int = 3
    var intensityConstraintRaw: String = IntensityConstraint.none.rawValue
    var currentFocusRaw: String = ""

    init(
        profileIdentifier: String = UUID().uuidString,
        accountIdentifier: String? = nil,
        age: Int = 31,
        weight: Double = 150,
        height: Double = 68,
        zone2TargetLow: Int = 130,
        zone2TargetHigh: Int = 150,
        coachingHapticsEnabled: Bool = true,
        coachingAlertCooldownSeconds: Int = 18,
        primaryGoal: CardioGoal = .generalFitness,
        fitnessLevel: FitnessLevel = .occasional
    ) {
        self.profileIdentifier = profileIdentifier
        self.accountIdentifier = accountIdentifier
        self.age = age
        self.maxHR = 220 - age
        self.weight = weight
        self.height = height
        self.currentPhase = TrainingPhase.phase1.rawValue
        self.phaseStartDate = Date()
        self.hasCompletedOnboarding = false
        self.hasSubmittedAssessment = false
        self.zone2TargetLow = zone2TargetLow
        self.zone2TargetHigh = zone2TargetHigh
        self.legDays = []
        self.coachingHapticsEnabled = coachingHapticsEnabled
        self.coachingAlertCooldownSeconds = coachingAlertCooldownSeconds
        self.primaryGoalRaw = primaryGoal.rawValue
        self.fitnessLevelRaw = fitnessLevel.rawValue
        self.currentFocusRaw = primaryGoal.initialFocus.rawValue
    }

    // MARK: - Legacy Phase (internal)

    var phase: TrainingPhase {
        get { TrainingPhase(rawValue: currentPhase) ?? .phase1 }
        set {
            currentPhase = newValue.rawValue
            // Keep focus in sync — if focus doesn't already match this phase,
            // update it to the phase's default focus mapping.
            if focus.mappedPhase != newValue {
                currentFocusRaw = newValue.toFocus.rawValue
            }
        }
    }

    // MARK: - Goal-Driven Computed Properties

    var primaryGoal: CardioGoal {
        get { CardioGoal(rawValue: primaryGoalRaw) ?? .generalFitness }
        set { primaryGoalRaw = newValue.rawValue }
    }

    var fitnessLevel: FitnessLevel {
        get { FitnessLevel(rawValue: fitnessLevelRaw) ?? .occasional }
        set { fitnessLevelRaw = newValue.rawValue }
    }

    var intensityConstraint: IntensityConstraint {
        get { IntensityConstraint(rawValue: intensityConstraintRaw) ?? .none }
        set { intensityConstraintRaw = newValue.rawValue }
    }

    var focus: TrainingFocus {
        get { TrainingFocus(rawValue: currentFocusRaw) ?? phase.toFocus }
        set {
            currentFocusRaw = newValue.rawValue
            currentPhase = newValue.mappedPhase.rawValue
        }
    }

    var weekNumber: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekOfYear], from: phaseStartDate, to: Date())
        return max(1, (components.weekOfYear ?? 0) + 1)
    }

    var zone2Range: ClosedRange<Int> {
        zone2TargetLow...zone2TargetHigh
    }

    var targetZoneRange: ClosedRange<Int> {
        zone2TargetLow...zone2TargetHigh
    }

    var coachingPreferences: CoachingPreferences {
        CoachingPreferences(
            hapticsEnabled: coachingHapticsEnabled,
            outOfRangeCooldown: TimeInterval(coachingAlertCooldownSeconds)
        )
    }

    var daysUntilEvent: Int? {
        guard let eventDate = targetEventDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: eventDate).day ?? 0
        return max(0, days)
    }

    var preferredExerciseTypes: [ExerciseType] {
        preferredModalities.compactMap { ExerciseType(rawValue: $0) }
    }

    // HR zones based on maxHR
    var zone1Ceiling: Int { Int(Double(maxHR) * 0.60) }
    var zone3Ceiling: Int { Int(Double(maxHR) * 0.80) }
    var zone4Ceiling: Int { Int(Double(maxHR) * 0.90) }

    // MARK: - Weekly Target Math
    //
    // The assessment collects two related-but-distinct weekly numbers:
    //
    //   * `weeklyCardioFrequency` — how many cardio sessions the user is
    //     *currently* doing. This is the realistic starting point (baseline).
    //   * `availableTrainingDays` — how many days per week they *could* train.
    //     This is the ceiling the plan ramps toward over time.
    //
    // The plan starts at baseline and earns +1 bumps through demonstrated
    // consistency (see `WeeklyTargetService`). The live, consistency-aware
    // target lives in `WeeklyTargetService.currentTarget(profile:workouts:)`
    // — any consumer that has workout history should call the service.
    //
    // The properties below are the *workout-free* fallback: baseline
    // clamped to ceiling, with no ramp. PlanOverview and ProgramExplanation
    // (which render for a brand-new user with no history) use these. They
    // show the starting value, which is correct at onboarding.
    //
    // `focus` never touches the total — it only shapes composition
    // (target-zone vs interval share).

    /// Current realistic baseline the user told us they're doing. Beginners
    /// hard-code to 2 regardless of `weeklyCardioFrequency` because the
    /// assessment treats them specially (beginner step stores 0 frequency).
    var baselineSessionsPerWeek: Int {
        if fitnessLevel == .beginner { return 2 }
        return max(0, min(7, weeklyCardioFrequency))
    }

    /// How many weeks of consistent training the user needs before earning
    /// an additional +1 session. Experienced and regular users ramp faster;
    /// beginners and return-to-training ramp slowly so volume doesn't
    /// outpace their readiness.
    var weeksPerRampStep: Int {
        if primaryGoal == .returnToTraining { return 4 }
        switch fitnessLevel {
        case .beginner: return 4
        case .occasional: return 3
        case .regular: return 2
        case .experienced: return 2
        }
    }

    /// The absolute ceiling the user said they *could* train — the plan will
    /// never exceed this even as they ramp up. Clamped to [1, 7].
    var availableSessionsCeiling: Int {
        max(1, min(7, availableTrainingDays))
    }

    /// Week-1 / workout-free starting target: baseline clamped to ceiling.
    ///
    /// For the live consistency-aware target that accounts for demonstrated
    /// training history, use `WeeklyTargetService.currentTarget(profile:workouts:)`.
    /// This property exists for contexts without workout data (onboarding,
    /// PlanOverview, ProgramExplanation for new users).
    var effectiveSessionsPerWeek: Int {
        max(1, min(availableSessionsCeiling, baselineSessionsPerWeek))
    }

    /// True when the ceiling exceeds the starting target — UI uses this to
    /// show the "building toward N days/week" line at onboarding.
    var hasHeadroomToBuild: Bool {
        availableSessionsCeiling > effectiveSessionsPerWeek
    }

    /// Number of interval days per week based on the starting target.
    /// For the live split, use `WeeklyTargetService.intervalSessions(total:profile:)`.
    var effectiveIntervalSessions: Int {
        WeeklyTargetService.intervalSessions(
            total: effectiveSessionsPerWeek, profile: self
        )
    }

    /// Remaining sessions after intervals — complement of interval count.
    var effectiveTargetZoneSessions: Int {
        max(0, effectiveSessionsPerWeek - effectiveIntervalSessions)
    }

    /// Duration for first workout, influenced by fitness level and typical workout minutes.
    var effectiveStartingDuration: TimeInterval {
        // Use their stated typical duration, but cap by fitness level
        let typicalSeconds = TimeInterval(typicalWorkoutMinutes) * 60
        let maxForLevel: TimeInterval
        switch fitnessLevel {
        case .beginner: maxForLevel = 30 * 60
        case .occasional: maxForLevel = 45 * 60
        case .regular: maxForLevel = 60 * 60
        case .experienced: maxForLevel = 90 * 60
        }
        return min(typicalSeconds, maxForLevel)
    }

    /// Whether to prefer low-impact exercise types in recommendations.
    var prefersLowImpact: Bool {
        intensityConstraint == .lowImpactPreferred
    }

    func advanceFocus() {
        guard let nextFocus = focus.next else { return }
        self.focus = nextFocus
        self.phaseStartDate = Date()
    }

    func advancePhase() {
        guard let next = phase.next else { return }
        self.phase = next
        self.phaseStartDate = Date()
    }

    func isLegDay(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return legDays.contains(weekday)
    }

    func isAdjacentToLegDay(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: date)!
        return isLegDay(dayBefore)
    }

    func shouldAvoidHighIntensity(on date: Date) -> Bool {
        if intensityConstraint == .avoidHighIntensity { return true }
        return isLegDay(date) || isAdjacentToLegDay(date)
    }
}
