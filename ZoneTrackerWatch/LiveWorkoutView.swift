import SwiftUI

struct LiveWorkoutView: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    @State private var showingEndConfirm = false
    @State private var selectedPage: Page = .coaching

    private enum Page: Hashable {
        case coaching
        case progress
        case metrics
        case controls
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            TabView(selection: $selectedPage) {
                CoachingPage(manager: manager, statusColor: statusColor)
                    .tag(Page.coaching)

                ProgressPage(manager: manager, statusColor: statusColor, adherenceFraction: adherenceFraction)
                    .tag(Page.progress)

                MetricsPage(manager: manager)
                    .tag(Page.metrics)

                ControlsPage(
                    manager: manager,
                    showingEndConfirm: $showingEndConfirm
                )
                .tag(Page.controls)
            }
            .tabViewStyle(.verticalPage)
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

    private var adherenceFraction: CGFloat {
        guard manager.elapsedTime > 0 else { return 0 }
        return min(1.0, manager.timeInActiveTarget / manager.elapsedTime)
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

// MARK: - Coaching Page

private struct CoachingPage: View {
    @ObservedObject var manager: WatchWorkoutManager
    let statusColor: Color

    var body: some View {
        VStack(spacing: 6) {
            topBar

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(manager.heartRate)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text("bpm")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(statusColor.opacity(0.6))
            }

            Text(manager.activeTargetText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(manager.coachingMessage)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(statusColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            metricsStrip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(manager.zoneBadge)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.18))
                .clipShape(Capsule())
            Spacer()
            Text(manager.formattedElapsed)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .contentTransition(.numericText())
        }
    }

    private var metricsStrip: some View {
        HStack(spacing: 6) {
            if manager.supportsDistance {
                metricCell(label: "DIST", value: manager.formattedDistance)
                metricCell(label: "PACE", value: manager.formattedPace)
            } else {
                metricCell(label: "CAL", value: manager.fallbackSecondaryValue)
                metricCell(label: "AVG HR", value: "\(manager.averageHR)")
            }
            metricCell(
                label: "ON TGT",
                value: "\(manager.adherencePercent)%",
                tint: statusColor
            )
        }
    }

    private func metricCell(
        label: String,
        value: String,
        tint: Color = .white
    ) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Color(white: 0.12))
        .cornerRadius(7)
    }
}

// MARK: - Progress Page

private struct ProgressPage: View {
    @ObservedObject var manager: WatchWorkoutManager
    let statusColor: Color
    let adherenceFraction: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ELAPSED")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
                Text(manager.formattedElapsed)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ON TARGET")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(manager.adherencePercent)%")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(statusColor)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.25))
                        Capsule()
                            .fill(statusColor)
                            .frame(width: max(0, geo.size.width * adherenceFraction))
                            .animation(.easeInOut(duration: 0.5), value: adherenceFraction)
                    }
                }
                .frame(height: 6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("SEGMENT")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
                Text(manager.activeSegmentTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Metrics Page

private struct MetricsPage: View {
    @ObservedObject var manager: WatchWorkoutManager

    var body: some View {
        VStack(spacing: 10) {
            metricRow(title: "AVG HR", value: "\(manager.averageHR)", unit: "bpm", color: .white)
            metricRow(title: "MAX HR", value: "\(manager.maxHR)", unit: "bpm", color: .orange)
            metricRow(title: "CALORIES", value: "\(Int(manager.activeCalories))", unit: "kcal", color: .white)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func metricRow(title: String, value: String, unit: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(white: 0.12))
        .cornerRadius(10)
    }
}

// MARK: - Controls Page

private struct ControlsPage: View {
    @ObservedObject var manager: WatchWorkoutManager
    @Binding var showingEndConfirm: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text(sessionStateLabel)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.gray)

            if manager.sessionState == .running {
                controlButton(
                    title: "Pause",
                    systemName: "pause.fill",
                    tint: .yellow
                ) {
                    manager.pause()
                }
            } else if manager.sessionState == .paused {
                controlButton(
                    title: "Resume",
                    systemName: "play.fill",
                    tint: .green
                ) {
                    manager.resume()
                }
            }

            controlButton(
                title: "End Workout",
                systemName: "xmark",
                tint: .red
            ) {
                showingEndConfirm = true
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var sessionStateLabel: String {
        switch manager.sessionState {
        case .running: return "WORKOUT IN PROGRESS"
        case .paused: return "PAUSED"
        default: return "CONTROLS"
        }
    }

    private func controlButton(
        title: String,
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(tint.opacity(0.18))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
