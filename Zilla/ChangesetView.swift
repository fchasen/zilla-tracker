import SwiftUI
import PhabricatorKit
import Folio
import FolioModel
import FolioHighlight

struct ChangesetView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    let changeset: Changeset
    let latestDiffID: Int

    @State private var containerWidth: CGFloat = 800
    @State private var showAllHunks: Bool = false

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
        let marks = commentMarks()
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
                    onCommentMarkTap: handleCommentMarkTap,
                    onCreateComment: handleCreateComment
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
    }

    private func expandLabel(remainingHunks: Int, lines: Int) -> String {
        let hunkLabel = remainingHunks == 1 ? "1 more hunk" : "\(remainingHunks) more hunks"
        let lineLabel = lines == 1 ? "1 line" : "\(lines) lines"
        return "Show \(hunkLabel) · \(lineLabel)"
    }

    private func commentMarks() -> [FolioCommentMark] {
        let onLatest = workspace.loadedRevisionInlines.filter {
            $0.diffID == latestDiffID && $0.path == changeset.currentPath && !$0.isDeleted
        }
        let myPHID = phab.currentUser?.phid
        let visible = onLatest.filter { inline in
            inline.transactionPHID != nil || inline.authorPHID == myPHID
        }
        guard !visible.isEmpty else { return [] }

        let visiblePHIDs = Set(visible.map(\.phid))
        let roots = visible.filter { inline in
            guard let parent = inline.replyToCommentPHID else { return true }
            return !visiblePHIDs.contains(parent)
        }

        return roots.map { root in
            let count = threadSize(rootPHID: root.phid, in: visible)
            return FolioCommentMark(
                id: root.phid,
                side: root.isNewFile ? .newFile : .oldFile,
                line: root.line,
                count: count
            )
        }
    }

    private func threadSize(rootPHID: String, in inlines: [InlineComment]) -> Int {
        var count = 1
        var stack: [String] = [rootPHID]
        while let parent = stack.popLast() {
            for child in inlines where child.replyToCommentPHID == parent {
                count += 1
                stack.append(child.phid)
            }
        }
        return count
    }

    private func handleCreateComment(line: Int, side: AnchorRange.Side) {
        workspace.beginInlineComposer(
            path: changeset.currentPath,
            line: line,
            length: 1,
            isNewFile: side == .newFile,
            replyTo: nil
        )
    }

    private func handleCommentMarkTap(_ mark: FolioCommentMark) {
        workspace.beginInlineComposer(
            path: changeset.currentPath,
            line: mark.line,
            length: 1,
            isNewFile: mark.side == .newFile,
            replyTo: mark.id
        )
    }
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
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

