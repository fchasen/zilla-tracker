import SwiftUI
import MarginaliaEditor
import PhabricatorKit

struct RevisionActionSheetState: Identifiable, Equatable {
    let action: RevisionAction
    var id: String { action.rawValue }
}

struct RevisionActionSheet: View {
    let state: RevisionActionSheetState
    let onSubmit: ([RevisionEditTransaction]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var commentBody: String = ""
    @State private var isSubmitting: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MarkdownEditor(
                        text: $commentBody,
                        isDisabled: isSubmitting,
                        dialect: .remarkup
                    )
                    .frame(minHeight: 140)
                } header: {
                    Text(commentLabel)
                } footer: {
                    if state.action == .reject {
                        Text("A reason is required when requesting changes.")
                            .scaledFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(actionTitle)
            #if os(macOS)
            .navigationSubtitle(actionSubtitle)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel, role: confirmRole) {
                        Task { await submit() }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isSubmitting || !canSubmit)
                }
            }
        }
        .frame(idealWidth: 480, idealHeight: 360)
    }

    private var actionTitle: String {
        switch state.action {
        case .comment: return "Add comment"
        case .accept: return "Accept revision"
        case .reject: return "Request changes"
        case .resign: return "Resign as reviewer"
        case .abandon: return "Abandon revision"
        case .reclaim: return "Reclaim revision"
        case .reopen: return "Reopen revision"
        case .close: return "Close revision"
        case .planChanges: return "Plan changes"
        case .requestReview: return "Request review"
        }
    }

    private var actionSubtitle: String {
        switch state.action {
        case .comment: return "Posts a comment without taking action."
        case .accept: return "Approves the revision and notifies the author."
        case .reject: return "Returns the revision to the author with a reason."
        case .resign: return "Removes you as a reviewer."
        case .abandon: return "Closes the revision without landing it."
        case .reclaim: return "Reopens an abandoned revision you authored."
        case .reopen: return "Reopens a closed revision."
        case .close: return "Marks the revision as closed."
        case .planChanges: return "Indicates that you're working on updates."
        case .requestReview: return "Asks reviewers to take another look."
        }
    }

    private var commentLabel: String {
        switch state.action {
        case .reject: return "Reason (required)"
        case .comment: return "Comment"
        default: return "Comment (optional)"
        }
    }

    private var confirmLabel: String {
        switch state.action {
        case .comment: return "Post"
        case .accept: return "Accept"
        case .reject: return "Request changes"
        case .resign: return "Resign"
        case .abandon: return "Abandon"
        case .reclaim: return "Reclaim"
        case .reopen: return "Reopen"
        case .close: return "Close"
        case .planChanges: return "Plan changes"
        case .requestReview: return "Request review"
        }
    }

    private var confirmRole: ButtonRole? {
        switch state.action {
        case .abandon, .close, .reject: return .destructive
        default: return nil
        }
    }

    private var canSubmit: Bool {
        if state.action == .reject {
            return !commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if state.action == .comment {
            return !commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func submit() async {
        let trimmed = commentBody.trimmingCharacters(in: .whitespacesAndNewlines)
        var transactions: [RevisionEditTransaction] = []
        if state.action != .comment {
            transactions.append(.action(state.action))
        }
        if !trimmed.isEmpty {
            transactions.append(.comment(trimmed))
        }
        guard !transactions.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        await onSubmit(transactions)
        dismiss()
    }
}
