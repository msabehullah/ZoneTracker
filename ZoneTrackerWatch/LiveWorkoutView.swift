import SwiftUI

struct LiveWorkoutView: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    @State private var showingEndConfirm = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: 6) {
                statusHeader
                targetRing
                metricsRow
                controlButtons
            }
            .padding(.horizontal, 4)
        }
        .navigationBarBackButtonHidden(true)
        .confirmationDialog("End Workout?", isPresented: $showingEndConfirm) {
            Button("End", role: .destructive) {
                Task { await manager.endWorkout() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var statusHeader: some View {
        VStack(spacing: 2) {
            Text(manager.activeSegmentTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            Text(manager.activeTargetText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.green)

            Text(manager.coachingPosition.shortLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(statusColor)
        }
    }

    private var targetRing: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.25), lineWidth: 8)

            Circle()
                .trim(from: 0, to: targetFraction)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: targetFraction)

            VStack(spacing: 1) {
                Text("\(manager.heartRate)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)

                Text(formattedTime)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.gray)

                Text(manager.workoutTitle)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
        .frame(width: 130, height: 130)
    }

    private var metricsRow: some View {
        HStack {
            metricColumn(title: "AVG", value: "\(manager.averageHR)", color: .white)
            Spacer()
            metricColumn(title: "MAX", value: "\(manager.maxHR)", color: .orange)
            Spacer()
            metricColumn(title: "ON", value: onTargetTime, color: .green)
        }
        .padding(.horizontal, 8)
    }

    private var controlButtons: some View {
        HStack(spacing: 16) {
            if manager.sessionState == .running {
                Button {
                    manager.pause()
                } label: {
                    controlIcon("pause.fill", foreground: .yellow, background: Color.yellow.opacity(0.2))
                }
                .buttonStyle(.plain)
            } else if manager.sessionState == .paused {
                Button {
                    manager.resume()
                } label: {
                    controlIcon("play.fill", foreground: .green, background: Color.green.opacity(0.2))
                }
                .buttonStyle(.plain)
            }

            Button {
                showingEndConfirm = true
            } label: {
                controlIcon("xmark", foreground: .red, background: Color.red.opacity(0.2))
            }
            .buttonStyle(.plain)
        }
    }

    private func metricColumn(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func controlIcon(_ systemName: String, foreground: Color, background: Color) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundColor(foreground)
            .frame(width: 44, height: 44)
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
