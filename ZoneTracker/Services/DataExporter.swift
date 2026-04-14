import Foundation

// MARK: - Data Exporter

struct DataExporter {

    /// Export workouts to CSV format.
    static func exportCSV(workouts: [WorkoutEntry]) -> String {
        var lines: [String] = []

        // Header
        lines.append("Date,Exercise,Session Type,Duration (min),Avg HR,Max HR,Min HR,Target Zone Time (min),HR Drift %,Recovery HR,RPE,Focus,Week,Notes")

        // Rows
        let sorted = workouts.sorted { $0.date < $1.date }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        for entry in sorted {
            let hr = entry.heartRateData
            let fields: [String] = [
                formatter.string(from: entry.date),
                entry.exerciseType.displayName,
                entry.sessionType.displayName,
                "\(entry.durationMinutes)",
                "\(hr.avgHR)",
                "\(hr.maxHR)",
                "\(hr.minHR)",
                "\(Int(hr.timeInZone2 / 60))",
                String(format: "%.1f", hr.hrDrift),
                hr.recoveryHR.map { "\($0)" } ?? "",
                entry.rpe.map { "\($0)" } ?? "",
                entry.focus.displayName,
                "\(entry.weekNumber)",
                escapeCSV(entry.notes ?? "")
            ]
            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    /// Generate a temporary file URL for sharing.
    static func writeToTempFile(csv: String) -> URL? {
        let filename = "ZoneTracker_Export_\(dateStamp()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Export write failed: \(error)")
            return nil
        }
    }

    private static func escapeCSV(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return text
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
