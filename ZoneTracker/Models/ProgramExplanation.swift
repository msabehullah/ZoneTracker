import Foundation

// MARK: - Program Explanation
//
// Builds a structured, plain-language explanation of the user's overall program
// from their profile + first workout recommendation. Designed to drive the
// post-assessment plan handoff screen — it answers "what am I actually doing,
// and why" without leaking jargon or implementation detail.
//
// The model is pure data so it stays trivially testable and can be regenerated
// any time the profile changes. Copy decisions live here, not in the view.

struct ProgramExplanation: Equatable {

    // MARK: Section

    struct Section: Equatable, Identifiable {
        let id: String
        let icon: String
        let title: String
        let body: String
        /// Optional bulleted highlights shown beneath the body.
        let bullets: [String]
    }

    // MARK: Properties

    let headline: String
    let subhead: String
    let sections: [Section]

    // MARK: Build

    /// Build the explanation from a profile and the recommended first workout.
    /// Pass the recommendation explicitly so the explanation matches exactly
    /// what the user is about to see queued up — no double-derivation.
    static func build(
        profile: UserProfile,
        firstWorkout: WorkoutRecommendation
    ) -> ProgramExplanation {
        let shape = FirstWorkoutStrategy.decideShape(for: profile)

        return ProgramExplanation(
            headline: makeHeadline(for: profile),
            subhead: makeSubhead(for: profile),
            sections: [
                goalSection(profile: profile),
                weeklyStructureSection(profile: profile, firstWorkout: firstWorkout),
                firstWorkoutSection(profile: profile, firstWorkout: firstWorkout, shape: shape),
                progressionSection(profile: profile),
                watchCoachingSection(profile: profile)
            ]
        )
    }

    // MARK: - Headline / Subhead

    private static func makeHeadline(for profile: UserProfile) -> String {
        switch profile.primaryGoal {
        case .aerobicBase: return "Your aerobic base plan"
        case .peakCardio: return "Your peak cardio plan"
        case .raceTraining:
            if let event = profile.targetEvent, !event.isEmpty {
                return "Your \(event) training plan"
            }
            return "Your race training plan"
        case .returnToTraining: return "Your comeback plan"
        case .generalFitness: return "Your cardio fitness plan"
        }
    }

    private static func makeSubhead(for profile: UserProfile) -> String {
        let goalLine: String
        switch profile.primaryGoal {
        case .aerobicBase:
            goalLine = "We'll build a deep aerobic engine you can stack everything else on top of."
        case .peakCardio:
            goalLine = "We'll grow your aerobic base first, then layer in the harder work that lifts your ceiling."
        case .raceTraining:
            if let days = profile.daysUntilEvent, days > 0 {
                goalLine = "\(days) days out — we'll build aerobic capacity, then sharpen race-specific fitness."
            } else {
                goalLine = "We'll structure your weeks so race-day fitness arrives on schedule."
            }
        case .returnToTraining:
            goalLine = "We'll rebuild consistency first, then carefully layer intensity back in."
        case .generalFitness:
            goalLine = "We'll keep cardio steady and sustainable so it actually sticks."
        }
        return goalLine
    }

    // MARK: - Goal Section

    private static func goalSection(profile: UserProfile) -> Section {
        let levelLine: String
        switch profile.fitnessLevel {
        case .beginner:
            levelLine = "Because you're new to structured cardio, the first few weeks stay easy and confidence-building."
        case .occasional:
            levelLine = "You've got a casual cardio base, so we start from a sustainable rhythm — no shock to the system."
        case .regular:
            levelLine = "You already train consistently, so we can move past the basics quickly."
        case .experienced:
            levelLine = "You know your zones, so we can be more aggressive with structure from day one."
        }

        var bullets: [String] = []
        bullets.append("Goal — \(profile.primaryGoal.shortName)")
        bullets.append("Current focus — \(profile.focus.displayName)")
        if profile.intensityConstraint != .none {
            bullets.append("Constraint — \(profile.intensityConstraint.displayName)")
        }

        return Section(
            id: "goal",
            icon: profile.primaryGoal.icon,
            title: "What you're training for",
            body: "\(profile.primaryGoal.tagline). \(levelLine)",
            bullets: bullets
        )
    }

    // MARK: - Weekly Structure Section

    private static func weeklyStructureSection(
        profile: UserProfile,
        firstWorkout: WorkoutRecommendation
    ) -> Section {
        let sessions = profile.effectiveSessionsPerWeek
        let zoneSessions = profile.effectiveTargetZoneSessions
        let intervalSessions = profile.effectiveIntervalSessions

        let intro: String
        if intervalSessions == 0 {
            intro = "We'll aim for \(sessions) cardio sessions a week, all in your target heart-rate zone. Easy intensity, real volume."
        } else {
            intro = "We'll aim for \(sessions) cardio sessions a week — the bulk in your target zone, with \(intervalSessions) harder day\(intervalSessions == 1 ? "" : "s") to push your ceiling."
        }

        let zoneLine = "Target zone: \(profile.zone2TargetLow)–\(profile.zone2TargetHigh) bpm. That's the sweet spot where you're working but could still hold a conversation."

        var bullets: [String] = []
        bullets.append("\(sessions) sessions a week")
        bullets.append("\(zoneSessions) target-zone day\(zoneSessions == 1 ? "" : "s")")
        if intervalSessions > 0 {
            bullets.append("\(intervalSessions) interval day\(intervalSessions == 1 ? "" : "s")")
        } else if profile.intensityConstraint == .avoidHighIntensity {
            bullets.append("No high-intensity work — by your request")
        } else {
            bullets.append("No intervals yet — base first")
        }

        return Section(
            id: "weeklyStructure",
            icon: "calendar",
            title: "How a week looks",
            body: "\(intro) \(zoneLine)",
            bullets: bullets
        )
    }

