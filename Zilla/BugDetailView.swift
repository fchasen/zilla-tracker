//
//  BugDetailView.swift
//  Zilla
//

import SwiftUI
import BugzillaKit
import Textual
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
private func copyToPasteboard(_ value: String) {
    #if canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    #elseif canImport(UIKit)
    UIPasteboard.general.string = value
    #endif
}

struct BugDetailView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(Workspace.self) private var workspace
    @Environment(ViewedBugsStore.self) private var viewedBugs
    let bugID: Bug.ID?

    @State private var composerText: String = ""
    @State private var composerSelection: TextSelection?
    @State private var isPostingComment = false
    @State private var composerError: String?
    @State private var dupePrompt: DupePromptIdentifier?
    @State private var updateError: String?

    private var bug: Bug? { workspace.loadedBug }
    private var comments: [Comment] { workspace.loadedComments }
    private var loadError: String? { workspace.bugLoadError }
    private var isLoading: Bool { workspace.isLoadingBug }

    var body: some View {
        Group {
            if bugID == nil {
                ContentUnavailableView(
                    "No bug selected",
                    systemImage: "ant",
                    description: Text("Pick a bug from the list.")
                )
            } else if let error = loadError, bug == nil {
                ContentUnavailableView(
                    "Couldn't load bug",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let bug {
                BugContent(
                    bug: bug,
                    comments: comments,
                    loadError: loadError,
                    composerText: $composerText,
                    composerSelection: $composerSelection,
                    isPosting: isPostingComment,
                    composerError: composerError,
                    onPost: { Task { await postComment() } },
                    onUpdate: { update in Task { await applyUpdate(update) } }
                )
            } else if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .toolbar {
            if workspace.isUpdatingBug {
                ToolbarItem(placement: .primaryAction) {
                    ProgressView().controlSize(.small)
                }
            } else if let bug {
                if !isClosed(bug) {
                    ToolbarItem(placement: .primaryAction) {
                        statusMenu(for: bug)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    resolveMenu(for: bug)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    workspace.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help(workspace.showInspector ? "Hide Inspector" : "Show Inspector")
                .disabled(workspace.loadedBug == nil)
            }
        }
        .alert(
            "Couldn't update bug",
            isPresented: Binding(
                get: { updateError != nil },
                set: { if !$0 { updateError = nil } }
            )
        ) {
            Button("OK") { updateError = nil }
        } message: {
            Text(updateError ?? "")
        }
        .sheet(item: $dupePrompt) { _ in
            DupeOfSheet { dupeOfID, comment in
                Task { await applyUpdate(BugUpdate(
                    status: "RESOLVED",
                    resolution: "DUPLICATE",
                    dupeOf: dupeOfID,
                    comment: comment.isEmpty ? nil : comment
                )) }
            }
        }
        .task(id: bugID) { await reload() }
    }

    @ViewBuilder
    private func resolveMenu(for bug: Bug) -> some View {
        Menu {
            if isClosed(bug) {
                Button("Reopen") {
                    Task { await applyUpdate(BugUpdate(status: "REOPENED", resolution: "")) }
                }
            } else {
                ForEach(Self.resolveOptions, id: \.code) { option in
                    Button("Resolve as \(option.label)") {
                        Task { await applyUpdate(BugUpdate(status: "RESOLVED", resolution: option.code)) }
                    }
                }
                Divider()
                Button("Mark as Duplicate…") {
                    dupePrompt = DupePromptIdentifier()
                }
            }
        } label: {
            Label("Resolve", systemImage: "checkmark.circle")
        }
    }

    @ViewBuilder
    private func statusMenu(for bug: Bug) -> some View {
        Menu {
            ForEach(Self.statusOptions, id: \.code) { option in
                Button {
                    Task { await applyUpdate(BugUpdate(status: option.code)) }
                } label: {
                    if bug.status.uppercased() == option.code {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
            if isUnassigned(bug), let me = auth.currentUser?.name {
                Divider()
                Button("Take") {
                    Task { await applyUpdate(BugUpdate(assignedTo: me)) }
                }
            }
        } label: {
            Label("Status", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private func isClosed(_ bug: Bug) -> Bool {
        ["RESOLVED", "VERIFIED", "CLOSED"].contains(bug.status.uppercased())
    }

    private func isUnassigned(_ bug: Bug) -> Bool {
        guard let raw = bug.assignedTo?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return true }
        return raw.lowercased().contains("nobody")
    }

    private static let resolveOptions: [(code: String, label: String)] = [
        ("FIXED", "Fixed"),
        ("INVALID", "Invalid"),
        ("WORKSFORME", "Works for Me"),
        ("INCOMPLETE", "Incomplete"),
        ("WONTFIX", "Won't Fix")
    ]

    private static let statusOptions: [(code: String, label: String)] = [
        ("NEW", "New"),
        ("ASSIGNED", "Assigned"),
        ("IN_PROGRESS", "In Progress")
    ]

    private func applyUpdate(_ update: BugUpdate) async {
        if let error = await workspace.applyBugUpdate(update, using: auth.client) {
            updateError = error.localizedDescription
        }
    }

    private func reload() async {
        composerText = ""
        composerSelection = nil
        composerError = nil
        guard let id = bugID else {
            workspace.clearLoadedBug()
            return
        }
        viewedBugs.markViewed(id)
        await workspace.loadBug(id: id, using: auth.client)
    }

    private func postComment() async {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = bugID else { return }

        isPostingComment = true
        composerError = nil
        defer { isPostingComment = false }

        let client = auth.client
        do {
            _ = try await client.addComment(bugID: id, text: trimmed, isMarkdown: true)
            composerText = ""
            composerSelection = nil
            await workspace.refreshLoadedComments(using: client)
        } catch {
            composerError = error.localizedDescription
        }
    }
}

private struct BugContent: View {
    let bug: Bug
    let comments: [Comment]
    let loadError: String?
    @Binding var composerText: String
    @Binding var composerSelection: TextSelection?
    let isPosting: Bool
    let composerError: String?
    let onPost: () -> Void
    let onUpdate: (BugUpdate) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BugHeader(bug: bug)
                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let description = descriptionComment {
                    DescriptionBlock(comment: description, attachments: bug.attachments)
                }
                if !phabricatorPatches.isEmpty {
                    PhabricatorSection(patches: phabricatorPatches)
                }
                if !rawPatches.isEmpty {
                    PatchesSection(patches: rawPatches)
                }
                if !bug.attachments.isEmpty {
                    AttachmentsSection(attachments: bug.attachments)
                }
                BugCommentsSection(
                    comments: threadComments,
                    attachmentsByID: attachmentsByID
                )
                Divider()
                CommentComposer(
                    text: $composerText,
                    selection: $composerSelection,
                    isPosting: isPosting,
                    error: composerError,
                    onPost: onPost
                )
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var descriptionComment: Comment? {
        comments.first { ($0.count ?? -1) == 0 }
    }

    private var threadComments: [Comment] {
        comments.filter { comment in
            guard (comment.count ?? -1) != 0 else { return false }
            if let id = comment.attachmentId,
               let attachment = attachmentsByID[id],
               isPhabricatorAttachment(attachment) {
                return false
            }
            return true
        }
    }

    private var attachmentsByID: [BugzillaKit.Attachment.ID: BugzillaKit.Attachment] {
        Dictionary(uniqueKeysWithValues: bug.attachments.map { ($0.id, $0) })
    }

    private var phabricatorPatches: [BugzillaKit.Attachment] {
        bug.attachments
            .filter { !$0.isObsolete && isPhabricatorAttachment($0) }
            .sorted { $0.creationTime > $1.creationTime }
    }

    private var rawPatches: [BugzillaKit.Attachment] {
        bug.attachments
            .filter { !$0.isObsolete && $0.isPatch && !isPhabricatorAttachment($0) }
            .sorted { $0.creationTime > $1.creationTime }
    }
}

private func isPhabricatorAttachment(_ attachment: BugzillaKit.Attachment) -> Bool {
    attachment.contentType == "text/x-phabricator-request"
}

private func isPrimaryPatchAttachment(_ attachment: BugzillaKit.Attachment) -> Bool {
    !attachment.isObsolete && (isPhabricatorAttachment(attachment) || attachment.isPatch)
}

private func isImageAttachment(_ attachment: BugzillaKit.Attachment) -> Bool {
    attachment.contentType.hasPrefix("image/")
}

private func attachmentURL(_ attachment: BugzillaKit.Attachment) -> URL? {
    URL(string: "https://bugzilla.mozilla.org/attachment.cgi?id=\(attachment.id)")
}

private struct BugHeader: View {
    let bug: Bug
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                BugTypePill(type: bug.type)

                Button(action: copyID) {
                    Text(verbatim: "\(bug.id)")
                        .font(.headline.monospaced())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(didCopy ? "Copied" : "Click to copy bug number")

                if let url = bmoURL {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.forward.square")
                            .foregroundStyle(.secondary)
                    }
                    .help("Open in Bugzilla")
                }

                StatusPill(bug: bug)

                if let priority = displayPriority {
                    MetaPill(label: priority, color: priorityColor(bug.priority))
                }
                if let severity = displaySeverity {
                    MetaPill(label: severity, color: severityColor(bug.severity))
                }

                if didCopy {
                    Text("Copied")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
            Text(bug.summary)
                .font(.title2)
                .textSelection(.enabled)
        }
    }

    private var displayPriority: String? {
        guard let p = bug.priority, !p.isEmpty, p != "--" else { return nil }
        return p
    }

    private var displaySeverity: String? {
        guard let s = bug.severity, !s.isEmpty, s != "--" else { return nil }
        return s
    }

    private func priorityColor(_ value: String?) -> Color {
        switch value?.uppercased() {
        case "P1": return .red
        case "P2": return .orange
        default: return .secondary
        }
    }

    private func severityColor(_ value: String?) -> Color {
        switch value?.uppercased() {
        case "S1", "BLOCKER", "CRITICAL": return .red
        case "S2", "MAJOR": return .orange
        default: return .secondary
        }
    }

    private var bmoURL: URL? {
        URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=\(bug.id)")
    }

    private func copyID() {
        copyToPasteboard(String(bug.id))
        withAnimation { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { didCopy = false }
        }
    }
}

private struct StatusPill: View {
    let bug: Bug

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        if bug.resolution.isEmpty {
            return bug.status.bugzillaTitleCased
        }
        return "\(bug.status.bugzillaTitleCased) · \(bug.resolution.bugzillaTitleCased)"
    }

    private var color: Color {
        switch bug.status.uppercased() {
        case "RESOLVED", "VERIFIED", "CLOSED": return .green
        case "ASSIGNED", "IN_PROGRESS": return .blue
        default: return .orange
        }
    }
}

private struct MetaPill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

struct BugMetadata: View {
    let bug: Bug
    let onUpdate: (BugUpdate) -> Void

    static let priorityOptions = ["--", "P1", "P2", "P3", "P4", "P5"]
    static let severityOptions = ["--", "S1", "S2", "S3", "S4", "N/A"]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
            row("Assignee", bug.assignedTo ?? "—")
            row("Reporter", bug.reporter ?? bug.creator ?? "—")
            row("Component", "\(bug.product) :: \(bug.component)")
            editableRow(
                label: "Priority",
                current: bug.priority,
                options: Self.priorityOptions,
                color: priorityColor(bug.priority)
            ) { value in
                onUpdate(BugUpdate(priority: value))
            }
            editableRow(
                label: "Severity",
                current: bug.severity,
                options: Self.severityOptions,
                color: severityColor(bug.severity)
            ) { value in
                onUpdate(BugUpdate(severity: value))
            }
            if !bug.keywords.isEmpty { row("Keywords", bug.keywords.joined(separator: ", ")) }
            if let when = bug.creationTime { dateRow("Created", when, relative: false) }
            if let when = bug.lastChangeTime { dateRow("Last change", when, relative: true) }
        }
        .font(.callout)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func dateRow(_ label: String, _ date: Date, relative: Bool) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            if relative {
                Text(date, format: .relative(presentation: .named))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(date, format: .dateTime.day().month().year())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func editableRow(
        label: String,
        current: String?,
        options: [String],
        color: Color?,
        onPick: @escaping (String) -> Void
    ) -> some View {
        let displayed = (current?.isEmpty == false ? current : nil) ?? "--"
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Menu {
                ForEach(options, id: \.self) { value in
                    Button {
                        onPick(value)
                    } label: {
                        if value == current || (value == "--" && (current == nil || current?.isEmpty == true)) {
                            Label(value, systemImage: "checkmark")
                        } else {
                            Text(value)
                        }
                    }
                }
                if let current, !current.isEmpty, !options.contains(current) {
                    Divider()
                    Text("Currently: \(current)")
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text(displayed).foregroundStyle(color ?? .primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func priorityColor(_ value: String?) -> Color? {
        switch value?.uppercased() {
        case "P1": return .red
        case "P2": return .orange
        default: return nil
        }
    }

    private func severityColor(_ value: String?) -> Color? {
        switch value?.uppercased() {
        case "S1", "BLOCKER", "CRITICAL": return .red
        case "S2", "MAJOR": return .orange
        default: return nil
        }
    }
}

// MARK: - Inspector

struct BugInspectorContent: View {
    let bug: Bug
    let onUpdate: (BugUpdate) -> Void
    let onOpenBug: (Bug.ID) -> Void

    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BugMetadata(bug: bug, onUpdate: onUpdate)

            if !bug.flags.isEmpty {
                Divider()
                FlagsSection(flags: bug.flags)
            }

            if let whiteboard = trimmedWhiteboard {
                Divider()
                WhiteboardSection(text: whiteboard)
            }

            if !bug.dependsOn.isEmpty || !bug.blocks.isEmpty {
                Divider()
                DependenciesSection(
                    dependsOn: bug.dependsOn,
                    blocks: bug.blocks,
                    onOpenBug: onOpenBug
                )
            }

            if !bug.cc.isEmpty {
                Divider()
                CCSection(cc: bug.cc)
            }
        }
        .task(id: bug.id) {
            let ids = Array(Set(bug.dependsOn + bug.blocks))
            if !ids.isEmpty {
                await workspace.loadDependencyMetadata(ids: ids, using: auth.client)
            }
        }
    }

    private var trimmedWhiteboard: String? {
        guard let raw = bug.whiteboard?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }
}

private struct InspectorSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            if let trailing {
                Text(trailing)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct FlagsSection: View {
    let flags: [Flag]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorSectionHeader(title: "Flags")
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(flags) { flag in
                    FlagPill(flag: flag)
                }
            }
        }
    }
}

private struct FlagPill: View {
    let flag: Flag

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .help(tooltip)
    }

    private var label: String {
        var text = "\(flag.name)\(flag.status)"
        if let requestee = flag.requestee, !requestee.isEmpty {
            text += stripDomain(requestee)
        }
        return text
    }

    private var color: Color {
        switch flag.status {
        case "+": return .green
        case "-": return .red
        case "?": return .orange
        default: return .secondary
        }
    }

    private var tooltip: String {
        var parts: [String] = []
        if let setter = flag.setter, !setter.isEmpty {
            parts.append("Set by \(setter)")
        }
        if let requestee = flag.requestee, !requestee.isEmpty {
            parts.append("→ \(requestee)")
        }
        if let date = flag.modificationDate {
            parts.append(Self.dateFormatter.string(from: date))
        }
        return parts.joined(separator: "  ·  ")
    }

    private func stripDomain(_ value: String) -> String {
        if let at = value.firstIndex(of: "@") {
            return String(value[..<at])
        }
        return value
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

private struct WhiteboardSection: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeader(title: "Whiteboard")
            Text(text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DependenciesSection: View {
    let dependsOn: [Int]
    let blocks: [Int]
    let onOpenBug: (Bug.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !dependsOn.isEmpty {
                DependencyList(title: "Depends on", ids: dependsOn, onOpenBug: onOpenBug)
            }
            if !blocks.isEmpty {
                DependencyList(title: "Blocks", ids: blocks, onOpenBug: onOpenBug)
            }
        }
    }
}

private struct DependencyList: View {
    let title: String
    let ids: [Int]
    let onOpenBug: (Bug.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeader(title: title, trailing: ids.count > 1 ? "\(ids.count)" : nil)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ids, id: \.self) { id in
                    DependencyRow(id: id, onOpen: onOpenBug)
                }
            }
        }
    }
}

private struct DependencyRow: View {
    @Environment(Workspace.self) private var workspace
    let id: Int
    let onOpen: (Bug.ID) -> Void

    var body: some View {
        Button {
            onOpen(id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "#\(id)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                if let summary = metadata?.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(isClosed ? Color.secondary : Color.primary)
                        .strikethrough(isClosed)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(metadata?.summary ?? "Open bug #\(id)")
    }

    private var metadata: DependencyMetadata? {
        workspace.dependencyMetadata[id]
    }

    private var isClosed: Bool {
        metadata?.isClosed ?? false
    }
}

private struct CCSection: View {
    let cc: [String]

    @State private var expanded: Bool = false

    private static let collapseThreshold = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeader(title: "CC", trailing: "\(cc.count)")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(visible, id: \.self) { email in
                    CCRow(email: email)
                }
            }
            if cc.count > Self.collapseThreshold {
                Button(expanded ? "Show less" : "Show all") {
                    expanded.toggle()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private var visible: [String] {
        if expanded || cc.count <= Self.collapseThreshold {
            return cc
        }
        return Array(cc.prefix(Self.collapseThreshold))
    }
}

private struct CCRow: View {
    let email: String
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 6) {
            Text(email)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if didCopy {
                Text("Copied")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy email") { copy() }
        }
    }

    private func copy() {
        copyToPasteboard(email)
        withAnimation { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { didCopy = false }
        }
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(subviews: subviews, in: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews: subviews, in: bounds.width)
        for (subview, offset) in zip(subviews, result.offsets) {
            subview.place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (offsets, CGSize(width: maxX, height: y + lineHeight))
    }
}

private struct BugCommentsSection: View {
    let comments: [Comment]
    let attachmentsByID: [BugzillaKit.Attachment.ID: BugzillaKit.Attachment]

    var body: some View {
        let visible = comments.filter { comment in
            if comment.attachmentId != nil { return true }
            return !comment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("Comments")
                    .font(.headline)
                ForEach(visible) { comment in
                    CommentBlock(
                        comment: comment,
                        attachment: comment.attachmentId.flatMap { attachmentsByID[$0] }
                    )
                }
            }
        }
    }
}

private struct DescriptionBlock: View {
    let comment: Comment
    let attachments: [BugzillaKit.Attachment]

    var body: some View {
        let stripped = stripAttachmentHeader(comment.text, hasAttachment: comment.attachmentId != nil)
        let attachment = comment.attachmentId.flatMap { id in
            attachments.first(where: { $0.id == id })
        }
        if !stripped.isEmpty || attachment != nil {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("Description")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    if let attachment, isImageAttachment(attachment) {
                        AttachmentImagePreview(attachment: attachment)
                    }
                    if !stripped.isEmpty {
                        StructuredText(markdown: stripped)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct CommentBlock: View {
    let comment: Comment
    let attachment: BugzillaKit.Attachment?

    var body: some View {
        let stripped = stripAttachmentHeader(comment.text, hasAttachment: attachment != nil)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(comment.creator)
                    .font(.caption.weight(.semibold))
                if let count = comment.count {
                    Text(verbatim: "#\(count)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(comment.creationTime, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let attachment, isImageAttachment(attachment) {
                AttachmentImagePreview(attachment: attachment)
            } else if let attachment {
                AttachmentInlineLink(attachment: attachment)
            }
            if !stripped.isEmpty {
                StructuredText(markdown: stripped)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private func stripAttachmentHeader(_ text: String, hasAttachment: Bool) -> String {
    guard hasAttachment else {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var lines = text.components(separatedBy: "\n")
    while let first = lines.first {
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            lines.removeFirst()
            continue
        }
        if trimmed.range(of: #"^Created attachment\s+\d+"#, options: .regularExpression) != nil {
            lines.removeFirst()
            continue
        }
        break
    }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct AttachmentImagePreview: View {
    let attachment: BugzillaKit.Attachment

    private static let maxHeight: CGFloat = 360

    var body: some View {
        if let url = attachmentURL(attachment) {
            Link(destination: url) {
                AsyncImage(url: url, transaction: Transaction(animation: .default)) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: Self.maxHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .failure:
                        failure
                    @unknown default:
                        failure
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Open attachment in Bugzilla")
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
            ProgressView()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
    }

    private var failure: some View {
        Label("Couldn't load image", systemImage: "photo.badge.exclamationmark")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct AttachmentInlineLink: View {
    let attachment: BugzillaKit.Attachment

    var body: some View {
        if let url = attachmentURL(attachment) {
            Link(destination: url) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Open attachment in Bugzilla")
        }
    }

    private var iconName: String {
        if attachment.isPatch { return "text.alignleft" }
        switch attachment.contentType.split(separator: "/").first {
        case "text": return "doc.text"
        case "video": return "film"
        case "audio": return "speaker.wave.2"
        default: return "paperclip"
        }
    }

    private var label: String {
        let summary = attachment.summary.trimmingCharacters(in: .whitespaces)
        if !summary.isEmpty { return summary }
        let name = attachment.fileName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Attachment #\(attachment.id)" : name
    }
}

// MARK: - Patches

private struct PhabricatorSection: View {
    let patches: [BugzillaKit.Attachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text("Phabricator")
                    .font(.headline)
                if patches.count > 1 {
                    Text("\(patches.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(patches) { patch in
                    PatchRow(attachment: patch)
                }
            }
        }
    }
}

private struct PatchesSection: View {
    let patches: [BugzillaKit.Attachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text(patches.count == 1 ? "Patch" : "Patches")
                    .font(.headline)
                if patches.count > 1 {
                    Text("\(patches.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(patches) { patch in
                    PatchRow(attachment: patch)
                }
            }
        }
    }
}

private struct PatchRow: View {
    let attachment: BugzillaKit.Attachment

    var body: some View {
        Link(destination: openURL) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: iconName)
                    .foregroundStyle(accentColor)
                    .imageScale(.large)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        if let revision = phabRevision {
                            Text(revision)
                                .font(.callout.weight(.semibold).monospaced())
                                .foregroundStyle(accentColor)
                        }
                        Text(title)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        ForEach(approvalChannels, id: \.self) { channel in
                            MetaPill(label: channel, color: .green)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(attachment.creator).lineLimit(1)
                        Text(verbatim: "·")
                        Text(attachment.creationTime, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        if isPhabricator {
                            Text(verbatim: "·")
                            Text("Phabricator")
                        } else {
                            Text(verbatim: "·")
                            Text("Patch")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accentColor.opacity(0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(isPhabricator ? "Open in Phabricator" : "Open patch in Bugzilla")
    }

    private var isPhabricator: Bool {
        attachment.contentType == "text/x-phabricator-request"
    }

    private var iconName: String {
        isPhabricator ? "arrow.up.right.square.fill" : "text.alignleft"
    }

    private var accentColor: Color {
        isPhabricator ? .blue : .indigo
    }

    private var phabRevision: String? {
        guard isPhabricator else { return nil }
        for candidate in [attachment.fileName, attachment.summary] {
            if let match = candidate.range(of: #"D\d+"#, options: .regularExpression) {
                return String(candidate[match])
            }
        }
        return nil
    }

    private var approvalChannels: [String] {
        attachment.flags.compactMap { flag in
            guard flag.status == "+" else { return nil }
            let prefix = "approval-mozilla-"
            guard flag.name.hasPrefix(prefix) else { return nil }
            let channel = String(flag.name.dropFirst(prefix.count))
            return channel.isEmpty ? nil : channel
        }
    }

    private var title: String {
        let summary = attachment.summary.trimmingCharacters(in: .whitespaces)
        if !summary.isEmpty { return summary }
        let name = attachment.fileName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Attachment #\(attachment.id)" : name
    }

    private var openURL: URL {
        if let revision = phabRevision,
           let url = URL(string: "https://phabricator.services.mozilla.com/\(revision)") {
            return url
        }
        return URL(string: "https://bugzilla.mozilla.org/attachment.cgi?id=\(attachment.id)")!
    }
}

// MARK: - Attachments

private struct AttachmentsSection: View {
    let attachments: [BugzillaKit.Attachment]

    @State private var showObsolete: Bool = false

    var body: some View {
        let active = attachments.filter { !$0.isObsolete && !isPrimaryPatchAttachment($0) }
        let obsolete = attachments.filter { $0.isObsolete }
        let total = active.count + obsolete.count
        let allObsolete = active.isEmpty && !obsolete.isEmpty

        if total > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                HStack {
                    Text("Attachments")
                        .font(.headline)
                    Text("\(total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if !active.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(active.sorted(by: { $0.creationTime < $1.creationTime })) { attachment in
                            AttachmentRow(attachment: attachment)
                        }
                    }
                }

                if !obsolete.isEmpty {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { showObsolete || allObsolete },
                            set: { showObsolete = $0 }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(obsolete.sorted(by: { $0.creationTime < $1.creationTime })) { attachment in
                                AttachmentRow(attachment: attachment)
                                    .opacity(0.55)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text("Obsolete (\(obsolete.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct AttachmentRow: View {
    let attachment: BugzillaKit.Attachment

    var body: some View {
        if let url = url {
            Link(destination: url) {
                rowContent
            }
            .buttonStyle(.plain)
            .help("Open attachment in Bugzilla")
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .strikethrough(attachment.isObsolete)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isPhabricator {
                        MetaPill(label: "Phab", color: .blue)
                    } else if attachment.isPatch {
                        MetaPill(label: "Patch", color: .indigo)
                    }
                }
                HStack(spacing: 6) {
                    Text(attachment.creator)
                        .lineLimit(1)
                    Text(verbatim: "·")
                    Text(attachment.creationTime, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    if let size = attachment.size, size > 0, !isPhabricator {
                        Text(verbatim: "·")
                        Text(formattedSize(size))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var displayName: String {
        let trimmed = attachment.fileName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        let summary = attachment.summary.trimmingCharacters(in: .whitespaces)
        return summary.isEmpty ? "Attachment #\(attachment.id)" : summary
    }

    private var url: URL? {
        URL(string: "https://bugzilla.mozilla.org/attachment.cgi?id=\(attachment.id)")
    }

    private var isPhabricator: Bool {
        attachment.contentType == "text/x-phabricator-request"
    }

    private var iconName: String {
        if isPhabricator { return "arrow.up.right.square" }
        if attachment.isPatch { return "text.alignleft" }
        switch attachment.contentType.split(separator: "/").first {
        case "image": return "photo"
        case "text": return "doc.text"
        case "video": return "film"
        case "audio": return "speaker.wave.2"
        default: return "doc"
        }
    }

    private var iconColor: Color {
        if attachment.isObsolete { return .secondary }
        if isPhabricator { return .blue }
        if attachment.isPatch { return .indigo }
        return .secondary
    }

    private func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct DupePromptIdentifier: Identifiable {
    let id = UUID()
}

struct DupeOfSheet: View {
    let onConfirm: (Int, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var bugIdText: String = ""
    @State private var comment: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Duplicate of") {
                    TextField("Bug ID", text: $bugIdText)
                        .textFieldStyle(.roundedBorder)
                }
                Section("Comment (optional)") {
                    TextEditor(text: $comment)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Mark as Duplicate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        guard let id = parsedID else { return }
                        onConfirm(id, comment.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(parsedID == nil)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 320)
        #endif
    }

    private var parsedID: Int? {
        Int(bugIdText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct CommentComposer: View {
    @Binding var text: String
    @Binding var selection: TextSelection?
    let isPosting: Bool
    let error: String?
    let onPost: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownEditor(
                text: $text,
                selection: $selection,
                headerLabel: "Add a comment",
                isDisabled: isPosting
            )

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(action: onPost) {
                    if isPosting {
                        ProgressView().controlSize(.small).frame(width: 60)
                    } else {
                        Text("Post").frame(width: 60)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Post comment (⌘↩)")
                .disabled(trimmedIsEmpty || isPosting)
            }
        }
    }

    private var trimmedIsEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
