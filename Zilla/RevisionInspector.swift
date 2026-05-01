import SwiftUI
import BugzillaKit
import PhabricatorKit

struct RevisionInspector: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(AuthStore.self) private var auth
    @Environment(\.openURL) private var openURL

    @State private var tagPickerPresented: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let revision = workspace.loadedRevision {
                    if let bug = revision.fields.bugzillaBugID, let id = Int(bug) {
                        bugLinkCard(id: id)
                    }
                    authorSection(revision: revision)
                    if hasReviewers(revision: revision) {
                        Divider()
                        reviewersSection(revision: revision)
                    }
                    Divider()
                    tagsSection(revision: revision)
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
        .task(id: workspace.loadedRevision?.fields.bugzillaBugID) {
            if let raw = workspace.loadedRevision?.fields.bugzillaBugID,
               let id = Int(raw) {
                await workspace.loadDependencyMetadata(ids: [id], using: auth.client)
            }
        }
        .sheet(isPresented: $tagPickerPresented) {
            ProjectPickerSheet(excludedPHIDs: currentTagPHIDs) { project in
                Task { await addTag(project) }
            }
        }
    }

    @ViewBuilder
    private func bugLinkCard(id: Bug.ID) -> some View {
        let meta = workspace.dependencyMetadata(for: id)
        let icon = bugTypeIcon(meta?.type)
        let link = Button {
            workspace.navigate(to: .bug(id))
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: icon.symbol)
                            .foregroundStyle(icon.color)
                        Text(verbatim: "#\(id)")
                            .scaledFont(.callout, weight: .semibold)
                            .foregroundStyle(.tint)
                        if let meta, !meta.status.isEmpty {
                            Text(meta.status)
                                .scaledFont(.caption2, weight: .semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let summary = meta?.summary, !summary.isEmpty {
                        Text(summary)
                            .scaledFont(.callout)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    } else {
                        Text("Open in app")
                            .scaledFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let assignee = meta?.assigneeDisplayName, !assignee.isEmpty {
                        Text("Assigned to \(assignee)")
                            .scaledFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .scaledFont(.caption, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Open #\(id) in Zilla")

        #if os(macOS)
        link.pointerStyle(.link)
        #else
        link
        #endif
    }

    private func bugTypeIcon(_ type: String?) -> (symbol: String, color: Color) {
        switch type?.lowercased() {
        case "defect": return ("ant.fill", .red)
        case "enhancement": return ("sparkles", .indigo)
        case "task": return ("clipboard", .gray)
        default: return ("ant.fill", .secondary)
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

    private var currentTagPHIDs: Set<String> {
        Set(workspace.loadedRevision?.attachments?.projects?.projectPHIDs ?? [])
    }

    private var sortedCurrentTags: [PhabricatorProject] {
        let phids = workspace.loadedRevision?.attachments?.projects?.projectPHIDs ?? []
        return phids
            .compactMap { workspace.revisionProjectDirectory[$0] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    private func tagsSection(revision: Revision) -> some View {
        let phids = revision.attachments?.projects?.projectPHIDs ?? []
        let unresolved = phids.filter { workspace.revisionProjectDirectory[$0] == nil }.count

        VStack(alignment: .leading, spacing: 8) {
            InspectorSectionHeader(
                title: "Tags",
                trailing: phids.isEmpty ? nil : "\(phids.count)",
                onAdd: phab.isSignedIn ? { tagPickerPresented = true } : nil
            )
            if phids.isEmpty {
                Text("No tags")
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(sortedCurrentTags) { project in
                        tagChip(project)
                    }
                    if unresolved > 0 {
                        Text("+\(unresolved) loading…")
                            .scaledFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .disabled(workspace.isUpdatingRevision)
    }

    @ViewBuilder
    private func tagChip(_ project: PhabricatorProject) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .scaledFont(.caption2)
            Text(project.name)
                .scaledFont(.caption, weight: .medium)
                .lineLimit(1)
            if phab.isSignedIn {
                Button {
                    Task { await removeTag(project) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .scaledFont(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove \(project.name)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.15), in: Capsule())
        .foregroundStyle(.primary)
    }

    @MainActor
    private func addTag(_ project: PhabricatorProject) async {
        guard !currentTagPHIDs.contains(project.phid) else { return }
        workspace.cacheProjects([project])
        if let error = await workspace.applyRevisionEdit(
            transactions: [.projectsAdd([project.phid])],
            using: phab.client
        ) {
            workspace.lastUpdateError = error.localizedDescription
        }
    }

    @MainActor
    private func removeTag(_ project: PhabricatorProject) async {
        guard currentTagPHIDs.contains(project.phid) else { return }
        if let error = await workspace.applyRevisionEdit(
            transactions: [.projectsRemove([project.phid])],
            using: phab.client
        ) {
            workspace.lastUpdateError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func propertiesSection(revision: Revision) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeader(title: "Properties")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
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
            .scaledFont(.callout)
        }
    }

    @ViewBuilder
    private func diffsSection(revision: Revision, latest: DiffDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeader(title: "Latest diff")
            HStack(spacing: 8) {
                Text(verbatim: "Diff \(latest.id)")
                    .scaledFont(.callout, design: .monospaced)
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                if let date = latest.dateCreated {
                    Text(date, format: .relative(presentation: .named))
                        .scaledFont(.caption)
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
                    .scaledFont(.callout, weight: .medium)
                if phid.hasPrefix("PHID-USER-"),
                   let user = workspace.revisionUserDirectory[phid],
                   let real = user.realName, !real.isEmpty,
                   real != user.userName {
                    Text("@\(user.userName)")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                } else if phid.hasPrefix("PHID-PROJ-") {
                    Text("Review group")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
    }

    @ViewBuilder
    private func avatar(phid: String) -> some View {
        if phid.hasPrefix("PHID-PROJ-") {
            Image(systemName: "person.2.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)
        } else if let user = workspace.revisionUserDirectory[phid], let url = user.image {
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
        if phid.hasPrefix("PHID-PROJ-"),
           let project = workspace.revisionProjectDirectory[phid] {
            return project.name
        }
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
            return AnyView(Image(systemName: "wrongwaysign.fill").foregroundStyle(.red))
        case Reviewer.Status.resigned:
            return AnyView(Image(systemName: "person.slash").foregroundStyle(.secondary))
        default:
            return AnyView(Image(systemName: "circle").foregroundStyle(.secondary))
        }
    }
}
