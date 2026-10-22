//
//  DraftEditorView.swift
//  Zilla
//

import SwiftUI
import SwiftData
import BugzillaKit

struct DraftEditorView: View {
    let draftID: UUID

    @Query private var matchingDrafts: [BugDraft]

    init(draftID: UUID) {
        self.draftID = draftID
        self._matchingDrafts = Query(filter: #Predicate<BugDraft> { $0.id == draftID })
    }

    var body: some View {
        if let draft = matchingDrafts.first {
            DraftEditorForm(draftID: draftID, draft: draft)
                .id(draftID)
        } else {
            ContentUnavailableView(
                "Draft not found",
                systemImage: "doc.text",
                description: Text("This draft was deleted or hasn't loaded yet.")
            )
        }
    }
}

private struct DraftEditorForm: View {
    let draftID: UUID
    @Bindable var draft: BugDraft

    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth
    @Environment(ResourceCache.self) private var cache
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var submitError: String?
    @State private var showDiscardConfirm = false
    @State private var summaryFocused = false
    @State private var description: DraftDescriptionBuffer

    init(draftID: UUID, draft: BugDraft) {
        self.draftID = draftID
        self.draft = draft
        self._description = State(initialValue: DraftDescriptionBuffer(draft: draft))
    }

    private var isSubmitting: Bool { workspace.isSubmittingDraft(draftID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Summary").scaledFont(.headline)
                    SpellCheckedTextField(
                        text: $draft.summary,
                        isFocused: $summaryFocused,
                        textStyle: .title3
                    )
                    .padding(10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .disabled(isSubmitting)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description").scaledFont(.headline)
                    MarkdownEditor(
                        text: Binding(get: { description.text }, set: { description.edit($0) }),
                        minHeight: 240,
                        isDisabled: isSubmitting,
                        allowsImages: true
                    )
                }

                if let submitError {
                    Label(submitError, systemImage: "exclamationmark.triangle")
                        .scaledFont(.callout)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(draft.displaySummary)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showDiscardConfirm = true
                } label: {
                    Label("Discard", systemImage: "trash")
                }
                .disabled(isSubmitting)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await submit(draft) }
                } label: {
                    Label("Create", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Submit to Bugzilla (⌘↩)")
                .disabled(!draft.isReadyToSubmit || isSubmitting)
            }
        }
        .confirmationDialog(
            "Discard this draft?",
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                discard(draft)
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The draft and any unsubmitted changes will be removed.")
        }
        .onAppear {
            if draft.summary.isEmpty {
                summaryFocused = true
            }
        }
        .onChange(of: draft.summary) { draft.updatedAt = .now }
        .onChange(of: draft.bugDescription) { _, stored in description.adopt(stored) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { description.commit() }
        }
        .onDisappear { description.commit() }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            description.commit()
            try? modelContext.save()
        }
        #endif
    }

    private func submit(_ draft: BugDraft) async {
        guard draft.isReadyToSubmit, !isSubmitting else { return }
        description.commit()
        submitError = nil
        workspace.beginDraftSubmit(draftID)
        defer { workspace.endDraftSubmit(draftID) }

        let uploads = PendingUploadStore.shared
        let descriptionSource = draft.bugDescription
        let imageMatches = PendingUploadReferences.matches(in: descriptionSource)
        do {
            for match in imageMatches { _ = try uploads.upload(for: match) }
        } catch {
            submitError = error.localizedDescription
            return
        }
        let description = imageMatches.isEmpty
            ? descriptionSource
            : PendingUploadReferences.replacingWithNames(descriptionSource)

        let payload = BugCreate(
            product: draft.product,
            component: draft.componentName,
            summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            version: draft.version,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : description,
            type: draft.type,
            severity: draft.severity,
            priority: draft.priority,
            points: draft.points,
            assignedTo: draft.assignedTo?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            keywords: draft.keywords,
            whiteboard: draft.whiteboard.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            blocks: draft.blocks,
            dependsOn: draft.dependsOn,
            seeAlso: draft.seeAlso,
            groups: draft.isConfidential ? [BugGroup.mozillaEmployeeConfidential] : []
        )

        do {
            let newID = try await auth.client.createBug(payload)
            if !imageMatches.isEmpty {
                await attachDescriptionImages(descriptionSource, to: newID, using: uploads)
            }
            let wasPushed = workspace.isDraftPushed(draftID)
            let hadBugShowing = workspace.selectedBugID != nil
            modelContext.delete(draft)
            if wasPushed {
                workspace.dismissDraft(draftID)
                if !hadBugShowing {
                    workspace.pendingRevealBugID = newID
                }
            } else if workspace.selectedDraftID == draftID {
                workspace.selectedDraftID = nil
                workspace.sidebarSelection = .smart(.myBugs)
                workspace.smartFilters[.myBugs] = .reported
                workspace.smartSorts[.myBugs] = .newest
                workspace.selectedBugID = newID
            }
            cache.invalidateBugSearches()
            workspace.bugListRefreshToken = UUID()
        } catch {
            submitError = error.localizedDescription
        }
    }

    private func attachDescriptionImages(_ source: String, to bugID: Bug.ID, using uploads: PendingUploadStore) async {
        do {
            let linked = try await uploads.resolveForBugzilla(source, bugID: bugID, using: auth.client)
            let comments = try await auth.client.comments(bugID: bugID)
            guard let description = comments.first(where: { $0.count == 0 }) ?? comments.first else { return }
            try await auth.client.updateComment(commentID: description.id, newText: linked)
        } catch {
            workspace.lastUpdateError = "Bug \(bugID) was created, but its images were not attached: \(error.localizedDescription)"
        }
    }

    private func discard(_ draft: BugDraft) {
        guard !isSubmitting else { return }
        description.discard()
        modelContext.delete(draft)
        workspace.dismissDraft(draftID)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
