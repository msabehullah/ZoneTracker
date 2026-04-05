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
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Progress")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                await viewModel.load(workouts: workouts, profile: profile)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Phase Timeline

    private var phaseTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Timeline")
                .font(.headline)
                .foregroundColor(.white)

            ForEach(viewModel.phaseTimeline.indices, id: \.self) { i in
                let item = viewModel.phaseTimeline[i]
                HStack(spacing: 12) {
                    Circle()
                        .fill(item.endDate == nil ? Color.zone2Green : Color.gray)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.phase.displayName + " — " + item.phase.subtitle)
                            .font(.subheadline.bold())
                            .foregroundColor(item.endDate == nil ? .white : .gray)

                        let start = item.startDate.shortDate
                        let end = item.endDate?.shortDate ?? "Current"
                        Text("\(start) → \(end)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
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
                noDataView("Resting HR data from your Apple Watch will appear here.")
            }
        }
    }

    // MARK: - Pace at 150 BPM

    private var paceChart: some View {
        chartCard(title: "Pace at 150 BPM", subtitle: "Speed that keeps you at 150 bpm") {
            if viewModel.paceAt150History.count > 1 {
                Chart {
                    ForEach(viewModel.paceAt150History.indices, id: \.self) { i in
                        let point = viewModel.paceAt150History[i]
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
                noDataView("Log treadmill Zone 2 sessions where your avg HR is near 150 bpm to track pace improvement.")
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
                noDataView("Log mile benchmark tests to track your progress over time.")
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
                noDataView("Recovery rate data will appear as you log workouts with heart rate data.")
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
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)
            }
            content()
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
    }

    private func noDataView(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
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
}
