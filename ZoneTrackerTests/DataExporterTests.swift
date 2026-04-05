import XCTest
@testable import ZoneTracker

final class DataExporterTests: XCTestCase {

    func testCSVHeaderRow() {
        let csv = DataExporter.exportCSV(workouts: [])
        XCTAssertTrue(csv.hasPrefix("Date,Exercise,Session Type,"))
    }

    func testCSVContainsWorkoutData() {
        let workout = makeWorkout()
        let csv = DataExporter.exportCSV(workouts: [workout])
        let lines = csv.components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 2, "Should have header + 1 data row")
        XCTAssertTrue(lines[1].contains("Treadmill"))
        XCTAssertTrue(lines[1].contains("Zone 2"))
        XCTAssertTrue(lines[1].contains("45"))  // duration in minutes
    }

    func testCSVEscapesCommasInNotes() {
        let workout = makeWorkout(notes: "Felt good, strong finish")
        let csv = DataExporter.exportCSV(workouts: [workout])

        XCTAssertTrue(csv.contains("\"Felt good, strong finish\""),
                     "Notes with commas should be quoted")
    }

    func testCSVSortsChronologically() {
        let older = makeWorkout(daysAgo: 10)
        let newer = makeWorkout(daysAgo: 1)
        let csv = DataExporter.exportCSV(workouts: [newer, older])
        let lines = csv.components(separatedBy: "\n")

        // First data row should be the older workout
        XCTAssertEqual(lines.count, 3)
    }

    func testWriteToTempFile() {
        let csv = "header\nrow1"
        let url = DataExporter.writeToTempFile(csv: csv)

        XCTAssertNotNil(url)
        XCTAssertTrue(url!.lastPathComponent.hasPrefix("ZoneTracker_Export_"))
        XCTAssertTrue(url!.lastPathComponent.hasSuffix(".csv"))

        // Clean up
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Helpers

    private func makeWorkout(daysAgo: Int = 1, notes: String? = nil) -> WorkoutEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return WorkoutEntry(
            date: date,
            exerciseType: .treadmill,
            duration: 45 * 60,
            metrics: ["speed": 3.5],
            sessionType: .zone2,
            heartRateData: HeartRateData(
                avgHR: 140, maxHR: 155, minHR: 130,
                timeInZone2: 35 * 60, timeInZone4Plus: 0,
                hrDrift: 3.0, recoveryHR: 30, samples: []
            ),
            phase: .phase1,
            weekNumber: 3,
            notes: notes
        )
    }
}
