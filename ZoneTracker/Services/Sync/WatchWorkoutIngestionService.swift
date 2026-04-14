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
            metrics: [:],
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
        return workout
    }
}
