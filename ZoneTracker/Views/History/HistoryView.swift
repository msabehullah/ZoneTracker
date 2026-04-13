import SwiftUI
import SwiftData

// MARK: - History View

struct HistoryView: View {
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]
    @Environment(\.modelContext) private var context
    let profile: UserProfile

    @State private var viewModel = HistoryViewModel()
    @State private var selectedWorkout: WorkoutEntry?

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    emptyState
                } else {
                    workoutList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.appBackground)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $selectedWorkout) { workout in
                WorkoutDetailView(workout: workout, profile: profile)
            }
            .onAppear { viewModel.load(workouts: workouts) }
            .onChange(of: workouts.count) { viewModel.load(workouts: workouts) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        ScrollView {
            FeatureEmptyStateCard(
                systemImage: "figure.run.circle.fill",
                title: "History builds as you train",
                message: "Completed Apple Watch sessions and manual workout logs will appear here automatically.",
                footnote: "Start your next planned workout from Dashboard."
            )
            .appCard()
            .padding(.horizontal)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
    }

    private var workoutList: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.groupedWorkouts, id: \.weekStart) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            workoutRow(entry)
                                .onTapGesture { selectedWorkout = entry }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        viewModel.deleteWorkout(entry, context: context)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text(viewModel.weekLabel(for: group.weekStart))
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .background(Color.appBackground)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private func workoutRow(_ entry: WorkoutEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.exerciseType.sfSymbol)
                .font(.title3)
                .foregroundColor(.zone2Green)
                .frame(width: 40, height: 40)
                .background(Color.zone2Green.opacity(0.15))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.exerciseType.displayName)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    if entry.sessionType.isInterval {
                        Text(entry.sessionType.displayName)
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                Text(entry.date.relativeDescription)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.formattedDuration)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.white)
                if entry.heartRateData.avgHR > 0 {
                    HStack(spacing: 4) {
                        Text(zoneBadge(for: entry))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(zoneColor(for: entry))
                        Text("\(entry.heartRateData.avgHR) bpm")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .appCard(cornerRadius: 14, padding: 14)
    }

    private func zoneBadge(for entry: WorkoutEntry) -> String {
        let avgHR = entry.heartRateData.avgHR
        guard avgHR > 0 else { return "—" }
        let classifier = HeartRateZoneClassifier(
            maxHeartRate: profile.maxHR,
            zone2Range: profile.zone2Range
        )
        return classifier.zone(for: avgHR).badge
    }

    private func zoneColor(for entry: WorkoutEntry) -> Color {
        let avgHR = entry.heartRateData.avgHR
        guard avgHR > 0 else { return .gray }
        let classifier = HeartRateZoneClassifier(
            maxHeartRate: profile.maxHR,
            zone2Range: profile.zone2Range
        )
        switch classifier.zone(for: avgHR) {
        case .zone1: return .gray
        case .zone2: return .green
        case .zone3: return .yellow
        case .zone4: return .orange
        case .zone5: return .red
        }
    }
}
