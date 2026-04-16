import Foundation

// MARK: - Onboarding Committer

/// Small, explicit helper that owns the two write-and-persist steps of
/// onboarding. Extracted out of `OnboardingView` so the save path is testable
/// without building a throwing `ModelContext`, and so the in-memory rollback
/// behavior on save failure is centralized and provable.
///
/// The committer never decides *what* to say to the user or *where* to go
/// next — that's the view's job. Its contract is narrow:
///
/// 1. Flip the relevant profile flags forward.
/// 2. Call `save`.
/// 3. If `save` throws, roll the flag back so the in-memory profile matches
///    what's actually on disk, then rethrow.
///
/// Callers observe success by "did not throw" and failure by a thrown error.
enum OnboardingCommitter {

    /// Commit the assessment draft into `profile` and persist. Sets
    /// `hasSubmittedAssessment = true` on success; rolls it back to `false`
    /// on save failure so the app's resume-on-plan-overview routing stays
    /// honest.
    static func commitAssessment(
        draft: AssessmentDraft,
        profile: UserProfile,
        accountIdentifier: String?,
        save: () throws -> Void
    ) throws {
        draft.apply(to: profile, resetFocus: true)
        profile.hasSubmittedAssessment = true
        profile.accountIdentifier = accountIdentifier

        do {
            try save()
        } catch {
            // Roll back the flag so the state machine still matches on-disk
            // state. Draft-applied fields remain on the in-memory profile so
            // the user can retry without re-answering; the next successful
            // save will persist everything together.
            profile.hasSubmittedAssessment = false
            throw error
        }
    }

    /// Mark onboarding complete and persist. Rolls `hasCompletedOnboarding`
    /// back to `false` on save failure so a cold relaunch doesn't skip past
    /// onboarding based on a flag that never made it to disk.
    static func finalizeOnboarding(
        profile: UserProfile,
        save: () throws -> Void
    ) throws {
        profile.hasCompletedOnboarding = true
        do {
            try save()
        } catch {
            profile.hasCompletedOnboarding = false
            throw error
        }
    }
}
