import Foundation
import HealthKit
import WatchKit
import Combine

@MainActor
class WatchWorkoutManager: NSObject, ObservableObject {
    let healthStore = HKHealthStore()

    // MARK: - Published State

    @Published var sessionState: HKWorkoutSessionState = .notStarted
    @Published var heartRate: Int = 0
    @Published var currentZone: Int = 1
    @Published var elapsedTime: TimeInterval = 0
    @Published var activeCalories: Double = 0
    @Published var averageHR: Int = 0
    @Published var maxHR: Int = 0
    @Published var timeInZone2: TimeInterval = 0

    // Summary data (populated on end)
    @Published var summaryAvgHR: Int = 0
    @Published var summaryMaxHR: Int = 0
    @Published var summaryCalories: Double = 0
    @Published var summaryDuration: TimeInterval = 0
    @Published var summaryTimeInZone2: TimeInterval = 0

    // MARK: - Internal State

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var timerCancellable: AnyCancellable?
    private var startDate: Date?

    // HR tracking
    private var hrSamples: [Int] = []
    private var lastZoneChangeTime: Date?
    private var zone2Accumulator: TimeInterval = 0

    // Zone config — synced from phone or defaults
    var userMaxHR: Int = 189
    var zone2Low: Int = 130
    var zone2High: Int = 150

    // MARK: - Authorization

    func requestAuthorization() async {
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKObjectType.workoutType()
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        } catch {
            print("HealthKit auth failed: \(error)")
        }
    }

    // MARK: - Start Workout

    func startWorkout(activityType: HKWorkoutActivityType) async {
        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        config.locationType = activityType == .running ? .outdoor : .indoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            session?.delegate = self
            builder?.delegate = self

            let start = Date()
            session?.startActivity(with: start)
            try await builder?.beginCollection(at: start)

            startDate = start
            sessionState = .running
            lastZoneChangeTime = start
            startTimer()
        } catch {
            print("Failed to start workout: \(error)")
        }
    }

    // MARK: - Pause / Resume / End

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    func endWorkout() async {
        session?.end()

        guard let builder else { return }

        do {
            try await builder.endCollection(at: Date())
            let workout = try await builder.finishWorkout()

            summaryDuration = workout?.duration ?? elapsedTime
            summaryAvgHR = averageHR
            summaryMaxHR = maxHR
            summaryCalories = activeCalories
            summaryTimeInZone2 = zone2Accumulator
        } catch {
            print("Failed to end workout: \(error)")
        }

        timerCancellable?.cancel()
    }

    // MARK: - Timer

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.startDate else { return }
                Task { @MainActor in
                    self.elapsedTime = Date().timeIntervalSince(start)
                }
            }
    }

    // MARK: - Zone Calculation

    func zoneFor(bpm: Int) -> Int {
        if bpm < zone2Low { return 1 }
        if bpm <= zone2High { return 2 }
        let zone3Ceiling = Int(Double(userMaxHR) * 0.80)
        let zone4Ceiling = Int(Double(userMaxHR) * 0.90)
        if bpm <= zone3Ceiling { return 3 }
        if bpm <= zone4Ceiling { return 4 }
        return 5
    }

    func zoneColor(for zone: Int) -> String {
        switch zone {
        case 1: return "gray"
        case 2: return "green"
        case 3: return "yellow"
        case 4: return "orange"
        case 5: return "red"
        default: return "gray"
        }
    }

    func zoneName(for zone: Int) -> String {
        switch zone {
        case 1: return "Recovery"
        case 2: return "Aerobic"
        case 3: return "Tempo"
        case 4: return "Threshold"
        case 5: return "VO2 Max"
        default: return "—"
        }
    }

    // MARK: - Update Metrics

    fileprivate func updateHeartRate(_ bpm: Int) {
        let now = Date()
        let previousZone = currentZone
        heartRate = bpm
        currentZone = zoneFor(bpm: bpm)
        hrSamples.append(bpm)

        // Track zone 2 time
        if previousZone == 2, let last = lastZoneChangeTime {
            zone2Accumulator += now.timeIntervalSince(last)
        }
        if currentZone != previousZone {
            lastZoneChangeTime = now
        }
        timeInZone2 = zone2Accumulator + (currentZone == 2 ? now.timeIntervalSince(lastZoneChangeTime ?? now) : 0)

        // Running averages
        averageHR = hrSamples.reduce(0, +) / hrSamples.count
        maxHR = hrSamples.max() ?? bpm
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            self.sessionState = toState
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session error: \(error)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            let statistics = workoutBuilder.statistics(for: quantityType)

            Task { @MainActor in
                switch quantityType {
                case HKQuantityType(.heartRate):
                    let bpm = Int(statistics?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0)
                    if bpm > 0 {
                        self.updateHeartRate(bpm)
                    }
                case HKQuantityType(.activeEnergyBurned):
                    self.activeCalories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                default:
                    break
                }
            }
        }
    }
}
