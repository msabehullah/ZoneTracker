import SwiftUI

// MARK: - Metrics Input View

struct MetricsInputView: View {
    let exerciseType: ExerciseType
    @Binding var metrics: [String: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SETTINGS")
                .font(.caption)
                .foregroundColor(.gray)

            VStack(spacing: 12) {
                ForEach(exerciseType.metricDefinitions) { def in
                    metricRow(def)
                }
            }
            .padding()
            .background(Color.cardBackground)
            .cornerRadius(12)
        }
    }

    private func metricRow(_ def: MetricDefinition) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(def.name)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Spacer()

                let value = metrics[def.key] ?? def.defaultValue
                if def.key == "pace" {
                    Text(formatPace(value))
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.white)
                } else if def.step >= 1 {
                    Text("\(Int(value))")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.white)
                } else {
                    Text(String(format: "%.1f", value))
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.white)
                }

                if !def.unit.isEmpty {
                    Text(def.unit)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Slider(
                value: Binding(
                    get: { metrics[def.key] ?? def.defaultValue },
                    set: { newValue in
                        // Snap to step
                        let stepped = (newValue / def.step).rounded() * def.step
                        metrics[def.key] = stepped
                    }
                ),
                in: def.min...def.max,
                step: def.step
            )
            .tint(.zone2Green)
        }
    }

    private func formatPace(_ minutesPerMile: Double) -> String {
        let totalSeconds = Int(minutesPerMile * 60)
        let min = totalSeconds / 60
        let sec = totalSeconds % 60
        return String(format: "%d:%02d", min, sec)
    }
}
