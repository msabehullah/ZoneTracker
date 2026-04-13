import Foundation
import SwiftData

#if DEBUG
@MainActor
enum SampleDataSeeder {
    static let launchArgument = "-codex-seed-sample-data"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func seedIfRequested(context: ModelContext, accountIdentifier: String?) {
        guard isEnabled else { return }

        let profileDescriptor = FetchDescriptor<UserProfile>()
        let workoutDescriptor = FetchDescriptor<WorkoutEntry>(
            sortBy: [SortDescriptor(\WorkoutEntry.date, order: .reverse)]
        )

        let profiles = (try? context.fetch(profileDescriptor)) ?? []
        let workouts = (try? context.fetch(workoutDescriptor)) ?? []

        let profile = profiles.first ?? UserProfile(accountIdentifier: accountIdentifier)
        if profiles.isEmpty {
            context.insert(profile)
        }

        for extraProfile in profiles.dropFirst() {
            context.delete(extraProfile)
        }

        for workout in workouts {
            context.delete(workout)
        }

        configure(profile: profile, accountIdentifier: accountIdentifier)

        for workout in makeWorkouts(accountIdentifier: accountIdentifier) {
            context.insert(workout)
        }

        try? context.save()
    }

    private static func configure(profile: UserProfile, accountIdentifier: String?) {
        profile.accountIdentifier = accountIdentifier
        profile.age = 34
        profile.maxHR = 186
        profile.weight = 172
        profile.height = 70
        profile.phase = .phase2
        profile.phaseStartDate = Date().weeksAgo(4)
        profile.hasCompletedOnboarding = true
        profile.zone2TargetLow = 132
        profile.zone2TargetHigh = 148
        profile.legDays = [6]
        profile.coachingHapticsEnabled = true
        profile.coachingAlertCooldownSeconds = 18
    }

    private static func makeWorkouts(accountIdentifier: String?) -> [WorkoutEntry] {
        [
            makeZone2Workout(
                daysAgo: 59,
                durationMinutes: 32,
                speed: 3.2,
                incline: 2.0,
                avgHR: 134,
                maxHR: 142,
                minHR: 118,
                zone2Minutes: 21,
                drift: 5.1,
                recovery: 20,
                phase: .phase1,
                weekNumber: 1,
                accountIdentifier: accountIdentifier
            ),
            makeZone2Workout(
                daysAgo: 52,
                durationMinutes: 36,
                speed: 3.4,
                incline: 2.5,
                avgHR: 136,
                maxHR: 145,
                minHR: 120,
                zone2Minutes: 25,
                drift: 4.4,
                recovery: 21,
                phase: .phase1,
                weekNumber: 2,
                accountIdentifier: accountIdentifier
            ),
            makeBenchmarkWorkout(
                daysAgo: 47,
                mileSeconds: 572,
                avgHR: 164,
                maxHR: 173,
                recovery: 24,
                phase: .phase1,
                weekNumber: 3,
                accountIdentifier: accountIdentifier
            ),
            makeZone2Workout(
                daysAgo: 41,
                durationMinutes: 40,
                speed: 3.7,
                incline: 3.0,
                avgHR: 139,
                maxHR: 147,
                minHR: 123,
                zone2Minutes: 31,
                drift: 4.0,
                recovery: 23,
                phase: .phase1,
                weekNumber: 4,
                accountIdentifier: accountIdentifier
            ),
            makeCrossTrainingWorkout(
                daysAgo: 34,
                exerciseType: .bike,
                durationMinutes: 42,
                avgHR: 141,
                maxHR: 149,
                minHR: 122,
                recovery: 24,
                phase: .phase1,
                weekNumber: 5,
                metrics: ["resistance": 9, "cadence": 79],
                accountIdentifier: accountIdentifier
            ),
            makeIntervalWorkout(
                daysAgo: 27,
                sessionType: .interval_30_30,
                durationMinutes: 34,
                avgHR: 156,
                maxHR: 176,
                minHR: 122,
                recovery: 29,
                phase: .phase2,
                weekNumber: 1,
                metrics: ["speed": 5.6, "incline": 1.5],
                accountIdentifier: accountIdentifier
            ),
            makeZone2Workout(
                daysAgo: 20,
                durationMinutes: 45,
                speed: 3.9,
                incline: 3.0,
                avgHR: 142,
                maxHR: 149,
                minHR: 124,
                zone2Minutes: 36,
                drift: 3.9,
                recovery: 25,
                phase: .phase2,
                weekNumber: 2,
                accountIdentifier: accountIdentifier
            ),
            makeBenchmarkWorkout(
                daysAgo: 15,
                mileSeconds: 534,
                avgHR: 168,
                maxHR: 178,
                recovery: 26,
                phase: .phase2,
                weekNumber: 3,
                accountIdentifier: accountIdentifier
            ),
            makeZone2Workout(
                daysAgo: 10,
                durationMinutes: 50,
                speed: 4.1,
                incline: 3.5,
                avgHR: 144,
                maxHR: 151,
                minHR: 126,
                zone2Minutes: 41,
                drift: 3.4,
                recovery: 27,
                phase: .phase2,
                weekNumber: 4,
                accountIdentifier: accountIdentifier
            ),
            makeZone2Workout(
                daysAgo: 4,
                durationMinutes: 52,
                speed: 4.2,
                incline: 3.5,
                avgHR: 145,
                maxHR: 152,
                minHR: 127,
                zone2Minutes: 43,
                drift: 3.2,
                recovery: 28,
                phase: .phase2,
                weekNumber: 5,
                accountIdentifier: accountIdentifier
            ),
            makeZone2Workout(
                daysAgo: 0,
                durationMinutes: 55,
                speed: 4.3,
                incline: 4.0,
                avgHR: 146,
                maxHR: 154,
                minHR: 128,
                zone2Minutes: 46,
                drift: 2.9,
                recovery: 29,
                phase: .phase2,
                weekNumber: 5,
                accountIdentifier: accountIdentifier
            )
        ]
    }

