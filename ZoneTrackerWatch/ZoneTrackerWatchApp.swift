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
            .onChange(of: connectivity.zone2Low) { _, newValue in
                workoutManager.zone2Low = newValue
            }
            .onChange(of: connectivity.zone2High) { _, newValue in
                workoutManager.zone2High = newValue
            }
            .onChange(of: connectivity.maxHR) { _, newValue in
                workoutManager.userMaxHR = newValue
            }
        }
    }
}
