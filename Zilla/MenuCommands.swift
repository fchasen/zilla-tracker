//
//  MenuCommands.swift
//  Zilla
//

#if os(macOS)
import SwiftUI
import AppKit
import BugzillaKit

struct ZillaCommands: Commands {
    let auth: AuthStore
    let phab: PhabricatorAuthStore
    let workspace: Workspace
    let viewedBugs: ViewedBugsStore

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Bug Draft") {
                workspace.newDraftRequested = true
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open Bug…") {
                workspace.quickSearchPresented = true
            }
            .keyboardShortcut(KeyEquivalent(" "), modifiers: .shift)
        }

        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                workspace.bugListRefreshToken = UUID()
                workspace.revisionListRefreshToken = UUID()
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Menu("Sort") {
                Picker("Sort", selection: sortBinding) {
                    ForEach(BugListSort.allCases) { sort in
                        Label(sort.label, systemImage: sort.systemImage).tag(sort)
                    }
                }
                .pickerStyle(.inline)
            }

            Divider()

            Button("Increase Font Size") {
                adjustFontScale(by: 1)
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(workspace.fontScaleStep >= FontScale.maxStep)

            Button("Decrease Font Size") {
                adjustFontScale(by: -1)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(workspace.fontScaleStep <= FontScale.minStep)

            Button("Reset Font Size") {
                workspace.fontScaleStep = FontScale.defaultStep
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(workspace.fontScaleStep == FontScale.defaultStep)

            Divider()

            Button(workspace.showInspector ? "Hide Inspector" : "Show Inspector") {
                workspace.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(workspace.loadedBug == nil && workspace.selectedDraftID == nil)
        }

        CommandMenu("Navigate") {
            Button("My Bugs") { workspace.sidebarSelection = .smart(.myBugs) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Needs Info") { workspace.sidebarSelection = .smart(.needsReview) }
                .keyboardShortcut("2", modifiers: .command)
            if workspace.hasTriageComponents(for: auth.currentUser?.name) {
                Button("Triage") { workspace.sidebarSelection = .smart(.triage) }
            }

            Divider()

            Button("Active Revisions") { workspace.sidebarSelection = .review(.active) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(!phab.isSignedIn)
            Button("Under Review") { workspace.sidebarSelection = .review(.review) }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(!phab.isSignedIn)
            Button("Landed") { workspace.sidebarSelection = .review(.landed) }
                .keyboardShortcut("5", modifiers: .command)
                .disabled(!phab.isSignedIn)

            Divider()

            Button("Drafts") { workspace.sidebarSelection = .allDrafts }
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }

        CommandMenu("Bug") {
            Button("Open in Browser") {
                guard let id = workspace.loadedBug?.id,
                      let url = URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=\(id)")
                else { return }
                NSWorkspace.shared.open(url)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(workspace.loadedBug == nil)

            Button("Copy Bug Link") {
                guard let id = workspace.loadedBug?.id else { return }
                copyToPasteboard("https://bugzilla.mozilla.org/show_bug.cgi?id=\(id)")
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(workspace.loadedBug == nil)

            Button("Copy Bug ID") {
                guard let id = workspace.loadedBug?.id else { return }
                copyToPasteboard(String(id))
            }
            .keyboardShortcut("c", modifiers: [.command, .control])
            .disabled(workspace.loadedBug == nil)

            Divider()

            Menu("Status") {
                ForEach(BugStatuses.open, id: \.code) { option in
                    Button(option.label) {
                        applyUpdate(BugUpdate(status: option.code))
                    }
                    .disabled(isClosed)
                }
                if isClosed {
                    Divider()
                    Button("Reopen") {
                        applyUpdate(BugUpdate(status: "REOPENED", resolution: ""))
                    }
                }
            }
            .disabled(workspace.loadedBug == nil)

            Menu("Resolve as") {
                ForEach(BugStatuses.resolutions, id: \.code) { option in
                    Button(option.label) {
                        applyUpdate(BugUpdate(status: "RESOLVED", resolution: option.code))
                    }
                }
            }
            .disabled(workspace.loadedBug == nil || isClosed)

            Button("Mark as Duplicate…") {
                workspace.dupePromptRequested = true
            }
            .disabled(workspace.loadedBug == nil || isClosed)

            Button("Take") {
                guard let me = auth.currentUser?.name else { return }
                applyUpdate(BugUpdate(assignedTo: me))
            }
            .disabled(workspace.loadedBug == nil
                || !BugStatuses.isUnassigned(workspace.loadedBug?.assignedTo)
                || auth.currentUser == nil)
        }

        CommandMenu("Account") {
            Button("Bugzilla Settings…") {
                workspace.bugzillaSettingsPresented = true
            }
            Button("Phabricator Settings…") {
                workspace.phabricatorSettingsPresented = true
            }

            Divider()

            Button("Sign Out from Bugzilla") {
                Task {
                    await auth.signOut()
                    workspace.reset()
                }
            }
            .disabled(!auth.isSignedIn)

            Button("Sign Out from Phabricator") {
                Task { await phab.signOut() }
            }
            .disabled(!phab.isSignedIn)
        }
    }

    private var isClosed: Bool {
        guard let bug = workspace.loadedBug else { return false }
        return BugStatuses.isClosed(bug.status)
    }

    private var sortBinding: Binding<BugListSort> {
        Binding(
            get: { workspace.bugListSort },
            set: { workspace.bugListSort = $0 }
        )
    }

    private func adjustFontScale(by delta: Int) {
        workspace.fontScaleStep = FontScale.clamp(workspace.fontScaleStep + delta)
    }

    private func applyUpdate(_ update: BugUpdate) {
        let client = auth.client
        Task {
            if let error = await workspace.applyBugUpdate(update, using: client) {
                workspace.lastUpdateError = error.localizedDescription
            }
        }
    }
}
#endif
