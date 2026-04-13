import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AccountStore {
    static let shared = AccountStore()

    enum SessionState: Equatable {
        case loading
        case signedOut
        case signedIn
    }

    private enum DefaultsKey {
        static let userID = "account.appleUserID"
        static let displayName = "account.displayName"
        static let email = "account.email"
    }

    var sessionState: SessionState = .loading
    var appleUserID: String?
    var displayName: String?
    var email: String?
    var lastErrorMessage: String?

    private let defaults = UserDefaults.standard
    private let provider = ASAuthorizationAppleIDProvider()

    private init() {
        appleUserID = defaults.string(forKey: DefaultsKey.userID)
        displayName = defaults.string(forKey: DefaultsKey.displayName)
        email = defaults.string(forKey: DefaultsKey.email)
        sessionState = appleUserID == nil ? .signedOut : .loading
    }

    var isSignedIn: Bool {
        sessionState == .signedIn && appleUserID != nil
    }

    func restoreSession() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-codex-bypass-auth") {
            activateSimulatorBypassSession()
            return
        }
        #endif

        guard let appleUserID else {
            sessionState = .signedOut
            return
        }

        do {
            let credentialState = try await credentialState(for: appleUserID)
            switch credentialState {
            case .authorized:
                sessionState = .signedIn
            case .revoked, .notFound, .transferred:
                clearPersistedSession()
            @unknown default:
                sessionState = .signedOut
            }
        } catch {
            // Keep a previously authenticated user signed in when the environment
            // cannot validate the Apple ID state, such as restricted simulator setups.
            lastErrorMessage = error.localizedDescription
            sessionState = .signedIn
        }
    }

    func handleAuthorization(result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                lastErrorMessage = "Unexpected Apple ID authorization payload."
                return
            }
            persist(credential: credential)
            sessionState = .signedIn
            lastErrorMessage = nil
        case .failure(let error):
            lastErrorMessage = error.localizedDescription
            sessionState = appleUserID == nil ? .signedOut : .signedIn
        }
    }

    func signOut() {
        clearPersistedSession()
    }

    private func persist(credential: ASAuthorizationAppleIDCredential) {
        appleUserID = credential.user
        defaults.set(credential.user, forKey: DefaultsKey.userID)

        let resolvedDisplayName = Self.displayName(from: credential.fullName) ?? displayName
        displayName = resolvedDisplayName
        defaults.set(resolvedDisplayName, forKey: DefaultsKey.displayName)

        let resolvedEmail = credential.email ?? email
        email = resolvedEmail
        defaults.set(resolvedEmail, forKey: DefaultsKey.email)
    }

    private func clearPersistedSession() {
        appleUserID = nil
        displayName = nil
        email = nil
        lastErrorMessage = nil
        sessionState = .signedOut

        defaults.removeObject(forKey: DefaultsKey.userID)
        defaults.removeObject(forKey: DefaultsKey.displayName)
        defaults.removeObject(forKey: DefaultsKey.email)
    }

    private func credentialState(for userID: String) async throws -> ASAuthorizationAppleIDProvider.CredentialState {
        try await withCheckedThrowingContinuation { continuation in
            provider.getCredentialState(forUserID: userID) { state, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: state)
                }
            }
        }
    }

    private static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        let formatted = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }

    #if DEBUG
    private func activateSimulatorBypassSession() {
        let simulatedUserID = appleUserID ?? "sim-user-123"
        appleUserID = simulatedUserID
        displayName = displayName ?? "Simulator User"
        email = email ?? "simulator@example.com"

        defaults.set(simulatedUserID, forKey: DefaultsKey.userID)
        defaults.set(displayName, forKey: DefaultsKey.displayName)
        defaults.set(email, forKey: DefaultsKey.email)
        sessionState = .signedIn
        lastErrorMessage = nil
    }
    #endif
}
