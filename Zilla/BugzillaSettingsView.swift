//
//  BugzillaSettingsView.swift
//  Zilla
//

import SwiftUI
import BugzillaKit

struct BugzillaSettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""

    private static let apiKeysURL = URL(string: "https://bugzilla.mozilla.org/userprefs.cgi?tab=apikey")!

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Bugzilla")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Divider()

            switch auth.state {
            case .signedIn(let user):
                signedInSection(user: user)
            default:
                signInSection
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private var signInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to load and update bugs from bugzilla.mozilla.org.")
                .foregroundStyle(.secondary)

            HStack {
                Text("API Key")
                Spacer()
                Link(destination: Self.apiKeysURL) {
                    Label("Get a key", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .pointerStyle(.link)
            }

            SecureField("API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            if let error = auth.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button(action: submit) {
                    if auth.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || auth.isBusy)
                .keyboardShortcut(.return)
            }
        }
    }

    @ViewBuilder
    private func signedInSection(user: User) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.realName ?? user.name)
                        .font(.headline)
                    if let nick = user.nick {
                        Text("@\(nick)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(user.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
            }
        }
    }

    private func submit() {
        Task { await auth.signIn(apiKey: apiKey) }
    }
}
