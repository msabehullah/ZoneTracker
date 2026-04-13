import SwiftUI
import SwiftData

// MARK: - Log Workout View

struct LogWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]

    let profile: UserProfile
    var recommendation: WorkoutRecommendation?

    @State private var viewModel = WorkoutLogViewModel()
    @State private var showExercisePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    exerciseSection
                    sessionTypeSection
                    durationSection
                    metricsSection

                    if viewModel.selectedSession.isInterval {
                        intervalSection
                    }

                    heartRateSection
                    rpeSection
                    notesSection
                    saveButton
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.zone2Green)
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerView(selected: $viewModel.selectedExercise) {
                    let old = viewModel.selectedExercise
                    viewModel.onExerciseTypeChanged(from: old)
                }
            }
            .sheet(isPresented: $viewModel.showingResult) {
                resultSheet
            }
            .onAppear {
                if let rec = recommendation {
                    viewModel.setupFromRecommendation(rec)
                } else {
                    viewModel.resetMetricsToDefaults()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Exercise Selection

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXERCISE")
                .font(.caption)
                .foregroundColor(.gray)

            Button {
                showExercisePicker = true
            } label: {
                HStack {
                    Image(systemName: viewModel.selectedExercise.sfSymbol)
                        .font(.title2)
                        .foregroundColor(.zone2Green)
                    Text(viewModel.selectedExercise.displayName)
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.cardBackground)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Session Type

    private var sessionTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SESSION TYPE")
                .font(.caption)
                .foregroundColor(.gray)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SessionType.allCases) { type in
                        Button {
                            viewModel.selectedSession = type
                            if type.isInterval {
                                viewModel.intervalProtocol = type.defaultIntervalProtocol
                            }
                        } label: {
                            Text(type.displayName)
                                .font(.caption)
                                .foregroundColor(viewModel.selectedSession == type ? .black : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(viewModel.selectedSession == type ? Color.zone2Green : Color.cardBackground)
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DURATION")
                .font(.caption)
                .foregroundColor(.gray)

            HStack {
                Stepper(
                    value: Binding(
                        get: { viewModel.durationMinutes },
                        set: { viewModel.durationMinutes = $0 }
                    ),
                    in: 5...180,
                    step: 5
                ) {
                    Text("\(viewModel.durationMinutes) min")
                        .font(.system(.title2, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.cardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        MetricsInputView(
            exerciseType: viewModel.selectedExercise,
            metrics: $viewModel.metrics
        )
    }

    // MARK: - Interval Protocol

    private var intervalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INTERVALS")
                .font(.caption)
                .foregroundColor(.gray)

            if let proto = viewModel.intervalProtocol {
                VStack(spacing: 12) {
                    HStack {
                        Text("Work")
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(proto.workDuration))s")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    HStack {
                        Text("Rest")
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(proto.restDuration))s")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.zone2Green)
                    }
                    HStack {
                        Text("Rounds")
                            .foregroundColor(.gray)
                        Spacer()
                        Stepper(
                            "\(proto.rounds)",
                            value: Binding(
                                get: { viewModel.intervalProtocol?.rounds ?? 0 },
                                set: { viewModel.intervalProtocol?.rounds = $0 }
                            ),
                            in: 1...30
                        )
                        .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("Target HR")
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(proto.targetWorkHRLow)–\(proto.targetWorkHRHigh) bpm")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }
                .padding()
                .background(Color.cardBackground)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Heart Rate

    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HEART RATE DATA")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Button {
                    Task { await viewModel.importFromWatch(profile: profile) }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isImportingFromWatch {
                            ProgressView().tint(.zone2Green)
                        }
                        Image(systemName: "applewatch")
                        Text("Import from Watch")
                    }
                    .font(.caption)
                    .foregroundColor(.zone2Green)
                }
                .disabled(viewModel.isImportingFromWatch)
            }

            let hr = viewModel.heartRateData
            if hr.avgHR > 0 {
                HStack(spacing: 16) {
                    hrStat("Avg", "\(hr.avgHR)")
                    hrStat("Max", "\(hr.maxHR)")
                    hrStat("Min", "\(hr.minHR)")
                    if let recovery = hr.recoveryHR {
                        hrStat("Recovery", "↓\(recovery)")
                    }
                }
                .padding()
                .background(Color.cardBackground)
                .cornerRadius(12)
            } else {
                Text("Import HR data from your Apple Watch, or it will be recorded as empty.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cardBackground)
                    .cornerRadius(12)
            }

            if let error = viewModel.importError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func hrStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - RPE

    private var rpeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RPE (optional)")
                .font(.caption)
                .foregroundColor(.gray)

            HStack(spacing: 6) {
                ForEach(1...10, id: \.self) { value in
                    Button {
                        viewModel.rpe = viewModel.rpe == value ? nil : value
                    } label: {
                        Text("\(value)")
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 28, height: 28)
                            .foregroundColor(viewModel.rpe == value ? .black : .white)
                            .background(viewModel.rpe == value ? rpeColor(value) : Color.cardBackground)
                            .cornerRadius(6)
                    }
                }
            }
        }
    }

    private func rpeColor(_ value: Int) -> Color {
        switch value {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        default: return .red
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES (optional)")
                .font(.caption)
                .foregroundColor(.gray)
            TextField("How did it feel?", text: $viewModel.notes, axis: .vertical)
                .lineLimit(3...5)
                .padding()
                .background(Color.cardBackground)
                .cornerRadius(12)
                .foregroundColor(.white)
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            _ = viewModel.saveWorkout(
                profile: profile,
                context: context,
                allWorkouts: workouts
            )
        } label: {
            Text("Save Workout")
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.zone2Green)
                .cornerRadius(14)
        }
    }

    // MARK: - Result Sheet

    private var resultSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.zone2Green)

                Text("Workout Saved!")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                if let rec = viewModel.resultRecommendation {
                    let plan = WorkoutPlanningService.plan(
                        from: rec,
                        profile: profile,
                        accountIdentifier: profile.accountIdentifier
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Up Next")
                            .font(.headline)
                            .foregroundColor(.white)
                        NextWorkoutCard(
                            recommendation: rec,
                            plan: plan,
                            watchStatus: "Send this recommendation to your Apple Watch when you're ready.",
                            onSendToWatch: {
                                ConnectivityManager.shared.sendWorkoutPlan(
                                    plan,
                                    profile: WorkoutPlanningService.companionProfile(
                                        from: profile,
                                        accountIdentifier: profile.accountIdentifier
                                    )
                                )
                            },
                            secondaryTitle: nil,
                            onManualLog: nil
                        )
                    }
                    .padding(.horizontal)
                }

                Button {
                    viewModel.showingResult = false
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.zone2Green)
                        .cornerRadius(14)
                }
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
        }
        .preferredColorScheme(.dark)
    }
}
