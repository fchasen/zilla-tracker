//
//  SignInView.swift
//  Zilla
//

import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @State private var apiKey: String = ""

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "ladybug.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Sign in to Bugzilla")
                .font(.title2.weight(.semibold))

            Text("Generate an API key at bugzilla.mozilla.org → Preferences → API Keys.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            SecureField("API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
                .disabled(auth.isBusy)
                .onSubmit(submit)

            if let message = auth.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button(action: submit) {
                if auth.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 100)
                } else {
                    Text("Sign In").frame(width: 100)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(apiKey.isEmpty || auth.isBusy)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        Task { await auth.signIn(apiKey: apiKey) }
    }
}

#Preview {
    SignInView()
        .environment(AuthStore())
}