    // MARK: - First Workout Section

    private static func firstWorkoutSection(
        profile: UserProfile,
        firstWorkout: WorkoutRecommendation,
        shape: FirstWorkoutStrategy.Shape
    ) -> Section {
        let modalityName = firstWorkout.exerciseType.displayName
        let minutes = firstWorkout.targetDurationMinutes

        let body: String
        switch shape {
        case .easyTargetZoneIntro:
            body = "A short \(minutes)-minute \(modalityName.lowercased()) session in your target zone. The goal is just to get one in — comfort, not effort."
        case .returnToTargetZone:
            body = "A gentle \(minutes)-minute \(modalityName.lowercased()) session in your target zone. We're rebuilding the habit before we rebuild the fitness."
        case .targetZoneBaseline:
            body = "A \(minutes)-minute \(modalityName.lowercased()) session in your target zone. This becomes your weekly anchor."
        case .aerobicSupport:
            body = "A longer \(minutes)-minute aerobic \(modalityName.lowercased()) session in your target zone. Race fitness sits on top of this kind of work."
        case .intervalIntro:
            body = "A short \(modalityName.lowercased()) interval intro: 4 rounds of 30 seconds hard / 30 seconds easy after a 10-minute warmup. Calibrates what \"hard\" actually feels like."
        case .benchmarkAssessment:
            body = "A mile benchmark — warmup, one all-out mile, cooldown. Gives us a clean baseline to build race-specific work from."
        case .tempoStarter:
            body = "A \(minutes)-minute \(modalityName.lowercased()) session with a short tempo block. We'll extend the tempo once we see how your legs respond."
        }

        var bullets: [String] = []
        bullets.append("\(minutes) minutes")
        bullets.append(modalityName)
        if firstWorkout.intervalProtocol != nil {
            bullets.append("Intervals included")
        } else {
            bullets.append("Steady target zone")
        }

        return Section(
            id: "firstWorkout",
            icon: "play.circle.fill",
            title: "Your first workout",
            body: body,
            bullets: bullets
        )
    }

    // MARK: - Progression Section

    private static func progressionSection(profile: UserProfile) -> Section {
        let body: String
        switch profile.primaryGoal {
        case .aerobicBase, .generalFitness:
            body = "We extend your target-zone sessions before adding intensity. Once you've stacked a few consistent weeks, durations grow first; harder days come later."
        case .peakCardio:
            switch profile.fitnessLevel {
            case .beginner, .occasional:
                body = "Aerobic base first, then intervals. We won't rush the harder work — it lands better when the foundation is in place."
            case .regular, .experienced:
                body = "Intervals are part of the plan from early on. We progress by adding rounds and extending work intervals as you adapt."
            }
        case .raceTraining:
            if let days = profile.daysUntilEvent {
                if days <= 28 {
                    body = "With your event close, we keep volume moderate and sharpen with race-pace work. The plan respects taper time before race day."
                } else {
                    body = "We build aerobic volume now, then layer in race-specific intensity as the event gets closer. Closer to race day, we'll taper to keep you fresh."
                }
            } else {
                body = "We build aerobic capacity first, then layer in race-specific intensity as you get closer to your event."
            }
        case .returnToTraining:
            body = "Consistency before intensity. Once you've strung together steady weeks, we'll start to bring back the harder work — but no sooner."
        }

        let nextFocus = profile.focus.next?.displayName
        var bullets: [String] = []
        bullets.append("Currently — \(profile.focus.displayName)")
        if let nextFocus {
            bullets.append("Next up — \(nextFocus)")
        }

        return Section(
            id: "progression",
            icon: "chart.line.uptrend.xyaxis",
            title: "How it progresses",
            body: body,
            bullets: bullets
        )
    }

    // MARK: - Watch Coaching Section

    private static func watchCoachingSection(profile: UserProfile) -> Section {
        let hapticsLine = profile.coachingHapticsEnabled
            ? "Your watch nudges with a haptic when you drift out of your target zone, so you can stay heads-up."
            : "Glance at your watch for live zone status — haptic alerts are off in your settings."

        let body = "On your wrist you'll see live heart rate, current zone, and a coaching cue telling you whether to push, ease up, or hold steady. \(hapticsLine)"

        var bullets: [String] = []
        bullets.append("Live HR + zone")
        bullets.append("Push / ease-up coaching")
        bullets.append(profile.coachingHapticsEnabled ? "Haptic alerts on" : "Haptic alerts off")

        return Section(
            id: "watchCoaching",
            icon: "applewatch.radiowaves.left.and.right",
            title: "How the watch coaches you",
            body: body,
            bullets: bullets
        )
    }
}
