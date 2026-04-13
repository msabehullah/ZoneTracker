import SwiftUI
import SwiftData
import Charts

// MARK: - Progress View

struct ProgressDashboardView: View {
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]
    let profile: UserProfile

    @State private var viewModel = ProgressViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    phaseTimeline
                    restingHRChart
                    paceChart
                    mileTimeChart
                    recoveryChart
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.appBackground)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                await viewModel.load(workouts: workouts, profile: profile)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    // MARK: - Phase Timeline

    private var phaseTimeline: some View {
        let currentItem = viewModel.phaseTimeline.last ?? (phase: profile.phase, startDate: profile.phaseStartDate, endDate: nil)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Timeline")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(currentItem.phase.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(currentItem.phase.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.zone2Green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.zone2Green.opacity(0.16))
                        )

                    Text(currentItem.phase.weekRange)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }

            HStack(spacing: 8) {
                ForEach(TrainingPhase.allCases) { phase in
                    phaseStep(phase, currentPhase: currentItem.phase)
                }
            }

            HStack(spacing: 12) {
                timelineMetric(title: "Started", value: currentItem.startDate.shortDate)
                timelineMetric(title: "Target", value: "\(currentItem.phase.targetSessionsPerWeek)x/week")
                timelineMetric(title: "Status", value: currentItem.endDate == nil ? "Current" : "Completed")
            }
        }
        .appCard()
    }

    // MARK: - Resting HR Chart

    private var restingHRChart: some View {
        chartCard(title: "Resting Heart Rate", subtitle: trend(for: viewModel.restingHRHistory.map(\.bpm))) {
            if viewModel.restingHRHistory.count > 1 {
                Chart {
                    ForEach(viewModel.restingHRHistory.indices, id: \.self) { i in
                        let point = viewModel.restingHRHistory[i]
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("BPM", point.bpm)
                        )
                        .foregroundStyle(Color.red.gradient)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("BPM", point.bpm)
                        )
                        .foregroundStyle(Color.red)
                        .symbolSize(20)
                    }
                }
                .frame(height: 180)
                .chartYAxisLabel("bpm")
                .chartYAxis { axisStyle() }
                .chartXAxis { dateAxisStyle() }
            } else {
                noDataView(
                    "Resting HR data from your Apple Watch will appear here.",
                    systemImage: "heart.circle.fill"
                )
            }
        }
    }

    // MARK: - Pace in Target Range

    private var paceChart: some View {
        chartCard(
            title: "Pace in Target Range",
            subtitle: "Treadmill speed while holding \(profile.zone2TargetLow)-\(profile.zone2TargetHigh) bpm"
        ) {
            if viewModel.paceInTargetHistory.count > 1 {
                Chart {
                    ForEach(viewModel.paceInTargetHistory.indices, id: \.self) { i in
                        let point = viewModel.paceInTargetHistory[i]
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Speed", point.speed)
                        )
                        .foregroundStyle(Color.zone2Green.gradient)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Speed", point.speed)
                        )
                        .foregroundStyle(Color.zone2Green)
                        .symbolSize(20)
                    }
                }
                .frame(height: 180)
                .chartYAxisLabel("mph")
                .chartYAxis { axisStyle() }
                .chartXAxis { dateAxisStyle() }
            } else {
                noDataView(
                    "Log treadmill Zone 2 sessions inside your target range to track pace improvement.",
                    systemImage: "speedometer"
                )
            }
        }
    }

    // MARK: - Mile Time

    private var mileTimeChart: some View {
        chartCard(title: "Mile Time", subtitle: viewModel.mileTimeHistory.last.map { viewModel.formattedMileTime($0.seconds) } ?? "—") {
            if viewModel.mileTimeHistory.count > 1 {
                Chart {
                    ForEach(viewModel.mileTimeHistory.indices, id: \.self) { i in
                        let point = viewModel.mileTimeHistory[i]
                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Seconds", point.seconds)
                        )
                        .foregroundStyle(Color.orange.gradient)
                        .cornerRadius(4)
                    }
                }
                .frame(height: 180)
                .chartYAxis { axisStyle() }
                .chartXAxis { dateAxisStyle() }
            } else {
                noDataView(
                    "Log mile benchmark tests to track your progress over time.",
                    systemImage: "flag.checkered"
                )
            }
        }
    }

    // MARK: - Recovery HR

    private var recoveryChart: some View {
        chartCard(title: "Recovery Rate", subtitle: "HR drop 1 min after stopping") {
            if viewModel.recoveryHRHistory.count > 1 {
                Chart {
                    ForEach(viewModel.recoveryHRHistory.indices, id: \.self) { i in
                        let point = viewModel.recoveryHRHistory[i]
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Drop", point.drop)
                        )
                        .foregroundStyle(Color.blue.gradient)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Drop", point.drop)
                        )
                        .foregroundStyle(Color.blue)
                        .symbolSize(20)
                    }
                }
                .frame(height: 180)
                .chartYAxisLabel("bpm drop")
                .chartYAxis { axisStyle() }
                .chartXAxis { dateAxisStyle() }
            } else {
                noDataView(
                    "Recovery rate data will appear as you log workouts with heart rate data.",
                    systemImage: "waveform.path.ecg"
                )
            }
        }
    }

    // MARK: - Helpers

    private func chartCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
            content()
        }
        .appCard()
    }

    private func phaseStep(_ phase: TrainingPhase, currentPhase: TrainingPhase) -> some View {
        let isCurrent = phase == currentPhase
        let isCompleted = phaseIndex(for: phase) < phaseIndex(for: currentPhase)
        let accent = isCurrent ? Color.zone2Green : (isCompleted ? Color.white.opacity(0.8) : Color.gray)
        let titleColor = isCurrent ? Color.white : (isCompleted ? Color.white.opacity(0.9) : Color.gray)
        let background = isCurrent ? Color.zone2Green.opacity(0.12) : Color.black.opacity(isCompleted ? 0.12 : 0.06)
        let border = isCurrent ? Color.zone2Green.opacity(0.45) : Color.cardBorder
        let status = isCurrent ? "Current" : (isCompleted ? "Done" : "Next")

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)

                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(accent)
                    .lineLimit(1)
            }

            Text(phase.displayName)
                .font(.caption.weight(.bold))
                .foregroundColor(titleColor)

            Text(phase.weekRange)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
        )
    }

    private func timelineMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func noDataView(_ message: String, systemImage: String) -> some View {
        InlineEmptyState(
            systemImage: systemImage,
            message: message,
            minHeight: 112
        )
    }

    private func axisStyle() -> some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisValueLabel()
                .foregroundStyle(.gray)
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.cardBorder)
        }
    }

    private func dateAxisStyle() -> some AxisContent {
        AxisMarks { value in
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                .foregroundStyle(.gray)
        }
    }

    private func trend(for values: [Int]) -> String {
        guard values.count >= 2 else { return "—" }
        let recent = Array(values.suffix(7))
        let earlier = Array(values.prefix(min(7, values.count / 2)))
        guard !recent.isEmpty, !earlier.isEmpty else { return "—" }
        let recentAvg = Double(recent.reduce(0, +)) / Double(recent.count)
        let earlierAvg = Double(earlier.reduce(0, +)) / Double(earlier.count)
        let diff = recentAvg - earlierAvg
        if abs(diff) < 1 { return "Stable" }
        return diff < 0 ? "↓ Improving" : "↑ Elevated"
    }

    private func phaseIndex(for phase: TrainingPhase) -> Int {
        TrainingPhase.allCases.firstIndex(of: phase) ?? 0
    }
}
