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
    @Environment(\.modelContext) private var modelContext
    @Query private var matchingDrafts: [BugDraft]

    @State private var descriptionSelection: TextSelection?
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var showDiscardConfirm = false
    @FocusState private var summaryFocused: Bool

    init(draftID: UUID) {
        self.draftID = draftID
        self._matchingDrafts = Query(filter: #Predicate<BugDraft> { $0.id == draftID })
    }

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
                    Text("Summary").font(.headline)
                    TextField("What's the bug?", text: $draft.summary, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .padding(10)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                        .focused($summaryFocused)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description").font(.headline)
                    MarkdownEditor(
                        text: $draft.bugDescription,
                        selection: $descriptionSelection,
                        minHeight: 240,
                        isDisabled: isSubmitting,
                        emptyPreviewLabel: "Nothing to preview yet."
                    )
                }

                if let submitError {
                    Label(submitError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    workspace.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help(workspace.showInspector ? "Hide Inspector" : "Show Inspector")
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
        guard draft.isReadyToSubmit else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

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
            blocks: draft.blocks
        )

        do {
            let newID = try await auth.client.createBug(payload)
            let destination = postSubmitDestination(for: draft)
            let metaToOpen = draft.blocks.first
            modelContext.delete(draft)
            workspace.selectedDraftID = nil
            workspace.sidebarSelection = destination
            if metaToOpen == nil {
                workspace.selectedBugID = newID
            }
            workspace.bugListRefreshToken = UUID()
        } catch {
            submitError = error.localizedDescription
        }
    }

    private func postSubmitDestination(for draft: BugDraft) -> SidebarSelection {
        if let metaID = draft.blocks.first {
            return .metaBug(metaID)
        }
        if let ref = draft.componentRef, isFollowedComponent(ref) {
            return .component(ref)
        }
        return .smart(.myBugs)
    }

    private func isFollowedComponent(_ ref: ComponentRef) -> Bool {
        let descriptor = FetchDescriptor<FollowedComponent>(
            predicate: #Predicate { $0.product == ref.product && $0.componentName == ref.component }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).isEmpty == false
    }

    private func discard(_ draft: BugDraft) {
        modelContext.delete(draft)
        workspace.selectedDraftID = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
