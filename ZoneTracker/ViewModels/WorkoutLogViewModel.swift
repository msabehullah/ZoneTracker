import Foundation
import SwiftData

// MARK: - Workout Log ViewModel

@MainActor
@Observable
class WorkoutLogViewModel {
    var selectedExercise: ExerciseType = .treadmill
    var selectedSession: SessionType = .zone2
    var duration: TimeInterval = 30 * 60 // 30 min default
    var metrics: [String: Double] = [:]
    var rpe: Int? = nil
    var notes: String = ""
    var heartRateData: HeartRateData = .empty
    var intervalProtocol: IntervalProtocol? = nil

    var isImportingFromWatch = false
    var importError: String?
    var showingResult = false
    var resultRecommendation: WorkoutRecommendation?
    private var didImportFromHealthKit = false

    private let healthKit = HealthKitManager.shared

    // MARK: - Initialize

    func setupFromRecommendation(_ rec: WorkoutRecommendation) {
        selectedExercise = rec.exerciseType
        selectedSession = rec.sessionType
        duration = rec.targetDuration
        metrics = rec.suggestedMetrics
        intervalProtocol = rec.intervalProtocol
        didImportFromHealthKit = false
    }

    func resetMetricsToDefaults() {
        metrics = [:]
        for def in selectedExercise.metricDefinitions {
            metrics[def.key] = def.defaultValue
        }
        if selectedSession.isInterval {
            intervalProtocol = selectedSession.defaultIntervalProtocol
        } else {
            intervalProtocol = nil
        }
        didImportFromHealthKit = false
    }

    func onExerciseTypeChanged(from oldType: ExerciseType) {
        if !metrics.isEmpty {
            metrics = RecommendationEngine.translateMetrics(
                from: oldType, to: selectedExercise, metrics: metrics
            )
        } else {
            resetMetricsToDefaults()
        }
    }

    // MARK: - Duration Helpers

    var durationMinutes: Int {
        get { Int(duration / 60) }
        set { duration = TimeInterval(newValue) * 60 }
    }

    // MARK: - Import from Apple Watch

    func importFromWatch(profile: UserProfile) async {
        isImportingFromWatch = true
        importError = nil

        do {
            guard let latest = try await healthKit.fetchLatestWorkout() else {
                importError = "No recent workout found in HealthKit."
                isImportingFromWatch = false
                return
            }

            selectedExercise = latest.type
            duration = latest.end.timeIntervalSince(latest.start)

            let hrData = try await healthKit.fetchWorkoutHeartRateData(
                from: latest.start, to: latest.end, profile: profile
            )
            heartRateData = hrData
            didImportFromHealthKit = true
        } catch {
            importError = "Failed to import: \(error.localizedDescription)"
        }

        isImportingFromWatch = false
    }

    // MARK: - Save Workout

    func saveWorkout(
        profile: UserProfile,
        context: ModelContext,
        allWorkouts: [WorkoutEntry]
    ) -> WorkoutRecommendation? {
        let entry = WorkoutEntry(
            accountIdentifier: profile.accountIdentifier,
            date: Date(),
            exerciseType: selectedExercise,
            duration: duration,
            metrics: metrics,
            sessionType: selectedSession,
            heartRateData: heartRateData,
            phase: profile.phase,
            weekNumber: profile.weekNumber,
            rpe: rpe,
            notes: notes.isEmpty ? nil : notes,
            intervalProtocol: intervalProtocol
        )
        entry.source = didImportFromHealthKit ? .healthKitImport : .manualEntry

        context.insert(entry)

        // Check for phase transition
        var updatedWorkouts = allWorkouts
        updatedWorkouts.append(entry)

        if PhaseManager.evaluatePhaseTransition(
            profile: profile, workouts: updatedWorkouts
        ) != nil {
            profile.advancePhase()
            // The transition message will be shown via the dashboard
        }

        // Generate next recommendation
        let recommendation = RecommendationEngine.recommend(
            profile: profile, workouts: updatedWorkouts
        )
        resultRecommendation = recommendation
        showingResult = true

        return recommendation
    }

    // MARK: - Available Session Types

    var availableSessionTypes: [SessionType] {
        SessionType.allCases.filter { _ in true } // All types available for manual entry
    }
}
