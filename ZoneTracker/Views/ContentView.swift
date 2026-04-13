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

            HistoryView(profile: profile)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear {
            #if DEBUG
            if let tab = Self.debugSelectedTab {
                selectedTab = tab
            }
            #endif
        }
    }
}

private extension ContentView {
    static var debugSelectedTab: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-codex-selected-tab"),
              arguments.indices.contains(index + 1),
              let tab = Int(arguments[index + 1]) else {
            return nil
        }
        return max(0, min(3, tab))
    }
}
