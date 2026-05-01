import SwiftUI
import SwiftData
import PhabricatorKit
import Folio
import FolioModel
import FolioHighlight

struct ChangesetView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext

    let changeset: Changeset
    let latestDiffID: Int

    @State private var containerWidth: CGFloat = 800
    @State private var showAllHunks: Bool = false
    @State private var lineSelection: FolioLineSelection?
    #if os(iOS)
    @State private var threadSheetRequest: ThreadSheetRequest?
    @State private var composerSheetRequest: ComposerSheetRequest?

    struct ThreadSheetRequest: Identifiable {
        let rootPHID: String
        var id: String { rootPHID }
    }

    struct ComposerSheetRequest: Identifiable {
        let line: Int
        let length: Int
        let isNewFile: Bool
        var id: String { "\(line)-\(length)-\(isNewFile)" }
    }
    #endif

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
            if isExpanded {
                body(for: workspace.changesetContent[changeset.id])
                    .padding(.top, 6)
            }
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
            #if os(macOS)
            .fill(Color(nsColor: .controlBackgroundColor))
            #else
            .fill(Color(uiColor: .secondarySystemBackground))
            #endif
    }

    private var disclosureRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button {
                toggleExpanded()
            } label: {
                Image(systemName: "chevron.right")
                    .scaledFont(.caption, weight: .semibold)
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
        case .hunks:
            folioView()
        }
    }

    @ViewBuilder
    private func folioView() -> some View {
        let totalHunks = changeset.hunks.count
        let visibleCount = showAllHunks ? totalHunks : min(1, totalHunks)
        let visibleHunks = changeset.hunks.prefix(visibleCount).map { hunk in
            UnifiedDiffParser.parse(
                corpus: hunk.corpus,
                oldStart: hunk.oldOffset,
                newStart: hunk.newOffset
            )
        }
        let mode: DiffViewMode = (containerWidth >= Self.splitWidthThreshold) ? .split : .unified
        let theme: HighlightTheme = (colorScheme == .dark) ? .dark : .light
        let visibleInlines = visibleInlineComments()
        let threadsByRoot = threads(in: visibleInlines)
        let marks = commentMarks(from: threadsByRoot)
        let hiddenLineEstimate = changeset.hunks
            .dropFirst(visibleCount)
            .reduce(0) { $0 + max($1.oldLen, $1.newLen) }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleHunks.enumerated()), id: \.offset) { _, parsed in
                FolioView(
                    path: changeset.currentPath,
                    content: .diff(parsed, anchor: nil, mode: mode),
                    showsHeader: false,
                    theme: theme,
                    cornerRadius: 0,
                    commentMarks: marks,
                    selection: $lineSelection,
                    onCommentMarkTap: handleCommentMarkTap,
                    onCreateComment: handleCreateComment,
                    threadSlot: macThreadSlot(threadsByRoot: threadsByRoot),
                    composerSlot: macComposerSlot()
                )
                .frame(maxWidth: .infinity)
            }
            if totalHunks > visibleCount {
                ExpandContextRow(
                    label: expandLabel(remainingHunks: totalHunks - visibleCount, lines: hiddenLineEstimate),
                    theme: theme,
                    onExpandFromTop: {
                        withAnimation(.snappy(duration: 0.18)) {
                            showAllHunks = true
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
        #if os(iOS)
        .sheet(item: $threadSheetRequest) { req in
            let visible = visibleInlineComments()
            let threads = threads(in: visible)
            let thread = threads[req.rootPHID] ?? []
            InlineThreadSheet(
                rootPHID: req.rootPHID,
                thread: thread,
                userDirectory: workspace.revisionUserDirectory,
                currentUserPHID: phab.currentUser?.phid,
                onEditDraft: handleEditDraft,
                onDeleteDraft: handleDeleteDraft
            )
        }
        .sheet(item: $composerSheetRequest) { req in
            InlineComposerSheet(
                path: changeset.currentPath,
                line: req.line,
                length: req.length,
                isNewFile: req.isNewFile,
                replyTo: nil,
                titleText: "New comment"
            )
        }
        #endif
    }

    private func macThreadSlot(threadsByRoot: [String: [InlineComment]]) -> ((FolioCommentMark) -> AnyView)? {
        #if os(macOS)
        return { mark in
            let thread = threadsByRoot[mark.id] ?? []
            let composerForThread = composerActiveForThread(thread: thread, mark: mark)
            return AnyView(
                InlineThreadView(
                    thread: thread,
                    userDirectory: workspace.revisionUserDirectory,
                    currentUserPHID: phab.currentUser?.phid,
                    onReply: { handleReply(mark: mark) },
                    onEditDraft: handleEditDraft,
                    onDeleteDraft: handleDeleteDraft,
                    composerContent: composerForThread.map { active in
                        { AnyView(composerHost(for: active, chromed: false)) }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            )
        }
        #else
        return nil
        #endif
    }

    private func composerActiveForThread(thread: [InlineComment], mark: FolioCommentMark) -> ActiveInlineComposer? {
        guard let active = workspace.activeInlineComposer,
              active.path == changeset.currentPath else {
            return nil
        }
        if active.replyTo == mark.id { return active }
        if let editing = active.editingPHID, thread.contains(where: { $0.phid == editing }) {
            return active
        }
        return nil
    }

    @ViewBuilder
    private func composerHost(for active: ActiveInlineComposer, chromed: Bool) -> some View {
        InlineComposerHost(
            path: active.path,
            line: active.line,
            length: active.length,
            isNewFile: active.isNewFile,
            replyTo: active.replyTo,
            editingPHID: active.editingPHID,
            chromed: chromed
        )
    }

    private func macComposerSlot() -> FolioComposerSlot? {
        #if os(macOS)
        guard let active = workspace.activeInlineComposer,
              active.path == changeset.currentPath else {
            return nil
        }
        if active.replyTo != nil || active.editingPHID != nil {
            return nil
        }
        let isNewFile = active.isNewFile
        return FolioComposerSlot(
            line: active.line,
            side: isNewFile ? .newFile : .oldFile,
            content: {
                AnyView(
                    composerHost(for: active, chromed: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                )
            }
        )
        #else
        return nil
        #endif
    }

    private func expandLabel(remainingHunks: Int, lines: Int) -> String {
        let hunkLabel = remainingHunks == 1 ? "1 more hunk" : "\(remainingHunks) more hunks"
        let lineLabel = lines == 1 ? "1 line" : "\(lines) lines"
        return "Show \(hunkLabel) · \(lineLabel)"
    }

    private func visibleInlineComments() -> [InlineComment] {
        let onLatest = workspace.loadedRevisionInlines.filter {
            $0.diffID == latestDiffID && $0.path == changeset.currentPath && !$0.isDeleted
        }
        let myPHID = phab.currentUser?.phid
        return onLatest.filter { inline in
            inline.transactionPHID != nil || inline.authorPHID == myPHID
        }
    }

    private func threads(in visible: [InlineComment]) -> [String: [InlineComment]] {
        let visiblePHIDs = Set(visible.map(\.phid))
        let roots = visible.filter { inline in
            guard let parent = inline.replyToCommentPHID else { return true }
            return !visiblePHIDs.contains(parent)
        }
        var result: [String: [InlineComment]] = [:]
        let byCreated: (InlineComment, InlineComment) -> Bool = { lhs, rhs in
            (lhs.dateCreated ?? .distantPast) < (rhs.dateCreated ?? .distantPast)
        }
        for root in roots {
            var collected: [InlineComment] = [root]
            var queue: [String] = [root.phid]
            while let parent = queue.popLast() {
                let children = visible
                    .filter { $0.replyToCommentPHID == parent }
                    .sorted(by: byCreated)
                for child in children {
                    collected.append(child)
                    queue.append(child.phid)
                }
            }
            result[root.phid] = collected
        }
        return result
    }

    private func commentMarks(from threadsByRoot: [String: [InlineComment]]) -> [FolioCommentMark] {
        threadsByRoot.compactMap { _, thread in
            guard let root = thread.first else { return nil }
            return FolioCommentMark(
                id: root.phid,
                side: root.isNewFile ? .newFile : .oldFile,
                line: root.line,
                count: thread.count
            )
        }
    }

    private func handleCreateComment(line: Int, side: AnchorRange.Side) {
        let startLine: Int
        let length: Int
        if let sel = lineSelection, sel.side == side, sel.contains(line) {
            startLine = sel.startLine
            length = sel.endLine - sel.startLine + 1
        } else {
            startLine = line
            length = 1
        }
        workspace.beginInlineComposer(
            path: changeset.currentPath,
            line: startLine,
            length: length,
            isNewFile: side == .newFile,
            replyTo: nil
        )
        #if os(iOS)
        composerSheetRequest = ComposerSheetRequest(
            line: startLine,
            length: length,
            isNewFile: side == .newFile
        )
        #endif
        lineSelection = nil
    }

    private func handleCommentMarkTap(_ mark: FolioCommentMark) {
        #if os(iOS)
        threadSheetRequest = ThreadSheetRequest(rootPHID: mark.id)
        #endif
    }

    private func handleReply(mark: FolioCommentMark) {
        workspace.beginInlineComposer(
            path: changeset.currentPath,
            line: mark.line,
            length: 1,
            isNewFile: mark.side == .newFile,
            replyTo: mark.id
        )
    }

    private func handleEditDraft(comment: InlineComment) {
        guard let revision = workspace.loadedRevision,
              let diffID = workspace.loadedRevisionDiff?.id else { return }
        let key = InlineDraftKey(
            revisionID: revision.id,
            diffID: diffID,
            path: comment.path,
            line: comment.line,
            isNewFile: comment.isNewFile,
            replyTo: comment.replyToCommentPHID
        )
        modelContext.saveInlineDraft(key, length: max(1, comment.length), content: comment.content)
        workspace.beginInlineComposer(
            path: comment.path,
            line: comment.line,
            length: max(1, comment.length),
            isNewFile: comment.isNewFile,
            replyTo: comment.replyToCommentPHID,
            editingPHID: comment.phid
        )
    }

    private func handleDeleteDraft(comment: InlineComment) {
        let phid = comment.phid
        let client = phab.client
        Task { @MainActor in
            if let error = await workspace.deleteInlineDraft(phid: phid, using: client) {
                workspace.lastUpdateError = error.localizedDescription
            }
        }
    }

}

struct ChangesetHeader: View {
    let changeset: Changeset

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
            pathText
                .scaledFont(.callout, design: .monospaced)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .truncationMode(.head)
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
            .scaledFont(.caption, weight: .semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

