import Foundation

// MARK: - Weekly Target Service
//
// Single source of truth for the user's current weekly session target.
// The target starts at baseline (`weeklyCardioFrequency`) and earns +1
// bumps through demonstrated consistency — not by calendar time alone.
//
// Algorithm: walk completed weeks since `phaseStartDate` forward. Each
// week where the user met at least half the then-current target (min 1)
// counts as "consistent." Every `weeksPerRampStep` consistent weeks
// earns a +1 bump. Inconsistent weeks simply don't count — they pause
// growth but don't reset it.
//
// Consumers with workout history (Dashboard, Progress, Recommendations,
// PhaseManager) call through this service. Consumers without history
// (PlanOverview, ProgramExplanation at onboarding) use the profile-only
// `effectiveSessionsPerWeek` which returns baseline — correct for a new
// user with no completed weeks.

struct WeeklyTargetService {

    // MARK: - Earned Bumps

    /// Count +1 bumps earned through consistency in completed weeks
    /// between `phaseStartDate` and `upTo`. The week containing `upTo`
    /// is excluded — only fully completed weeks contribute.
    ///
    /// The target for each week depends on bumps earned in prior weeks,
    /// so this is a forward-scan: week 1's target = baseline, and each
    /// subsequent week's target reflects cumulative consistency.
    static func earnedBumps(
        profile: UserProfile,
        workouts: [WorkoutEntry],
        upTo: Date = Date()
    ) -> Int {
        let baseline = profile.baselineSessionsPerWeek
        let ceiling = profile.availableSessionsCeiling
        let step = profile.weeksPerRampStep
        guard step > 0 else { return 0 }
        let calendar = Calendar.current

        var weekStart = profile.phaseStartDate.startOfWeek
        let stopWeekStart = upTo.startOfWeek
        var consistentWeeks = 0

        while weekStart < stopWeekStart {
            let weekEnd = calendar.date(
                byAdding: .weekOfYear, value: 1, to: weekStart
            )!

            // Target for this week is based on bumps earned so far
            let bumps = consistentWeeks / step
            let weekTarget = max(1, min(ceiling, baseline + bumps))

            // Consistent if completed >= half the target (floor 1)
            let threshold = max(1, Int(ceil(Double(weekTarget) * 0.5)))

            let sessions = workouts.filter {
                $0.date >= weekStart && $0.date < weekEnd
            }.count

            if sessions >= threshold {
                consistentWeeks += 1
            }

            weekStart = weekEnd
        }

        return consistentWeeks / step
    }

    // MARK: - Current Target

    /// The plan's weekly session target as of a given date: baseline +
    /// consistency-earned bumps, clamped to [1, ceiling]. When `asOf` is
    /// omitted (default = now), this returns the current week's target —
    /// the single source of truth for downstream display and logic.
    ///
    /// Pass an earlier date to get the target that was in effect during
    /// that week. For example, passing the start of last week returns the
    /// target last week was judged against — which may differ from the
    /// current target if last week's consistency earned a new bump.
    static func currentTarget(
        profile: UserProfile,
        workouts: [WorkoutEntry],
        asOf date: Date = Date()
    ) -> Int {
        let bumps = earnedBumps(profile: profile, workouts: workouts, upTo: date)
        return max(
            1,
            min(
                profile.availableSessionsCeiling,
                profile.baselineSessionsPerWeek + bumps
            )
        )
    }

    // MARK: - Composition

    /// Interval session count for a given total, respecting focus and
    /// intensity constraints. Mirrors the focus-driven split from the
    /// profile but accepts an explicit total so it stays in sync with
    /// the consistency-aware target.
    static func intervalSessions(
        total: Int,
        profile: UserProfile
    ) -> Int {
        if profile.intensityConstraint == .avoidHighIntensity { return 0 }
        switch profile.focus {
        case .buildingBase, .activeRecovery:
            return 0
        case .developingSpeed:
            return min(2, total / 3)
        case .peakPerformance:
            return min(3, total / 2)
        }
    }

    /// Target-zone sessions: complement of intervals, always >= 0.
    static func targetZoneSessions(
        total: Int,
        profile: UserProfile
    ) -> Int {
        max(0, total - intervalSessions(total: total, profile: profile))
    }

    /// Whether the plan has room to grow toward the ceiling.
    static func hasHeadroomToBuild(
        currentTarget: Int,
        ceiling: Int
    ) -> Bool {
        ceiling > currentTarget
    }
}
