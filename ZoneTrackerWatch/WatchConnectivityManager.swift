import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    private enum ContextKey {
        static let profilePayload = "companionProfilePayload"
        static let workoutPlanPayload = "workoutPlanPayload"
    }

    @Published var companionProfile: WatchCompanionProfile?
    @Published var currentPlan: WorkoutExecutionPlan?
    @Published var lastCompletionSentAt: Date?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func sendWorkoutCompletion(_ payload: WorkoutCompletionPayload) {
        do {
            let message = try WatchSyncEnvelope.workoutCompletionMessage(payload)
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(message, replyHandler: nil)
            }

            // Reliable delivery path for phone wake-up / background delivery.
            WCSession.default.transferUserInfo(message)
            lastCompletionSentAt = Date()
        } catch {
            print("Failed to send workout completion: \(error)")
        }
    }

    private func apply(message: [String: Any]) {
        guard let messageType = WatchSyncEnvelope.messageType(from: message) else { return }

        do {
            switch messageType {
            case .companionProfile:
                companionProfile = try WatchSyncEnvelope.decodeProfile(from: message)
            case .workoutPlan:
                currentPlan = try WatchSyncEnvelope.decodeWorkoutPlan(from: message)
            case .workoutCompletion:
                break
            }
        } catch {
            print("Failed to decode watch sync message: \(error)")
        }
    }

    private func applyApplicationContext(_ applicationContext: [String: Any]) {
        if let profileData = applicationContext[ContextKey.profilePayload] as? Data,
           let profile = try? JSONDecoder().decode(WatchCompanionProfile.self, from: profileData) {
            companionProfile = profile
        }

        if let planData = applicationContext[ContextKey.workoutPlanPayload] as? Data,
           let plan = try? JSONDecoder().decode(WorkoutExecutionPlan.self, from: planData) {
            currentPlan = plan
        } else {
            currentPlan = nil
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("Watch WCSession activation failed: \(error)")
        }

        if !session.receivedApplicationContext.isEmpty {
            Task { @MainActor in
                self.applyApplicationContext(session.receivedApplicationContext)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.apply(message: message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyApplicationContext(applicationContext)
        }
    }
}
