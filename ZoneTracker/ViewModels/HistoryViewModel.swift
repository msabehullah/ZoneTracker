import Foundation
import SwiftData

// MARK: - History ViewModel

@MainActor
@Observable
class HistoryViewModel {
    var groupedWorkouts: [(weekStart: Date, entries: [WorkoutEntry])] = []
    var selectedWorkout: WorkoutEntry?

    func load(workouts: [WorkoutEntry]) {
        groupedWorkouts = workouts.groupedByWeek()
    }

    func weekLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: date) ?? date
        return "Week of \(formatter.string(from: date)) – \(formatter.string(from: end))"
    }

    func deleteWorkout(_ workout: WorkoutEntry, context: ModelContext) {
        context.delete(workout)
        // Refresh grouping
        groupedWorkouts = groupedWorkouts.map { group in
            (weekStart: group.weekStart, entries: group.entries.filter { $0.id != workout.id })
        }.filter { !$0.entries.isEmpty }
    }
}
