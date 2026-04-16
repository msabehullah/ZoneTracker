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
    // The plan starts at the user's baseline and earns +1 session every
    // `weeksPerRampStep` weeks, up to the ceiling. The ramp speed depends
    // on fitness level (experienced/regular ramp every 2 weeks; occasional
    // every 3; beginner/return-to-training every 4). Week 1 always starts
    // at baseline — no instant jump.
    //
    // `weekNumber` (weeks since `phaseStartDate`) drives the ramp. Since
    // `phaseStartDate` resets on focus transitions, the ramp restarts
    // naturally when the user enters a new training phase. Consistency
    // gating happens at the recommendation layer: when
    // `PhaseManager.missedSessionsLastWeek` fires, the engine falls back
    // to "repeat last week," preventing the user from being pushed toward
    // a ramped target they haven't been hitting.
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

    /// How many +1 bumps the plan has earned based on time in the current
    /// focus. Week 1 earns 0 bumps. Each `weeksPerRampStep` weeks after
    /// that earns another +1, up to however many are needed to reach the
    /// ceiling. Since `weekNumber` resets when focus transitions fire (via
    /// `phaseStartDate`), the ramp restarts naturally after phase changes.
    var earnedRampBumps: Int {
        max(0, (weekNumber - 1) / weeksPerRampStep)
    }

    /// The absolute ceiling the user said they *could* train — the plan will
    /// never exceed this even as they ramp up. Clamped to [1, 7].
    var availableSessionsCeiling: Int {
        max(1, min(7, availableTrainingDays))
    }

    /// The plan's actual current weekly target: baseline + time-earned
    /// bumps, capped by the user's stated ceiling, never below one.
    ///
    /// The ramp is deterministic from `weekNumber` (weeks since
    /// `phaseStartDate`). Consistency gating happens at the recommendation
    /// layer: `PhaseManager.missedSessionsLastWeek` triggers a "repeat
    /// last week" fallback that prevents the user from experiencing ramped
    /// volume when they haven't been showing up. The plan *target* still
    /// grows — the engine just doesn't push them to hit it until they've
    /// been consistent again.
    var currentPlannedSessionsPerWeek: Int {
        let target = baselineSessionsPerWeek + earnedRampBumps
        return max(1, min(availableSessionsCeiling, target))
    }

    /// Authoritative weekly session target used everywhere downstream
    /// (Dashboard, Progress, PlanOverview, ProgramExplanation). Reads the
    /// current planned target so users aren't shown their ceiling as if it
    /// were a commitment.
    var effectiveSessionsPerWeek: Int {
        currentPlannedSessionsPerWeek
    }

    /// True when the plan hasn't maxed out the user's stated capacity yet —
    /// UI uses this to show the "building toward N days/week" line so the
    /// ceiling they selected doesn't feel ignored.
    var hasHeadroomToBuild: Bool {
        availableSessionsCeiling > currentPlannedSessionsPerWeek
    }

    /// Number of interval days per week. Composition is focus-driven (base
    /// focus stays all target-zone; intervals ramp up through developing-speed
    /// and peak). Caps keep the interval share sane even at 7 training days so
    /// we don't flip the week majority-hard. Respects `.avoidHighIntensity`.
    var effectiveIntervalSessions: Int {
        if intensityConstraint == .avoidHighIntensity { return 0 }
        let total = effectiveSessionsPerWeek
        switch focus {
        case .buildingBase, .activeRecovery:
            return 0
        case .developingSpeed:
            // Roughly one interval per three sessions, capped at 2.
            return min(2, total / 3)
        case .peakPerformance:
            // Roughly one interval per two sessions, capped at 3.
            return min(3, total / 2)
        }
    }

    /// Remaining sessions after intervals are allocated become target-zone
    /// days. Always computed as a complement so the two always sum to total.
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
