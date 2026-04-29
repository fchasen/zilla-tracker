import SwiftUI
import PhabricatorKit

struct RevisionHeader: View {
    @Environment(\.openURL) private var openURL
    @Environment(PhabricatorAuthStore.self) private var phab
    let revision: Revision

    @State private var didCopy: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(revision.revisionLabel)
                    .font(.headline.monospaced())
                    .foregroundStyle(.secondary)
                Button {
                    copyToPasteboard(revision.revisionLabel)
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { didCopy = false }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Copy revision ID")
                if let url = revision.fields.uri {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Open D\(revision.id) in browser")
                }
                StatusBadge(status: revision.fields.status)
                if revision.fields.isDraft {
                    StatusBadge(status: RevisionStatus(value: "draft", name: "Draft", closed: false))
                }
                if let myStatus = myReviewerStatus {
                    Text(myStatus)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(myStateColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(myStateColor)
                }
                Spacer()
            }
            Text(revision.fields.title)
                .font(.title2)
                .textSelection(.enabled)
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
