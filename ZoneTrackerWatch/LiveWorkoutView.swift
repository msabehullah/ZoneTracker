import SwiftUI
import HealthKit

struct LiveWorkoutView: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    @State private var showingEndConfirm = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: 4) {
                zoneRing
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

    // MARK: - Zone Ring + HR

    private var zoneRing: some View {
        ZStack {
            // Zone ring background
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 8)

            // Zone ring fill — shows % of time in Zone 2
            Circle()
                .trim(from: 0, to: zone2Fraction)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: zone2Fraction)

            // Current HR + zone
            VStack(spacing: 0) {
                Text("\(manager.heartRate)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(zoneColor)

                Text(manager.zoneName(for: manager.currentZone))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(zoneColor.opacity(0.8))

                Text(formattedTime)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 130, height: 130)
    }

    private var zone2Fraction: CGFloat {
        guard manager.elapsedTime > 0 else { return 0 }
        return min(1.0, manager.timeInZone2 / manager.elapsedTime)
    }

    private var zoneColor: Color {
        switch manager.currentZone {
        case 1: return .gray
        case 2: return .green
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        default: return .gray
        }
    }

    // MARK: - Metrics Row

    private var metricsRow: some View {
        HStack {
            VStack(spacing: 1) {
                Text("AVG")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                Text("\(manager.averageHR)")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            Spacer()

            VStack(spacing: 1) {
                Text("MAX")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                Text("\(manager.maxHR)")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.orange)
            }

            Spacer()

            VStack(spacing: 1) {
                Text("CAL")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                Text("\(Int(manager.activeCalories))")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 16) {
            if manager.sessionState == .running {
                Button {
                    manager.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.title3)
                        .foregroundColor(.yellow)
                        .frame(width: 44, height: 44)
                        .background(Color.yellow.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else if manager.sessionState == .paused {
                Button {
                    manager.resume()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                        .frame(width: 44, height: 44)
                        .background(Color.green.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Button {
                showingEndConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundColor(.red)
                    .frame(width: 44, height: 44)
                    .background(Color.red.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let total = Int(manager.elapsedTime)
        let min = total / 60
        let sec = total % 60
        return String(format: "%d:%02d", min, sec)
    }
}
