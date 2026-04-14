import SwiftUI

struct LiveWorkoutView: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    @State private var showingEndConfirm = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            GeometryReader { geometry in
                let metrics = LiveWorkoutLayoutMetrics(size: geometry.size)

                VStack(spacing: metrics.contentSpacing) {
                    statusHeader(metrics: metrics)
                    targetRing(metrics: metrics)
                    metricsRow(metrics: metrics)
                    controlButtons(metrics: metrics)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, metrics.bottomPadding)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("End Workout?", isPresented: $showingEndConfirm) {
            Button("End", role: .destructive) {
                Task { await manager.endWorkout() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func statusHeader(metrics: LiveWorkoutLayoutMetrics) -> some View {
        VStack(spacing: metrics.headerSpacing) {
            Text(manager.activeSegmentTitle)
                .font(.system(size: metrics.segmentTitleSize, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            if metrics.usesInlineStatusRow {
                HStack(spacing: 6) {
                    Text(manager.activeTargetText)
                        .font(.system(size: metrics.targetTextSize, weight: .medium, design: .monospaced))
                        .foregroundColor(.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    Spacer(minLength: 4)

                    Text(manager.coachingPosition.shortLabel)
                        .font(.system(size: metrics.statusTextSize, weight: .bold, design: .rounded))
                        .foregroundColor(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            } else {
                Text(manager.activeTargetText)
                    .font(.system(size: metrics.targetTextSize, weight: .medium, design: .monospaced))
                    .foregroundColor(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(manager.coachingPosition.shortLabel)
                    .font(.system(size: metrics.statusTextSize, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func targetRing(metrics: LiveWorkoutLayoutMetrics) -> some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.25), lineWidth: metrics.ringLineWidth)

            Circle()
                .trim(from: 0, to: targetFraction)
                .stroke(
                    Color.green,
                    style: StrokeStyle(lineWidth: metrics.ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: targetFraction)

            VStack(spacing: metrics.ringTextSpacing) {
                Text("\(manager.heartRate)")
                    .font(.system(size: metrics.heartRateSize, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(formattedTime)
                    .font(.system(size: metrics.timeTextSize, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(1)

                Text(manager.workoutTitle)
                    .font(.system(size: metrics.workoutTitleSize))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, metrics.ringInnerPadding)
        }
        .frame(width: metrics.ringSize, height: metrics.ringSize)
        .frame(maxWidth: .infinity)
    }

    private func metricsRow(metrics: LiveWorkoutLayoutMetrics) -> some View {
        HStack(spacing: metrics.metricSpacing) {
            metricColumn(title: "AVG", value: "\(manager.averageHR)", color: .white, metrics: metrics)
            metricColumn(title: "MAX", value: "\(manager.maxHR)", color: .orange, metrics: metrics)
            metricColumn(title: "ON", value: onTargetTime, color: .green, metrics: metrics)
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButtons(metrics: LiveWorkoutLayoutMetrics) -> some View {
        HStack(spacing: metrics.buttonSpacing) {
            if manager.sessionState == .running {
                Button {
                    manager.pause()
                } label: {
                    controlIcon(
                        "pause.fill",
                        foreground: .yellow,
                        background: Color.yellow.opacity(0.2),
                        metrics: metrics
                    )
                }
                .buttonStyle(.plain)
            } else if manager.sessionState == .paused {
                Button {
                    manager.resume()
                } label: {
                    controlIcon(
                        "play.fill",
                        foreground: .green,
                        background: Color.green.opacity(0.2),
                        metrics: metrics
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                showingEndConfirm = true
            } label: {
                controlIcon(
                    "xmark",
                    foreground: .red,
                    background: Color.red.opacity(0.2),
                    metrics: metrics
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricColumn(
        title: String,
        value: String,
        color: Color,
        metrics: LiveWorkoutLayoutMetrics
    ) -> some View {
        VStack(spacing: metrics.metricTextSpacing) {
            Text(title)
                .font(.system(size: metrics.metricTitleSize, weight: .medium, design: .rounded))
                .foregroundColor(.gray)

            Text(value)
                .font(.system(size: metrics.metricValueSize, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity)
    }

    private func controlIcon(
        _ systemName: String,
        foreground: Color,
        background: Color,
        metrics: LiveWorkoutLayoutMetrics
    ) -> some View {
        Image(systemName: systemName)
            .font(metrics.buttonIconFont)
            .foregroundColor(foreground)
            .frame(width: metrics.buttonSize, height: metrics.buttonSize)
            .background(background)
            .clipShape(Circle())
    }

    private var targetFraction: CGFloat {
        guard manager.elapsedTime > 0 else { return 0 }
        return min(1.0, manager.timeInActiveTarget / manager.elapsedTime)
    }

    private var onTargetTime: String {
        manager.timeInActiveTarget.minutesAndSeconds
    }

    private var formattedTime: String {
        manager.elapsedTime.minutesAndSeconds
    }

    private var statusColor: Color {
        switch manager.coachingPosition {
        case .belowTarget: return .yellow
        case .inTarget: return .green
        case .aboveTarget: return .orange
        case .unavailable: return .gray
        }
    }
}

private struct LiveWorkoutLayoutMetrics {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let contentSpacing: CGFloat
    let headerSpacing: CGFloat
    let usesInlineStatusRow: Bool
    let segmentTitleSize: CGFloat
    let targetTextSize: CGFloat
    let statusTextSize: CGFloat
    let ringSize: CGFloat
    let ringLineWidth: CGFloat
    let ringInnerPadding: CGFloat
    let ringTextSpacing: CGFloat
    let heartRateSize: CGFloat
    let timeTextSize: CGFloat
    let workoutTitleSize: CGFloat
    let metricSpacing: CGFloat
    let metricTextSpacing: CGFloat
    let metricTitleSize: CGFloat
    let metricValueSize: CGFloat
    let buttonSize: CGFloat
    let buttonSpacing: CGFloat
    let buttonIconFont: Font

    init(size: CGSize) {
        let width = max(size.width, 136)
        let height = max(size.height, 170)
        let scale = min(max(min(width / 184, height / 224), 0.72), 1.18)
        let compactViewport = width < 176 || height < 212

        horizontalPadding = compactViewport ? max(6, 8 * scale) : max(8, 10 * scale)
        topPadding = compactViewport ? max(4, 5 * scale) : max(6, 7 * scale)
        bottomPadding = compactViewport ? max(2, 3 * scale) : max(4, 5 * scale)
        contentSpacing = compactViewport ? max(3, 4 * scale) : max(5, 6 * scale)
        headerSpacing = compactViewport ? 1 : 2
        usesInlineStatusRow = compactViewport

        segmentTitleSize = max(11, 13 * scale)
        targetTextSize = max(10, 11.5 * scale)
        statusTextSize = max(10, 11.5 * scale)

        metricSpacing = compactViewport ? max(4, 5 * scale) : max(8, 9 * scale)
        metricTextSpacing = compactViewport ? 0 : 1
        metricTitleSize = max(7, 8.5 * scale)
        metricValueSize = max(10, 14 * scale)

        buttonSize = compactViewport ? max(28, 34 * scale) : max(34, 40 * scale)
        buttonSpacing = compactViewport ? max(8, 10 * scale) : max(12, 14 * scale)

        let headerHeight = usesInlineStatusRow
            ? segmentTitleSize + max(targetTextSize, statusTextSize) + headerSpacing + 8
            : segmentTitleSize + targetTextSize + statusTextSize + (headerSpacing * 2) + 12
        let metricsHeight = metricTitleSize + metricValueSize + metricTextSpacing + 8
        let controlsHeight = buttonSize
        let verticalBudget = height
            - topPadding
            - bottomPadding
            - headerHeight
            - metricsHeight
            - controlsHeight
            - (contentSpacing * 3)
        let horizontalBudget = width - (horizontalPadding * 2)

        ringSize = max(52, min(horizontalBudget, verticalBudget))

        let ringScale = min(max(ringSize / 102, 0.68), 1.16)
        ringLineWidth = compactViewport ? max(5, 6 * ringScale) : max(6, 7 * ringScale)
        ringInnerPadding = max(6, 8 * ringScale)
        ringTextSpacing = ringScale < 0.82 ? 0 : 1
        heartRateSize = max(24, 36 * ringScale)
        timeTextSize = max(10, 12 * ringScale)
        workoutTitleSize = max(9, 10.5 * ringScale)
        buttonIconFont = ringScale < 0.82 ? .footnote.weight(.semibold) : (compactViewport ? .body : .title3)
    }
}
