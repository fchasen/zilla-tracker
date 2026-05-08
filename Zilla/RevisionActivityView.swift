import SwiftUI
import PhabricatorKit
import Textual
import FolioCodeView
import FolioModel
import FolioHighlight

struct RevisionActivityView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                InspectorSectionHeader(
                    title: "Activity",
                    trailing: visibleTransactions.isEmpty
                        ? nil
                        : "\(visibleTransactions.count)"
                )
                Spacer()
                if hiddenCount > 0 || workspace.activityShowAll {
                    let toggle = Toggle("Show all", isOn: $workspace.activityShowAll)
                        .controlSize(.small)
                        .help(workspace.activityShowAll
                              ? "Hide non-comment activity"
                              : "\(hiddenCount) non-comment item\(hiddenCount == 1 ? "" : "s") hidden")
                    #if os(macOS)
                    toggle.toggleStyle(.checkbox)
                    #else
                    toggle.toggleStyle(.button)
                        .scaledFont(.caption)
                    #endif
                }
            }
            if workspace.loadedRevisionTransactions.isEmpty {
                Text("No activity yet.")
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
            } else if visibleTransactions.isEmpty {
                Text("No comments yet.")
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleTransactions, id: \.id) { transaction in
                        ActivityRow(transaction: transaction)
                    }
                }
            }
        }
    }

    private var sortedTransactions: [RevisionTransaction] {
        workspace.loadedRevisionTransactions.sorted { $0.dateCreated < $1.dateCreated }
    }

    private var visibleTransactions: [RevisionTransaction] {
        workspace.activityShowAll
            ? sortedTransactions
            : sortedTransactions.filter(\.isComment)
    }

    private var hiddenCount: Int {
        sortedTransactions.count - sortedTransactions.filter(\.isComment).count
    }
}

