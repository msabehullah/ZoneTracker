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

    var onWorkoutCompletionReceived: ((WorkoutCompletionPayload) -> Void)?

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
                onWorkoutCompletionReceived?(payload)
            } catch {
                print("Failed to decode workout completion: \(error)")
            }
        case .companionProfile, .workoutPlan:
            break
        }
    }
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
