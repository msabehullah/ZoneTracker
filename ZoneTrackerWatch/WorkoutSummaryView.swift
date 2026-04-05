import SwiftUI

struct WorkoutSummaryView: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.green)

                Text("Workout Complete")
                    .font(.system(.headline, design: .rounded))

                VStack(spacing: 8) {
                    summaryRow("Duration", value: formattedDuration)
                    summaryRow("Avg HR", value: "\(manager.summaryAvgHR) bpm")
                    summaryRow("Max HR", value: "\(manager.summaryMaxHR) bpm")
                    summaryRow("Calories", value: "\(Int(manager.summaryCalories)) kcal")
                    summaryRow("Zone 2 Time", value: formattedZone2Time)

                    // Zone 2 percentage bar
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Zone 2: \(zone2Percentage)%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.green)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(Color.green)
                                    .frame(width: geo.size.width * zone2Fraction, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.top, 4)
                }
                .padding(12)
                .background(Color(white: 0.15))
                .cornerRadius(12)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(.horizontal)
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Helpers

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    private var formattedDuration: String {
        let total = Int(manager.summaryDuration)
        let min = total / 60
        let sec = total % 60
        return String(format: "%d:%02d", min, sec)
    }

    private var formattedZone2Time: String {
        let total = Int(manager.summaryTimeInZone2)
        let min = total / 60
        let sec = total % 60
        return String(format: "%d:%02d", min, sec)
    }

    private var zone2Fraction: CGFloat {
        guard manager.summaryDuration > 0 else { return 0 }
        return min(1.0, manager.summaryTimeInZone2 / manager.summaryDuration)
    }

    private var zone2Percentage: Int {
        Int(zone2Fraction * 100)
    }
}
