import SwiftUI

// MARK: - Next Workout Card (Standalone)

struct NextWorkoutCard: View {
    let recommendation: WorkoutRecommendation
    let plan: WorkoutExecutionPlan?
    let watchStatus: String
    var compact: Bool = false
    var onSendToWatch: () -> Void
    var secondaryTitle: String?
    var onManualLog: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            watchStatusRow

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

            if !compact {
                Text(recommendation.reasoning)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            if !compact, let activeSegment = plan?.segments.first {
                HStack(spacing: 8) {
                    Image(systemName: activeSegment.kind == .steady ? "waveform.path.ecg" : "timer")
                        .foregroundColor(.zone2Green)
                        .font(.caption)
                    Text(segmentSummary(activeSegment))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white.opacity(0.82))
                        .lineLimit(1)
                }
            }

            if !compact, let secondaryTitle, let onManualLog {
                HStack(spacing: 10) {
                    primaryButton
                    Button(action: onManualLog) {
                        Text(secondaryTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.cardBorder)
                            .cornerRadius(10)
                    }
                }
            } else {
                primaryButton
            }
        }
        .appCard(padding: 14)
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

    private var primaryButton: some View {
        Button(action: onSendToWatch) {
            Text("Send to Apple Watch")
                .font(.subheadline.bold())
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.zone2Green)
                .cornerRadius(10)
        }
    }

    private var watchStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "applewatch")
                .foregroundColor(.zone2Green)
                .font(.caption)
            Text(watchStatus)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
    }

    private func segmentSummary(_ segment: WorkoutPlanSegment) -> String {
        let durationText = segment.duration.minutesAndSeconds
        if let target = segment.targetRange?.displayText {
            return "\(segment.title) · \(durationText) · \(target)"
        }
        return "\(segment.title) · \(durationText)"
    }
}
