import SwiftUI
import SwiftData

// MARK: - Dashboard View

struct DashboardView: View {
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]
    @Environment(\.modelContext) private var context
    let profile: UserProfile

    @State private var viewModel = DashboardViewModel()
    @State private var connectivity = ConnectivityManager.shared
    @State private var showingLogWorkout = false
    @State private var showFocusTransition = false
    @State private var deliveryBanner: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    focusHeader
                    nextWorkoutCard
                    weekProgressView
                    quickStats
                    restingHRSparkline
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.appBackground)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingLogWorkout) {
                LogWorkoutView(profile: profile, recommendation: viewModel.nextRecommendation)
            }
            .alert("Focus Advanced!", isPresented: $showFocusTransition) {
                Button("Let's Go!") {
                    viewModel.load(profile: profile, workouts: workouts)
                }
            } message: {
                Text(viewModel.focusTransitionMessage ?? "")
            }
            .onAppear {
                viewModel.load(profile: profile, workouts: workouts)
                Task { await viewModel.loadRestingHR() }
            }
            .onChange(of: workouts.count) {
                viewModel.load(profile: profile, workouts: workouts)
                if viewModel.focusTransitionMessage != nil {
                    showFocusTransition = true
                }
            }
            .overlay(alignment: .top) {
                if let deliveryBanner {
                    Text(deliveryBanner)
                        .font(.caption.bold())
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.zone2Green)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    // MARK: - Focus Header

    private var focusHeader: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.focus.displayName)
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundColor(.white)
                    Text("Goal: \(profile.primaryGoal.shortName)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Week \(profile.weekNumber)")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.zone2Green)
                    if let days = profile.daysUntilEvent, days > 0 {
                        Text("\(days) days to event")
                            .font(.caption)
                            .foregroundColor(.zone2Green.opacity(0.8))
                    }
                }
            }

            // Focus progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.cardBorder)
                        .frame(height: 5)
                    Capsule()
                        .fill(Color.zone2Green)
                        .frame(width: focusProgress(geo.size.width), height: 5)
                }
            }
            .frame(height: 5)
        }
        .appCard(padding: 12)
    }

    private func focusProgress(_ totalWidth: CGFloat) -> CGFloat {
        let minWeeks = max(profile.focus.minimumWeeks, 4)
        let progress = min(1.0, Double(profile.weekNumber) / Double(minWeeks))
        return totalWidth * progress
    }

    // MARK: - Next Workout Card

    private var nextWorkoutCard: some View {
        Group {
            if let recommendation = viewModel.nextRecommendation {
                VStack(alignment: .trailing, spacing: 8) {
                    NextWorkoutCard(
                        recommendation: recommendation,
                        plan: viewModel.currentPlan,
                        watchStatus: watchStatusText,
                        compact: true,
                        onSendToWatch: sendPlanToWatch
                    )

                    Button("Log Manually") {
                        showingLogWorkout = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.zone2Green)
                }
            }
        }
    }

    // MARK: - Week Progress

    private var weekProgressView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("This Week")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(viewModel.sessionsThisWeek)")
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(.zone2Green)
                    Text("/ \(viewModel.targetSessionsThisWeek)")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            // Dots for sessions
            HStack(spacing: 6) {
                ForEach(0..<viewModel.targetSessionsThisWeek, id: \.self) { i in
                    Circle()
                        .fill(i < viewModel.sessionsThisWeek ? Color.zone2Green : Color.cardBorder)
                        .frame(width: 16, height: 16)
                }
            }
        }
        .appCard()
    }

    // MARK: - Quick Stats

    private var quickStats: some View {
        HStack(spacing: 12) {
            statBox("Total", "\(viewModel.totalSessions)", "sessions")
            statBox("Streak", "\(viewModel.currentStreak)", "weeks")
            statBox("Best Mile", viewModel.bestMileTime, "")
        }
    }

    private func statBox(_ title: String, _ value: String, _ subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(.title2, design: .monospaced).bold())
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle.isEmpty ? " " : subtitle)
                .font(.caption2)
                .foregroundColor(.gray.opacity(subtitle.isEmpty ? 0 : 1))
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .appCard(cornerRadius: 14, padding: 12)
    }

    // MARK: - Resting HR Sparkline

    private var restingHRSparkline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Resting Heart Rate")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Spacer()
                if let latest = viewModel.restingHRData.last {
                    Text("\(latest.bpm) bpm")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white)
                }
            }

            if viewModel.restingHRData.count > 1 {
                RestingHRSparkline(data: viewModel.restingHRData)
                    .frame(height: 50)
            } else {
                InlineEmptyState(
                    systemImage: "heart.circle.fill",
                    message: "Resting HR data from your Apple Watch will appear here.",
                    minHeight: 78
                )
            }
        }
        .appCard()
    }

    private var watchStatusText: String {
        if !connectivity.isWatchAppInstalled {
            return "Watch app not installed"
        }
        if connectivity.lastSentPlanIdentifier == viewModel.currentPlan?.id {
            return "Already on your watch"
        }
        if connectivity.isReachable {
            return "Watch connected and ready"
        }
        if connectivity.isPaired {
            return "Queued for watch delivery"
        }
        return "Pair Apple Watch for coaching"
    }

    private func sendPlanToWatch() {
        viewModel.sendPlanToWatch(profile: profile)
        let message: String
        if connectivity.isReachable {
            message = "Plan sent to Apple Watch"
        } else if connectivity.isWatchAppInstalled {
            message = "Plan queued for Apple Watch delivery"
        } else {
            message = "Watch plan updated in the companion flow"
        }

        withAnimation(.spring(response: 0.3)) {
            deliveryBanner = message
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                deliveryBanner = nil
            }
        }
    }
}
