import SwiftUI
import SwiftData

// MARK: - App Entry Point

@main
struct ZoneTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(for: [WorkoutEntry.self, UserProfile.self])
    }
}

// MARK: - App Root View

/// Decides whether to show Onboarding or the main tab interface.
struct AppRootView: View {
    @State private var accountStore = AccountStore.shared
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]
    @Environment(\.modelContext) private var context
    @State private var createdProfile: UserProfile?

    private var activeProfile: UserProfile? {
        profiles.first ?? createdProfile
    }

    var body: some View {
        Group {
            switch accountStore.sessionState {
            case .loading:
                Color.appBackground
                    .overlay {
                        ProgressView()
                            .tint(.zone2Green)
                    }
                    .ignoresSafeArea()

            case .signedOut:
                SignInView()

            case .signedIn:
                if let profile = activeProfile {
                    if profile.hasCompletedOnboarding {
                        ContentView(profile: profile)
                    } else {
                        OnboardingView(profile: profile) {
                            AppSyncCoordinator.shared.synchronizeIfPossible(
                                accountStore: accountStore,
                                profile: profile,
                                workouts: workouts,
                                context: context
                            )
                        }
                    }
                } else {
                    Color.appBackground
                        .ignoresSafeArea()
                        .task { createProfileIfNeeded() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Initialize singletons
            _ = ConnectivityManager.shared
            await accountStore.restoreSession()
            installWatchCompletionHandler()
        }
        .task(id: accountStore.appleUserID) {
            #if DEBUG
            SampleDataSeeder.seedIfRequested(
                context: context,
                accountIdentifier: accountStore.appleUserID
            )
            #endif

            AppSyncCoordinator.shared.backfillIdentity(
                profile: profiles.first,
                workouts: workouts,
                accountIdentifier: accountStore.isSignedIn ? accountStore.appleUserID : nil
            )
            guard accountStore.isSignedIn else { return }
            AppSyncCoordinator.shared.synchronizeIfPossible(
                accountStore: accountStore,
                profile: profiles.first,
                workouts: workouts,
                context: context
            )
        }
        .onChange(of: workouts.count) {
            AppSyncCoordinator.shared.synchronizeIfPossible(
                accountStore: accountStore,
                profile: profiles.first,
                workouts: workouts,
                context: context
            )
        }
    }

    private func createProfileIfNeeded() {
        guard profiles.isEmpty, createdProfile == nil else { return }
        let profile = UserProfile(accountIdentifier: accountStore.appleUserID)
        context.insert(profile)
        try? context.save()
        createdProfile = profile
    }

    private func installWatchCompletionHandler() {
        ConnectivityManager.shared.onWorkoutCompletionReceived = { payload in
            let profileDescriptor = FetchDescriptor<UserProfile>()
            let workoutDescriptor = FetchDescriptor<WorkoutEntry>(
                sortBy: [SortDescriptor(\WorkoutEntry.date, order: .reverse)]
            )

            guard let fetchedProfiles = try? context.fetch(profileDescriptor),
                  let profile = fetchedProfiles.first else { return }
            let currentWorkouts = (try? context.fetch(workoutDescriptor)) ?? []

            if let newWorkout = WatchWorkoutIngestionService.ingest(
                completion: payload,
                profile: profile,
                context: context,
                existingWorkouts: currentWorkouts
            ) {
                var updatedWorkouts = currentWorkouts
                updatedWorkouts.insert(newWorkout, at: 0)
                AppSyncCoordinator.shared.synchronizeIfPossible(
                    accountStore: accountStore,
                    profile: profile,
                    workouts: updatedWorkouts,
                    context: context
                )
            }
        }
    }
}
