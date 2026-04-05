import SwiftUI

// MARK: - Content View (Tab Navigation)

struct ContentView: View {
    let profile: UserProfile
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(profile: profile)
                .tabItem {
                    Label("Dashboard", systemImage: "heart.fill")
                }
                .tag(0)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "list.bullet.rectangle")
                }
                .tag(1)

            ProgressDashboardView(profile: profile)
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)

            SettingsView(profile: profile)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(.zone2Green)
        .preferredColorScheme(.dark)
    }
}
