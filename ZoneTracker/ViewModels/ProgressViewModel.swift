import Foundation

// MARK: - Progress ViewModel

@MainActor
@Observable
class ProgressViewModel {
    var restingHRHistory: [(date: Date, bpm: Int)] = []
    var paceInTargetHistory: [(date: Date, speed: Double)] = []
    var mileTimeHistory: [(date: Date, seconds: TimeInterval)] = []
    var recoveryHRHistory: [(date: Date, drop: Int)] = []
    var phaseTimeline: [(phase: TrainingPhase, startDate: Date, endDate: Date?)] = []

    private let healthKit = HealthKitManager.shared

    func load(workouts: [WorkoutEntry], profile: UserProfile) async {
        // Resting HR from HealthKit
        do {
            restingHRHistory = try await healthKit.fetchRestingHeartRate(days: 90)
        } catch {
            restingHRHistory = []
        }

        // Pace in the user's target range — from treadmill Zone 2 workouts
        paceInTargetHistory = workouts
            .filter { $0.exerciseType == .treadmill && $0.sessionType == .zone2 }
            .sorted { $0.date < $1.date }
            .compactMap { workout in
                let avgHR = workout.heartRateData.avgHR
                guard avgHR > 0,
                      let speed = workout.metrics["speed"],
                      profile.zone2Range.contains(avgHR) else {
                    return nil
                }
                return (date: workout.date, speed: speed)
            }

        // Mile benchmarks
        mileTimeHistory = workouts
            .filter { $0.sessionType == .benchmark_mile }
            .sorted { $0.date < $1.date }
            .map { (date: $0.date, seconds: $0.duration) }

        // Recovery HR
        recoveryHRHistory = workouts
            .sorted { $0.date < $1.date }
            .compactMap { workout in
                guard let recovery = workout.heartRateData.recoveryHR, recovery > 0 else { return nil }
                return (date: workout.date, drop: recovery)
            }

        // Build phase timeline
        buildPhaseTimeline(workouts: workouts, profile: profile)
    }

    private func buildPhaseTimeline(workouts: [WorkoutEntry], profile: UserProfile) {
        var timeline: [(phase: TrainingPhase, startDate: Date, endDate: Date?)] = []
        let sorted = workouts.sorted { $0.date < $1.date }

        var currentPhase: TrainingPhase?
        var phaseStart: Date?

        for workout in sorted {
            if workout.phase != currentPhase {
                // Close previous phase
                if let prev = currentPhase, let start = phaseStart {
                    timeline.append((phase: prev, startDate: start, endDate: workout.date))
                }
                currentPhase = workout.phase
                phaseStart = workout.date
            }
        }

        // Current open phase
        if let phase = currentPhase, let start = phaseStart {
            timeline.append((phase: phase, startDate: start, endDate: nil))
        } else if timeline.isEmpty {
            // No workouts yet — show current phase from profile
            timeline.append((phase: profile.phase, startDate: profile.phaseStartDate, endDate: nil))
        }

        phaseTimeline = timeline
    }

    // MARK: - Formatted Values

    func formattedMileTime(_ seconds: TimeInterval) -> String {
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return String(format: "%d:%02d", min, sec)
    }

    func formattedPace(_ speed: Double) -> String {
        guard speed > 0 else { return "—" }
        let paceMinutes = 60.0 / speed
        let min = Int(paceMinutes)
        let sec = Int((paceMinutes - Double(min)) * 60)
        return String(format: "%d:%02d /mi", min, sec)
    }
}
