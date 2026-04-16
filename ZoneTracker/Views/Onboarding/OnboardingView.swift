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
    /// Set when a `context.save()` during onboarding fails. Surfaces as an
    /// alert so the user knows to retry and the view stays on the current
    /// step instead of silently advancing past a dropped save.
    @State private var saveError: String?

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
        content
            .alert(
                "Couldn't save",
                isPresented: saveErrorBinding,
                actions: {
                    Button("OK", role: .cancel) { saveError = nil }
                },
                message: {
                    if let saveError { Text(saveError) }
                }
            )
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .assessment:
            AssessmentFlowView(
                draft: $draft,
                mode: .initialOnboarding
            ) { resetFocus in
                // Only advance when the assessment commit actually persisted.
                // Otherwise we'd present the plan overview on top of a profile
                // that still looks un-submitted on cold relaunch.
                if commitInitial(resetFocus: resetFocus) {
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .planOverview }
                }
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

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    /// Commit assessment answers to the profile and persist the intermediate
    /// `hasSubmittedAssessment` flag. Returns `true` only on successful save;
    /// callers should gate their "advance to next phase" transition on this.
    ///
    /// On failure we roll the in-memory flag back so the state machine remains
    /// honest — the user didn't actually submit if we couldn't persist — and
    /// surface an alert so they know to retry.
    private func commitInitial(resetFocus: Bool) -> Bool {
        // Delegate the flag-flip + rollback logic to OnboardingCommitter so it
        // is unit-testable without a throwing ModelContext.
        do {
            try OnboardingCommitter.commitAssessment(
                draft: draft,
                profile: profile,
                accountIdentifier: AccountStore.shared.appleUserID,
                save: { try context.save() }
            )
        } catch {
            saveError = "We couldn't save your answers. Please try again."
            print("Onboarding commit failed to save: \(error)")
            return false
        }

        saveError = nil
        Task {
            try? await HealthKitManager.shared.requestAuthorization()
        }
        return true
    }

    /// Final completion — Start Coaching. Only calls `onComplete()` when the
    /// completion flag actually persisted, otherwise the app would route the
    /// user into `ContentView` even though a cold relaunch would drop them
    /// back into onboarding.
    private func finishOnboarding() {
        do {
            try OnboardingCommitter.finalizeOnboarding(
                profile: profile,
                save: { try context.save() }
            )
        } catch {
            saveError = "We couldn't finish setting up your plan. Please try again."
            print("Onboarding finalize failed to save: \(error)")
            return
        }
        saveError = nil
        onComplete()
    }
}
