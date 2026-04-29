import SwiftUI
import PhabricatorKit
#if os(macOS)
import PierreDiffsSwift
#endif

struct ChangesetView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(\.openURL) private var openURL

    let changeset: Changeset
    let latestDiffID: Int

    @State private var containerWidth: CGFloat = 800

    init(changeset: Changeset, latestDiffID: Int) {
        self.changeset = changeset
        self.latestDiffID = latestDiffID
    }

    private var isExpanded: Bool {
        workspace.expandedChangesets.contains(changeset.currentPath)
    }

    private func toggleExpanded() {
        if isExpanded {
            workspace.expandedChangesets.remove(changeset.currentPath)
        } else {
            workspace.expandedChangesets.insert(changeset.currentPath)
        }
    }

    private static let splitWidthThreshold: CGFloat = 720

    var body: some View {
        @Bindable var workspace = workspace
        VStack(alignment: .leading, spacing: 0) {
            disclosureRow
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            body(for: workspace.changesetContent[changeset.id])
                .padding(.top, isExpanded ? 6 : 0)
                .frame(maxHeight: isExpanded ? .infinity : 0, alignment: .top)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        .background(diffCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.snappy(duration: 0.18), value: isExpanded)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newValue in
            containerWidth = newValue
        }
    }

    private var diffCardBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private var disclosureRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button {
                toggleExpanded()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse" : "Expand")

            ChangesetHeader(changeset: changeset)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleExpanded()
                }
        }
    }

    @ViewBuilder
    private func body(for content: ChangesetContentSource?) -> some View {
        outdatedSection
        switch content {
        case .none:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        case .binary:
            ContentUnavailableView(
                "Binary file",
                systemImage: "doc.on.doc",
                description: Text("Binary or image content isn't displayed in-app.")
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        case .hunks(let old, let new):
            #if os(macOS)
            pierreView(old: old, new: new)
            #else
            ContentUnavailableView {
                Label("Diff viewer is macOS-only for now", systemImage: "macwindow")
            } description: {
                Text("Open the revision in your browser to see the diff.")
            } actions: {
                if let revision = workspace.loadedRevision, let url = revision.fields.uri {
                    Button("Open in Browser") { openURL(url) }
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private var outdatedSection: some View {
        let outdated = workspace.loadedRevisionInlines.filter {
            $0.path == changeset.currentPath && $0.diffID != latestDiffID && !$0.isDeleted
        }
        if !outdated.isEmpty {
            DisclosureGroup("Outdated comments (\(outdated.count))") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(outdated, id: \.phid) { inline in
                        OutdatedInlineRow(inline: inline)
                    }
                }
                .padding(.vertical, 4)
            }
            .font(.callout)
        }
    }

    #if os(macOS)
    @ViewBuilder
    private func pierreView(old: String, new: String) -> some View {
        let useSplit = containerWidth >= Self.splitWidthThreshold
        let resolvedStyle: DiffStyle = useSplit ? .split : .unified
        let annotations = annotationsForFile()

        // The WebView reports its painted height as `intrinsicContentSize`
        // (see ScrollPassThroughWebView in PierreDiffsSwift); `.fixedSize`
        // tells SwiftUI to use that instead of stretching to fill the
        // ScrollView. No `@State` binding to a height value is needed.
        PierreDiffView(
            oldContent: old,
            newContent: new,
            fileName: changeset.currentPath,
            diffStyle: .constant(resolvedStyle),
            overflowMode: .constant(.wrap),
            annotations: annotations,
            onLineClickWithPosition: handleLineClick,
            onAnnotationClick: handleAnnotationClick,
            onAnnotationDelete: handleAnnotationDelete,
            onAnnotationDraftSubmit: handleDraftSubmit,
            onAnnotationDraftCancel: handleDraftCancel
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private func annotationsForFile() -> [DiffAnnotation] {
        workspace.loadedRevisionInlines.diffAnnotations(
            forPath: changeset.currentPath,
            userDirectory: workspace.revisionUserDirectory,
            currentUserPHID: phab.currentUser?.phid,
            currentUser: phab.currentUser,
            latestDiffID: latestDiffID,
            activeComposer: workspace.activeInlineComposer
        )
    }

    private func handleLineClick(position: LineClickPosition, localPoint: CGPoint) {
        // Pierre reports the click side as "additions", "deletions", or
        // "unified". A click on the deletions side anchors the comment to the
        // old file; everything else anchors to the new file.
        let isNew = position.side != "deletions"
        workspace.beginInlineComposer(
            path: changeset.currentPath,
            line: position.lineNumber,
            length: 1,
            isNewFile: isNew,
            replyTo: nil
        )
    }

    private func handleDraftSubmit(annotationID: String, commentID: String, body: String, side: String, lineNumber: Int) {
        guard let composer = workspace.activeInlineComposer,
              composer.syntheticID == annotationID || composer.syntheticID == commentID else {
            return
        }
        Task { @MainActor in
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            workspace.activeInlineComposer = nil
            if let error = await workspace.createInlineDraft(
                path: composer.path,
                line: composer.line,
                length: composer.length,
                isNewFile: composer.isNewFile,
                content: trimmed,
                replyTo: composer.replyTo,
                using: phab.client
            ) {
                workspace.lastUpdateError = error.localizedDescription
                // Re-open the composer with the user's draft so they don't lose
                // their text.
                workspace.beginInlineComposer(
                    path: composer.path,
                    line: composer.line,
                    length: composer.length,
                    isNewFile: composer.isNewFile,
                    replyTo: composer.replyTo
                )
            }
        }
    }

    private func handleDraftCancel(annotationID: String, commentID: String, side: String, lineNumber: Int) {
        if let composer = workspace.activeInlineComposer,
           composer.syntheticID == annotationID || composer.syntheticID == commentID {
            workspace.activeInlineComposer = nil
        }
    }

    private func handleAnnotationClick(id: String, side: String, lineNumber: Int, localPoint: CGPoint) {
        // Tapping an existing thread starts an in-diff reply on that thread.
        let isNew = side != "deletions"
        workspace.beginInlineComposer(
            path: changeset.currentPath,
            line: lineNumber,
            length: 1,
            isNewFile: isNew,
            replyTo: id
        )
    }

    private func handleAnnotationDelete(id: String, side: String, lineNumber: Int) {
        guard let inline = workspace.loadedRevisionInlines.first(where: { $0.phid == id }) else { return }
        let myPHID = phab.currentUser?.phid
        guard inline.transactionPHID == nil, inline.authorPHID == myPHID else { return }
        Task {
            _ = await workspace.deleteInlineDraft(phid: id, using: phab.client)
        }
    }
    #endif
}

struct ChangesetHeader: View {
    let changeset: Changeset

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
            pathText
                .font(.callout.monospaced())
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Spacer(minLength: 8)
            if changeset.addLines > 0 {
                pill(text: "+\(changeset.addLines)", color: .green)
            }
            if changeset.delLines > 0 {
                pill(text: "−\(changeset.delLines)", color: .red)
            }
            if let typeLabel {
                pill(text: typeLabel, color: .blue)
            }
        }
        .contentShape(Rectangle())
    }

    private var pathText: Text {
        if let oldPath = changeset.oldPath, oldPath != changeset.currentPath {
            return Text(oldPath).foregroundStyle(.secondary)
                + Text(" → ").foregroundStyle(.secondary)
                + Text(changeset.currentPath)
        }
        return Text(changeset.currentPath)
    }

    private var iconName: String {
        switch changeset.fileType {
        case .image: return "photo"
        case .binary: return "doc.on.doc"
        case .symlink: return "link"
        case .directory: return "folder"
        default:
            switch changeset.type {
            case .add: return "doc.badge.plus"
            case .delete: return "doc.badge.minus"
            case .moveHere, .copyHere: return "arrow.turn.right.up"
            default: return "doc.text"
            }
        }
    }

    private var typeLabel: String? {
        switch changeset.type {
        case .add: return "New"
        case .delete: return "Deleted"
        case .moveHere: return "Moved"
        case .copyHere: return "Copied"
        case .multicopy: return "Copied"
        default: return nil
        }
    }

    private func pill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

struct OutdatedInlineRow: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openURL) private var openURL
    let inline: InlineComment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if let phid = inline.authorPHID,
                   let user = workspace.revisionUserDirectory[phid] {
                    Text(user.realName ?? user.userName)
                        .font(.callout.weight(.medium))
                }
                Text(inline.content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("View in Browser") {
                    if let revision = workspace.loadedRevision,
                       let url = URL(string: "https://phabricator.services.mozilla.com/D\(revision.id)#inline-\(inline.phid)") {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(8)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}
