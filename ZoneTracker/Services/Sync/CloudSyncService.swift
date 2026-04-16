import CloudKit
import Foundation

struct CloudProfileSnapshot: Equatable, Sendable {
    var accountIdentifier: String
    var profileIdentifier: String
    var age: Int
    var maxHeartRate: Int
    var weight: Double
    var height: Double
    var currentPhase: String
    var phaseStartDate: Date
    var hasCompletedOnboarding: Bool
    /// Intermediate onboarding state — true once the assessment is committed
    /// but before "Start Coaching" is tapped. Optional for backward
    /// compatibility with older cloud records that predate the field; absent
    /// records decode as `nil`, which is treated as "unknown → false" by the
    /// coordinator when rebuilding a local profile.
    var hasSubmittedAssessment: Bool?
    var zone2Low: Int
    var zone2High: Int
    var legDays: [Int]
    var coachingHapticsEnabled: Bool
    var coachingAlertCooldownSeconds: Int
    // Goal-driven fields
    var primaryGoalRaw: String
    var targetEvent: String?
    var targetEventDate: Date?
    var fitnessLevelRaw: String
    var weeklyCardioFrequency: Int
    var typicalWorkoutMinutes: Int
    var preferredModalities: [String]
    var availableTrainingDays: Int
    var intensityConstraintRaw: String
    var currentFocusRaw: String

    static func from(profile: UserProfile, accountIdentifier: String) -> CloudProfileSnapshot {
        CloudProfileSnapshot(
            accountIdentifier: accountIdentifier,
            profileIdentifier: profile.profileIdentifier,
            age: profile.age,
            maxHeartRate: profile.maxHR,
            weight: profile.weight,
            height: profile.height,
            currentPhase: profile.currentPhase,
            phaseStartDate: profile.phaseStartDate,
            hasCompletedOnboarding: profile.hasCompletedOnboarding,
            hasSubmittedAssessment: profile.hasSubmittedAssessment,
            zone2Low: profile.zone2TargetLow,
            zone2High: profile.zone2TargetHigh,
            legDays: profile.legDays,
            coachingHapticsEnabled: profile.coachingHapticsEnabled,
            coachingAlertCooldownSeconds: profile.coachingAlertCooldownSeconds,
            primaryGoalRaw: profile.primaryGoalRaw,
            targetEvent: profile.targetEvent,
            targetEventDate: profile.targetEventDate,
            fitnessLevelRaw: profile.fitnessLevelRaw,
            weeklyCardioFrequency: profile.weeklyCardioFrequency,
            typicalWorkoutMinutes: profile.typicalWorkoutMinutes,
            preferredModalities: profile.preferredModalities,
            availableTrainingDays: profile.availableTrainingDays,
            intensityConstraintRaw: profile.intensityConstraintRaw,
            currentFocusRaw: profile.currentFocusRaw
        )
    }
}

struct CloudWorkoutSnapshot: Equatable, Sendable {
    var workoutIdentifier: UUID
    var accountIdentifier: String
    var completionIdentifier: String?
    var planIdentifier: String?
    var recommendationIdentifier: String?
    var sourceRaw: String
    var date: Date
    var exerciseTypeRaw: String
    var duration: TimeInterval
    var metricsData: Data?
    var sessionTypeRaw: String
    var heartRateDataEncoded: Data?
    var phaseRaw: String
    var weekNumber: Int
    var rpe: Int?
    var notes: String?
    var intervalProtocolData: Data?
    var focusRaw: String

    static func from(workout: WorkoutEntry, accountIdentifier: String) -> CloudWorkoutSnapshot {
        CloudWorkoutSnapshot(
            workoutIdentifier: workout.id,
            accountIdentifier: accountIdentifier,
            completionIdentifier: workout.completionIdentifier,
            planIdentifier: workout.planIdentifier,
            recommendationIdentifier: workout.recommendationIdentifier,
            sourceRaw: workout.sourceRaw,
            date: workout.date,
            exerciseTypeRaw: workout.exerciseTypeRaw,
            duration: workout.duration,
            metricsData: workout.metricsData,
            sessionTypeRaw: workout.sessionTypeRaw,
            heartRateDataEncoded: workout.heartRateDataEncoded,
            phaseRaw: workout.phaseRaw,
            weekNumber: workout.weekNumber,
            rpe: workout.rpe,
            notes: workout.notes,
            intervalProtocolData: workout.intervalProtocolData,
            focusRaw: workout.focusRaw
        )
    }
}