struct ActivityRow: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(\.colorScheme) private var colorScheme
    let transaction: RevisionTransaction
    @State private var rowWidth: CGFloat = 800

    private static let narrowThreshold: CGFloat = 560

    var body: some View {
        Group {
            if isCompact {
                compactRow
                    .padding(rowPadding)
            } else if isNarrow {
                narrowRow
                    .padding(.vertical, rowPadding)
            } else {
                expandedRow
                    .padding(rowPadding)
            }
        }
        .background {
            if isCommentLike {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
        }
        .overlay {
            if isCommentLike {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newValue in
            rowWidth = newValue
        }
    }

    private var isCommentLike: Bool {
        switch transaction.kind {
        case .comment, .inline: return true
        default: return false
        }
    }

    private var rowPadding: CGFloat {
        isCommentLike ? 12 : 4
    }

    private var isNarrow: Bool {
        rowWidth < Self.narrowThreshold
    }

    private var expandedRow: some View {
        HStack(alignment: .top, spacing: 12) {
            if isCommentLike {
                avatar(size: 28)
            }
            VStack(alignment: .leading, spacing: 4) {
                headerLine
                bodyView(narrow: false)
            }
            Spacer(minLength: 0)
        }
    }

    private var compactRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if isCommentLike {
                avatar(size: 22)
            }
            headerLine
            Spacer(minLength: 0)
        }
    }

    private var narrowRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                if isCommentLike {
                    avatar(size: 22)
                }
                headerLine
                Spacer(minLength: 0)
            }
            .padding(.horizontal, isCommentLike ? 12 : 0)
            bodyView(narrow: true)
        }
    }

    private var headerLine: some View {
        HStack(spacing: 6) {
            if !isCommentLike, let icon = activityIcon {
                Image(systemName: icon.systemName)
                    .scaledFont(.callout)
                    .foregroundStyle(icon.tint ?? Color.secondary)
            }
            Text(authorName)
                .scaledFont(.callout, weight: .semibold)
            if case .buildStatus(_, let new) = transaction.kind {
                Text("reported a build")
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
                BuildStatusPill(status: new)
            } else if let caption = activityCaption {
                Text(caption)
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: "·")
                .foregroundStyle(.tertiary)
            Text(transaction.dateCreated, format: .relative(presentation: .named))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isCompact: Bool {
        if isInline { return false }
        if primaryCommentBody != nil { return false }
        return !hasStructuredBody
    }

    private var hasStructuredBody: Bool {
        switch transaction.kind {
        case .titleChange, .summaryChange, .testPlanChange,
             .statusChange, .bugIDChange,
             .reviewersChanged, .subscribersChanged, .projectsChanged:
            return true
        case .diffUpdate(let id, _):
            return id != nil
        default:
            return false
        }
    }

    @ViewBuilder
    private func avatar(size: CGFloat) -> some View {
        let user = transaction.authorPHID.flatMap { workspace.revisionUserDirectory[$0] }
        UserAvatar(
            email: user?.primaryEmail,
            size: size,
            imageURL: user?.image
        )
    }

    private var authorName: String {
        if let phid = transaction.authorPHID {
            if let user = workspace.revisionUserDirectory[phid] {
                return user.realName ?? user.userName
            }
            if let system = SystemActor.displayName(forPHID: phid) {
                return system
            }
        }
        return "Someone"
    }

    @ViewBuilder
    private func bodyView(narrow: Bool) -> some View {
        if isInline, let inlineDescriptor {
            VStack(alignment: .leading, spacing: 6) {
                if isThreadHead, let hunk = anchoredHunk(for: inlineDescriptor) {
                    FolioView(
                        path: inlineDescriptor.path,
                        content: .diff(
                            hunk,
                            anchor: AnchorRange(
                                line: inlineDescriptor.line,
                                length: max(1, transaction.fields.length ?? 1),
                                side: (transaction.fields.isNewFile ?? true) ? .newFile : .oldFile
                            ),
                            mode: .unified
                        ),
                        isOutdated: isOutdatedAgainstLatestDiff,
                        theme: colorScheme == .dark ? .dark : .light,
                        cornerRadius: sliverCornerRadius(narrow: narrow),
                        onPathTap: { workspace.revealChangeset(path: inlineDescriptor.path) },
                        isExpandable: false,
                        contextLinesBelow: 0,
                        roundsBottomCorners: false
                    )
                } else {
                    inlineFileLink(inlineDescriptor)
                        .padding(.horizontal, narrow ? 12 : 0)
                }
                if let body = primaryCommentBody, !body.isEmpty {
                    RemarkupText(source: body)
                        .scaledFont(.callout)
                        .textSelection(.enabled)
                        .padding(.horizontal, narrow ? 12 : 0)
                }
            }
        } else if let body = primaryCommentBody {
            RemarkupText(source: body)
                .scaledFont(.callout)
                .textSelection(.enabled)
                .padding(.horizontal, narrow ? 12 : 0)
        } else {
            structuredBody(narrow: narrow)
                .padding(.horizontal, narrow ? 12 : 0)
        }
    }

    @ViewBuilder
    private func structuredBody(narrow _: Bool) -> some View {
        switch transaction.kind {
        case .titleChange(let old, let new):
            ActivityTextDelta(label: "Title", old: old, new: new, monospaced: false, lineLimit: 2)
        case .summaryChange(let old, let new):
            ActivityTextDelta(label: "Summary", old: old, new: new, monospaced: false, lineLimit: 4)
        case .testPlanChange(let old, let new):
            ActivityTextDelta(label: "Test plan", old: old, new: new, monospaced: false, lineLimit: 4)
        case .statusChange(let old, let new):
            ActivityStatusPills(old: old, new: new)
        case .bugIDChange(let old, let new):
            ActivityBugLink(old: old, new: new)
        case .diffUpdate(let diffID, _):
            ActivityDiffPill(diffID: diffID, isLatest: diffID == workspace.loadedRevisionDiff?.id)
        case .reviewersChanged(let operations):
            ActivityReviewerChips(
                operations: operations,
                userDirectory: workspace.revisionUserDirectory,
                projectDirectory: workspace.revisionProjectDirectory
            )
        case .subscribersChanged(let adds, let removes):
            ActivityPHIDChips(
                adds: adds,
                removes: removes,
                userDirectory: workspace.revisionUserDirectory,
                projectDirectory: workspace.revisionProjectDirectory
            )
        case .projectsChanged(let adds, let removes):
            ActivityPHIDChips(
                adds: adds,
                removes: removes,
                userDirectory: workspace.revisionUserDirectory,
                projectDirectory: workspace.revisionProjectDirectory
            )
        case .comment, .inline, .verb, .columnsChanged, .buildStatus, .unknown:
            EmptyView()
        }
    }

    static func humanizeBuildStatusStatic(_ raw: String?) -> String {
        switch (raw ?? "").lowercased() {
        case "0", "preparing":                return "Preparing"
        case "1", "building", "inprogress":   return "Building"
        case "2", "passed":                   return "Passed"
        case "3", "failed":                   return "Failed"
        case "4", "aborted":                  return "Aborted"
        case "5", "error", "errored":         return "Error"
        case "6", "paused":                   return "Paused"
        case "7", "deadlocked":               return "Deadlocked"
        default:
            if let raw, !raw.isEmpty { return raw.capitalized }
            return "Updated"
        }
    }

    private var isThreadHead: Bool {
        transaction.fields.replyToCommentPHID == nil
    }

    private func sliverCornerRadius(narrow: Bool) -> CGFloat {
        #if os(iOS)
        return 0
        #else
        return narrow ? 0 : 6
        #endif
    }

    private var isOutdatedAgainstLatestDiff: Bool {
        guard let txDiffID = transaction.fields.diffID,
              let loadedID = workspace.loadedRevisionDiff?.id else {
            return false
        }
        return txDiffID != loadedID
    }

    private func anchoredHunk(for descriptor: InlineDescriptor) -> DiffHunk? {
        FolioActivityIntegration.anchoredHunk(
            in: workspace.loadedRevisionDiff,
            path: descriptor.path,
            line: descriptor.line,
            side: (transaction.fields.isNewFile ?? true) ? .newFile : .oldFile
        )
    }

    private var isInline: Bool {
        transaction.fields.path != nil && transaction.fields.line != nil
    }

    private struct InlineDescriptor {
        let path: String
        let line: Int
    }

    private var inlineDescriptor: InlineDescriptor? {
        guard let path = transaction.fields.path,
              let line = transaction.fields.line else { return nil }
        return InlineDescriptor(path: path, line: line)
    }

    @ViewBuilder
    private func inlineFileLink(_ descriptor: InlineDescriptor) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "text.bubble")
                .scaledFont(.caption2)
                .foregroundStyle(.secondary)
            let jumpButton = Button {
                workspace.revealChangeset(path: descriptor.path)
            } label: {
                Text("\(descriptor.path):\(descriptor.line)")
                    .scaledFont(.callout, design: .monospaced)
                    .foregroundStyle(.tint)
                    .underline(true, color: .clear)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .buttonStyle(.plain)
            .help("Jump to \(descriptor.path):\(descriptor.line)")
            #if os(macOS)
            jumpButton.pointerStyle(.link)
            #else
            jumpButton
            #endif
        }
    }

    private var primaryCommentBody: String? {
        switch transaction.type {
        case "comment", "inline":
            return transaction.comments.last(where: { ($0.removed ?? false) == false })?.content.raw
        default:
            // Some Phabricator forks report different inline transaction
            // type strings; fall back to the comment body when fields suggest
            // an inline anchor.
            if isInline {
                return transaction.comments.last(where: { ($0.removed ?? false) == false })?.content.raw
            }
            return nil
        }
    }

    private var activityCaption: String? {
        switch transaction.kind {
        case .comment, .inline:
            return nil
        case .titleChange:
            return "edited the title"
        case .summaryChange:
            return "edited the summary"
        case .testPlanChange:
            return "edited the test plan"
        case .statusChange:
            return "changed status"
        case .bugIDChange:
            return "linked a bug"
        case .diffUpdate(let id, _):
            if let id { return "uploaded Diff \(id)" }
            return "uploaded a new diff"
        case .reviewersChanged(let ops):
            return reviewersCaption(for: ops)
        case .subscribersChanged(let adds, let removes):
            return chipsCaption(noun: "subscriber", adds: adds.count, removes: removes.count)
        case .projectsChanged(let adds, let removes):
            return chipsCaption(noun: "tag", adds: adds.count, removes: removes.count)
        case .columnsChanged:
            return "moved on the workboard"
        case .buildStatus(_, let new):
            return "build \(humanizeBuildStatus(new))"
        case .verb(.accept):         return "accepted this revision"
        case .verb(.reject):         return "rejected this revision"
        case .verb(.requestChanges): return "requested changes"
        case .verb(.abandon):        return "abandoned this revision"
        case .verb(.reclaim):        return "reclaimed this revision"
        case .verb(.reopen):         return "reopened this revision"
        case .verb(.close):          return "closed this revision"
        case .verb(.planChanges):    return "planned changes"
        case .verb(.requestReview):  return "requested review"
        case .verb(.resign):         return "resigned as a reviewer"
        case .verb(.create):         return "created this revision"
        case .verb(.commandeer):     return "commandeered this revision"
        case .verb(.mfaConfirmed):   return "confirmed via MFA"
        case .unknown(let raw):
            return humanizeUnknownType(raw)
        }
    }

    private func humanizeUnknownType(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func humanizeBuildStatus(_ raw: String?) -> String {
        switch (raw ?? "").lowercased() {
        case "0", "preparing":                return "preparing"
        case "1", "building", "inprogress":   return "building"
        case "2", "passed":                   return "passed"
        case "3", "failed":                   return "failed"
        case "4", "aborted":                  return "aborted"
        case "5", "error", "errored":         return "errored"
        case "6", "paused":                   return "paused"
        case "7", "deadlocked":               return "deadlocked"
        default:
            if let raw, !raw.isEmpty { return raw }
            return "updated"
        }
    }

    private func chipsCaption(noun: String, adds: Int, removes: Int) -> String {
        if adds > 0 && removes == 0 { return "added \(adds) \(noun)\(adds == 1 ? "" : "s")" }
        if removes > 0 && adds == 0 { return "removed \(removes) \(noun)\(removes == 1 ? "" : "s")" }
        return "updated \(noun)s"
    }

    private func reviewersCaption(for ops: [RevisionTransaction.TransactionFields.Operation]) -> String {
        let adds = ops.filter { $0.operation == "add" }.count
        let removes = ops.filter { $0.operation == "remove" }.count
        let updates = ops.filter { $0.operation == "update" }.count
        if updates > 0 && adds == 0 && removes == 0 { return "updated reviewer status" }
        return chipsCaption(noun: "reviewer", adds: adds, removes: removes)
    }

    private struct ActivityIcon {
        let systemName: String
        let tint: Color?
    }

    private var activityIcon: ActivityIcon? {
        switch transaction.kind {
        case .comment:               return ActivityIcon(systemName: "bubble.left", tint: nil)
        case .inline:                return ActivityIcon(systemName: "text.bubble", tint: nil)
        case .titleChange:           return ActivityIcon(systemName: "pencil", tint: nil)
        case .summaryChange:         return ActivityIcon(systemName: "text.alignleft", tint: nil)
        case .testPlanChange:        return ActivityIcon(systemName: "checklist", tint: nil)
        case .statusChange:          return ActivityIcon(systemName: "arrow.right.circle", tint: nil)
        case .bugIDChange:           return ActivityIcon(systemName: "ladybug", tint: nil)
        case .diffUpdate:            return ActivityIcon(systemName: "arrow.triangle.2.circlepath", tint: .blue)
        case .reviewersChanged:      return ActivityIcon(systemName: "person.2", tint: nil)
        case .subscribersChanged:    return ActivityIcon(systemName: "bell", tint: nil)
        case .projectsChanged:       return ActivityIcon(systemName: "tag", tint: nil)
        case .columnsChanged:        return ActivityIcon(systemName: "rectangle.split.3x1", tint: nil)
        case .buildStatus(_, let new):
            return buildStatusIcon(for: new)
        case .verb(.accept):         return ActivityIcon(systemName: "checkmark.seal.fill", tint: .green)
        case .verb(.reject),
             .verb(.requestChanges): return ActivityIcon(systemName: "exclamationmark.triangle.fill", tint: .orange)
        case .verb(.abandon):        return ActivityIcon(systemName: "archivebox.fill", tint: nil)
        case .verb(.reclaim):        return ActivityIcon(systemName: "arrow.uturn.backward.circle", tint: .blue)
        case .verb(.reopen):         return ActivityIcon(systemName: "arrow.up.circle.fill", tint: .blue)
        case .verb(.close):          return ActivityIcon(systemName: "lock.fill", tint: nil)
        case .verb(.planChanges):    return ActivityIcon(systemName: "pencil.circle.fill", tint: .yellow)
        case .verb(.requestReview):  return ActivityIcon(systemName: "paperplane.fill", tint: .blue)
        case .verb(.resign):         return ActivityIcon(systemName: "person.crop.circle.badge.minus", tint: nil)
        case .verb(.create):         return ActivityIcon(systemName: "sparkles", tint: .blue)
        case .verb(.commandeer):     return ActivityIcon(systemName: "person.badge.shield.checkmark", tint: nil)
        case .verb(.mfaConfirmed):   return ActivityIcon(systemName: "key.fill", tint: nil)
        case .unknown:               return ActivityIcon(systemName: "circle.dashed", tint: nil)
        }
    }

    private func buildStatusIcon(for raw: String?) -> ActivityIcon {
        switch (raw ?? "").lowercased() {
        case "2", "passed":
            return ActivityIcon(systemName: "checkmark.circle.fill", tint: .green)
        case "3", "failed", "5", "error", "errored", "7", "deadlocked":
            return ActivityIcon(systemName: "xmark.octagon.fill", tint: .red)
        case "4", "aborted":
            return ActivityIcon(systemName: "stop.circle.fill", tint: nil)
        case "6", "paused":
            return ActivityIcon(systemName: "pause.circle.fill", tint: nil)
        default:
            return ActivityIcon(systemName: "hammer.fill", tint: .blue)
        }
    }
}

