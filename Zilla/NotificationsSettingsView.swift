//
//  NotificationsSettingsView.swift
//  Zilla
//

#if os(macOS)
import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    @Environment(NotificationCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(NotificationSettings.needinfoKey) private var needinfo = true
    @AppStorage(NotificationSettings.reviewKey) private var review = true
    @AppStorage(NotificationSettings.patchKey) private var patch = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "bell.badge.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(.red)
                        .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text("Notifications")
                            .scaledFont(.title2, weight: .semibold)
                        Text("Zilla checks Bugzilla and Phabricator for new requests and activity while it is running.")
                            .scaledFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }

                    authorizationNotice

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Needinfo requests", isOn: $needinfo)
                        Divider()
                        Toggle("Review requests", isOn: $review)
                        Divider()
                        Toggle("Activity on my patches", isOn: $patch)
                    }
                    .toggleStyle(.switch)
                    .scaledFont(.body)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 18)
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
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 460, idealWidth: 480)
        .onChange(of: needinfo) { coordinator.settingsChanged() }
        .onChange(of: review) { coordinator.settingsChanged() }
        .onChange(of: patch) { coordinator.settingsChanged() }
        .task { await coordinator.refreshAuthorizationStatus() }
    }

    @ViewBuilder
    private var authorizationNotice: some View {
        switch coordinator.authorizationStatus {
        case .denied:
            notice(
                systemImage: "bell.slash.fill",
                message: "Notifications for Zilla are turned off in System Settings.",
                actionTitle: "Open System Settings",
                action: openSystemSettings
            )
        case .notDetermined:
            notice(
                systemImage: "bell.fill",
                message: "Allow Zilla to post notifications.",
                actionTitle: "Allow Notifications",
                action: { Task { await coordinator.requestAuthorization() } }
            )
        default:
            EmptyView()
        }
    }

    private func notice(
        systemImage: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Label(message, systemImage: systemImage)
                .scaledFont(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(actionTitle, action: action)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 420)
    }

    private func openSystemSettings() {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)") else {
            return
        }
        openURL(url)
    }
}
#endif
