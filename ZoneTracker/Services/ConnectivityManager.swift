import Foundation
import WatchConnectivity

// MARK: - Phone-side WatchConnectivity Manager

@MainActor
class ConnectivityManager: NSObject, ObservableObject {
    static let shared = ConnectivityManager()

    @Published var lastSyncDate: Date?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Send Zone Settings to Watch

    func sendZoneSettings(profile: UserProfile) {
        guard WCSession.default.isReachable else {
            // Queue as application context — delivered when Watch wakes
            sendAsContext(profile: profile)
            return
        }

        let message: [String: Any] = [
            "type": "zoneSettings",
            "maxHR": profile.maxHR,
            "zone2Low": profile.zone2TargetLow,
            "zone2High": profile.zone2TargetHigh,
            "phase": profile.phase.rawValue
        ]

        WCSession.default.sendMessage(message, replyHandler: nil)
    }

    private func sendAsContext(profile: UserProfile) {
        let context: [String: Any] = [
            "maxHR": profile.maxHR,
            "zone2Low": profile.zone2TargetLow,
            "zone2High": profile.zone2TargetHigh,
            "phase": profile.phase.rawValue
        ]

        try? WCSession.default.updateApplicationContext(context)
    }

    // MARK: - Receive Workout from Watch

    var onWorkoutReceived: ((_ data: [String: Any]) -> Void)?
}

// MARK: - WCSessionDelegate

extension ConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WCSession activation failed: \(error)")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    // Receive messages from Watch
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        Task { @MainActor in
            switch type {
            case "workoutComplete":
                self.lastSyncDate = Date()
                self.onWorkoutReceived?(message)
            default:
                break
            }
        }
    }

    // Receive user info transfers (queued workout data)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let type = userInfo["type"] as? String, type == "workoutComplete" else { return }

        Task { @MainActor in
            self.lastSyncDate = Date()
            self.onWorkoutReceived?(userInfo)
        }
    }
}
