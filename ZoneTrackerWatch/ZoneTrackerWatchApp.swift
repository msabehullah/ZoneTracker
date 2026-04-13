import SwiftUI

@main
struct ZoneTrackerWatchApp: App {
    @StateObject private var workoutManager = WatchWorkoutManager()
    @StateObject private var connectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                StartView()
            }
            .environmentObject(workoutManager)
            .environmentObject(connectivity)
            .onAppear {
                workoutManager.updateCompanionProfile(connectivity.companionProfile)
            }
            .onChange(of: connectivity.companionProfile) { _, newValue in
                workoutManager.updateCompanionProfile(newValue)
            }
        }
    }
}
