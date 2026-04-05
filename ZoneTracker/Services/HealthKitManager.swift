import Foundation
import HealthKit

// MARK: - HealthKit Manager

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    @Published var isAuthorized = false
    @Published var restingHeartRate: Int?

    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
        if let rhr = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) { types.insert(rhr) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(distance) }
        types.insert(HKObjectType.workoutType())
        return types
    }()

    private let writeTypes: Set<HKSampleType> = {
        var types = Set<HKSampleType>()
        types.insert(HKObjectType.workoutType())
        return types
    }()

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
        isAuthorized = true
    }

    // MARK: - Heart Rate Queries

    /// Fetch HR samples within a time window
    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HRSample] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let hrSamples = (samples as? [HKQuantitySample])?.map { sample in
                    HRSample(
                        timestamp: sample.startDate,
                        bpm: Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
                    )
                } ?? []

                continuation.resume(returning: hrSamples)
            }
            healthStore.execute(query)
        }
    }

    /// Build HeartRateData from raw samples for a workout
    func fetchWorkoutHeartRateData(from start: Date, to end: Date, profile: UserProfile) async throws -> HeartRateData {
        let samples = try await fetchHeartRateSamples(from: start, to: end)
        guard !samples.isEmpty else { return .empty }

        let bpms = samples.map(\.bpm)
        let avgHR = bpms.reduce(0, +) / bpms.count
        let maxHR = bpms.max() ?? 0
        let minHR = bpms.min() ?? 0

        let calculator = HRZoneCalculator(profile: profile)
        let zoneTime = calculator.timeInZones(samples: samples)
        let timeInZ2 = zoneTime[.zone2] ?? 0
        let timeInZ4Plus = (zoneTime[.zone4] ?? 0) + (zoneTime[.zone5] ?? 0)

        let drift = HRZoneCalculator.calculateDrift(samples: samples)

        // Recovery HR: samples from 1 min after workout end
        let recoveryEnd = end.addingTimeInterval(90)
        let recoverySamples = try await fetchHeartRateSamples(from: end, to: recoveryEnd)
        let recoveryHR: Int? = if let lastWorkoutHR = samples.last?.bpm,
                                   let oneMinLater = recoverySamples.last?.bpm {
            lastWorkoutHR - oneMinLater
        } else {
            nil
        }

        return HeartRateData(
            avgHR: avgHR,
            maxHR: maxHR,
            minHR: minHR,
            timeInZone2: timeInZ2,
            timeInZone4Plus: timeInZ4Plus,
            hrDrift: drift,
            recoveryHR: recoveryHR,
            samples: samples
        )
    }

    // MARK: - Resting Heart Rate

    func fetchRestingHeartRate(days: Int = 30) async throws -> [(date: Date, bpm: Int)] {
        guard let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return [] }

        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: rhrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let results = (samples as? [HKQuantitySample])?.map { sample in
                    (date: sample.startDate, bpm: Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))))
                } ?? []

                continuation.resume(returning: results)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Write Workout

    func saveWorkout(entry: WorkoutEntry) async throws {
        let workoutConfig = HKWorkoutConfiguration()
        workoutConfig.activityType = activityType(for: entry.exerciseType)

        let workout = HKWorkout(
            activityType: activityType(for: entry.exerciseType),
            start: entry.date.addingTimeInterval(-entry.duration),
            end: entry.date,
            duration: entry.duration,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: ["ZoneTracker": true]
        )

        try await healthStore.save(workout)
    }

    // MARK: - Latest Workout

    func fetchLatestWorkout() async throws -> (start: Date, end: Date, type: ExerciseType)? {
        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let workout = samples?.first as? HKWorkout else {
                    continuation.resume(returning: nil)
                    return
                }

                let exerciseType = self.mapActivityType(workout.workoutActivityType)
                continuation.resume(returning: (start: workout.startDate, end: workout.endDate, type: exerciseType))
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Helpers

    private func activityType(for exerciseType: ExerciseType) -> HKWorkoutActivityType {
        switch exerciseType {
        case .treadmill: return .running
        case .elliptical: return .elliptical
        case .stairClimber: return .stairClimbing
        case .bike: return .cycling
        case .rowing: return .rowing
        case .outdoorRun: return .running
        case .rucking: return .hiking
        }
    }

    private func mapActivityType(_ type: HKWorkoutActivityType) -> ExerciseType {
        switch type {
        case .running: return .treadmill
        case .elliptical: return .elliptical
        case .stairClimbing: return .stairClimber
        case .cycling: return .bike
        case .rowing: return .rowing
        case .hiking: return .rucking
        default: return .treadmill
        }
    }
}
