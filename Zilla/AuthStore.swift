//
//  AuthStore.swift
//  Zilla
//

import Foundation
import BugzillaKit

@Observable
@MainActor
final class AuthStore {
    enum State: Equatable {
        case unknown
        case signedOut
        case signingIn
        case signedIn(User)
        case error(String)
    }

    private static let keychainService = "mozilla.Zilla.api-key"
    private static let keychainAccount = "default"
    static let defaultBaseURL = URL(string: "https://bugzilla.mozilla.org")!

    var state: State = .unknown
    let client: BugzillaClient
    private let keychain: Keychain

    init(baseURL: URL = AuthStore.defaultBaseURL) {
        self.client = BugzillaClient(baseURL: baseURL)
        self.keychain = Keychain(service: AuthStore.keychainService)
    }

    func bootstrap() async {
        guard let key = keychain.get(account: Self.keychainAccount) else {
            state = .signedOut
            return
        }
        await client.setAuthentication(.apiKey(key))
        do {
            let user = try await client.whoami()
            state = .signedIn(user)
        } catch {
            await client.setAuthentication(.none)
            state = .signedOut
        }
    }

    func signIn(apiKey: String) async {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .error("Enter an API key.")
            return
        }
        state = .signingIn
        await client.setAuthentication(.apiKey(trimmed))
        do {
            let user = try await client.whoami()
            try? keychain.set(trimmed, account: Self.keychainAccount)
            state = .signedIn(user)
        } catch BugzillaError.unauthorized {
            await client.setAuthentication(.none)
            state = .error("That API key was rejected.")
        } catch {
            await client.setAuthentication(.none)
            state = .error(error.localizedDescription)
        }
    }

    func signOut() async {
        keychain.delete(account: Self.keychainAccount)
        await client.setAuthentication(.none)
        state = .signedOut
    }

    var currentUser: User? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    var isBusy: Bool {
        if case .signingIn = state { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let message) = state { return message }
        return nil
    }
}
