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
        if let height = HKQuantityType.quantityType(forIdentifier: .height) { types.insert(height) }
        if let bodyMass = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(bodyMass) }
        types.insert(HKObjectType.characteristicType(forIdentifier: .biologicalSex)!)
        types.insert(HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!)
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

    // MARK: - User Characteristics

    struct UserCharacteristics {
        var age: Int?
        var weightLbs: Double?
        var heightInches: Double?
        var biologicalSex: String? // "male", "female", "other"
    }

    func fetchUserCharacteristics() async -> UserCharacteristics {
        var result = UserCharacteristics()

        // Biological sex
        if let sex = try? healthStore.biologicalSex().biologicalSex {
            switch sex {
            case .male: result.biologicalSex = "male"
            case .female: result.biologicalSex = "female"
            case .other: result.biologicalSex = "other"
            default: break
            }
        }

        // Age from date of birth
        if let dob = try? healthStore.dateOfBirthComponents(),
           let birthDate = Calendar.current.date(from: dob) {
            let ageComponents = Calendar.current.dateComponents([.year], from: birthDate, to: Date())
            result.age = ageComponents.year
        }

        // Height (most recent sample)
        if let heightType = HKQuantityType.quantityType(forIdentifier: .height) {
            result.heightInches = await fetchMostRecentQuantity(type: heightType, unit: .inch())
        }

        // Weight (most recent sample)
        if let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            result.weightLbs = await fetchMostRecentQuantity(type: bodyMassType, unit: .pound())
        }

        return result
    }

    private func fetchMostRecentQuantity(type: HKQuantityType, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-codex-seed-sample-data") {
            return Self.debugRestingHeartRate(days: days)
        }
        #endif

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

    #if DEBUG
    nonisolated private static func debugRestingHeartRate(days: Int) -> [(date: Date, bpm: Int)] {
        let baseline = [61, 61, 60, 60, 59, 59, 58, 58, 57, 57, 56, 56]
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let step = max(1, days / max(baseline.count - 1, 1))

        return baseline.enumerated().map { index, bpm in
            let date = Calendar.current.date(byAdding: .day, value: index * step, to: start) ?? start
            return (date: date, bpm: bpm)
        }
    }
    #endif

    // MARK: - Write Workout

    func saveWorkout(entry: WorkoutEntry) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(for: entry.exerciseType)
        configuration.locationType = Self.locationType(for: entry.exerciseType)

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: nil
        )
        let startDate = entry.date.addingTimeInterval(-entry.duration)

        try await beginCollection(for: builder, at: startDate)
        try await addMetadata(
            [
                "ZoneTracker": true,
                HKMetadataKeyIndoorWorkout: entry.exerciseType == .treadmill
            ],
            to: builder
        )
        try await endCollection(for: builder, at: entry.date)
        _ = try await finishWorkout(for: builder)
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

                let exerciseType = Self.mapActivityType(
                    workout.workoutActivityType,
                    metadata: workout.metadata
                )
                continuation.resume(returning: (start: workout.startDate, end: workout.endDate, type: exerciseType))
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Helpers

    nonisolated private static func activityType(for exerciseType: ExerciseType) -> HKWorkoutActivityType {
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

    nonisolated private static func locationType(for exerciseType: ExerciseType) -> HKWorkoutSessionLocationType {
        switch exerciseType {
        case .treadmill:
            return .indoor
        case .outdoorRun, .rucking:
            return .outdoor
        default:
            return .unknown
        }
    }

    nonisolated private static func mapActivityType(
        _ type: HKWorkoutActivityType,
        metadata: [String: Any]? = nil
    ) -> ExerciseType {
        switch type {
        case .running:
            if let indoor = metadata?[HKMetadataKeyIndoorWorkout] as? Bool, indoor {
                return .treadmill
            }
            return .outdoorRun
        case .walking:
            return .outdoorRun
        case .elliptical: return .elliptical
        case .stairClimbing: return .stairClimber
        case .cycling: return .bike
        case .rowing: return .rowing
        case .hiking: return .rucking
        default: return .treadmill
        }
    }

    private func beginCollection(for builder: HKWorkoutBuilder, at startDate: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: startDate) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "ZoneTracker.HealthKit", code: 1))
                }
            }
        }
    }

    private func addMetadata(_ metadata: [String: Any], to builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.addMetadata(metadata) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "ZoneTracker.HealthKit", code: 2))
                }
            }
        }
    }

    private func endCollection(for builder: HKWorkoutBuilder, at endDate: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: endDate) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "ZoneTracker.HealthKit", code: 3))
                }
            }
        }
    }

    private func finishWorkout(for builder: HKWorkoutBuilder) async throws -> HKWorkout {
        try await withCheckedThrowingContinuation { continuation in
            builder.finishWorkout { workout, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let workout {
                    continuation.resume(returning: workout)
                } else {
                    continuation.resume(throwing: NSError(domain: "ZoneTracker.HealthKit", code: 4))
                }
            }
        }
    }
}
