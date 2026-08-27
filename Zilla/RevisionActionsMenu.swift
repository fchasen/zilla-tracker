import SwiftUI
import PhabricatorKit

struct RevisionActionsMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab
    let revision: Revision

    var body: some View {
        Menu {
            if isReviewer && isOpen {
                Button { open(.accept) } label: {
                    Label("Accept", systemImage: "checkmark.circle.fill")
                }
                Button { open(.reject) } label: {
                    Label("Request changes", systemImage: "exclamationmark.bubble.fill")
                }
            }
            if isReviewer {
                Button { open(.resign) } label: {
                    Label("Resign as reviewer", systemImage: "person.crop.circle.badge.minus")
                }
            }
            if isAuthor && isOpen && !isAbandoned {
                Button { open(.planChanges) } label: {
                    Label("Plan changes", systemImage: "pencil.line")
                }
                Button { open(.requestReview) } label: {
                    Label("Request review", systemImage: "eye")
                }
                Divider()
                Button(role: .destructive) { open(.abandon) } label: {
                    Label("Abandon", systemImage: "trash")
                }
            }
            if isAuthor && isAbandoned {
                Button { open(.reclaim) } label: {
                    Label("Reclaim revision", systemImage: "arrow.uturn.backward")
                }
            }
            if isClosed || isAbandoned {
                Button { open(.reopen) } label: {
                    Label("Reopen", systemImage: "arrow.counterclockwise")
                }
            }
            if isAuthor && revision.fields.status.value == RevisionStatus.Value.accepted {
                Button { open(.close) } label: {
                    Label("Close", systemImage: "lock.fill")
                }
            }
            if hasMyDrafts {
                Divider()
                Button { publishDrafts() } label: {
                    Label("Publish drafts", systemImage: "paperplane.fill")
                }
            }
        } label: {
            Label {
                Text("Review")
            } icon: {
                Image(systemName: viewerStatusIcon)
                    .foregroundStyle(viewerStatusTint)
            }
        }
    }

    private var viewerReviewerStatuses: [String] {
        guard let reviewers = revision.attachments?.reviewers?.reviewers else { return [] }
        var out: [String] = []
        if let myPHID, let mine = reviewers.first(where: { $0.reviewerPHID == myPHID }) {
            out.append(mine.status)
        }
        for reviewer in reviewers where phab.viewerProjectPHIDs.contains(reviewer.reviewerPHID) {
            out.append(reviewer.status)
        }
        return out
    }

    private var viewerStatusIcon: String {
        let statuses = viewerReviewerStatuses
        if statuses.contains(where: { $0 == Reviewer.Status.rejected || $0 == Reviewer.Status.rejectedPrior }) {
            return "exclamationmark.bubble.fill"
        }
        if statuses.contains(where: { $0 == Reviewer.Status.accepted || $0 == Reviewer.Status.acceptedPrior }) {
            return "checkmark.circle.fill"
        }
        return "checkmark.circle"
    }

    private var viewerStatusTint: Color {
        let statuses = viewerReviewerStatuses
        if statuses.contains(where: { $0 == Reviewer.Status.rejected || $0 == Reviewer.Status.rejectedPrior }) {
            return .orange
        }
        if statuses.contains(where: { $0 == Reviewer.Status.accepted || $0 == Reviewer.Status.acceptedPrior }) {
            return .green
        }
        return .primary
    }

    private var myPHID: String? { phab.currentUser?.phid }

    private var isAuthor: Bool {
        guard let myPHID else { return false }
        return revision.fields.authorPHID == myPHID
    }

    private var isReviewer: Bool {
        guard let reviewers = revision.attachments?.reviewers?.reviewers else { return false }
        let projectPHIDs = phab.viewerProjectPHIDs
        return reviewers.contains { reviewer in
            if let myPHID, reviewer.reviewerPHID == myPHID { return true }
            return projectPHIDs.contains(reviewer.reviewerPHID)
        }
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
        Task {
            switch action {
            case .accept:
                await acceptRevision()
            case .reject:
                await requestChanges()
            default:
                if let error = await workspace.applyRevisionEdit(transactions: [.action(action)], using: phab.client) {
                    workspace.lastUpdateError = error.localizedDescription
                }
            }
        }
    }

    private func acceptRevision() async {
        var transactions: [RevisionEditTransaction] = [.action(.accept)]
        let submitted = workspace.revisionCommentDrafts[revision.id] ?? ""
        let trimmed = submitted.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            transactions.append(.comment(Markdown.toRemarkup(CommentMarkdown.autolinkReferences(in: trimmed))))
        }
        workspace.revisionCommentErrors.removeValue(forKey: revision.id)
        if let error = await workspace.applyRevisionEdit(transactions: transactions, using: phab.client) {
            workspace.lastUpdateError = error.localizedDescription
            return
        }
        if !trimmed.isEmpty {
            consumeDraft(submitted)
        }
    }

    private func requestChanges() async {
        let submitted = workspace.revisionCommentDrafts[revision.id] ?? ""
        let trimmed = submitted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            workspace.revisionCommentErrors[revision.id] = "Enter a reason in the comment box before requesting changes."
            workspace.pendingScrollToRevisionComment = UUID()
            return
        }
        workspace.revisionCommentErrors.removeValue(forKey: revision.id)
        if let error = await workspace.applyRevisionEdit(
            transactions: [
                .action(.reject),
                .comment(Markdown.toRemarkup(CommentMarkdown.autolinkReferences(in: trimmed)))
            ],
            using: phab.client
        ) {
            workspace.lastUpdateError = error.localizedDescription
            return
        }
        consumeDraft(submitted)
    }

    private func consumeDraft(_ submitted: String) {
        let current = workspace.revisionCommentDrafts[revision.id] ?? ""
        if let remainder = DraftConsumption.remainder(after: submitted, in: current), !remainder.isEmpty {
            workspace.revisionCommentDrafts[revision.id] = remainder
        } else {
            workspace.revisionCommentDrafts.removeValue(forKey: revision.id)
        }
    }

    private func publishDrafts() {
        Task {
            if let error = await workspace.applyRevisionEdit(transactions: [], using: phab.client) {
                workspace.lastUpdateError = error.localizedDescription
            }
        }
    }
}
