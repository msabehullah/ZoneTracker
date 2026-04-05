import Foundation
import WatchConnectivity

// MARK: - Watch-side WatchConnectivity Manager

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var maxHR: Int = 189
    @Published var zone2Low: Int = 130
    @Published var zone2High: Int = 150
    @Published var phase: String = "phase1"

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Send Workout to Phone

    func sendWorkoutToPhone(
        duration: TimeInterval,
        avgHR: Int,
        maxHR: Int,
        calories: Double,
        timeInZone2: TimeInterval,
        activityType: String
    ) {
        let data: [String: Any] = [
            "type": "workoutComplete",
            "duration": duration,
            "avgHR": avgHR,
            "maxHR": maxHR,
            "calories": calories,
            "timeInZone2": timeInZone2,
            "activityType": activityType,
            "date": Date().timeIntervalSince1970
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(data, replyHandler: nil)
        } else {
            // Queue for delivery when phone is reachable
            WCSession.default.transferUserInfo(data)
        }
    }

    // MARK: - Apply Settings from Phone

    private func applySettings(_ settings: [String: Any]) {
        if let hr = settings["maxHR"] as? Int { maxHR = hr }
        if let low = settings["zone2Low"] as? Int { zone2Low = low }
        if let high = settings["zone2High"] as? Int { zone2High = high }
        if let p = settings["phase"] as? String { phase = p }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Load any queued application context
        if !session.receivedApplicationContext.isEmpty {
            Task { @MainActor in
                self.applySettings(session.receivedApplicationContext)
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String, type == "zoneSettings" else { return }
        Task { @MainActor in
            self.applySettings(message)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applySettings(applicationContext)
        }
    }
}
