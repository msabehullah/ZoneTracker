import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct ZoneTrackerProvider: TimelineProvider {
    func placeholder(in context: Context) -> ZoneEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ZoneEntry) -> Void) {
        completion(.placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ZoneEntry>) -> Void) {
        // Read from shared UserDefaults (app group)
        let defaults = UserDefaults(suiteName: "group.com.zonetracker.app") ?? .standard

        let entry = ZoneEntry(
            date: Date(),
            focus: defaults.string(forKey: "widget_phase") ?? "Building Your Base",
            weekNumber: defaults.integer(forKey: "widget_weekNumber"),
            sessionsThisWeek: defaults.integer(forKey: "widget_sessionsThisWeek"),
            targetSessions: defaults.integer(forKey: "widget_targetSessions"),
            nextWorkoutType: defaults.string(forKey: "widget_nextSessionType") ?? "Target Zone",
            nextWorkoutDuration: defaults.integer(forKey: "widget_nextDuration")
        )

        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Timeline Entry

struct ZoneEntry: TimelineEntry {
    let date: Date
    let focus: String
    let weekNumber: Int
    let sessionsThisWeek: Int
    let targetSessions: Int
    let nextWorkoutType: String
    let nextWorkoutDuration: Int

    static let placeholder = ZoneEntry(
        date: Date(),
        focus: "Building Your Base",
        weekNumber: 3,
        sessionsThisWeek: 2,
        targetSessions: 3,
        nextWorkoutType: "Target Zone",
        nextWorkoutDuration: 45
    )
}

// MARK: - Widget Views

struct ZoneTrackerWidgetEntryView: View {
    var entry: ZoneEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        case .accessoryCircular:
            circularWidget
        case .accessoryRectangular:
            rectangularWidget
        default:
            smallWidget
        }
    }

    // MARK: - Small Widget

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("ZoneTracker")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.gray)
            }

            Spacer()

            // Session dots
            HStack(spacing: 4) {
                ForEach(0..<entry.targetSessions, id: \.self) { i in
                    Circle()
                        .fill(i < entry.sessionsThisWeek ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 12, height: 12)
                }
            }

            Text("\(entry.sessionsThisWeek)/\(entry.targetSessions) this week")
                .font(.system(size: 11))
                .foregroundColor(.gray)

            Spacer()

            Text(entry.nextWorkoutType)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.green)
            Text("\(entry.nextWorkoutDuration) min")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
        }
        .padding(12)
        .containerBackground(.black, for: .widget)
    }

    // MARK: - Medium Widget

    private var mediumWidget: some View {
        HStack(spacing: 16) {
            // Left: progress
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.focus)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("Week \(entry.weekNumber)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.green)

                Spacer()

                HStack(spacing: 4) {
                    ForEach(0..<entry.targetSessions, id: \.self) { i in
                        Circle()
                            .fill(i < entry.sessionsThisWeek ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 14, height: 14)
                    }
                }
                Text("\(entry.sessionsThisWeek)/\(entry.targetSessions) sessions")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            Divider()
                .background(Color.gray.opacity(0.3))

            // Right: next workout
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT WORKOUT")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.gray)
                    .kerning(1)

                Spacer()

                Text(entry.nextWorkoutType)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                Text("\(entry.nextWorkoutDuration) min")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                Text("Open to start")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .containerBackground(.black, for: .widget)
    }

    // MARK: - Lock Screen Circular

    private var circularWidget: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Text("\(entry.sessionsThisWeek)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("/\(entry.targetSessions)")
                    .font(.system(size: 10, design: .monospaced))
            }
        }
    }

    // MARK: - Lock Screen Rectangular

    private var rectangularWidget: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                Text(entry.focus)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            Text("\(entry.sessionsThisWeek)/\(entry.targetSessions) sessions · \(entry.nextWorkoutType) next")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Widget Configuration

@main
struct ZoneTrackerWidget: Widget {
    let kind = "ZoneTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ZoneTrackerProvider()) { entry in
            ZoneTrackerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("ZoneTracker")
        .description("See your weekly progress and next workout at a glance.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}
