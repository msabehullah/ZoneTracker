import CloudKit
import XCTest
@testable import ZoneTracker

final class CloudSyncErrorFormatterTests: XCTestCase {

    // MARK: - Raw string matching (NSError path)

    func testUnknownRecordTypeMapsToFriendlyMessage() {
        // Mirrors the exact text the user saw on-device:
        // "did not find record type: ZTProfile".
        let error = NSError(
            domain: "CKErrorDomain",
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "did not find record type: ZTProfile"]
        )
        let message = CloudSyncErrorFormatter.friendlyMessage(for: error)
        XCTAssertFalse(message.contains("ZTProfile"), "Raw record-type text leaked: \(message)")
        XCTAssertTrue(message.lowercased().contains("still being set up") ||
                      message.lowercased().contains("data is safe"))
    }

    func testNetworkWordingMapsToOfflineMessage() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: -1009,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        )
        let message = CloudSyncErrorFormatter.friendlyMessage(for: error)
        XCTAssertTrue(message.lowercased().contains("offline"))
    }

    // MARK: - CKError code paths

    func testCKErrorNetworkUnavailableMapsToOffline() {
        let error = CKError(.networkUnavailable)
        let message = CloudSyncErrorFormatter.friendlyMessage(for: error)
        XCTAssertTrue(message.lowercased().contains("offline"))
    }

    func testCKErrorNotAuthenticatedMapsToSignIntoICloud() {
        let error = CKError(.notAuthenticated)
        let message = CloudSyncErrorFormatter.friendlyMessage(for: error)
        XCTAssertTrue(message.lowercased().contains("icloud"))
    }

    func testCKErrorQuotaExceededMentionsStorage() {
        let error = CKError(.quotaExceeded)
        let message = CloudSyncErrorFormatter.friendlyMessage(for: error)
        XCTAssertTrue(message.lowercased().contains("storage") ||
                      message.lowercased().contains("full"))
    }

    func testCKErrorUnknownItemMapsToSetupMessage() {
        let error = CKError(.unknownItem)
        let message = CloudSyncErrorFormatter.friendlyMessage(for: error)
        XCTAssertTrue(message.lowercased().contains("still being set up") ||
                      message.lowercased().contains("data is safe"))
    }

    // MARK: - Unknown fallback

    func testGenericErrorUsesSafeFallback() {
        let error = NSError(domain: "com.example", code: 42, userInfo: [:])
        let message = CloudSyncErrorFormatter.friendlyMessage(for: error)
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(message.lowercased().contains("data is safe") ||
                      message.lowercased().contains("unavailable"))
    }
}
