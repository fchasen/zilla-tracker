//
//  DraftEditorView.swift
//  Zilla
//

import SwiftUI
import SwiftData
import BugzillaKit

struct DraftEditorView: View {
    let draftID: UUID

    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth
    @Environment(ResourceCache.self) private var cache
    @Environment(\.modelContext) private var modelContext
    @Query private var matchingDrafts: [BugDraft]

    @State private var submitError: String?
    @State private var showDiscardConfirm = false
    @FocusState private var summaryFocused: Bool

    init(draftID: UUID) {
        self.draftID = draftID
        self._matchingDrafts = Query(filter: #Predicate<BugDraft> { $0.id == draftID })
    }

    private var isSubmitting: Bool { workspace.isSubmittingDraft(draftID) }

    var body: some View {
        if let draft = matchingDrafts.first {
            content(for: draft)
        } else {
            ContentUnavailableView(
                "Draft not found",
                systemImage: "doc.text",
                description: Text("This draft was deleted or hasn't loaded yet.")
            )
        }
    }

    @ViewBuilder
    private func content(for draft: BugDraft) -> some View {
        @Bindable var draft = draft

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Summary").scaledFont(.headline)
                    TextField("", text: $draft.summary, axis: .vertical)
                        .textFieldStyle(.plain)
                        .scaledFont(.title3)
                        .padding(10)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                        .focused($summaryFocused)
                        .disabled(isSubmitting)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description").scaledFont(.headline)
                    MarkdownEditor(
                        text: $draft.bugDescription,
                        minHeight: 240,
                        isDisabled: isSubmitting
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
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await submit(draft) }
                    } label: {
                        Label("Create", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Submit to Bugzilla (⌘↩)")
                    .disabled(!draft.isReadyToSubmit)
                }
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
        .onChange(of: draft.bugDescription) { draft.updatedAt = .now }
    }

    private func submit(_ draft: BugDraft) async {
        guard draft.isReadyToSubmit, !isSubmitting else { return }
        submitError = nil
        workspace.beginDraftSubmit(draftID)
        defer { workspace.endDraftSubmit(draftID) }

        let payload = BugCreate(
            product: draft.product,
            component: draft.componentName,
            summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            version: draft.version,
            description: draft.bugDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : draft.bugDescription,
            type: draft.type,
            severity: draft.severity,
            priority: draft.priority,
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

    private func discard(_ draft: BugDraft) {
        guard !isSubmitting else { return }
        modelContext.delete(draft)
        workspace.dismissDraft(draftID)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
