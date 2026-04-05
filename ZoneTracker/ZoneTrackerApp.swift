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
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if let profile = profiles.first {
                if profile.hasCompletedOnboarding {
                    ContentView(profile: profile)
                } else {
                    OnboardingView(profile: profile) {}
                }
            } else {
                // First launch — create profile and show onboarding
                Color.appBackground
                    .ignoresSafeArea()
                    .onAppear { createProfile() }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Initialize singletons
            _ = ConnectivityManager.shared
            await NotificationManager.shared.requestAuthorization()
        }
    }

    private func createProfile() {
        let profile = UserProfile()
        context.insert(profile)
    }
}
