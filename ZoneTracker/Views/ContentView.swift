import SwiftUI

// MARK: - Content View (Swipeable App Sections)

struct ContentView: View {
    let profile: UserProfile
    @State private var selectedSection: AppSection = .dashboard

    var body: some View {
        TabView(selection: $selectedSection) {
            DashboardView(profile: profile)
                .tag(AppSection.dashboard)

            HistoryView(profile: profile)
                .tag(AppSection.history)

            ProgressDashboardView(profile: profile)
                .tag(AppSection.progress)

            SettingsView(profile: profile)
                .tag(AppSection.settings)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppSectionBar(selectedSection: $selectedSection)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .background(Color.appBackground.opacity(0.94))
        }
        .tint(.zone2Green)
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear {
            #if DEBUG
            if let section = Self.debugSelectedSection {
                selectedSection = section
            }
            #endif
        }
    }
}

private enum AppSection: Int, CaseIterable, Identifiable {
    case dashboard
    case history
    case progress
    case settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .history: return "History"
        case .progress: return "Progress"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "heart.fill"
        case .history: return "list.bullet.rectangle"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .settings: return "gearshape.fill"
        }
    }
}

private struct AppSectionBar: View {
    @Binding var selectedSection: AppSection

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSection = section
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundColor(selectedSection == section ? .black : .white.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selectedSection == section ? Color.zone2Green : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.cardBorder, lineWidth: 1)
        )
    }
}

private extension ContentView {
    static var debugSelectedSection: AppSection? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-codex-selected-tab"),
              arguments.indices.contains(index + 1),
              let tab = Int(arguments[index + 1]),
              let section = AppSection(rawValue: max(0, min(3, tab))) else {
            return nil
        }
        return section
    }
}
