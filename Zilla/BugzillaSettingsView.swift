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
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle("Bugzilla")
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
        switch auth.state {
        case .signedIn(let user):
            SettingsAccountCard(
                title: "Bugzilla",
                primaryName: user.realName ?? user.name,
                secondaryName: user.nick.map { "@\($0)" } ?? user.name,
                isBusy: auth.isBusy,
                onSignOut: { Task { await auth.signOut() } },
                onDone: { dismiss() }
            )
        default:
            BugzillaSignInForm(
                apiKey: $apiKey,
                isBusy: auth.isBusy,
                errorMessage: auth.errorMessage,
                apiKeysURL: Self.apiKeysURL,
                onSignIn: submit,
                onCancel: { dismiss() }
            )
        }
    }

    private func submit() {
        Task { await auth.signIn(apiKey: apiKey) }
    }
}

private struct BugzillaSignInForm: View {
    @Binding var apiKey: String
    let isBusy: Bool
    let errorMessage: String?
    let apiKeysURL: URL
    let onSignIn: () -> Void
    let onCancel: () -> Void

    @FocusState private var keyFieldFocused: Bool

    private var canSubmit: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty && !isBusy
    }

    var body: some View {
        SettingsHeroLayout(
            iconSystemName: "ladybug.fill",
            iconTint: .red,
            title: "Connect to Bugzilla",
            subtitle: "Sign in to load and update bugs from bugzilla.mozilla.org.",
            primaryActionTitle: "Sign In",
            primaryAction: onSignIn,
            primaryEnabled: canSubmit,
            isBusy: isBusy,
            secondaryActionTitle: "Cancel",
            secondaryAction: onCancel
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("API Key")
                        .scaledFont(.subheadline, weight: .medium)
                    Spacer()
                    Link(destination: apiKeysURL) {
                        Label("Get a key", systemImage: "arrow.up.right.square")
                            .labelStyle(.titleAndIcon)
                            .scaledFont(.caption)
                    }
                    .buttonStyle(.borderless)
                }

                SecureField("Paste your API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .focused($keyFieldFocused)
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
            .onAppear { keyFieldFocused = true }
        }
    }
}

struct SettingsHeroLayout<Body: View>: View {
    let iconSystemName: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let primaryActionTitle: String
    let primaryAction: () -> Void
    let primaryEnabled: Bool
    let isBusy: Bool
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?
    @ViewBuilder var contentBody: () -> Body

    init(
        iconSystemName: String,
        iconTint: Color,
        title: String,
        subtitle: String,
        primaryActionTitle: String,
        primaryAction: @escaping () -> Void,
        primaryEnabled: Bool,
        isBusy: Bool,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder contentBody: @escaping () -> Body
    ) {
        self.iconSystemName = iconSystemName
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.primaryActionTitle = primaryActionTitle
        self.primaryAction = primaryAction
        self.primaryEnabled = primaryEnabled
        self.isBusy = isBusy
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
        self.contentBody = contentBody
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .center, spacing: 22) {
                    Image(systemName: iconSystemName)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(iconTint)
                        .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text(title)
                            .scaledFont(.title2, weight: .semibold)
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .scaledFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }

                    contentBody()
                        .frame(maxWidth: 420)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }

            Divider()

            HStack(spacing: 12) {
                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(action: primaryAction) {
                    Group {
                        if isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(primaryActionTitle)
                        }
                    }
                    .frame(minWidth: 88)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!primaryEnabled)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

struct SettingsAccountCard: View {
    let title: String
    let primaryName: String
    let secondaryName: String
    let isBusy: Bool
    let onSignOut: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "checkmark.seal.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(.green)
                        .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text("Connected")
                            .scaledFont(.title2, weight: .semibold)
                        Text("Signed in to \(title).")
                            .scaledFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        Text(primaryName)
                            .scaledFont(.headline)
                        Text(secondaryName)
                            .scaledFont(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }

            Divider()

            HStack {
                Button("Sign Out", role: .destructive, action: onSignOut)
                    .disabled(isBusy)
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}