    private static func makeZone2Workout(
        daysAgo: Int,
        durationMinutes: Int,
        speed: Double,
        incline: Double,
        avgHR: Int,
        maxHR: Int,
        minHR: Int,
        zone2Minutes: Int,
        drift: Double,
        recovery: Int,
        phase: TrainingPhase,
        weekNumber: Int,
        accountIdentifier: String?
    ) -> WorkoutEntry {
        let end = workoutEndDate(daysAgo: daysAgo)
        let duration = TimeInterval(durationMinutes * 60)
        let hrData = HeartRateData(
            avgHR: avgHR,
            maxHR: maxHR,
            minHR: minHR,
            timeInZone2: TimeInterval(zone2Minutes * 60),
            timeInZone4Plus: 0,
            hrDrift: drift,
            recoveryHR: recovery,
            samples: steadySamples(end: end, duration: duration, values: [
                minHR, avgHR - 5, avgHR - 2, avgHR, avgHR + 1,
                avgHR, avgHR + 2, avgHR + 1, maxHR - 1, avgHR
            ])
        )

        return WorkoutEntry(
            accountIdentifier: accountIdentifier,
            source: .manualEntry,
            date: end,
            exerciseType: .treadmill,
            duration: duration,
            metrics: ["speed": speed, "incline": incline],
            sessionType: .zone2,
            heartRateData: hrData,
            phase: phase,
            weekNumber: weekNumber,
            rpe: 5,
            notes: "Held a smooth conversational pace.",
            intervalProtocol: nil
        )
    }

    private static func makeBenchmarkWorkout(
        daysAgo: Int,
        mileSeconds: Int,
        avgHR: Int,
        maxHR: Int,
        recovery: Int,
        phase: TrainingPhase,
        weekNumber: Int,
        accountIdentifier: String?
    ) -> WorkoutEntry {
        let end = workoutEndDate(daysAgo: daysAgo)
        let duration = TimeInterval(mileSeconds)
        let hrData = HeartRateData(
            avgHR: avgHR,
            maxHR: maxHR,
            minHR: avgHR - 20,
            timeInZone2: 0,
            timeInZone4Plus: max(0, duration - 120),
            hrDrift: 7.5,
            recoveryHR: recovery,
            samples: steadySamples(end: end, duration: duration, values: [
                avgHR - 18, avgHR - 10, avgHR - 3, avgHR + 2, maxHR
            ])
        )

        return WorkoutEntry(
            accountIdentifier: accountIdentifier,
            source: .manualEntry,
            date: end,
            exerciseType: .outdoorRun,
            duration: duration,
            metrics: ["pace": Double(mileSeconds) / 60.0],
            sessionType: .benchmark_mile,
            heartRateData: hrData,
            phase: phase,
            weekNumber: weekNumber,
            rpe: 8,
            notes: "Strong finish on the final quarter mile.",
            intervalProtocol: nil
        )
    }

