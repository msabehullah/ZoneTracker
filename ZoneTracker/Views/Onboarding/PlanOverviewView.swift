import SwiftUI

// MARK: - Plan Overview View

/// Shown immediately after the initial assessment commits, before the user
/// enters the main dashboard. Reads like a real program handoff — what they're
/// training for, what an early week looks like, what their first workout is,
/// how the plan progresses, and how the watch coaches them. Last-chance edit
/// button lives at the bottom.
struct PlanOverviewView: View {
    let profile: UserProfile
    var onStartCoaching: () -> Void
    var onEdit: () -> Void

    private var firstWorkout: WorkoutRecommendation {
        WorkoutRecommendation.defaultFirstWorkout(profile: profile)
    }

    private var explanation: ProgramExplanation {
        ProgramExplanation.build(profile: profile, firstWorkout: firstWorkout)
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    hero
                    weekSnapshotCard

                    ForEach(explanation.sections) { section in
                        sectionCard(section)
                    }

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 130)
            }

            VStack(spacing: 10) {
                Spacer()
                Button(action: onStartCoaching) {
                    Text("Start Coaching")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.zone2Green)
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)

                Button(action: onEdit) {
                    Text("Edit Plan")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.zone2Green)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .background(
                LinearGradient(
                    colors: [Color.appBackground.opacity(0), Color.appBackground],
                    startPoint: .top,
                    endPoint: .center
                )
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: profile.primaryGoal.icon)
                .font(.system(size: 40))
                .foregroundColor(.zone2Green)

            Text(explanation.headline)
                .font(.title.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(explanation.subhead)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Week Snapshot

    /// Numerical at-a-glance card. Lives outside the ProgramExplanation copy
    /// because it's a metric block, not narrative.
    private var weekSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("YOUR WEEK AT A GLANCE")

            HStack(spacing: 0) {
                metricColumn(
                    value: "\(profile.effectiveSessionsPerWeek)",
                    caption: "sessions",
                    color: .white
                )
                Divider().overlay(Color.cardBorder).frame(height: 40)
                metricColumn(
                    value: "\(profile.effectiveTargetZoneSessions)",
                    caption: "target zone",
                    color: .zone2Green
                )
                Divider().overlay(Color.cardBorder).frame(height: 40)
                metricColumn(
                    value: "\(profile.effectiveIntervalSessions)",
                    caption: "intervals",
                    color: .orange
                )
            }

            Text("Target heart rate: \(profile.zone2TargetLow)–\(profile.zone2TargetHigh) bpm")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cardBackground)
        .cornerRadius(14)
    }

    private func metricColumn(value: String, caption: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundColor(color)
            Text(caption)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section Card

    private func sectionCard(_ section: ProgramExplanation.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.zone2Green)
                    .frame(width: 24, height: 24)
                    .background(Color.zone2Green.opacity(0.15))
                    .clipShape(Circle())

                Text(section.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white)
            }

            Text(section.body)
                .font(.subheadline)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)

            if !section.bullets.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(section.bullets, id: \.self) { bullet in
                        Text(bullet)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.cardBorder.opacity(0.85))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cardBackground)
        .cornerRadius(14)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundColor(.gray)
            .kerning(1)
    }
}

// MARK: - Flow Layout

/// Simple wrap layout so pills reflow on any width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return layout(maxWidth: maxWidth, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(maxWidth: bounds.width, subviews: subviews)
        for (index, point) in result.offsets.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, offsets: [CGPoint]) {
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }

        return (CGSize(width: totalWidth, height: y + rowHeight), offsets)
    }
}
