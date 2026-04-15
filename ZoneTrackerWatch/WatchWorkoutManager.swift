import Combine
import Foundation
import HealthKit
import WatchKit

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    let healthStore = HKHealthStore()

    @Published var sessionState: HKWorkoutSessionState = .notStarted
    @Published var heartRate: Int = 0
    @Published var currentZone: Int = 1
    @Published var elapsedTime: TimeInterval = 0
    @Published var activeCalories: Double = 0
    @Published var averageHR: Int = 0
    @Published var maxHR: Int = 0
    @Published var timeInActiveTarget: TimeInterval = 0
    @Published var distanceMeters: Double = 0
    @Published var coachingPosition: HeartRateTargetPosition = .unavailable
    @Published var activeSegmentTitle: String = "Ready"
    @Published var activeTargetText: String = "—"
    @Published var workoutTitle: String = "Next Workout"
    @Published var activeExerciseType: ExerciseType = .treadmill

    @Published var summaryAvgHR: Int = 0
    @Published var summaryMaxHR: Int = 0
    @Published var summaryCalories: Double = 0
    @Published var summaryDuration: TimeInterval = 0
    @Published var summaryTimeInTarget: TimeInterval = 0
    @Published var summaryTargetLabel: String = "Time on Target"

    // Coaching display properties
    var coachingMessage: String {
        switch coachingPosition {
        case .belowTarget: return "Push Harder"
        case .inTarget: return "Perfect Pace"
        case .aboveTarget: return "Ease Up"
        case .unavailable: return "Warming Up"
        }
    }

    var zoneBadge: String {
        guard heartRate > 0 else { return "—" }
        return "Z\(currentZone)"
    }

    var adherencePercent: Int {
        guard elapsedTime > 0 else { return 0 }
        return min(100, Int((timeInActiveTarget / elapsedTime) * 100))
    }

    var formattedElapsed: String {
        elapsedTime.minutesAndSeconds
    }

    var formattedTimeOnTarget: String {
        timeInActiveTarget.minutesAndSeconds
    }

    // MARK: - Distance & Pace

    /// True when the active exercise type is one whose distance/pace are
    /// meaningful and tracked by HealthKit's distance quantity samples.
    var supportsDistance: Bool {
        switch activeExerciseType {
        case .treadmill, .outdoorRun, .rucking, .bike: return true
        case .elliptical, .stairClimber, .rowing, .swimming: return false
        }
    }

    /// Display-ready distance in miles (e.g., "1.24 mi"). Empty placeholder
    /// when the modality doesn't track distance or no samples have arrived yet.
    var formattedDistance: String {
        guard supportsDistance else { return "—" }
        let miles = distanceMeters / 1609.344
        if miles < 0.01 { return "0.00 mi" }
        return String(format: "%.2f mi", miles)
    }

    /// Display-ready average pace in min/mi for the session so far. Falls back
    /// to "—" when distance is too small to compute a stable pace, or when the
    /// modality doesn't support pace.
    var formattedPace: String {
        guard supportsDistance else { return "—" }
        let miles = distanceMeters / 1609.344
        // Need a meaningful sample before pace stabilizes.
        guard miles >= 0.05, elapsedTime > 10 else { return "—" }
        let secondsPerMile = elapsedTime / miles
        let minutes = Int(secondsPerMile) / 60
        let seconds = Int(secondsPerMile) % 60
        return String(format: "%d:%02d /mi", minutes, seconds)
    }

    /// Secondary live label used by views when pace doesn't apply (bike RPM
    /// would require a cadence sensor we don't read, so fall back to calories).
    var fallbackSecondaryLabel: String { "CAL" }
    var fallbackSecondaryValue: String { "\(Int(activeCalories))" }

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var timerCancellable: AnyCancellable?
    private var startDate: Date?
    private var activePlan: WorkoutExecutionPlan?
    private var companionProfile: WatchCompanionProfile?
    private var telemetry: WatchWorkoutTelemetry?
    private var coachingEngine = HeartRateCoachingEngine()
    private var lastSegmentIdentifier: String?
    /// Fires exactly once per session when the elapsed time first crosses the
    /// planned target duration. Reset in `resetSessionState`.
    private var workoutFinishedAlertFired: Bool = false

    func requestAuthorization() async {
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKObjectType.workoutType()
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        } catch {
            print("HealthKit auth failed: \(error)")
        }
    }

    func updateCompanionProfile(_ profile: WatchCompanionProfile?) {
        companionProfile = profile
    }

    func startPlannedWorkout(_ plan: WorkoutExecutionPlan) async {
        guard let companionProfile else { return }
        await start(plan: plan, companionProfile: companionProfile)
    }

    func startFreeWorkout(exerciseType: ExerciseType) async {
        guard let companionProfile else { return }
        let plan = makeFreeWorkoutPlan(exerciseType: exerciseType, companionProfile: companionProfile)
        await start(plan: plan, companionProfile: companionProfile)
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    func endWorkout() async {
        session?.end()

        guard let builder else { return }
        let endDate = Date()

        do {
            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()
            telemetry?.finalize(at: endDate, targetRange: currentTargetRange)
            publishSummary(workoutDuration: workout?.duration ?? elapsedTime, endDate: endDate)
            sendCompletionPayload(endDate: endDate)
        } catch {
            print("Failed to end workout: \(error)")
        }

        timerCancellable?.cancel()
    }

    private func start(
        plan: WorkoutExecutionPlan,
        companionProfile: WatchCompanionProfile
    ) async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType(for: plan.exerciseType)
        configuration.locationType = locationType(for: plan.exerciseType)

        resetSessionState(plan: plan, companionProfile: companionProfile)

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()
            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            session?.delegate = self
            builder?.delegate = self

            let startDate = Date()
            session?.startActivity(with: startDate)
            try await builder?.beginCollection(at: startDate)

            self.startDate = startDate
            sessionState = .running
            telemetry?.reset(startDate: startDate)
            updateActiveSegment(at: startDate)
            startTimer()
        } catch {
            print("Failed to start workout: \(error)")
        }
    }

    private func resetSessionState(
        plan: WorkoutExecutionPlan,
        companionProfile: WatchCompanionProfile
    ) {
        activePlan = plan
        self.companionProfile = companionProfile
        let classifier = HeartRateZoneClassifier(
            maxHeartRate: companionProfile.maxHeartRate,
            zone2Range: companionProfile.zone2Low...companionProfile.zone2High
        )
        telemetry = WatchWorkoutTelemetry(zoneClassifier: classifier)
        coachingEngine.reset()
        lastSegmentIdentifier = nil
        workoutFinishedAlertFired = false

        heartRate = 0
        currentZone = 1
        elapsedTime = 0
        activeCalories = 0
        averageHR = 0
        maxHR = 0
        timeInActiveTarget = 0
        distanceMeters = 0
        activeExerciseType = plan.exerciseType
        coachingPosition = .unavailable
        activeSegmentTitle = plan.segments.first?.title ?? plan.sessionType.displayName
        activeTargetText = plan.overallTargetRange.displayText
        workoutTitle = plan.sessionType.displayName

        summaryAvgHR = 0
        summaryMaxHR = 0
        summaryCalories = 0
        summaryDuration = 0
        summaryTimeInTarget = 0
        summaryTargetLabel = "On Target"
    }

    private func publishSummary(workoutDuration: TimeInterval, endDate: Date) {
        guard let telemetry else { return }
        let heartRateData = telemetry.makeHeartRateData()

        summaryDuration = workoutDuration
        summaryAvgHR = heartRateData.avgHR
        summaryMaxHR = heartRateData.maxHR
        summaryCalories = activeCalories
        summaryTimeInTarget = telemetry.timeInTarget
        summaryTargetLabel = "Time on Target"
    }

    private func sendCompletionPayload(endDate: Date) {
        guard let telemetry,
              let startDate else { return }

        let payload = WorkoutCompletionPayload(
            id: UUID().uuidString,
            planIdentifier: activePlan?.isFreeWorkout == true ? nil : activePlan?.id,
            recommendationIdentifier: activePlan?.recommendationIdentifier,
            accountIdentifier: activePlan?.accountIdentifier ?? companionProfile?.accountIdentifier,
            profileIdentifier: activePlan?.profileIdentifier ?? companionProfile?.profileIdentifier,
            startedAt: startDate,
            endedAt: endDate,
            sessionType: activePlan?.sessionType ?? .zone2,
            exerciseType: activePlan?.exerciseType ?? .treadmill,
            intervalProtocol: activePlan?.intervalProtocol,
            calories: activeCalories,
            heartRateData: telemetry.makeHeartRateData(),
            completedSegments: completedSegmentCount(at: endDate),
            plannedSegments: activePlan?.segments.count ?? 1,
            notes: activePlan?.isFreeWorkout == true ? "Free workout" : nil,
            distanceMeters: distanceMeters,
            timeInTarget: telemetry.timeInTarget
        )
        WatchConnectivityManager.shared.sendWorkoutCompletion(payload)
    }

    private func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] currentDate in
                guard let self, let startDate = self.startDate else { return }
                self.elapsedTime = currentDate.timeIntervalSince(startDate)
                self.telemetry?.advance(to: currentDate, targetRange: self.currentTargetRange)
                self.timeInActiveTarget = self.telemetry?.timeInTarget ?? 0
                self.updateActiveSegment(at: currentDate)
                self.checkWorkoutFinishedAlert()
            }
    }

    /// Fires a one-shot noticeable haptic + banner text when elapsed time
    /// first meets or crosses the planned target duration. The user can keep
    /// training after this fires — the alert is informational, not a stop.
    private func checkWorkoutFinishedAlert() {
        guard !workoutFinishedAlertFired,
              let activePlan,
              activePlan.targetDuration > 0,
              elapsedTime >= activePlan.targetDuration else { return }

        workoutFinishedAlertFired = true
        activeSegmentTitle = "Target Reached"
        playWorkoutFinishedHaptic()
    }

    /// Attention-grabbing finished pattern: `.notification` immediately, then
    /// a follow-up `.success` so it reads as distinctly different from an
    /// in-target nudge.
    private func playWorkoutFinishedHaptic() {
        WKInterfaceDevice.current().play(.notification)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            WKInterfaceDevice.current().play(.success)
            try? await Task.sleep(nanoseconds: 250_000_000)
            WKInterfaceDevice.current().play(.notification)
        }
    }

    private func updateActiveSegment(at currentDate: Date) {
        guard let startDate else { return }
        let elapsed = currentDate.timeIntervalSince(startDate)
        let segment = activePlan?.activeSegment(at: elapsed) ?? activePlan?.activeSegmentFallback

        activeSegmentTitle = segment?.title ?? "Workout"
        activeTargetText = segment?.targetRange?.displayText ?? activePlan?.overallTargetRange.displayText ?? "—"

        if let segment, segment.id != lastSegmentIdentifier {
            lastSegmentIdentifier = segment.id
        }
    }

    private var currentTargetRange: TargetHeartRateRange? {
        guard let startDate else { return activePlan?.overallTargetRange }
        let elapsed = Date().timeIntervalSince(startDate)
        return activePlan?.activeSegment(at: elapsed).targetRange ?? activePlan?.overallTargetRange
    }

    fileprivate func updateHeartRate(_ bpm: Int, at date: Date) {
        telemetry?.update(
            heartRate: bpm,
            at: date,
            targetRange: currentTargetRange
        )

        heartRate = bpm
        averageHR = telemetry?.averageHeartRate ?? 0
        maxHR = telemetry?.maximumHeartRate ?? 0
        timeInActiveTarget = telemetry?.timeInTarget ?? 0

        if let companionProfile {
            let classifier = HeartRateZoneClassifier(
                maxHeartRate: companionProfile.maxHeartRate,
                zone2Range: companionProfile.zone2Low...companionProfile.zone2High
            )
            currentZone = classifier.zone(for: bpm).rawValue
        }

        let coachingPreferences = activePlan?.coachingPreferences ??
            companionProfile?.coachingPreferences ??
            .default
        let coachingSnapshot = coachingEngine.evaluate(
            heartRate: bpm,
            targetRange: currentTargetRange,
            at: date,
            preferences: coachingPreferences
        )
        coachingPosition = coachingSnapshot.position

        if coachingPreferences.hapticsEnabled {
            playHaptic(for: coachingSnapshot.alert)
        }
    }

    private func playHaptic(for alert: HeartRateCoachingAlert) {
        // Single pulses were too easy to miss on-wrist, especially mid-run.
        // Double-pulse patterns for out-of-range alerts give them a
        // distinctive rhythm the wrist actually notices; `.backInTarget`
        // stays a single `.success` chirp so it reads as "you're fine".
        switch alert {
        case .belowTarget:
            WKInterfaceDevice.current().play(.notification)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                WKInterfaceDevice.current().play(.directionUp)
            }
        case .aboveTarget:
            WKInterfaceDevice.current().play(.notification)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                WKInterfaceDevice.current().play(.directionDown)
            }
        case .backInTarget:
            WKInterfaceDevice.current().play(.success)
        case .none:
            break
        }
    }

    private func completedSegmentCount(at endDate: Date) -> Int {
        guard let startDate,
              let activePlan else { return 0 }

        let elapsed = endDate.timeIntervalSince(startDate)
        return activePlan.segments.filter { elapsed >= $0.endOffset }.count
    }

    private func makeFreeWorkoutPlan(
        exerciseType: ExerciseType,
        companionProfile: WatchCompanionProfile
    ) -> WorkoutExecutionPlan {
        let targetRange = companionProfile.zone2TargetRange
        return WorkoutExecutionPlan(
            id: UUID().uuidString,
            recommendationIdentifier: UUID().uuidString,
            accountIdentifier: companionProfile.accountIdentifier,
            profileIdentifier: companionProfile.profileIdentifier,
            createdAt: Date(),
            phase: companionProfile.phase,
            sessionType: .zone2,
            exerciseType: exerciseType,
            targetDuration: 30 * 60,
            overallTargetRange: targetRange,
            intervalProtocol: nil,
            suggestedMetrics: [:],
            segments: [
                WorkoutPlanSegment(
                    id: "steady",
                    title: "Free Workout",
                    kind: .steady,
                    startOffset: 0,
                    duration: 30 * 60,
                    targetRange: targetRange,
                    cue: "Stay steady in your target zone."
                )
            ],
            coachingPreferences: companionProfile.coachingPreferences,
            rationale: "Free workout using your current target zone settings.",
            isFreeWorkout: true
        )
    }

    private func activityType(for exerciseType: ExerciseType) -> HKWorkoutActivityType {
        switch exerciseType {
        case .treadmill: return .running
        case .elliptical: return .elliptical
        case .stairClimber: return .stairClimbing
        case .bike: return .cycling
        case .rowing: return .rowing
        case .outdoorRun: return .running
        case .rucking: return .hiking
        case .swimming: return .swimming
        }
    }

    private func locationType(for exerciseType: ExerciseType) -> HKWorkoutSessionLocationType {
        switch exerciseType {
        case .outdoorRun, .rucking:
            return .outdoor
        default:
            return .indoor
        }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.sessionState = toState
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session error: \(error)")
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)

            Task { @MainActor in
                switch quantityType {
                case HKQuantityType(.heartRate):
                    let bpm = Int(
                        statistics?.mostRecentQuantity()?.doubleValue(
                            for: HKUnit.count().unitDivided(by: .minute())
                        ) ?? 0
                    )
                    if bpm > 0 {
                        self.updateHeartRate(bpm, at: Date())
                    }
                case HKQuantityType(.activeEnergyBurned):
                    self.activeCalories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                case HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling):
                    if let meters = statistics?.sumQuantity()?.doubleValue(for: .meter()) {
                        self.distanceMeters = meters
                    }
                default:
                    break
                }
            }
        }
    }
}
