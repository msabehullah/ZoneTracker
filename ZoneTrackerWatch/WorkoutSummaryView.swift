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
                    summaryRow("Duration", value: manager.summaryDuration.minutesAndSeconds)
                    summaryRow("Avg HR", value: "\(manager.summaryAvgHR) bpm")
                    summaryRow("Max HR", value: "\(manager.summaryMaxHR) bpm")
                    summaryRow("Calories", value: "\(Int(manager.summaryCalories)) kcal")
                    summaryRow(manager.summaryTargetLabel, value: manager.summaryTimeInTarget.minutesAndSeconds)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Adherence: \(adherencePercentage)%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.green)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(adherenceColor)
                                    .frame(width: geo.size.width * adherenceFraction, height: 6)
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

    private var adherenceFraction: CGFloat {
        guard manager.summaryDuration > 0 else { return 0 }
        return min(1.0, manager.summaryTimeInTarget / manager.summaryDuration)
    }

    private var adherencePercentage: Int {
        Int(adherenceFraction * 100)
    }

    private var adherenceColor: Color {
        if adherencePercentage >= 80 { return .green }
        if adherencePercentage >= 50 { return .yellow }
        return .orange
    }
}
