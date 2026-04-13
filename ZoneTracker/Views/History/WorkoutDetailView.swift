import SwiftUI
import Charts

// MARK: - Workout Detail View

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let workout: WorkoutEntry
    let profile: UserProfile

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    heartRateChart
                    zoneBreakdown
                    metricsSection
                    driftSection

                    if let notes = workout.notes, !notes.isEmpty {
                        notesSection(notes)
                    }

                    if let rpe = workout.rpe {
                        rpeSection(rpe)
                    }
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.zone2Green)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: workout.exerciseType.sfSymbol)
                .font(.system(size: 36))
                .foregroundColor(.zone2Green)

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.exerciseType.displayName)
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Text(workout.date.fullDate)
                    .font(.caption)
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    Label(workout.formattedDuration, systemImage: "clock")
                    Label(workout.sessionType.displayName, systemImage: "tag")
                    Label(workout.phase.displayName, systemImage: "chart.line.uptrend.xyaxis")
                }
                .font(.caption)
                .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - HR Chart

    private var heartRateChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate")
                .font(.headline)
                .foregroundColor(.white)

            let samples = workout.heartRateData.samples
            if samples.count > 1 {
                Chart {
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("BPM", sample.bpm)
                        )
                        .foregroundStyle(Color.red.gradient)
                        .interpolationMethod(.catmullRom)
                    }

                    // Zone 2 band
                    RuleMark(y: .value("Z2 Low", profile.zone2TargetLow))
                        .foregroundStyle(.green.opacity(0.4))
                        .lineStyle(StrokeStyle(dash: [4, 4]))
                    RuleMark(y: .value("Z2 High", profile.zone2TargetHigh))
                        .foregroundStyle(.green.opacity(0.4))
                        .lineStyle(StrokeStyle(dash: [4, 4]))
                }
                .frame(height: 200)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            Text("\(value.as(Int.self) ?? 0)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.cardBorder)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel(format: .dateTime.minute())
                            .foregroundStyle(.gray)
                    }
                }

                // Summary stats
                HStack(spacing: 16) {
                    hrStatBox("Avg", "\(workout.heartRateData.avgHR)")
                    hrStatBox("Max", "\(workout.heartRateData.maxHR)")
                    hrStatBox("Min", "\(workout.heartRateData.minHR)")
                    if let recovery = workout.heartRateData.recoveryHR {
                        hrStatBox("Recovery", "↓\(recovery)")
                    }
                }
            } else {
                Text("No heart rate data recorded for this session.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
    }

    private func hrStatBox(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .monospaced).bold())
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Zone Breakdown

    private var zoneBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time in Zones")
                .font(.headline)
                .foregroundColor(.white)

            let hr = workout.heartRateData
            let total = max(workout.duration, 1)

            VStack(spacing: 6) {
                zoneBar("Zone 2", time: hr.timeInZone2, total: total, color: .green)
                zoneBar("Zone 4+", time: hr.timeInZone4Plus, total: total, color: .orange)
                zoneBar("Other", time: max(0, total - hr.timeInZone2 - hr.timeInZone4Plus), total: total, color: .gray)
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
    }

    private func zoneBar(_ label: String, time: TimeInterval, total: TimeInterval, color: Color) -> some View {
        let pct = max(0, min(1, time / total))
        return HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 60, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.cardBorder).frame(height: 8)
                    Capsule().fill(color).frame(width: geo.size.width * pct, height: 8)
                }
            }
            .frame(height: 8)

            Text("\(Int(pct * 100))%")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.headline)
                .foregroundColor(.white)

            let defs = workout.exerciseType.metricDefinitions
            ForEach(defs) { def in
                if let value = workout.metrics[def.key] {
                    HStack {
                        Text(def.name)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                        if def.key == "pace" {
                            Text(formatPace(value))
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.white)
                        } else if def.step >= 1 {
                            Text("\(Int(value)) \(def.unit)")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.white)
                        } else {
                            Text("\(String(format: "%.1f", value)) \(def.unit)")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }
                }
            }

            if let proto = workout.intervalProtocol {
                Divider().overlay(Color.cardBorder)
                HStack {
                    Text("Interval Protocol")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(proto.description)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Drift

    private var driftSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HR Drift")
                .font(.headline)
                .foregroundColor(.white)

            let drift = workout.heartRateData.hrDrift
            HStack {
                Image(systemName: drift >= 10 ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundColor(drift >= 10 ? .orange : .green)
                Text(drift >= 10
                    ? "Significant drift detected (\(String(format: "%.1f", drift))%). This intensity is still challenging."
                    : "Stable heart rate — drift was \(String(format: "%.1f", drift))%."
                )
                .font(.caption)
                .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Notes & RPE

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.headline)
                .foregroundColor(.white)
            Text(notes)
                .font(.body)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
    }

    private func rpeSection(_ rpe: Int) -> some View {
        HStack {
            Text("RPE")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Text("\(rpe) / 10")
                .font(.system(.title3, design: .monospaced))
                .foregroundColor(rpe <= 5 ? .green : rpe <= 7 ? .yellow : .red)
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Helpers

    private func formatPace(_ minutesPerMile: Double) -> String {
        let totalSeconds = Int(minutesPerMile * 60)
        let min = totalSeconds / 60
        let sec = totalSeconds % 60
        return String(format: "%d:%02d /mi", min, sec)
    }
}
