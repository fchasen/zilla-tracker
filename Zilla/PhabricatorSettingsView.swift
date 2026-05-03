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
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle("Phabricator")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #else
        content
            .frame(minWidth: 460, idealWidth: 480)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch phab.state {
        case .signedIn(let user):
            SettingsAccountCard(
                title: "Phabricator",
                primaryName: user.realName ?? user.userName,
                secondaryName: "@\(user.userName)",
                isBusy: phab.isBusy,
                onSignOut: { Task { await phab.signOut() } },
                onDone: { dismiss() }
            )
        default:
            PhabricatorSignInForm(
                token: $token,
                isBusy: phab.isBusy,
                errorMessage: phab.errorMessage,
                tokensURL: Self.tokensURL,
                onSignIn: submit,
                onCancel: { dismiss() }
            )
        }
    }

    private func submit() {
        Task { await phab.signIn(token: token) }
    }
}

private struct PhabricatorSignInForm: View {
    @Binding var token: String
    let isBusy: Bool
    let errorMessage: String?
    let tokensURL: URL
    let onSignIn: () -> Void
    let onCancel: () -> Void

    @FocusState private var tokenFieldFocused: Bool

    private var canSubmit: Bool {
        !token.trimmingCharacters(in: .whitespaces).isEmpty && !isBusy
    }

    var body: some View {
        SettingsHeroLayout(
            iconSystemName: "flame.fill",
            iconTint: .orange,
            title: "Connect to Phabricator",
            subtitle: "Sign in to view your active revisions and embed Phabricator pages inside Zilla.",
            primaryActionTitle: "Sign In",
            primaryAction: onSignIn,
            primaryEnabled: canSubmit,
            isBusy: isBusy,
            secondaryActionTitle: "Cancel",
            secondaryAction: onCancel
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("API Token")
                        .scaledFont(.subheadline, weight: .medium)
                    Spacer()
                    Link(destination: tokensURL) {
                        Label("Get a token", systemImage: "arrow.up.right.square")
                            .labelStyle(.titleAndIcon)
                            .scaledFont(.caption)
                    }
                    .buttonStyle(.borderless)
                }

                SecureField("api-…", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .focused($tokenFieldFocused)
                    .onSubmit(onSignIn)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .scaledFont(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .onAppear { tokenFieldFocused = true }
        }
    }
}
