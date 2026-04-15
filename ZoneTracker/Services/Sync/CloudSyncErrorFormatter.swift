import CloudKit
import Foundation

// MARK: - Cloud Sync Error Formatter
//
// Raw CloudKit errors read as implementation leakage in the UI — users saw
// things like "did not find record type: ZTProfile" on the account card and
// assumed the app was broken. This type maps known failure modes to short,
// user-facing explanations while preserving full detail in logs (keep the
// raw `error` going to `print` at the call site).

enum CloudSyncErrorFormatter {

    /// Map any `Error` returned from a CloudKit path to a short, user-friendly
    /// sentence suitable for the Settings account card. Unknown errors fall
    /// back to a generic line rather than dumping localized description.
    static func friendlyMessage(for error: Error) -> String {
        if let ckError = error as? CKError {
            return message(for: ckError)
        }

        // Schema-push errors from server-side development container surface as
        // plain `NSError` with recognizable substrings. Match on those so the
        // user gets something meaningful even when CKError wrapping is lost.
        let description = (error as NSError).localizedDescription.lowercased()
        if description.contains("did not find record type") ||
           description.contains("record type") && description.contains("not found") {
            return "Cloud backup is still being set up for this account — your data is safe on this device."
        }
        if description.contains("network") || description.contains("offline") {
            return "Offline — we'll sync the next time you're online."
        }
        if description.contains("icloud") && description.contains("account") {
            return "iCloud isn't available on this device. Sign into iCloud to enable cloud backup."
        }
        return "Cloud backup is temporarily unavailable. Your data is safe on this device."
    }

    private static func message(for error: CKError) -> String {
        switch error.code {
        case .networkUnavailable, .networkFailure:
            return "Offline — we'll sync the next time you're online."
        case .notAuthenticated:
            return "Sign into iCloud in Settings to enable cloud backup."
        case .quotaExceeded:
            return "Your iCloud storage is full. Free up space to resume cloud backup."
        case .zoneNotFound, .userDeletedZone:
            return "Cloud backup zone is being rebuilt — this can take a moment."
        case .unknownItem, .invalidArguments:
            // "did not find record type" surfaces under .unknownItem /
            // .invalidArguments on simulators and unconfigured dev containers.
            return "Cloud backup is still being set up for this account — your data is safe on this device."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud is busy — we'll retry automatically."
        case .permissionFailure:
            return "This device doesn't have permission to sync. Check iCloud settings."
        case .incompatibleVersion:
            return "Update the app to restore cloud backup."
        default:
            return "Cloud backup hit a temporary issue. Your data is safe on this device."
        }
    }
}
