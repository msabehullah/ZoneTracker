import Foundation

enum WatchSyncMessageType: String {
    case companionProfile
    case workoutPlan
    case workoutCompletion
}

enum WatchSyncEnvelope {
    private static let typeKey = "type"
    private static let payloadKey = "payload"

    static func profileMessage(_ profile: WatchCompanionProfile) throws -> [String: Any] {
        try makeMessage(type: .companionProfile, payload: profile)
    }

    static func workoutPlanMessage(_ plan: WorkoutExecutionPlan) throws -> [String: Any] {
        try makeMessage(type: .workoutPlan, payload: plan)
    }

    static func workoutCompletionMessage(_ payload: WorkoutCompletionPayload) throws -> [String: Any] {
        try makeMessage(type: .workoutCompletion, payload: payload)
    }

    static func decodeProfile(from message: [String: Any]) throws -> WatchCompanionProfile {
        try decode(message, as: .companionProfile)
    }

    static func decodeWorkoutPlan(from message: [String: Any]) throws -> WorkoutExecutionPlan {
        try decode(message, as: .workoutPlan)
    }

    static func decodeWorkoutCompletion(from message: [String: Any]) throws -> WorkoutCompletionPayload {
        try decode(message, as: .workoutCompletion)
    }

    static func messageType(from message: [String: Any]) -> WatchSyncMessageType? {
        guard let rawValue = message[typeKey] as? String else { return nil }
        return WatchSyncMessageType(rawValue: rawValue)
    }

    private static func makeMessage<T: Encodable>(
        type: WatchSyncMessageType,
        payload: T
    ) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return [
            typeKey: type.rawValue,
            payloadKey: data
        ]
    }

    private static func decode<T: Decodable>(
        _ message: [String: Any],
        as expectedType: WatchSyncMessageType
    ) throws -> T {
        guard messageType(from: message) == expectedType else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Unexpected watch sync message type.")
            )
        }

        guard let data = message[payloadKey] as? Data else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Missing watch sync payload data.")
            )
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}
