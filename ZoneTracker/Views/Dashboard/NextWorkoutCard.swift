import SwiftUI

// MARK: - Next Workout Card (Standalone)

struct NextWorkoutCard: View {
    let recommendation: WorkoutRecommendation
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: recommendation.exerciseType.sfSymbol)
                    .font(.title2)
                    .foregroundColor(.zone2Green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.sessionType.displayName)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.white)
                    Text(recommendation.exerciseType.displayName)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                adjustmentBadge
            }

            Divider().overlay(Color.cardBorder)

            HStack(spacing: 20) {
                metricPill(
                    icon: "clock",
                    value: "\(recommendation.targetDurationMinutes)",
                    unit: "min"
                )
                metricPill(
                    icon: "heart.fill",
                    value: "\(recommendation.targetHRLow)–\(recommendation.targetHRHigh)",
                    unit: "bpm"
                )
            }

            if !recommendation.suggestedMetrics.isEmpty {
                Text(recommendation.formattedMetrics)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }

            if let proto = recommendation.intervalProtocol {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(proto.description)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }

            Text(recommendation.reasoning)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(3)

            Button(action: onStart) {
                Text("Start Workout")
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.zone2Green)
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
    }

    private var adjustmentBadge: some View {
        Group {
            switch recommendation.adjustmentType {
            case .increaseIntensity:
                Label("Up", systemImage: "arrow.up")
            case .decreaseIntensity:
                Label("Down", systemImage: "arrow.down")
            case .increaseDuration:
                Label("Longer", systemImage: "plus")
            case .addIntervalRounds:
                Label("+Round", systemImage: "plus.circle")
            case .holdSteady:
                Label("Hold", systemImage: "equal")
            case .phaseTransition:
                Label("Level Up", systemImage: "star.fill")
            }
        }
        .font(.caption2)
        .foregroundColor(.zone2Green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.zone2Green.opacity(0.15))
        .cornerRadius(8)
    }

    private func metricPill(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.zone2Green)
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.white)
            Text(unit)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
}
