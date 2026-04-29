import SwiftUI
import PhabricatorKit

struct RevisionActionsMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab
    let revision: Revision
    let onAction: (RevisionActionSheetState) -> Void

    var body: some View {
        Menu {
            if isReviewer && isOpen {
                Button("Accept") { open(.accept) }
                Button("Request changes") { open(.reject) }
            }
            if isReviewer {
                Button("Resign as reviewer") { open(.resign) }
            }
            if isAuthor && isOpen && !isAbandoned {
                Button("Plan changes") { open(.planChanges) }
                Button("Request review") { open(.requestReview) }
                Divider()
                Button("Abandon", role: .destructive) { open(.abandon) }
            }
            if isAuthor && isAbandoned {
                Button("Reclaim revision") { open(.reclaim) }
            }
            if isClosed || isAbandoned {
                Button("Reopen") { open(.reopen) }
            }
            if isAuthor && revision.fields.status.value == RevisionStatus.Value.accepted {
                Button("Close") { open(.close) }
            }
            if hasMyDrafts {
                Divider()
                Button("Publish drafts") { publishDrafts() }
            }
            Divider()
            Button("Comment…") { open(.comment) }
        } label: {
            Label("Review", systemImage: "checkmark.circle")
        }
    }

    private var myPHID: String? { phab.currentUser?.phid }

    private var isAuthor: Bool {
        guard let myPHID else { return false }
        return revision.fields.authorPHID == myPHID
    }

    private var isReviewer: Bool {
        guard let myPHID else { return false }
        return revision.attachments?.reviewers?.reviewers.contains(where: { $0.reviewerPHID == myPHID }) ?? false
    }

    private var isOpen: Bool { revision.fields.status.isOpen }
    private var isClosed: Bool { revision.fields.status.value == RevisionStatus.Value.published }
    private var isAbandoned: Bool { revision.fields.status.value == RevisionStatus.Value.abandoned }

    private var hasMyDrafts: Bool {
        guard let myPHID else { return false }
        return workspace.loadedRevisionInlines.contains {
            $0.transactionPHID == nil && $0.authorPHID == myPHID && !$0.isDeleted
        }
    }

    private func open(_ action: RevisionAction) {
        onAction(RevisionActionSheetState(action: action))
    }

    private func publishDrafts() {
        Task {
            if let error = await workspace.applyRevisionEdit(transactions: [], using: phab.client) {
                workspace.lastUpdateError = error.localizedDescription
            }
        }
    }
}
