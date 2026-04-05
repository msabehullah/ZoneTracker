import SwiftUI
import SwiftData

// MARK: - Dashboard View

struct DashboardView: View {
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]
    @Environment(\.modelContext) private var context
    let profile: UserProfile

    @State private var viewModel = DashboardViewModel()
    @State private var showingLogWorkout = false
    @State private var showPhaseTransition = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    phaseHeader
                    nextWorkoutCard
                    weekProgressView
                    quickStats
                    restingHRSparkline
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .background(Color.appBackground)
            .navigationTitle("Dashboard")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingLogWorkout) {
                LogWorkoutView(profile: profile, recommendation: viewModel.nextRecommendation)
            }
            .alert("Phase Complete!", isPresented: $showPhaseTransition) {
                Button("Awesome!") {
                    viewModel.load(profile: profile, workouts: workouts)
                }
            } message: {
                Text(viewModel.phaseTransitionMessage ?? "")
            }
            .onAppear {
                viewModel.load(profile: profile, workouts: workouts)
                Task { await viewModel.loadRestingHR() }
            }
            .onChange(of: workouts.count) {
                viewModel.load(profile: profile, workouts: workouts)
                if viewModel.phaseTransitionMessage != nil {
                    showPhaseTransition = true
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Phase Header

    private var phaseHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.phase.displayName)
                        .font(.system(.title2, design: .rounded).bold())
                        .foregroundColor(.white)
                    Text(profile.phase.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
                Text("Week \(profile.weekNumber)")
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(.zone2Green)
            }

            // Phase progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.cardBorder)
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.zone2Green)
                        .frame(width: phaseProgress(geo.size.width), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
    }

    private func phaseProgress(_ totalWidth: CGFloat) -> CGFloat {
        let minWeeks = max(profile.phase.minimumWeeks, 6)
        let progress = min(1.0, Double(profile.weekNumber) / Double(minWeeks))
        return totalWidth * progress
    }

    // MARK: - Next Workout Card

    private var nextWorkoutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Next Workout")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if let rec = viewModel.nextRecommendation {
                    Image(systemName: rec.exerciseType.sfSymbol)
                        .font(.title2)
                        .foregroundColor(.zone2Green)
                }
            }

            if let rec = viewModel.nextRecommendation {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rec.sessionType.displayName)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.zone2Green)
                        Text(rec.exerciseType.displayName)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Divider().frame(height: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(rec.targetDurationMinutes) min")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.white)
                        Text("\(rec.targetHRLow)–\(rec.targetHRHigh) bpm")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }

                if !rec.suggestedMetrics.isEmpty {
                    Text(rec.formattedMetrics)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }

                if let proto = rec.intervalProtocol {
                    Text(proto.description)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.orange)
                }

                Text(rec.reasoning)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(3)

                Button {
                    showingLogWorkout = true
                } label: {
                    Text("Start Workout")
                        .font(.subheadline.bold())
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.zone2Green)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
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
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
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
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.cardBackground)
        .cornerRadius(12)
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
                Text("Resting HR data will appear here from your Apple Watch.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
    }
}
