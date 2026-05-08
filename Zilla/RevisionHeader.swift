import SwiftUI
import PhabricatorKit

struct RevisionHeader: View {
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(Workspace.self) private var workspace
    let revision: Revision
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: revision.fields.isViewRestricted ? "lock.fill" : "globe")
                    .scaledFont(.caption)
                    .foregroundStyle(revision.fields.isViewRestricted ? Color.orange : .secondary)
                    .help(revision.fields.isViewRestricted ? "Restricted view policy" : "Public view policy")
                Button(action: copyRevision) {
                    Text(revision.revisionLabel)
                        .scaledFont(.headline, design: .monospaced)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(didCopy ? "Copied" : "Click to copy revision")
                .contextMenu {
                    Button("Copy Revision") {
                        copyRevision()
                    }
                    Button("Copy Link") {
                        copyToPasteboard(revisionURL.absoluteString)
                    }
                }
                StatusBadge(status: revision.fields.status)
                if revision.fields.isDraft {
                    StatusBadge(status: RevisionStatus(value: "draft", name: "Draft", closed: false))
                }
                if let myStatus = myReviewerStatus {
                    Text(myStatus)
                        .scaledFont(.caption, weight: .semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(myStateColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(myStateColor)
                }
                if didCopy {
                    Text("Copied")
                        .scaledFont(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Spacer()
            }
            Text(revisionTitleAttributed(revision.fields.title))
                .scaledFont(.title2)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                if let authorName {
                    Text(authorName)
                }
                if authorName != nil {
                    Text(verbatim: "·")
                        .foregroundStyle(.tertiary)
                }
                Text(revision.fields.dateCreated, format: .dateTime.year().month().day())
            }
            .scaledFont(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var authorName: String? {
        let phid = revision.fields.authorPHID
        if let user = workspace.revisionUserDirectory[phid] {
            return user.realName ?? user.userName
        }
        return nil
    }

    private var revisionURL: URL {
        revision.fields.uri ?? URL(string: "https://phabricator.services.mozilla.com/D\(revision.id)")!
    }

    private func copyRevision() {
        copyToPasteboard(revision.revisionLabel)
        withAnimation { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { didCopy = false }
        }
    }

    private var myReviewerStatus: String? {
        guard let myPHID = phab.currentUser?.phid,
              let reviewers = revision.attachments?.reviewers?.reviewers else { return nil }
        guard let mine = reviewers.first(where: { $0.reviewerPHID == myPHID }) else { return nil }
        switch mine.status {
        case Reviewer.Status.accepted: return "You accepted"
        case Reviewer.Status.rejected: return "You requested changes"
        case Reviewer.Status.blocking: return "Blocking"
        case Reviewer.Status.resigned: return "Resigned"
        default: return nil
        }
    }

    private var myStateColor: Color {
        switch myReviewerStatus {
        case "You accepted": return .green
        case "You requested changes": return .red
        case "Blocking": return .orange
        case "Resigned": return .secondary
        default: return .secondary
        }
    }
}
