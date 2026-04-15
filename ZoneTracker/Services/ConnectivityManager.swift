import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class ConnectivityManager: NSObject {
    static let shared = ConnectivityManager()

    private enum ContextKey {
        static let profilePayload = "companionProfilePayload"
        static let workoutPlanPayload = "workoutPlanPayload"
    }

    var lastSyncDate: Date?
    var lastSentPlanIdentifier: String?
    var isReachable = false
    var isPaired = false
    var isWatchAppInstalled = false

    /// Legacy callback. Prefer `setWorkoutCompletionHandler(_:)` which drains
    /// any payloads that arrived before the handler was installed. Kept as a
    /// property so existing call sites that assign directly still work, but
    /// new code should go through the setter.
    var onWorkoutCompletionReceived: ((WorkoutCompletionPayload) -> Void)? {
        didSet { flushPendingCompletionsIfReady() }
    }

    /// Payloads that arrived before any handler was installed. WCSession is
    /// activated from `init()` (well before `AppRootView.task` installs a
    /// handler), so `didReceiveUserInfo` / `didReceiveMessage` can realistically
    /// fire against an empty callback. Without this buffer those completions
    /// were silently lost — matching the "watch workout didn't come back"
    /// reports. Keyed by completionIdentifier so repeated deliveries (sendMessage
    /// + transferUserInfo redundancy) don't queue the same payload twice.
    private var pendingCompletions: [WorkoutCompletionPayload] = []

    private var cachedProfile: WatchCompanionProfile?
    private var cachedPlan: WorkoutExecutionPlan?

    private override init() {
        super.init()
        activateIfSupported()
    }

    func activateIfSupported() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        refresh(session: session)
    }

    func sendCompanionProfile(
        _ profile: WatchCompanionProfile,
        preservePlan: Bool = true
    ) {
        do {
            cachedProfile = profile
            if !preservePlan {
                cachedPlan = nil
                lastSentPlanIdentifier = nil
            }
            let message = try WatchSyncEnvelope.profileMessage(profile)
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(message, replyHandler: nil)
            }
            try updateApplicationContext(profile: profile, plan: nil)
        } catch {
            print("Failed to send companion profile: \(error)")
        }
    }

    func sendWorkoutPlan(
        _ plan: WorkoutExecutionPlan,
        profile: WatchCompanionProfile
    ) {
        do {
            cachedProfile = profile
            cachedPlan = plan
            let message = try WatchSyncEnvelope.workoutPlanMessage(plan)
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(message, replyHandler: nil)
            }
            try updateApplicationContext(profile: profile, plan: plan)
            lastSentPlanIdentifier = plan.id
        } catch {
            print("Failed to send workout plan: \(error)")
        }
    }

    private func updateApplicationContext(
        profile: WatchCompanionProfile,
        plan: WorkoutExecutionPlan?
    ) throws {
        var context: [String: Any] = [
            ContextKey.profilePayload: try JSONEncoder().encode(profile)
        ]
        if let resolvedPlan = plan ?? cachedPlan {
            context[ContextKey.workoutPlanPayload] = try JSONEncoder().encode(resolvedPlan)
        }
        try WCSession.default.updateApplicationContext(context)
    }

    private func refresh(session: WCSession) {
        isReachable = session.isReachable
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
    }

    private func handleMessage(_ message: [String: Any]) {
        guard let messageType = WatchSyncEnvelope.messageType(from: message) else { return }

        switch messageType {
        case .workoutCompletion:
            do {
                let payload = try WatchSyncEnvelope.decodeWorkoutCompletion(from: message)
                lastSyncDate = Date()
                deliverOrQueue(payload)
            } catch {
                print("Failed to decode workout completion: \(error)")
            }
        case .companionProfile, .workoutPlan:
            break
        }
    }

    // MARK: - Durable completion delivery

    /// Install the handler that ingests completions into SwiftData. Safe to
    /// call any time after app startup — buffered payloads flush immediately.
    func setWorkoutCompletionHandler(_ handler: @escaping (WorkoutCompletionPayload) -> Void) {
        onWorkoutCompletionReceived = handler
        // didSet on the property will call flushPendingCompletionsIfReady().
    }

    /// Deliver synchronously if a handler exists, otherwise buffer the payload
    /// for the next flush. Dedupes by `completionIdentifier` (`payload.id`) so
    /// the sendMessage + transferUserInfo redundancy on the watch side doesn't
    /// queue the same completion twice.
    private func deliverOrQueue(_ payload: WorkoutCompletionPayload) {
        if let handler = onWorkoutCompletionReceived {
            handler(payload)
            return
        }
        guard !pendingCompletions.contains(where: { $0.id == payload.id }) else { return }
        pendingCompletions.append(payload)
    }

    private func flushPendingCompletionsIfReady() {
        guard let handler = onWorkoutCompletionReceived,
              !pendingCompletions.isEmpty else { return }
        let drained = pendingCompletions
        pendingCompletions.removeAll()
        for payload in drained {
            handler(payload)
        }
    }

    #if DEBUG
    /// Test-only accessor so unit tests can assert buffer contents without
    /// reaching into private state elsewhere in the app.
    var debug_pendingCompletionCount: Int { pendingCompletions.count }

    /// Test-only entry point — lets tests inject a decoded payload through the
    /// same queue-or-deliver path WCSession uses, without needing a live
    /// WCSession in the simulator (which doesn't work).
    func debug_injectCompletion(_ payload: WorkoutCompletionPayload) {
        deliverOrQueue(payload)
    }

    /// Test-only reset so tests are order-independent against the shared instance.
    func debug_reset() {
        pendingCompletions.removeAll()
        onWorkoutCompletionReceived = nil
    }
    #endif
}

extension ConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("WCSession activation failed: \(error)")
        }

        Task { @MainActor in
            self.refresh(session: session)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refresh(session: session)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleMessage(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.handleMessage(userInfo)
        }
    }
}
