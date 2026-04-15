import SwiftUI
import SwiftData

// MARK: - Onboarding View

/// Thin wrapper around ``AssessmentFlowView`` that:
/// 1. Holds the initial assessment draft for a first-time user.
/// 2. Commits the draft to the profile, then shows ``PlanOverviewView``.
/// 3. Calls `onComplete` once the user taps "Start Coaching".
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: UserProfile
    var onComplete: () -> Void

    @State private var draft: AssessmentDraft
    @State private var phase: Phase

    private enum Phase {
        case assessment
        case planOverview
    }

    init(profile: UserProfile, onComplete: @escaping () -> Void) {
        self.profile = profile
        self.onComplete = onComplete
        // Resume where the user left off. If the assessment was already
        // submitted but "Start Coaching" wasn't tapped, reopen the plan
        // overview rather than making them redo the assessment.
        _phase = State(initialValue: profile.hasSubmittedAssessment ? .planOverview : .assessment)
        _draft = State(initialValue: profile.hasSubmittedAssessment
                       ? AssessmentDraft.from(profile: profile)
                       : .blank)
    }

    var body: some View {
        switch phase {
        case .assessment:
            AssessmentFlowView(
                draft: $draft,
                mode: .initialOnboarding
            ) { resetFocus in
                commitInitial(resetFocus: resetFocus)
                withAnimation(.easeInOut(duration: 0.3)) { phase = .planOverview }
            }

        case .planOverview:
            PlanOverviewView(
                profile: profile,
                onStartCoaching: finishOnboarding,
                onEdit: {
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .assessment }
                }
            )
        }
    }

    private func commitInitial(resetFocus: Bool) {
        // For initial onboarding we always reset focus to the goal's initial focus.
        draft.apply(to: profile, resetFocus: true)
        // Intermediate state: answers are saved, but the user hasn't tapped
        // "Start Coaching" yet. If the app is killed on the plan overview,
        // the next launch returns here instead of either restarting the
        // assessment or jumping past the handoff.
        profile.hasSubmittedAssessment = true
        profile.accountIdentifier = AccountStore.shared.appleUserID

        // Explicitly persist — autosave was racing with app termination
        // and dropping the assessment commit on cold relaunch.
        do {
            try context.save()
        } catch {
            print("Onboarding commit failed to save: \(error)")
        }

        Task {
            try? await HealthKitManager.shared.requestAuthorization()
        }
    }

    private func finishOnboarding() {
        // Start Coaching is the actual completion moment — mark onboarding
        // complete here and persist before handing control to the parent.
        profile.hasCompletedOnboarding = true
        do {
            try context.save()
        } catch {
            print("Onboarding finalize failed to save: \(error)")
        }
        onComplete()
    }
}
