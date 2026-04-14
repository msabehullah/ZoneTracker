import SwiftUI

struct LiveWorkoutView: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    @State private var showingEndConfirm = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            GeometryReader { geometry in
                let m = LiveWorkoutLayoutMetrics(size: geometry.size)

                VStack(spacing: m.sectionSpacing) {
                    coachingBanner(m: m)
                    heartRateHero(m: m)
                    adherenceBar(m: m)
                    statsRow(m: m)
                    controlButtons(m: m)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, m.horizontalPadding)
                .padding(.top, m.topPadding)
                .padding(.bottom, m.bottomPadding)
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

    // MARK: - Coaching Banner

    private func coachingBanner(m: LiveWorkoutLayoutMetrics) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: m.statusDotSize, height: m.statusDotSize)

            Text(manager.coachingMessage)
                .font(.system(size: m.coachingTextSize, weight: .bold, design: .rounded))
                .foregroundColor(statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            Text(manager.zoneBadge)
                .font(.system(size: m.zoneBadgeTextSize, weight: .heavy, design: .monospaced))
                .foregroundColor(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.18))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Heart Rate Hero

    private func heartRateHero(m: LiveWorkoutLayoutMetrics) -> some View {
        VStack(spacing: m.heroSpacing) {
            // Heart rate number — the dominant element
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(manager.heartRate)")
                    .font(.system(size: m.heartRateSize, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())

                Text("bpm")
                    .font(.system(size: m.bpmLabelSize, weight: .medium, design: .rounded))
                    .foregroundColor(statusColor.opacity(0.6))
            }

            // Target range + segment
            HStack(spacing: 6) {
                Text(manager.activeTargetText)
                    .font(.system(size: m.targetTextSize, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if m.showsSegmentInline {
                    Text("·")
                        .foregroundColor(.gray.opacity(0.5))
                    Text(manager.activeSegmentTitle)
                        .font(.system(size: m.targetTextSize, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Adherence Bar

    private func adherenceBar(m: LiveWorkoutLayoutMetrics) -> some View {
        VStack(spacing: m.adherenceSpacing) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.25))
                        .frame(height: m.adherenceBarHeight)
                    Capsule()
                        .fill(statusColor)
                        .frame(
                            width: max(0, geo.size.width * adherenceFraction),
                            height: m.adherenceBarHeight
                        )
                        .animation(.easeInOut(duration: 0.5), value: adherenceFraction)
                }
            }
            .frame(height: m.adherenceBarHeight)

            HStack {
                Text(manager.formattedElapsed)
                    .font(.system(size: m.timeTextSize, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Text("\(manager.adherencePercent)% on target")
                    .font(.system(size: m.timeTextSize, weight: .medium, design: .monospaced))
                    .foregroundColor(statusColor.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats Row

    private func statsRow(m: LiveWorkoutLayoutMetrics) -> some View {
        HStack(spacing: m.metricSpacing) {
            metricColumn(title: "AVG", value: "\(manager.averageHR)", color: .white, m: m)
            metricColumn(title: "MAX", value: "\(manager.maxHR)", color: .orange, m: m)
            metricColumn(title: "CAL", value: "\(Int(manager.activeCalories))", color: .white, m: m)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricColumn(
        title: String,
        value: String,
        color: Color,
        m: LiveWorkoutLayoutMetrics
    ) -> some View {
        VStack(spacing: m.metricTextSpacing) {
            Text(title)
                .font(.system(size: m.metricTitleSize, weight: .medium, design: .rounded))
                .foregroundColor(.gray)

            Text(value)
                .font(.system(size: m.metricValueSize, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controls

    private func controlButtons(m: LiveWorkoutLayoutMetrics) -> some View {
        HStack(spacing: m.buttonSpacing) {
            if manager.sessionState == .running {
                Button {
                    manager.pause()
                } label: {
                    controlIcon(
                        "pause.fill",
                        foreground: .yellow,
                        background: Color.yellow.opacity(0.2),
                        m: m
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
                        m: m
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
                    m: m
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func controlIcon(
        _ systemName: String,
        foreground: Color,
        background: Color,
        m: LiveWorkoutLayoutMetrics
    ) -> some View {
        Image(systemName: systemName)
            .font(m.buttonIconFont)
            .foregroundColor(foreground)
            .frame(width: m.buttonSize, height: m.buttonSize)
            .background(background)
            .clipShape(Circle())
    }

    // MARK: - Computed

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

// MARK: - Layout Metrics

private struct LiveWorkoutLayoutMetrics {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let sectionSpacing: CGFloat
    let showsSegmentInline: Bool

    // Coaching banner
    let statusDotSize: CGFloat
    let coachingTextSize: CGFloat
    let zoneBadgeTextSize: CGFloat

    // Heart rate hero
    let heartRateSize: CGFloat
    let bpmLabelSize: CGFloat
    let heroSpacing: CGFloat
    let targetTextSize: CGFloat

    // Adherence
    let adherenceBarHeight: CGFloat
    let adherenceSpacing: CGFloat
    let timeTextSize: CGFloat

    // Stats
    let metricSpacing: CGFloat
    let metricTextSpacing: CGFloat
    let metricTitleSize: CGFloat
    let metricValueSize: CGFloat

    // Controls
    let buttonSize: CGFloat
    let buttonSpacing: CGFloat
    let buttonIconFont: Font

    init(size: CGSize) {
        let width = max(size.width, 136)
        let height = max(size.height, 170)
        let scale = min(max(min(width / 184, height / 224), 0.72), 1.18)
        let compact = width < 176 || height < 212

        horizontalPadding = compact ? max(6, 8 * scale) : max(8, 10 * scale)
        topPadding = compact ? max(4, 5 * scale) : max(6, 7 * scale)
        bottomPadding = compact ? max(2, 3 * scale) : max(4, 5 * scale)
        sectionSpacing = compact ? max(3, 4 * scale) : max(5, 6 * scale)
        showsSegmentInline = !compact

        // Coaching banner
        statusDotSize = max(6, 8 * scale)
        coachingTextSize = max(10, 12 * scale)
        zoneBadgeTextSize = max(9, 11 * scale)

        // Heart rate — the hero element, as large as possible
        heartRateSize = compact ? max(36, 48 * scale) : max(44, 56 * scale)
        bpmLabelSize = max(10, 13 * scale)
        heroSpacing = compact ? 1 : 2
        targetTextSize = max(10, 11.5 * scale)

        // Adherence bar
        adherenceBarHeight = max(4, 5 * scale)
        adherenceSpacing = compact ? 2 : 3
        timeTextSize = max(9, 10.5 * scale)

        // Stats row
        metricSpacing = compact ? max(4, 5 * scale) : max(8, 9 * scale)
        metricTextSpacing = compact ? 0 : 1
        metricTitleSize = max(7, 8.5 * scale)
        metricValueSize = max(10, 14 * scale)

        // Controls
        buttonSize = compact ? max(28, 34 * scale) : max(34, 40 * scale)
        buttonSpacing = compact ? max(8, 10 * scale) : max(12, 14 * scale)
        let ringScale = min(max(scale, 0.68), 1.16)
        buttonIconFont = ringScale < 0.82 ? .footnote.weight(.semibold) : (compact ? .body : .title3)
    }
}
