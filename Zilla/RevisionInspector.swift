import SwiftUI
import PhabricatorKit

struct RevisionInspector: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let revision = workspace.loadedRevision {
                    statusSection(revision: revision)
                    Divider()
                    authorSection(revision: revision)
                    if hasReviewers(revision: revision) {
                        Divider()
                        reviewersSection(revision: revision)
                    }
                    Divider()
                    propertiesSection(revision: revision)
                    if let inline = workspace.loadedRevisionDiff {
                        Divider()
                        diffsSection(revision: revision, latest: inline)
                    }
                } else {
                    ContentUnavailableView(
                        "Revision not loaded",
                        systemImage: "doc.text"
                    )
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func statusSection(revision: Revision) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBadge(status: revision.fields.status)
        }
    }

    @ViewBuilder
    private func authorSection(revision: Revision) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeader(title: "Author")
            personRow(phid: revision.fields.authorPHID, trailing: nil)
        }
    }

    private func hasReviewers(revision: Revision) -> Bool {
        !(revision.attachments?.reviewers?.reviewers.isEmpty ?? true)
    }

    @ViewBuilder
    private func reviewersSection(revision: Revision) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeader(
                title: "Reviewers",
                trailing: "\(revision.attachments?.reviewers?.reviewers.count ?? 0)"
            )
            ForEach(revision.attachments?.reviewers?.reviewers ?? [], id: \.reviewerPHID) { reviewer in
                personRow(
                    phid: reviewer.reviewerPHID,
                    trailing: reviewerStateIcon(reviewer)
                )
            }
        }
    }

    @ViewBuilder
    private func propertiesSection(revision: Revision) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeader(title: "Properties")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                if let bug = revision.fields.bugzillaBugID, let id = Int(bug) {
                    GridRow {
                        Text("Bug").foregroundStyle(.secondary)
                        Button("#\(bug)") { workspace.selectedBugID = id }
                            .buttonStyle(.borderless)
                    }
                }
                GridRow {
                    Text("Created").foregroundStyle(.secondary)
                    Text(revision.fields.dateCreated, format: .dateTime)
                }
                GridRow {
                    Text("Last change").foregroundStyle(.secondary)
                    Text(revision.fields.dateModified, format: .relative(presentation: .named))
                }
                if let diff = workspace.loadedRevisionDiff {
                    let adds = diff.changesets.reduce(0) { $0 + $1.addLines }
                    let dels = diff.changesets.reduce(0) { $0 + $1.delLines }
                    GridRow {
                        Text("Lines").foregroundStyle(.secondary)
                        Text("+\(adds)  −\(dels)")
                            .monospacedDigit()
                    }
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func diffsSection(revision: Revision, latest: DiffDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeader(title: "Latest diff")
            HStack(spacing: 8) {
                Text("Diff \(latest.id)")
                    .font(.callout.monospaced())
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                if let date = latest.dateCreated {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func personRow(phid: String, trailing: AnyView?) -> some View {
        HStack(spacing: 8) {
            avatar(phid: phid)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: phid))
                    .font(.callout.weight(.medium))
                if let user = workspace.revisionUserDirectory[phid],
                   let real = user.realName, !real.isEmpty,
                   real != user.userName {
                    Text("@\(user.userName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
    }

    @ViewBuilder
    private func avatar(phid: String) -> some View {
        if let user = workspace.revisionUserDirectory[phid], let url = user.image {
            AsyncImage(url: url) { image in
                image.resizable()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)
        }
    }

    private func displayName(for phid: String) -> String {
        if let user = workspace.revisionUserDirectory[phid] {
            return user.realName ?? user.userName
        }
        return "@\(phid.suffix(6))"
    }

    private func reviewerStateIcon(_ reviewer: Reviewer) -> AnyView? {
        switch reviewer.status {
        case Reviewer.Status.accepted, Reviewer.Status.acceptedPrior:
            return AnyView(Image(systemName: "checkmark.seal.fill").foregroundStyle(.green))
        case Reviewer.Status.rejected, Reviewer.Status.rejectedPrior:
            return AnyView(Image(systemName: "xmark.seal.fill").foregroundStyle(.red))
        case Reviewer.Status.blocking:
            return AnyView(Image(systemName: "lock.fill").foregroundStyle(.orange))
        case Reviewer.Status.resigned:
            return AnyView(Image(systemName: "person.slash").foregroundStyle(.secondary))
        default:
            return AnyView(Image(systemName: "circle").foregroundStyle(.secondary))
        }
    }
}
