import SwiftUI
import SwiftData

// MARK: - Dashboard View

struct DashboardView: View {
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]
    let profile: UserProfile
    var onOpenSettings: (() -> Void)? = nil

    @State private var viewModel = DashboardViewModel()
    @State private var connectivity = ConnectivityManager.shared
    @State private var showingLogWorkout = false
    @State private var showFocusTransition = false
    @State private var deliveryBanner: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    heroPanel
                    missionPanel
                    insightRail
                    recoveryBand
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(dashboardBackdrop)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if let onOpenSettings {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onOpenSettings) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .accessibilityLabel("Open Settings")
                    }
                }
            }
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

    private var dashboardBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.04, green: 0.08, blue: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.zone2Green.opacity(0.11))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 130, y: -210)

            Circle()
                .fill(Color.orange.opacity(0.09))
                .frame(width: 220, height: 220)
                .blur(radius: 85)
                .offset(x: -140, y: 260)
        }
    }

    // MARK: - Hero

    private var heroPanel: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.13, blue: 0.12),
                            Color(red: 0.05, green: 0.08, blue: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            Circle()
                .fill(Color.zone2Green.opacity(0.14))
                .frame(width: 180, height: 180)
                .blur(radius: 28)
                .offset(x: 180, y: 24)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TODAY")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(.zone2Green)
                        Text(profile.focus.displayName)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Training for \(profile.primaryGoal.shortName)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.68))
                    }

                    Spacer(minLength: 16)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Week \(profile.weekNumber)")
                            .font(.system(.headline, design: .monospaced).bold())
                            .foregroundColor(.white)
                        if let days = profile.daysUntilEvent, days > 0 {
                            Text("\(days) days out")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.zone2Green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.zone2Green.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }
                }

                HStack(alignment: .center, spacing: 18) {
                    weeklyOrbit

                    VStack(alignment: .leading, spacing: 12) {
                        heroMetric(
                            title: "Current target",
                            value: "\(viewModel.targetSessionsThisWeek) sessions",
                            accent: .white
                        )
                        if viewModel.targetSessionsThisWeek < profile.availableSessionsCeiling {
                            heroMetric(
                                title: "Build ceiling",
                                value: "\(profile.availableSessionsCeiling) days/week",
                                accent: .zone2Green
                            )
                        }
                        heroMetric(
                            title: "Progression",
                            value: "+1 every \(profile.weeksPerRampStep) consistent weeks",
                            accent: .white.opacity(0.82)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(profile.focus.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.75))
                        Spacer()
                        Text("\(viewModel.sessionsThisWeek) of \(viewModel.targetSessionsThisWeek)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.zone2Green)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                            Capsule()
                                .fill(Color.zone2Green)
                                .frame(width: weeklyProgressWidth(totalWidth: geo.size.width), height: 8)
                        }
                    }
                    .frame(height: 8)
                }
            }
            .padding(22)
        }
    }

    private var weeklyOrbit: some View {
        let target = max(viewModel.targetSessionsThisWeek, 1)
        let progress = min(1, Double(viewModel.sessionsThisWeek) / Double(target))

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 12)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.zone2Green, .white, .zone2Green]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(viewModel.sessionsThisWeek)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("of \(target)")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(.zone2Green)
                Text("this week")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 112, height: 112)
    }

    private func heroMetric(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(accent)
        }
    }

    private func weeklyProgressWidth(totalWidth: CGFloat) -> CGFloat {
        let target = max(viewModel.targetSessionsThisWeek, 1)
        let progress = min(1, Double(viewModel.sessionsThisWeek) / Double(target))
        return totalWidth * progress
    }

    // MARK: - Mission

    @ViewBuilder
    private var missionPanel: some View {
        if let recommendation = viewModel.nextRecommendation {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TODAY'S MISSION")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(.zone2Green)
                        Text(recommendation.sessionType.coachingLabel)
                            .font(.system(.title3, design: .rounded).bold())
                            .foregroundColor(.white)
                        Text(recommendation.exerciseType.displayName)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()
                    Image(systemName: recommendation.exerciseType.sfSymbol)
                        .font(.title2)
                        .foregroundColor(.zone2Green)
                        .frame(width: 42, height: 42)
                        .background(Color.zone2Green.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                HStack(spacing: 10) {
                    missionStat(label: "TIME", value: "\(recommendation.targetDurationMinutes) min")
                    missionStat(label: "TARGET", value: "\(recommendation.targetHRLow)-\(recommendation.targetHRHigh) bpm")
                }

                if !recommendation.suggestedMetrics.isEmpty {
                    Text(recommendation.formattedMetrics)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white.opacity(0.72))
                }

                if let proto = recommendation.intervalProtocol {
                    Text(proto.description)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.orange)
                }

                Text(recommendation.reasoning)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button(action: sendPlanToWatch) {
                        Text("Send to Apple Watch")
                            .font(.subheadline.bold())
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.zone2Green)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button {
                        showingLogWorkout = true
                    } label: {
                        Text("Log Manually")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "applewatch")
                        .font(.caption)
                        .foregroundColor(.zone2Green)
                    Text(watchStatusText)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            .padding(20)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 28,
                    topTrailingRadius: 20,
                    style: .continuous
                )
                .fill(Color.cardBackground)
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 28,
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: 28,
                        topTrailingRadius: 20,
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            )
        }
    }

    private func missionStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Insight Rail

    private var insightRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                insightChip(title: "Streak", value: "\(viewModel.currentStreak)", detail: "weeks")
                insightChip(title: "Total", value: "\(viewModel.totalSessions)", detail: "sessions")
                insightChip(title: "Best Mile", value: viewModel.bestMileTime, detail: "record")
                insightChip(
                    title: "Build Rate",
                    value: "+1 / \(profile.weeksPerRampStep) consistent w",
                    detail: viewModel.targetSessionsThisWeek < profile.availableSessionsCeiling
                        ? "toward \(profile.availableSessionsCeiling)" : "at ceiling"
                )
            }
            .padding(.horizontal, 2)
        }
    }

    private func insightChip(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(.title3, design: .monospaced).bold())
                .foregroundColor(.white)
            Text(detail)
                .font(.caption)
                .foregroundColor(.white.opacity(0.64))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Recovery

    private var recoveryBand: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RECOVERY SIGNAL")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(.zone2Green)
                    Text("Resting Heart Rate")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                }
                Spacer()
                if let latest = viewModel.restingHRData.last {
                    Text("\(latest.bpm) bpm")
                        .font(.system(.subheadline, design: .monospaced).bold())
                        .foregroundColor(.white)
                }
            }

            if viewModel.restingHRData.count > 1 {
                RestingHRSparkline(data: viewModel.restingHRData)
                    .frame(height: 68)
            } else {
                Text("Resting HR data from your Apple Watch will appear here automatically.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.cardBackground, Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
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
