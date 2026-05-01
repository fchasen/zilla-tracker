//
//  PhabricatorAuthStore.swift
//  Zilla
//

import Foundation
import PhabricatorKit

@Observable
@MainActor
final class PhabricatorAuthStore {
    enum State: Equatable {
        case unknown
        case signedOut
        case signingIn
        case signedIn(PhabricatorUser)
        case error(String)
    }

    private static let keychainService = "mozilla.Zilla.phabricator-token"
    private static let keychainAccount = "default"
    nonisolated static let defaultBaseURL = URL(string: "https://phabricator.services.mozilla.com")!

    var state: State = .unknown
    private(set) var viewerProjectPHIDs: Set<String> = []
    let client: PhabricatorClient
    var cacheClearHook: (@MainActor () -> Void)?
    private let keychain: Keychain

    init(baseURL: URL = PhabricatorAuthStore.defaultBaseURL) {
        self.client = PhabricatorClient(baseURL: baseURL)
        self.keychain = Keychain(service: PhabricatorAuthStore.keychainService)
    }

    func bootstrap() async {
        guard let token = keychain.get(account: Self.keychainAccount) else {
            state = .signedOut
            return
        }
        await client.setAuthentication(.apiToken(token))
        do {
            let user = try await client.whoami()
            state = .signedIn(user)
            await loadViewerProjects(userPHID: user.phid)
        } catch {
            await client.setAuthentication(.none)
            state = .signedOut
        }
    }

    func signIn(token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .error("Enter an API token.")
            return
        }
        state = .signingIn
        await client.setAuthentication(.apiToken(trimmed))
        do {
            let user = try await client.whoami()
            try? keychain.set(trimmed, account: Self.keychainAccount)
            state = .signedIn(user)
            await loadViewerProjects(userPHID: user.phid)
        } catch PhabricatorError.unauthorized {
            await client.setAuthentication(.none)
            state = .error("That API token was rejected. Tokens start with \"api-\" and are generated at phabricator.services.mozilla.com/settings/panel/apitokens/.")
        } catch let PhabricatorError.api(code, info) where code == "ERR-INVALID-AUTH" || code == "ERR-INVALID-SESSION" {
            await client.setAuthentication(.none)
            state = .error("Token rejected: \(info)")
        } catch let PhabricatorError.api(code, info) {
            await client.setAuthentication(.none)
            state = .error("\(code): \(info)")
        } catch {
            await client.setAuthentication(.none)
            state = .error(error.localizedDescription)
        }
    }

    func signOut() async {
        keychain.delete(account: Self.keychainAccount)
        await client.setAuthentication(.none)
        state = .signedOut
        viewerProjectPHIDs = []
        cacheClearHook?()
    }

    private func loadViewerProjects(userPHID: String) async {
        var phids: Set<String> = []
        var cursor: String?
        repeat {
            var query = ProjectQuery.forMember(userPHID)
            query.after = cursor
            do {
                let result = try await client.searchProjects(query)
                phids.formUnion(result.data.map(\.phid))
                cursor = result.cursor?.after
            } catch {
                break
            }
        } while cursor != nil
        viewerProjectPHIDs = phids
    }

    var currentUser: PhabricatorUser? {
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

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }
}
