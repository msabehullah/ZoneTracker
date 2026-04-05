import Foundation
import SwiftUI

// MARK: - Date Extensions

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var startOfWeek: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }

    var weekday: Int {
        Calendar.current.component(.weekday, from: self)
    }

    func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: self) ?? self
    }

    func weeksAgo(_ weeks: Int) -> Date {
        Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: self) ?? self
    }

    var relativeDescription: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: self)
    }

    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: self)
    }

    var fullDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    var minutesAndSeconds: String {
        let totalSeconds = Int(self)
        let min = totalSeconds / 60
        let sec = totalSeconds % 60
        return String(format: "%d:%02d", min, sec)
    }

    var formattedDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }
}

// MARK: - Int Extensions

extension Int {
    var bpmFormatted: String { "\(self) bpm" }
}

// MARK: - View Extensions

extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(16)
    }

    func monospaced() -> some View {
        self.font(.system(.body, design: .monospaced))
    }
}

// MARK: - Color Extensions

extension Color {
    static let appBackground = Color.black
    static let cardBackground = Color(white: 0.12)
    static let cardBorder = Color(white: 0.2)
    static let accentGreen = Color.green
    static let zone2Green = Color(red: 0.2, green: 0.8, blue: 0.4)
    static let zone4Orange = Color(red: 1.0, green: 0.6, blue: 0.2)
}

// MARK: - Array Extensions

extension Array where Element == WorkoutEntry {
    func inCurrentWeek() -> [WorkoutEntry] {
        let startOfWeek = Date().startOfWeek
        return filter { $0.date >= startOfWeek }
    }

    func inPhase(_ phase: TrainingPhase) -> [WorkoutEntry] {
        filter { $0.phase == phase }
    }

    func zone2Sessions() -> [WorkoutEntry] {
        filter { $0.sessionType == .zone2 }
    }

    func intervalSessions() -> [WorkoutEntry] {
        filter { $0.sessionType.isInterval }
    }

    func sortedByDate() -> [WorkoutEntry] {
        sorted { $0.date > $1.date }
    }

    func groupedByWeek() -> [(weekStart: Date, entries: [WorkoutEntry])] {
        let grouped = Dictionary(grouping: self) { $0.date.startOfWeek }
        return grouped
            .map { (weekStart: $0.key, entries: $0.value.sortedByDate()) }
            .sorted { $0.weekStart > $1.weekStart }
    }
}
