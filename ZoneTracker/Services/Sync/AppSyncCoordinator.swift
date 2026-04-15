import CloudKit
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppSyncCoordinator {
    static let shared = AppSyncCoordinator()

    var lastSyncDate: Date?
    var lastSyncError: String?

    private init() {}

    private static var isCloudSyncAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    func synchronizeIfPossible(
        accountStore: AccountStore,
        profile: UserProfile?,
        workouts: [WorkoutEntry],
        context: ModelContext
    ) {
        guard Self.isCloudSyncAvailable else {
            backfillIdentity(
                profile: profile,
                workouts: workouts,
                accountIdentifier: accountStore.appleUserID
            )
            lastSyncError = "Cloud backup is only available on a physical device."
            return
        }

        guard let accountIdentifier = accountStore.appleUserID,
              accountStore.isSignedIn else {
            return
        }

        Task {
            await performSynchronization(
                accountIdentifier: accountIdentifier,
                profile: profile,
                workouts: workouts,
                context: context
            )
        }
    }

    func backfillIdentity(
        profile: UserProfile?,
        workouts: [WorkoutEntry],
        accountIdentifier: String?
    ) {
        if let profile {
            if profile.profileIdentifier.isEmpty {
                profile.profileIdentifier = UUID().uuidString
            }
            if profile.accountIdentifier != accountIdentifier {
                profile.accountIdentifier = accountIdentifier
            }
        }

        for workout in workouts {
            if workout.accountIdentifier != accountIdentifier {
                workout.accountIdentifier = accountIdentifier
            }
            if workout.sourceRaw.isEmpty {
                workout.source = .manualEntry
            }
        }
    }

    private func performSynchronization(
        accountIdentifier: String,
        profile: UserProfile?,
        workouts: [WorkoutEntry],
        context: ModelContext
    ) async {
        backfillIdentity(profile: profile, workouts: workouts, accountIdentifier: accountIdentifier)

        do {
            let remoteProfile = try await CloudSyncService.shared.fetchProfile(accountIdentifier: accountIdentifier)
            let remoteWorkouts = try await CloudSyncService.shared.fetchWorkouts(accountIdentifier: accountIdentifier)

            merge(remoteProfile: remoteProfile, remoteWorkouts: remoteWorkouts, localProfile: profile, localWorkouts: workouts, accountIdentifier: accountIdentifier, context: context)

            if let profile {
                try await CloudSyncService.shared.save(
                    profile: CloudProfileSnapshot.from(profile: profile, accountIdentifier: accountIdentifier)
                )
            }

            let workoutSnapshots = workouts.map {
                CloudWorkoutSnapshot.from(workout: $0, accountIdentifier: accountIdentifier)
            }
            try await CloudSyncService.shared.save(workouts: workoutSnapshots)

            lastSyncDate = Date()
            lastSyncError = nil
        } catch {
            // Log full raw detail for debugging; surface a friendly message
            // to the UI instead of the raw CloudKit text
            // ("did not find record type: ZTProfile", etc.) which users can't
            // act on and makes the app feel broken.
            print("CloudKit sync failed: \(error)")
            lastSyncError = CloudSyncErrorFormatter.friendlyMessage(for: error)
        }
    }

    private func merge(
        remoteProfile: CloudProfileSnapshot?,
        remoteWorkouts: [CloudWorkoutSnapshot],
        localProfile: UserProfile?,
        localWorkouts: [WorkoutEntry],
        accountIdentifier: String,
        context: ModelContext
    ) {
        if let remoteProfile {
            if let localProfile {
                if !localProfile.hasCompletedOnboarding && remoteProfile.hasCompletedOnboarding {
                    apply(remoteProfile: remoteProfile, to: localProfile)
                } else {
                    localProfile.accountIdentifier = accountIdentifier
                }
            } else {
                context.insert(makeProfile(from: remoteProfile))
            }
        }

        let existingWorkoutIDs = Set(localWorkouts.map(\.id))
        for snapshot in remoteWorkouts where !existingWorkoutIDs.contains(snapshot.workoutIdentifier) {
            context.insert(makeWorkout(from: snapshot))
        }
    }

    private func apply(remoteProfile: CloudProfileSnapshot, to profile: UserProfile) {
        profile.profileIdentifier = remoteProfile.profileIdentifier
        profile.accountIdentifier = remoteProfile.accountIdentifier
        profile.age = remoteProfile.age
        profile.maxHR = remoteProfile.maxHeartRate
        profile.weight = remoteProfile.weight
        profile.height = remoteProfile.height
        profile.phaseStartDate = remoteProfile.phaseStartDate
        profile.hasCompletedOnboarding = remoteProfile.hasCompletedOnboarding
        profile.zone2TargetLow = remoteProfile.zone2Low
        profile.zone2TargetHigh = remoteProfile.zone2High
        profile.legDays = remoteProfile.legDays
        profile.coachingHapticsEnabled = remoteProfile.coachingHapticsEnabled
        profile.coachingAlertCooldownSeconds = remoteProfile.coachingAlertCooldownSeconds
        profile.primaryGoalRaw = remoteProfile.primaryGoalRaw
        profile.targetEvent = remoteProfile.targetEvent
        profile.targetEventDate = remoteProfile.targetEventDate
        profile.fitnessLevelRaw = remoteProfile.fitnessLevelRaw
        profile.weeklyCardioFrequency = remoteProfile.weeklyCardioFrequency
        profile.typicalWorkoutMinutes = remoteProfile.typicalWorkoutMinutes
        profile.preferredModalities = remoteProfile.preferredModalities
        profile.availableTrainingDays = remoteProfile.availableTrainingDays
        profile.intensityConstraintRaw = remoteProfile.intensityConstraintRaw
        // Set currentFocusRaw first, then currentPhase — the phase setter
        // only overwrites focusRaw when they don't match, so this preserves
        // the exact focus (e.g. activeRecovery) from the remote record.
        profile.currentFocusRaw = remoteProfile.currentFocusRaw
        profile.currentPhase = remoteProfile.currentPhase
    }

    private func makeProfile(from snapshot: CloudProfileSnapshot) -> UserProfile {
        let profile = UserProfile(
            profileIdentifier: snapshot.profileIdentifier,
            accountIdentifier: snapshot.accountIdentifier,
            age: snapshot.age,
            weight: snapshot.weight,
            height: snapshot.height,
            zone2TargetLow: snapshot.zone2Low,
            zone2TargetHigh: snapshot.zone2High,
            coachingHapticsEnabled: snapshot.coachingHapticsEnabled,
            coachingAlertCooldownSeconds: snapshot.coachingAlertCooldownSeconds
        )
        profile.maxHR = snapshot.maxHeartRate
        profile.phaseStartDate = snapshot.phaseStartDate
        profile.hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        profile.legDays = snapshot.legDays
        profile.primaryGoalRaw = snapshot.primaryGoalRaw
        profile.targetEvent = snapshot.targetEvent
        profile.targetEventDate = snapshot.targetEventDate
        profile.fitnessLevelRaw = snapshot.fitnessLevelRaw
        profile.weeklyCardioFrequency = snapshot.weeklyCardioFrequency
        profile.typicalWorkoutMinutes = snapshot.typicalWorkoutMinutes
        profile.preferredModalities = snapshot.preferredModalities
        profile.availableTrainingDays = snapshot.availableTrainingDays
        profile.intensityConstraintRaw = snapshot.intensityConstraintRaw
        profile.currentFocusRaw = snapshot.currentFocusRaw
        profile.currentPhase = snapshot.currentPhase
        return profile
    }

    private func makeWorkout(from snapshot: CloudWorkoutSnapshot) -> WorkoutEntry {
        let focus = TrainingFocus(rawValue: snapshot.focusRaw)
        let entry = WorkoutEntry(
            accountIdentifier: snapshot.accountIdentifier,
            completionIdentifier: snapshot.completionIdentifier,
            planIdentifier: snapshot.planIdentifier,
            recommendationIdentifier: snapshot.recommendationIdentifier,
            source: WorkoutSource(rawValue: snapshot.sourceRaw) ?? .cloudImport,
            date: snapshot.date,
            exerciseType: ExerciseType(rawValue: snapshot.exerciseTypeRaw) ?? .treadmill,
            duration: snapshot.duration,
            metrics: [:],
            sessionType: SessionType(rawValue: snapshot.sessionTypeRaw) ?? .zone2,
            heartRateData: .empty,
            phase: TrainingPhase(rawValue: snapshot.phaseRaw) ?? .phase1,
            focus: focus,
            weekNumber: snapshot.weekNumber,
            rpe: snapshot.rpe,
            notes: snapshot.notes,
            intervalProtocol: nil
        )
        entry.id = snapshot.workoutIdentifier
        entry.metricsData = snapshot.metricsData
        entry.heartRateDataEncoded = snapshot.heartRateDataEncoded
        entry.intervalProtocolData = snapshot.intervalProtocolData
        return entry
    }
}
