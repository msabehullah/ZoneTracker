import SwiftUI
import SwiftData

// MARK: - History View

struct HistoryView: View {
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]
    @Environment(\.modelContext) private var context

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
            .background(Color.appBackground)
            .navigationTitle("History")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $selectedWorkout) { workout in
                WorkoutDetailView(workout: workout)
            }
            .onAppear { viewModel.load(workouts: workouts) }
            .onChange(of: workouts.count) { viewModel.load(workouts: workouts) }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("No workouts yet")
                .font(.headline)
                .foregroundColor(.gray)
            Text("Your workout history will appear here.")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Text(entry.zoneBadge)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(zoneColor(for: entry))
                        Text("\(entry.heartRateData.avgHR) bpm")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(12)
    }

    private func zoneColor(for entry: WorkoutEntry) -> Color {
        let avg = entry.heartRateData.avgHR
        if avg <= 150 { return .green }
        if avg <= 170 { return .yellow }
        if avg <= 180 { return .orange }
        return .red
    }
}