    private static func makeIntervalWorkout(
        daysAgo: Int,
        sessionType: SessionType,
        durationMinutes: Int,
        avgHR: Int,
        maxHR: Int,
        minHR: Int,
        recovery: Int,
        phase: TrainingPhase,
        weekNumber: Int,
        metrics: [String: Double],
        accountIdentifier: String?
    ) -> WorkoutEntry {
        let end = workoutEndDate(daysAgo: daysAgo)
        let duration = TimeInterval(durationMinutes * 60)
        let protocolTemplate = sessionType.defaultIntervalProtocol
        let values = [128, 140, 156, 171, 138, 174, 142, maxHR, 144, 166, 139]
        let hrData = HeartRateData(
            avgHR: avgHR,
            maxHR: maxHR,
            minHR: minHR,
            timeInZone2: 9 * 60,
            timeInZone4Plus: 12 * 60,
            hrDrift: 6.2,
            recoveryHR: recovery,
            samples: steadySamples(end: end, duration: duration, values: values)
        )

        return WorkoutEntry(
            accountIdentifier: accountIdentifier,
            source: .manualEntry,
            date: end,
            exerciseType: .treadmill,
            duration: duration,
            metrics: metrics,
            sessionType: sessionType,
            heartRateData: hrData,
            phase: phase,
            weekNumber: weekNumber,
            rpe: 7,
            notes: "Intervals stayed controlled and repeatable.",
            intervalProtocol: protocolTemplate
        )
    }

    private static func makeCrossTrainingWorkout(
        daysAgo: Int,
        exerciseType: ExerciseType,
        durationMinutes: Int,
        avgHR: Int,
        maxHR: Int,
        minHR: Int,
        recovery: Int,
        phase: TrainingPhase,
        weekNumber: Int,
        metrics: [String: Double],
        accountIdentifier: String?
    ) -> WorkoutEntry {
        let end = workoutEndDate(daysAgo: daysAgo)
        let duration = TimeInterval(durationMinutes * 60)
        let hrData = HeartRateData(
            avgHR: avgHR,
            maxHR: maxHR,
            minHR: minHR,
            timeInZone2: duration * 0.72,
            timeInZone4Plus: 0,
            hrDrift: 4.9,
            recoveryHR: recovery,
            samples: steadySamples(end: end, duration: duration, values: [
                minHR, avgHR - 4, avgHR - 1, avgHR, avgHR + 2, maxHR - 1, avgHR
            ])
        )

        return WorkoutEntry(
            accountIdentifier: accountIdentifier,
            source: .manualEntry,
            date: end,
            exerciseType: exerciseType,
            duration: duration,
            metrics: metrics,
            sessionType: .zone2,
            heartRateData: hrData,
            phase: phase,
            weekNumber: weekNumber,
            rpe: 5,
            notes: "Easy aerobic cross-training day.",
            intervalProtocol: nil
        )
    }

    private static func workoutEndDate(daysAgo: Int) -> Date {
        Calendar.current.date(
            bySettingHour: 7,
            minute: 30,
            second: 0,
            of: Date().daysAgo(daysAgo)
        ) ?? Date().daysAgo(daysAgo)
    }

    private static func steadySamples(end: Date, duration: TimeInterval, values: [Int]) -> [HRSample] {
        guard !values.isEmpty else { return [] }
        let start = end.addingTimeInterval(-duration)
        let step = duration / Double(max(values.count - 1, 1))
        return values.enumerated().map { index, value in
            HRSample(
                timestamp: start.addingTimeInterval(Double(index) * step),
                bpm: value
            )
        }
    }
}
#endif