private struct ActivityTextDelta: View {
    let label: String
    let old: String?
    let new: String?
    let monospaced: Bool
    let lineLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(label):")
                    .scaledFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                if let new = displayNew, !new.isEmpty {
                    Text(new)
                        .scaledFont(.callout, design: monospaced ? .monospaced : .default)
                        .lineLimit(lineLimit)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                } else {
                    Text("(empty)")
                        .scaledFont(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            if let old = displayOld, !old.isEmpty, old != displayNew {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("was:")
                        .scaledFont(.caption)
                        .foregroundStyle(.tertiary)
                    Text(old)
                        .scaledFont(.caption, design: monospaced ? .monospaced : .default)
                        .strikethrough(true, color: .secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var displayNew: String? { new?.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var displayOld: String? { old?.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private struct ActivityStatusPills: View {
    let old: String?
    let new: String?

    var body: some View {
        HStack(spacing: 6) {
            if let old, !old.isEmpty {
                pill(text: humanize(old), tint: tint(for: old))
                    .opacity(0.6)
                Image(systemName: "arrow.right")
                    .scaledFont(.caption2)
                    .foregroundStyle(.tertiary)
            }
            pill(text: humanize(new ?? "?"), tint: tint(for: new ?? ""))
        }
    }

    private func pill(text: String, tint: Color) -> some View {
        Text(text)
            .scaledFont(.caption, weight: .medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private func humanize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func tint(for status: String) -> Color {
        switch status {
        case "accepted": return .green
        case "needs-review": return .blue
        case "needs-revision", "changes-planned": return .orange
        case "abandoned": return .secondary
        case "published", "closed": return .purple
        case "draft": return .secondary
        default: return .secondary
        }
    }
}

private struct ActivityBugLink: View {
    let old: String?
    let new: String?

    var body: some View {
        HStack(spacing: 6) {
            if let oldText, !oldText.isEmpty {
                Text("Bug \(oldText)")
                    .scaledFont(.caption, design: .monospaced)
                    .strikethrough(true, color: .secondary)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .scaledFont(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let newText, !newText.isEmpty {
                Text("Bug \(newText)")
                    .scaledFont(.callout, design: .monospaced)
                    .textSelection(.enabled)
            } else {
                Text("(unlinked)")
                    .scaledFont(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var oldText: String? { old?.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var newText: String? { new?.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private struct BuildStatusPill: View {
    let status: String?

    var body: some View {
        Text(ActivityRow.humanizeBuildStatusStatic(status))
            .scaledFont(.caption, weight: .medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch (status ?? "").lowercased() {
        case "2", "passed": return .green
        case "3", "failed", "5", "error", "errored", "7", "deadlocked": return .red
        case "4", "aborted", "6", "paused": return .secondary
        case "0", "preparing", "1", "building", "inprogress": return .blue
        default: return .secondary
        }
    }
}

private struct ActivityDiffPill: View {
    let diffID: Int?
    let isLatest: Bool

    var body: some View {
        if let diffID {
            HStack(spacing: 6) {
                Text("Diff \(diffID)")
                    .scaledFont(.caption, weight: .medium, design: .monospaced)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15), in: Capsule())
                    .foregroundStyle(.blue)
                if isLatest {
                    Text("(latest)")
                        .scaledFont(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct ActivityReviewerChips: View {
    let operations: [RevisionTransaction.TransactionFields.Operation]
    let userDirectory: [String: PhabricatorUser]
    let projectDirectory: [String: PhabricatorProject]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !adds.isEmpty {
                chipRow(symbol: "plus", tint: .green, items: adds.map(label(for:)))
            }
            if !removes.isEmpty {
                chipRow(symbol: "minus", tint: .red, items: removes.map(label(for:)))
            }
            if !updates.isEmpty {
                chipRow(symbol: "arrow.right", tint: .secondary, items: updates.map(label(for:)))
            }
        }
    }

    private var adds: [RevisionTransaction.TransactionFields.Operation] {
        operations.filter { $0.operation == "add" }
    }
    private var removes: [RevisionTransaction.TransactionFields.Operation] {
        operations.filter { $0.operation == "remove" }
    }
    private var updates: [RevisionTransaction.TransactionFields.Operation] {
        operations.filter { ($0.operation ?? "") != "add" && ($0.operation ?? "") != "remove" }
    }

    private func label(for op: RevisionTransaction.TransactionFields.Operation) -> String {
        let name: String
        if let phid = op.phid {
            if let user = userDirectory[phid] {
                name = user.realName ?? user.userName
            } else if let proj = projectDirectory[phid] {
                name = "#\(proj.slug ?? proj.name)"
            } else {
                name = phid.replacingOccurrences(of: "PHID-USER-", with: "@")
                    .replacingOccurrences(of: "PHID-PROJ-", with: "#")
            }
        } else {
            name = "?"
        }
        if op.isBlocking == true { return "\(name) (blocking)" }
        return name
    }

    private func chipRow(symbol: String, tint: Color, items: [String]) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: symbol)
                .scaledFont(.caption2, weight: .bold)
                .foregroundStyle(tint)
                .frame(width: 12)
            FlowLayout(spacing: 4) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .scaledFont(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(tint.opacity(0.12), in: Capsule())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct ActivityPHIDChips: View {
    let adds: [String]
    let removes: [String]
    let userDirectory: [String: PhabricatorUser]
    let projectDirectory: [String: PhabricatorProject]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !adds.isEmpty {
                chipRow(symbol: "plus", tint: .green, items: adds.map(label(for:)))
            }
            if !removes.isEmpty {
                chipRow(symbol: "minus", tint: .red, items: removes.map(label(for:)))
            }
        }
    }

    private func label(for phid: String) -> String {
        if let user = userDirectory[phid] {
            return user.realName ?? user.userName
        }
        if let proj = projectDirectory[phid] {
            return "#\(proj.slug ?? proj.name)"
        }
        return phid
            .replacingOccurrences(of: "PHID-USER-", with: "@")
            .replacingOccurrences(of: "PHID-PROJ-", with: "#")
    }

    private func chipRow(symbol: String, tint: Color, items: [String]) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: symbol)
                .scaledFont(.caption2, weight: .bold)
                .foregroundStyle(tint)
                .frame(width: 12)
            FlowLayout(spacing: 4) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .scaledFont(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(tint.opacity(0.12), in: Capsule())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
        }
    }
}
