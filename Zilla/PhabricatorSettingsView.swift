//
//  PhabricatorSettingsView.swift
//  Zilla
//

import SwiftUI
import PhabricatorKit

struct PhabricatorSettingsView: View {
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(\.dismiss) private var dismiss

    @State private var token: String = ""

    private static let tokensURL = URL(string: "https://phabricator.services.mozilla.com/settings/panel/apitokens/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Phabricator")
                    .scaledFont(.title2, weight: .semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Divider()

            switch phab.state {
            case .signedIn(let user):
                signedInSection(user: user)
            default:
                signInSection
            }

            #if !os(macOS)
            Spacer()
            #endif
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private var signInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to view your active revisions and embed Phabricator pages inside Zilla.")
                .foregroundStyle(.secondary)

            HStack {
                Text("API Token")
                Spacer()
                Link(destination: Self.tokensURL) {
                    Label("Get a token", systemImage: "arrow.up.right.square")
                        .scaledFont(.caption)
                }
                .buttonStyle(.borderless)
                .linkPointerStyle()
            }

            SecureField("api-…", text: $token)
                .textFieldStyle(.roundedBorder)

            if let error = phab.errorMessage {
                Text(error)
                    .scaledFont(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button {
                    Task { await phab.signIn(token: token) }
                } label: {
                    if phab.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || phab.isBusy)
                .keyboardShortcut(.return)
            }
        }
    }

    @ViewBuilder
    private func signedInSection(user: PhabricatorUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.realName ?? user.userName)
                        .scaledFont(.headline)
                    Text("@\(user.userName)")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("Sign Out", role: .destructive) {
                    Task { await phab.signOut() }
                }
            }
        }
    }
}
