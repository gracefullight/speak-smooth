// SpeakSmooth/Graph/AuthManager.swift
import Foundation
import MSAL

@Observable
@MainActor
final class AuthManager {
    private static let redirectUri = "msauth.com.speaksmooth.app://auth"
    private static let authority = "https://login.microsoftonline.com/common"
    private static let scopes = ["Tasks.ReadWrite"]

    private static var clientId: String {
        (Bundle.main.object(forInfoDictionaryKey: "MSALClientId") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var application: MSALPublicClientApplication?
    private var currentAccount: MSALAccount?

    private(set) var isSignedIn = false
    private(set) var accountName: String?

    init() {
        setupMSAL()
    }

    private func setupMSAL() {
        guard !Self.clientId.isEmpty else { return }
        guard let authorityURL = URL(string: Self.authority) else { return }
        do {
            let authority = try MSALAADAuthority(url: authorityURL)
            let config = MSALPublicClientApplicationConfig(
                clientId: Self.clientId,
                redirectUri: Self.redirectUri,
                authority: authority
            )
            self.application = try MSALPublicClientApplication(configuration: config)
            loadAccount()
        } catch {
            print("MSAL setup error: \(error)")
        }
    }

    private func loadAccount() {
        guard let application else { return }
        do {
            let accounts = try application.allAccounts()
            if let account = accounts.first {
                currentAccount = account
                isSignedIn = true
                accountName = account.username
            }
        } catch {
            print("Load account error: \(error)")
        }
    }

    func signIn() async throws {
        guard let application else { throw AuthError.notConfigured }

        let parameters = MSALInteractiveTokenParameters(
            scopes: Self.scopes,
            webviewParameters: MSALWebviewParameters()
        )
        parameters.promptType = .selectAccount

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
            application.acquireToken(with: parameters) { result, error in
                if let error { continuation.resume(throwing: error) }
                else if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: AuthError.unknown) }
            }
        }

        currentAccount = result.account
        isSignedIn = true
        accountName = result.account.username
    }

    func signOut() throws {
        guard let application, let account = currentAccount else { return }
        try application.remove(account)
        currentAccount = nil
        isSignedIn = false
        accountName = nil
    }

    func getAccessToken() async throws -> String {
        guard let application, let account = currentAccount else {
            throw AuthError.notSignedIn
        }

        let silentParams = MSALSilentTokenParameters(scopes: Self.scopes, account: account)
        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
                application.acquireTokenSilent(with: silentParams) { result, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let result { continuation.resume(returning: result) }
                    else { continuation.resume(throwing: AuthError.unknown) }
                }
            }
            return result.accessToken
        } catch {
            let interactiveParams = MSALInteractiveTokenParameters(
                scopes: Self.scopes,
                webviewParameters: MSALWebviewParameters()
            )
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
                application.acquireToken(with: interactiveParams) { result, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let result { continuation.resume(returning: result) }
                    else { continuation.resume(throwing: AuthError.unknown) }
                }
            }
            currentAccount = result.account
            return result.accessToken
        }
    }
}

enum AuthError: LocalizedError {
    case notConfigured
    case notSignedIn
    case unknown

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "MSAL not configured (set MSALClientId in Info.plist)"
        case .notSignedIn: return "Not signed in to Microsoft"
        case .unknown: return "Unknown auth error"
        }
    }
}

#if DEBUG
extension AuthManager {
    func setAuthStateForTesting(isSignedIn: Bool, accountName: String? = nil) {
        self.isSignedIn = isSignedIn
        self.accountName = accountName
    }
}
#endif