actor CloudSyncService {
    static let shared = CloudSyncService()

    private enum RecordType {
        static let profile = "ZTProfile"
        static let workout = "ZTWorkout"
    }

    private let database = CKContainer.default().privateCloudDatabase

    func fetchProfile(accountIdentifier: String) async throws -> CloudProfileSnapshot? {
        let predicate = NSPredicate(format: "accountIdentifier == %@", accountIdentifier)
        let records = try await fetchAllRecords(recordType: RecordType.profile, predicate: predicate, resultsLimit: 1)
        return try records.first.map(Self.profileSnapshot(from:))
    }

    func fetchWorkouts(accountIdentifier: String) async throws -> [CloudWorkoutSnapshot] {
        let predicate = NSPredicate(format: "accountIdentifier == %@", accountIdentifier)
        let records = try await fetchAllRecords(recordType: RecordType.workout, predicate: predicate, resultsLimit: 200)
        return try records.map(Self.workoutSnapshot(from:))
    }

    func save(profile snapshot: CloudProfileSnapshot) async throws {
        let recordID = CKRecord.ID(recordName: "profile-\(snapshot.accountIdentifier)")
        let record = CKRecord(recordType: RecordType.profile, recordID: recordID)
        apply(snapshot: snapshot, to: record)
        _ = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: false
        )
    }

    func save(workouts snapshots: [CloudWorkoutSnapshot]) async throws {
        guard !snapshots.isEmpty else { return }
        let records = snapshots.map { snapshot in
            let recordID = CKRecord.ID(recordName: "workout-\(snapshot.workoutIdentifier.uuidString)")
            let record = CKRecord(recordType: RecordType.workout, recordID: recordID)
            apply(snapshot: snapshot, to: record)
            return record
        }

        _ = try await database.modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .changedKeys,
            atomically: false
        )
    }

    private func fetchAllRecords(
        recordType: String,
        predicate: NSPredicate,
        resultsLimit: Int
    ) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        let query = CKQuery(recordType: recordType, predicate: predicate)
        var response = try await database.records(matching: query, resultsLimit: resultsLimit)

        while true {
            records.append(contentsOf: response.matchResults.compactMap { _, result in
                try? result.get()
            })

            guard let cursor = response.queryCursor else { break }
            response = try await database.records(continuingMatchFrom: cursor, resultsLimit: resultsLimit)
        }

        return records
    }

    private func apply(snapshot: CloudProfileSnapshot, to record: CKRecord) {
        record["accountIdentifier"] = snapshot.accountIdentifier as CKRecordValue
        record["profileIdentifier"] = snapshot.profileIdentifier as CKRecordValue
        record["age"] = snapshot.age as CKRecordValue
        record["maxHeartRate"] = snapshot.maxHeartRate as CKRecordValue
        record["weight"] = snapshot.weight as CKRecordValue
        record["height"] = snapshot.height as CKRecordValue
        record["currentPhase"] = snapshot.currentPhase as CKRecordValue
        record["phaseStartDate"] = snapshot.phaseStartDate as CKRecordValue
        record["hasCompletedOnboarding"] = snapshot.hasCompletedOnboarding as CKRecordValue
        record["hasSubmittedAssessment"] = snapshot.hasSubmittedAssessment as CKRecordValue?
        record["zone2Low"] = snapshot.zone2Low as CKRecordValue
        record["zone2High"] = snapshot.zone2High as CKRecordValue
        record["legDaysData"] = (try? JSONEncoder().encode(snapshot.legDays)) as CKRecordValue?
        record["coachingHapticsEnabled"] = snapshot.coachingHapticsEnabled as CKRecordValue
        record["coachingAlertCooldownSeconds"] = snapshot.coachingAlertCooldownSeconds as CKRecordValue
        record["primaryGoalRaw"] = snapshot.primaryGoalRaw as CKRecordValue
        record["targetEvent"] = snapshot.targetEvent as CKRecordValue?
        record["targetEventDate"] = snapshot.targetEventDate as CKRecordValue?
        record["fitnessLevelRaw"] = snapshot.fitnessLevelRaw as CKRecordValue
        record["weeklyCardioFrequency"] = snapshot.weeklyCardioFrequency as CKRecordValue
        record["typicalWorkoutMinutes"] = snapshot.typicalWorkoutMinutes as CKRecordValue
        record["preferredModalitiesData"] = (try? JSONEncoder().encode(snapshot.preferredModalities)) as CKRecordValue?
        record["availableTrainingDays"] = snapshot.availableTrainingDays as CKRecordValue
        record["intensityConstraintRaw"] = snapshot.intensityConstraintRaw as CKRecordValue
        record["currentFocusRaw"] = snapshot.currentFocusRaw as CKRecordValue
    }

    private func apply(snapshot: CloudWorkoutSnapshot, to record: CKRecord) {
        record["workoutIdentifier"] = snapshot.workoutIdentifier.uuidString as CKRecordValue
        record["accountIdentifier"] = snapshot.accountIdentifier as CKRecordValue
        record["completionIdentifier"] = snapshot.completionIdentifier as CKRecordValue?
        record["planIdentifier"] = snapshot.planIdentifier as CKRecordValue?
        record["recommendationIdentifier"] = snapshot.recommendationIdentifier as CKRecordValue?
        record["sourceRaw"] = snapshot.sourceRaw as CKRecordValue
        record["date"] = snapshot.date as CKRecordValue
        record["exerciseTypeRaw"] = snapshot.exerciseTypeRaw as CKRecordValue
        record["duration"] = snapshot.duration as CKRecordValue
        record["metricsData"] = snapshot.metricsData as CKRecordValue?
        record["sessionTypeRaw"] = snapshot.sessionTypeRaw as CKRecordValue
        record["heartRateDataEncoded"] = snapshot.heartRateDataEncoded as CKRecordValue?
        record["phaseRaw"] = snapshot.phaseRaw as CKRecordValue
        record["weekNumber"] = snapshot.weekNumber as CKRecordValue
        record["rpe"] = snapshot.rpe as CKRecordValue?
        record["notes"] = snapshot.notes as CKRecordValue?
        record["intervalProtocolData"] = snapshot.intervalProtocolData as CKRecordValue?
        record["focusRaw"] = snapshot.focusRaw as CKRecordValue
    }

    private static func profileSnapshot(from record: CKRecord) throws -> CloudProfileSnapshot {
        CloudProfileSnapshot(
            accountIdentifier: record["accountIdentifier"] as? String ?? "",
            profileIdentifier: record["profileIdentifier"] as? String ?? UUID().uuidString,
            age: record["age"] as? Int ?? 31,
            maxHeartRate: record["maxHeartRate"] as? Int ?? 189,
            weight: record["weight"] as? Double ?? 150,
            height: record["height"] as? Double ?? 68,
            currentPhase: record["currentPhase"] as? String ?? TrainingPhase.phase1.rawValue,
            phaseStartDate: record["phaseStartDate"] as? Date ?? Date(),
            hasCompletedOnboarding: record["hasCompletedOnboarding"] as? Bool ?? false,
            // Older records predate this field; leave it as nil rather than
            // silently defaulting to false so the coordinator can distinguish
            // "remote has no opinion" from "remote says not yet submitted".
            hasSubmittedAssessment: record["hasSubmittedAssessment"] as? Bool,
            zone2Low: record["zone2Low"] as? Int ?? 130,
            zone2High: record["zone2High"] as? Int ?? 150,
            legDays: decodeLegDays(from: record["legDaysData"] as? Data),
            coachingHapticsEnabled: record["coachingHapticsEnabled"] as? Bool ?? true,
            coachingAlertCooldownSeconds: record["coachingAlertCooldownSeconds"] as? Int ?? 18,
            primaryGoalRaw: record["primaryGoalRaw"] as? String ?? CardioGoal.generalFitness.rawValue,
            targetEvent: record["targetEvent"] as? String,
            targetEventDate: record["targetEventDate"] as? Date,
            fitnessLevelRaw: record["fitnessLevelRaw"] as? String ?? FitnessLevel.occasional.rawValue,
            weeklyCardioFrequency: record["weeklyCardioFrequency"] as? Int ?? 2,
            typicalWorkoutMinutes: record["typicalWorkoutMinutes"] as? Int ?? 30,
            preferredModalities: decodeModalities(from: record["preferredModalitiesData"] as? Data),
            availableTrainingDays: record["availableTrainingDays"] as? Int ?? 3,
            intensityConstraintRaw: record["intensityConstraintRaw"] as? String ?? "none",
            currentFocusRaw: record["currentFocusRaw"] as? String ?? ""
        )
    }

    private static func workoutSnapshot(from record: CKRecord) throws -> CloudWorkoutSnapshot {
        let workoutIdentifier = UUID(uuidString: record["workoutIdentifier"] as? String ?? "") ?? UUID()

        return CloudWorkoutSnapshot(
            workoutIdentifier: workoutIdentifier,
            accountIdentifier: record["accountIdentifier"] as? String ?? "",
            completionIdentifier: record["completionIdentifier"] as? String,
            planIdentifier: record["planIdentifier"] as? String,
            recommendationIdentifier: record["recommendationIdentifier"] as? String,
            sourceRaw: record["sourceRaw"] as? String ?? WorkoutSource.cloudImport.rawValue,
            date: record["date"] as? Date ?? Date(),
            exerciseTypeRaw: record["exerciseTypeRaw"] as? String ?? ExerciseType.treadmill.rawValue,
            duration: record["duration"] as? Double ?? 0,
            metricsData: record["metricsData"] as? Data,
            sessionTypeRaw: record["sessionTypeRaw"] as? String ?? SessionType.zone2.rawValue,
            heartRateDataEncoded: record["heartRateDataEncoded"] as? Data,
            phaseRaw: record["phaseRaw"] as? String ?? TrainingPhase.phase1.rawValue,
            weekNumber: record["weekNumber"] as? Int ?? 1,
            rpe: record["rpe"] as? Int,
            notes: record["notes"] as? String,
            intervalProtocolData: record["intervalProtocolData"] as? Data,
            focusRaw: record["focusRaw"] as? String ?? ""
        )
    }

    private static func decodeLegDays(from data: Data?) -> [Int] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Int].self, from: data)) ?? []
    }

    private static func decodeModalities(from data: Data?) -> [String] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
