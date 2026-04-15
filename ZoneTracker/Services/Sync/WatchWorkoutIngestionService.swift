import Foundation
import SwiftData

enum WatchWorkoutIngestionService {
    @MainActor
    static func ingest(
        completion payload: WorkoutCompletionPayload,
        profile: UserProfile,
        context: ModelContext,
        existingWorkouts: [WorkoutEntry]
    ) -> WorkoutEntry? {
        if existingWorkouts.contains(where: { $0.completionIdentifier == payload.id }) {
            return nil
        }

        let workout = WorkoutEntry(
            accountIdentifier: payload.accountIdentifier ?? profile.accountIdentifier,
            completionIdentifier: payload.id,
            planIdentifier: payload.planIdentifier,
            recommendationIdentifier: payload.recommendationIdentifier,
            source: payload.planIdentifier == nil ? .watchFreeWorkout : .watchPlanned,
            date: payload.endedAt,
            exerciseType: payload.exerciseType,
            duration: payload.duration,
            metrics: buildMetrics(payload: payload),
            sessionType: payload.sessionType,
            heartRateData: payload.heartRateData,
            phase: profile.phase,
            focus: profile.focus,
            weekNumber: profile.weekNumber,
            rpe: nil,
            notes: payload.notes,
            intervalProtocol: payload.intervalProtocol
        )

        context.insert(workout)

        // Explicit save — watch completions were inserting into the context
        // but SwiftData's autosave was not flushing reliably before the
        // next app suspension, so freshly-received workouts occasionally
        // didn't survive cold relaunch.
        do {
            try context.save()
        } catch {
            print("Watch workout ingest failed to persist: \(error)")
        }

        return workout
    }

    /// Copies the meaningful numeric fields off the payload into the metrics
    /// dict so the phone UI (progress, history, adherence) has real data
    /// rather than zeros. Keys are stable strings the rest of the app reads.
    private static func buildMetrics(payload: WorkoutCompletionPayload) -> [String: Double] {
        var metrics: [String: Double] = [:]
        metrics["calories"] = payload.calories
        metrics["distanceMeters"] = payload.distanceMeters
        metrics["timeInTarget"] = payload.timeInTarget
        metrics["completedSegments"] = Double(payload.completedSegments)
        metrics["plannedSegments"] = Double(payload.plannedSegments)
        return metrics
    }
}
