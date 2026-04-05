import SwiftUI

@main
struct ZoneTrackerWatchApp: App {
    @StateObject private var workoutManager = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                StartView()
            }
            .environmentObject(workoutManager)
        }
    }
}
