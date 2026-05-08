//
//  BugDetailView.swift
//  Zilla
//

import SwiftUI
import BugzillaKit
import Textual

struct BugStatusOption: Hashable {
    let code: String
    let label: String
}

enum BugStatuses {
    static let open: [BugStatusOption] = [
        .init(code: "NEW", label: "New"),
        .init(code: "ASSIGNED", label: "Assigned"),
        .init(code: "IN_PROGRESS", label: "In Progress")
    ]

    static let resolutions: [BugStatusOption] = [
        .init(code: "FIXED", label: "Fixed"),
        .init(code: "INVALID", label: "Invalid"),
        .init(code: "WORKSFORME", label: "Works for Me"),
        .init(code: "INCOMPLETE", label: "Incomplete"),
        .init(code: "WONTFIX", label: "Won't Fix")
    ]

    static let closedStatuses: Set<String> = ["RESOLVED", "VERIFIED", "CLOSED"]

    static func isClosed(_ status: String) -> Bool {
        closedStatuses.contains(status.uppercased())
    }

    static func isUnassigned(_ assignee: String?) -> Bool {
        guard let raw = assignee?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return true }
        return raw.lowercased().contains("nobody")
    }
}

struct BugDetailView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(Workspace.self) private var workspace
    @Environment(ViewedBugsStore.self) private var viewedBugs
    let bugID: Bug.ID?

    @State private var isPostingComment = false
    @State private var composerError: String?
    @State private var dupePrompt: DupePromptIdentifier?
    @State private var updateError: String?

    #if os(iOS)
    @State private var isPresentingCommentSheet: Bool = false
    #endif

    private var composerTextBinding: Binding<String> {
        Binding(
            get: { bugID.flatMap { workspace.bugCommentDrafts[$0] } ?? "" },
            set: { newValue in
                guard let id = bugID else { return }
                if newValue.isEmpty {
                    workspace.bugCommentDrafts.removeValue(forKey: id)
                } else {
                    workspace.bugCommentDrafts[id] = newValue
                }
            }
        )
    }

    private var composerText: String {
        composerTextBinding.wrappedValue
    }

    private var isShowingLoadedBug: Bool { workspace.loadedBug?.id == bugID }
    private var bug: Bug? { isShowingLoadedBug ? workspace.loadedBug : nil }
    private var comments: [Comment] { isShowingLoadedBug ? workspace.loadedComments : [] }
    private var loadError: String? { workspace.bugLoadError }
    private var isLoading: Bool { workspace.isLoadingBug }
    private var bugMentionCompletionContext: MentionCompletionContext {
        MentionCompletionContext.bugzilla(
            bug: bug,
            comments: comments.filter { ($0.count ?? -1) != 0 }
        )
    }

    var body: some View {
        Group {
            if bugID == nil {
                EmptyStateIcon(systemName: "ant")
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
                    composerText: composerTextBinding,
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
            if let bug {
                if !BugStatuses.isClosed(bug.status) {
                    ToolbarItem(placement: .primaryAction) {
                        statusMenu(for: bug)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    resolveMenu(for: bug)
                }
            } else if workspace.isUpdatingBug || isLoading {
                ToolbarItem(placement: .primaryAction) {
                    ProgressView().controlSize(.small)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    workspace.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help(workspace.showInspector ? "Hide Inspector" : "Show Inspector")
                .disabled(bug == nil)
            }
            #if os(iOS)
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Button {
                    isPresentingCommentSheet = true
                } label: {
                    Label("New Comment", systemImage: "square.and.pencil")
                }
                .disabled(bug == nil || !auth.isSignedIn)
            }
            #endif
        }
        #if os(iOS)
        .navigationTitle(bugID.map { Text(verbatim: "Bug \($0)") } ?? Text(""))
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingCommentSheet) {
            BugCommentSheet(
                bugID: bugID,
                text: composerTextBinding,
                mentionCompletionContext: bugMentionCompletionContext,
                onPost: { Task { await postComment() } },
                isPosting: isPostingComment,
                error: composerError
            )
        }
        #endif
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
        .onChange(of: workspace.dupePromptRequested) { _, requested in
            if requested {
                workspace.dupePromptRequested = false
                if let bug, !BugStatuses.isClosed(bug.status) {
                    dupePrompt = DupePromptIdentifier()
                }
            }
        }
        .interceptingMozillaLinks(workspace: workspace)
        .task(id: bugID) { await reload() }
        .onAppear { restoreCachedBugIfNeeded() }
    }

    private func restoreCachedBugIfNeeded() {
        guard let id = bugID, workspace.loadedBug?.id != id else { return }
        _ = workspace.restoreCachedBug(id: id)
    }

    @ViewBuilder
    private func resolveMenu(for bug: Bug) -> some View {
        Menu {
            if BugStatuses.isClosed(bug.status) {
                Button("Reopen") {
                    Task { await applyUpdate(BugUpdate(status: "REOPENED", resolution: "")) }
                }
            } else {
                ForEach(BugStatuses.resolutions, id: \.code) { option in
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
            ForEach(BugStatuses.open, id: \.code) { option in
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
            if BugStatuses.isUnassigned(bug.assignedTo), let me = auth.currentUser?.name {
                Divider()
                Button("Take") {
                    Task { await applyUpdate(BugUpdate(assignedTo: me)) }
                }
            }
        } label: {
            if workspace.isUpdatingBug {
                ProgressView().controlSize(.small)
            } else {
                Label("Status", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(workspace.isUpdatingBug)
    }

    private func applyUpdate(_ update: BugUpdate) async {
        if let error = await workspace.applyBugUpdate(update, using: auth.client) {
            updateError = error.localizedDescription
        }
    }

    private func reload() async {
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
            _ = try await client.addComment(
                bugID: id,
                text: CommentMarkdown.autolinkReferences(in: trimmed),
                isMarkdown: true
            )
            workspace.bugCommentDrafts.removeValue(forKey: id)
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
    let isPosting: Bool
    let composerError: String?
    let onPost: () -> Void
    let onUpdate: (BugUpdate) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BugHeader(bug: bug, onUpdate: onUpdate)
                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .scaledFont(.caption)
                        .foregroundStyle(.orange)
                }
                if let description = descriptionComment {
                    DescriptionBlock(
                        bug: bug,
                        comment: description,
                        attachments: bug.attachments,
                        mentionCompletionContext: mentionCompletionContext
                    )
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
                    bugID: bug.id,
                    comments: threadComments,
                    attachmentsByID: attachmentsByID,
                    mentionCompletionContext: mentionCompletionContext,
                    onQuote: quoteIntoComposer
                )
                #if os(macOS)
                Divider()
                CommentComposer(
                    text: $composerText,
                    isPosting: isPosting,
                    error: composerError,
                    mentionCompletionContext: mentionCompletionContext,
                    onPost: onPost
                )
                #endif
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func quoteIntoComposer(_ text: String) {
        let quoted = text
            .components(separatedBy: "\n")
            .map { line -> String in
                var stripped = Substring(line)
                while stripped.first == ">" {
                    stripped = stripped.dropFirst()
                    if stripped.first == " " { stripped = stripped.dropFirst() }
                }
                return stripped.isEmpty ? ">" : "> \(stripped)"
            }
            .joined(separator: "\n")
        let separator: String
        if composerText.isEmpty {
            separator = ""
        } else if composerText.hasSuffix("\n\n") {
            separator = ""
        } else if composerText.hasSuffix("\n") {
            separator = "\n"
        } else {
            separator = "\n\n"
        }
        composerText.append(separator + quoted + "\n\n")
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

    private var mentionCompletionContext: MentionCompletionContext {
        MentionCompletionContext.bugzilla(bug: bug, comments: threadComments)
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
    let onUpdate: (BugUpdate) -> Void
    @Environment(\.openExternalURL) private var openExternalURL
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth
    @State private var didCopy = false
    @State private var editedSummary: String = ""
    @FocusState private var summaryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                BugTypePill(
                    type: bug.type,
                    isMeta: bug.summary.range(of: #"^\s*\[meta\]"#, options: [.regularExpression, .caseInsensitive]) != nil,
                    linkTransfer: BugLinkTransfer(id: bug.id, summary: bug.summary)
                )

                Button(action: copyID) {
                    Text(verbatim: "\(bug.id)")
                        .scaledFont(.headline, design: .monospaced)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(didCopy ? "Copied" : "Click to copy bug number")

                if let url = bmoURL {
                    Button {
                        openExternalURL(url)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .linkPointerStyle()
                    .help("Open in Bugzilla")
                    .contextMenu {
                        Button("Copy Link") {
                            copyToPasteboard(url.absoluteString)
                        }
                    }
                }

                StatusPill(bug: bug)

                if bug.type?.lowercased() == "defect" {
                    MetaPill(
                        label: displaySeverity ?? "S?",
                        color: displaySeverity == nil ? .secondary : severityColor(bug.severity)
                    )
                } else if let priority = displayPriority {
                    MetaPill(label: priority, color: priorityColor(bug.priority))
                }

                if didCopy {
                    Text("Copied")
                        .scaledFont(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .bugBlockDrop(target: bug.id)
            if isReporter {
                TextField("Summary", text: $editedSummary)
                    .textFieldStyle(.plain)
                    .scaledFont(.title2)
                    .focused($summaryFocused)
                    .lineLimit(1...3)
                    .accessibilityLabel("Bug summary")
                    .accessibilityHint("Press Return to save, Escape to cancel.")
                    .onSubmit { commitSummary() }
                    .onKeyPress(.escape) {
                        revertSummary()
                        summaryFocused = false
                        return .handled
                    }
                    .onChange(of: summaryFocused) { _, focused in
                        if !focused { commitSummary() }
                    }
                    .onAppear { editedSummary = bug.summary }
                    .onChange(of: bug.id) { _, _ in
                        revertSummary()
                        summaryFocused = false
                    }
                    .onChange(of: bug.summary) { _, new in
                        guard !summaryFocused, !workspace.isUpdatingBug else { return }
                        editedSummary = new
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                Color.secondary.opacity(summaryFocused ? 0.35 : 0),
                                lineWidth: 1
                            )
                    )
            } else {
                Text(bug.summary)
                    .scaledFont(.title2)
                    .textSelection(.enabled)
            }
        }
    }

    private var isReporter: Bool {
        guard let me = auth.currentUser?.name else { return false }
        return bug.creator == me || bug.reporter == me
    }

    private func revertSummary() {
        editedSummary = bug.summary
    }

    private func commitSummary() {
        let trimmed = editedSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            revertSummary()
            return
        }
        guard trimmed != bug.summary else { return }
        onUpdate(BugUpdate(summary: trimmed))
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
            .scaledFont(.caption, weight: .semibold)
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
            .scaledFont(.caption, weight: .semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

struct BugMetadata: View {
    let bug: Bug
    let onUpdate: (BugUpdate) -> Void

    @State private var showingAssignPicker = false

    static let priorityOptions = ["--", "P1", "P2", "P3", "P4", "P5"]
    static let severityOptions = ["--", "S1", "S2", "S3", "S4", "N/A"]
    static let pointsOptions = ["---", "?", "1", "2", "3", "5", "8", "13"]
    static let milestoneOptions = ["---", "Future"]
    static let flagOptions: [(label: String, status: String)] = [
        ("—", "X"),
        ("?", "?"),
        ("+", "+"),
        ("-", "-")
    ]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
            assigneeRow
            row("Reporter", User.displayName(for: bug.reporter ?? bug.creator, detail: bug.creatorDetail))
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
            editableRow(
                label: "Points",
                current: bug.points,
                options: Self.pointsOptions,
                color: nil
            ) { value in
                onUpdate(BugUpdate(points: value))
            }
            editableRow(
                label: "Milestone",
                current: bug.targetMilestone,
                options: milestoneChoices,
                color: nil
            ) { value in
                onUpdate(BugUpdate(targetMilestone: value))
            }
            flagRow(label: "QE Verify", flagName: "qe-verify")
            flagRow(label: "A11y Review", flagName: "a11y-review")
            if !bug.keywords.isEmpty { row("Keywords", bug.keywords.joined(separator: ", ")) }
            if let when = bug.creationTime { dateRow("Created", when, relative: false) }
            if let when = bug.lastChangeTime { dateRow("Last change", when, relative: true) }
        }
        .scaledFont(.callout)
    }

    @ViewBuilder
    private var assigneeRow: some View {
        GridRow {
            Text("Assignee").foregroundStyle(.secondary)
            Button {
                showingAssignPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(User.displayName(for: bug.assignedTo, detail: bug.assignedToDetail))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .scaledFont(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(bug.assignedTo ?? "")
            .popover(isPresented: $showingAssignPicker, arrowEdge: .bottom) {
                UserSearchPopover { user in
                    showingAssignPicker = false
                    onUpdate(BugUpdate(assignedTo: user.name))
                }
            }
        }
    }

    private var milestoneChoices: [String] {
        var opts = Self.milestoneOptions
        if let m = bug.targetMilestone?.trimmingCharacters(in: .whitespaces),
           !m.isEmpty,
           !opts.contains(m) {
            opts.append(m)
        }
        return opts
    }

    @ViewBuilder
    private func flagRow(label: String, flagName: String) -> some View {
        let existing = bug.flags.first { $0.name == flagName }
        let current = existing?.status
        let displayed = (current.flatMap { $0.isEmpty ? nil : $0 }) ?? "—"
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Menu {
                ForEach(Self.flagOptions, id: \.status) { option in
                    Button {
                        let update = FlagUpdate(
                            id: existing?.id,
                            name: existing == nil ? flagName : nil,
                            status: option.status
                        )
                        onUpdate(BugUpdate(flags: [update]))
                    } label: {
                        let isSelected = option.status == (current?.isEmpty == false ? current : "X")
                        if isSelected {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                Text(displayed).foregroundStyle(flagColor(current) ?? .primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func flagColor(_ status: String?) -> Color? {
        switch status {
        case "+": return .green
        case "-": return .red
        case "?": return .orange
        default: return nil
        }
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

    @State private var quickAddTarget: QuickAddTarget?

    private enum QuickAddTarget: String, Identifiable {
        case dependsOn, blocks, seeAlso
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BugMetadata(bug: bug, onUpdate: onUpdate)

            Divider()
            NeedinfoSection(bug: bug, onUpdate: onUpdate)

            if !nonNeedinfoFlags.isEmpty {
                Divider()
                FlagsSection(flags: nonNeedinfoFlags)
            }

            if let whiteboard = trimmedWhiteboard {
                Divider()
                WhiteboardSection(text: whiteboard)
            }

            Divider()
            DependenciesSection(
                bugID: bug.id,
                dependsOn: bug.dependsOn,
                blocks: bug.blocks,
                seeAlso: bug.seeAlso,
                onOpenBug: onOpenBug,
                onAddDependsOn: { quickAddTarget = .dependsOn },
                onAddBlocks: { quickAddTarget = .blocks },
                onAddSeeAlso: { quickAddTarget = .seeAlso },
                onRemoveDependsOn: { id in onUpdate(BugUpdate(dependsOn: .remove([id]))) },
                onRemoveBlocks: { id in onUpdate(BugUpdate(blocks: .remove([id]))) },
                onRemoveSeeAlso: { url in onUpdate(BugUpdate(seeAlso: .remove([url]))) }
            )

            if !bug.cc.isEmpty {
                Divider()
                CCSection(cc: bug.cc)
            }
        }
        .task(id: bug.id) {
            var ids = Set(bug.dependsOn + bug.blocks)
            for url in bug.seeAlso {
                if let id = bmoBugID(from: url) {
                    ids.insert(id)
                }
            }
            if !ids.isEmpty {
                await workspace.loadDependencyMetadata(ids: Array(ids), using: auth.client)
            }
        }
        .sheet(item: $quickAddTarget) { target in
            QuickSearchSheet { pickedID in
                quickAddTarget = nil
                guard pickedID != bug.id else { return }
                switch target {
                case .dependsOn:
                    onUpdate(BugUpdate(dependsOn: .add([pickedID])))
                case .blocks:
                    onUpdate(BugUpdate(blocks: .add([pickedID])))
                case .seeAlso:
                    let url = "https://bugzilla.mozilla.org/show_bug.cgi?id=\(pickedID)"
                    onUpdate(BugUpdate(seeAlso: .add([url])))
                }
            }
        }
    }

    private func bmoBugID(from url: String) -> Bug.ID? {
        guard let comps = URLComponents(string: url),
              let host = comps.host?.lowercased(),
              host == "bugzilla.mozilla.org" else { return nil }
        if let item = comps.queryItems?.first(where: { $0.name == "id" }),
           let value = item.value {
            return Int(value)
        }
        return nil
    }

    private var trimmedWhiteboard: String? {
        guard let raw = bug.whiteboard?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }

    private var nonNeedinfoFlags: [Flag] {
        bug.flags.filter { $0.name != "needinfo" }
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

private struct NeedinfoSection: View {
    let bug: Bug
    let onUpdate: (BugUpdate) -> Void

    @Environment(AuthStore.self) private var auth
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorSectionHeader(
                title: "Needinfo",
                trailing: requests.count > 1 ? "\(requests.count)" : nil
            )
            if requests.isEmpty {
                Text("No outstanding requests")
                    .scaledFont(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(requests) { flag in
                        NeedinfoRow(
                            flag: flag,
                            isMe: isCurrentUser(flag.requestee)
                        ) {
                            onUpdate(BugUpdate(flags: [
                                FlagUpdate(id: flag.id, status: "X")
                            ]))
                        }
                    }
                }
            }

            Button {
                showingPicker = true
            } label: {
                Label("Request needinfo…", systemImage: "plus.circle")
                    .scaledFont(.caption)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                UserSearchPopover { user in
                    showingPicker = false
                    onUpdate(BugUpdate(flags: [
                        FlagUpdate(name: "needinfo", status: "?", requestee: user.name)
                    ]))
                }
            }
        }
    }

    private var requests: [Flag] {
        bug.flags.filter { $0.name == "needinfo" }
    }

    private func isCurrentUser(_ requestee: String?) -> Bool {
        guard let requestee, !requestee.isEmpty else { return false }
        let me = auth.currentUser
        if let name = me?.name, name.caseInsensitiveCompare(requestee) == .orderedSame { return true }
        if let email = me?.email, email.caseInsensitiveCompare(requestee) == .orderedSame { return true }
        return false
    }
}

private struct NeedinfoRow: View {
    let flag: Flag
    let isMe: Bool
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isMe ? "person.crop.circle.badge.questionmark" : "person.crop.circle")
                .scaledFont(.caption)
                .foregroundStyle(isMe ? Color.orange : Color.secondary)
            Text(displayName)
                .scaledFont(.callout)
                .foregroundStyle(isMe ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isMe {
                Button("Clear", action: onClear)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .help(tooltip)
    }

    private var displayName: String {
        if isMe { return "You" }
        return User.displayName(for: flag.requestee)
    }

    private var tooltip: String {
        var parts: [String] = []
        if let setter = flag.setter, !setter.isEmpty {
            parts.append("Requested by \(setter)")
        }
        if let requestee = flag.requestee, !requestee.isEmpty {
            parts.append("→ \(requestee)")
        }
        return parts.joined(separator: "  ·  ")
    }
}

private struct UserSearchPopover: View {
    let onPick: (User) -> Void

    @Environment(AuthStore.self) private var auth
    @State private var query = ""
    @State private var matches: [User] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search users…", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _, value in
                    scheduleSearch(value)
                }
            if isSearching {
                ProgressView().controlSize(.small)
            } else if matches.isEmpty {
                Text(query.count < 2 ? "Type at least 2 characters" : "No matches")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(matches) { user in
                            Button {
                                onPick(user)
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(user.realName ?? user.name)
                                        .scaledFont(.callout)
                                    Text(user.name)
                                        .scaledFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            matches = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
            await runSearch(trimmed)
        }
    }

    private func runSearch(_ text: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let users = try await auth.client.searchUsers(match: text, limit: 20)
            if !Task.isCancelled {
                matches = users
            }
        } catch is CancellationError {
        } catch {
            matches = []
        }
    }
}

private struct FlagPill: View {
    let flag: Flag

    var body: some View {
        Text(label)
            .scaledFont(.caption, weight: .semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .help(tooltip)
    }

    private var label: String {
        var text = "\(flag.name)\(flag.status)"
        if let requestee = flag.requestee, !requestee.isEmpty {
            text += User.localPart(of: requestee)
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
                .scaledFont(.callout, design: .monospaced)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DependenciesSection: View {
    let bugID: Bug.ID
    let dependsOn: [Int]
    let blocks: [Int]
    let seeAlso: [String]
    let onOpenBug: (Bug.ID) -> Void
    let onAddDependsOn: () -> Void
    let onAddBlocks: () -> Void
    let onAddSeeAlso: () -> Void
    let onRemoveDependsOn: (Bug.ID) -> Void
    let onRemoveBlocks: (Bug.ID) -> Void
    let onRemoveSeeAlso: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DependencyList(
                title: "Depends on",
                bugID: bugID,
                ids: dependsOn,
                direction: .dragBlocksTarget,
                onOpenBug: onOpenBug,
                onAdd: onAddDependsOn,
                onRemove: onRemoveDependsOn
            )
            DependencyList(
                title: "Blocks",
                bugID: bugID,
                ids: blocks,
                direction: .targetBlocksDrag,
                onOpenBug: onOpenBug,
                onAdd: onAddBlocks,
                onRemove: onRemoveBlocks
            )
            SeeAlsoList(
                urls: seeAlso,
                onOpenBug: onOpenBug,
                onAdd: onAddSeeAlso,
                onRemove: onRemoveSeeAlso
            )
        }
    }
}

private struct SeeAlsoList: View {
    let urls: [String]
    let onOpenBug: (Bug.ID) -> Void
    let onAdd: () -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeader(
                title: "See also",
                trailing: urls.count > 1 ? "\(urls.count)" : nil,
                onAdd: onAdd
            )
            if urls.isEmpty {
                Text("No related bugs")
                    .scaledFont(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(urls, id: \.self) { url in
                        SeeAlsoRow(url: url, onOpenBug: onOpenBug, onRemove: onRemove)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SeeAlsoRow: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openURL) private var openURL
    let url: String
    let onOpenBug: (Bug.ID) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        Button {
            if let id = bmoBugID {
                onOpenBug(id)
            } else if let resolved = URL(string: url) {
                openURL(resolved)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let id = bmoBugID {
                    Text(verbatim: "#\(id)")
                        .scaledFont(.caption, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    if let summary = workspace.dependencyMetadata(for: id)?.summary {
                        Text(summary)
                            .scaledFont(.callout)
                            .foregroundStyle(isClosed(id) ? Color.secondary : Color.primary)
                            .strikethrough(isClosed(id))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(url)
                            .scaledFont(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Image(systemName: "arrow.up.right.square")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(displayURL)
                        .scaledFont(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(url)
        .contextMenu {
            if let id = bmoBugID {
                Button("Open in Bugzilla") {
                    if let resolved = URL(string: url) { openURL(resolved) }
                }
                Button("Copy Bug Link") { copyToPasteboard(url) }
                Button("Copy Bug ID") { copyToPasteboard(String(id)) }
            } else {
                Button("Open Link") {
                    if let resolved = URL(string: url) { openURL(resolved) }
                }
                Button("Copy Link") { copyToPasteboard(url) }
            }
            Divider()
            Button("Remove", role: .destructive) { onRemove(url) }
        }
    }

    private var bmoBugID: Bug.ID? {
        guard let comps = URLComponents(string: url),
              let host = comps.host?.lowercased(),
              host == "bugzilla.mozilla.org" else { return nil }
        if let item = comps.queryItems?.first(where: { $0.name == "id" }),
           let value = item.value, let id = Int(value) {
            return id
        }
        return nil
    }

    private var displayURL: String {
        if let comps = URLComponents(string: url), let host = comps.host {
            return host + comps.path
        }
        return url
    }

    private func isClosed(_ id: Bug.ID) -> Bool {
        workspace.dependencyMetadata(for: id)?.isClosed ?? false
    }
}

private struct DependencyList: View {
    let title: String
    let bugID: Bug.ID
    let ids: [Int]
    let direction: BlockDirection
    let onOpenBug: (Bug.ID) -> Void
    let onAdd: () -> Void
    let onRemove: (Bug.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeader(
                title: title,
                trailing: ids.count > 1 ? "\(ids.count)" : nil,
                onAdd: onAdd
            )
            VStack(alignment: .leading, spacing: 4) {
                if ids.isEmpty {
                    Text("Drop bugs here to add")
                        .scaledFont(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(ids, id: \.self) { id in
                        DependencyRow(id: id, onOpen: onOpenBug, onRemove: onRemove)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .bugBlockDrop(target: bugID, fixed: direction)
    }
}

private struct DependencyRow: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openURL) private var openURL
    let id: Int
    let onOpen: (Bug.ID) -> Void
    let onRemove: (Bug.ID) -> Void

    var body: some View {
        Button {
            onOpen(id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "#\(id)")
                    .scaledFont(.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                if let summary = metadata?.summary {
                    Text(summary)
                        .scaledFont(.callout)
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
        .contextMenu {
            Button("Open in Bugzilla") {
                if let url = URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=\(id)") {
                    openURL(url)
                }
            }
            Button("Copy Bug Link") {
                copyToPasteboard("https://bugzilla.mozilla.org/show_bug.cgi?id=\(id)")
            }
            Button("Copy Bug ID") { copyToPasteboard(String(id)) }
            Divider()
            Button("Remove", role: .destructive) { onRemove(id) }
        }
    }

    private var metadata: DependencyMetadata? {
        workspace.dependencyMetadata(for: id)
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
                .scaledFont(.caption)
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
            Text(User.displayName(for: email))
                .scaledFont(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if didCopy {
                Text("Copied")
                    .scaledFont(.caption2)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .help(email)
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

struct FlowLayout: Layout {
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
    let bugID: Bug.ID
    let comments: [Comment]
    let attachmentsByID: [BugzillaKit.Attachment.ID: BugzillaKit.Attachment]
    let mentionCompletionContext: MentionCompletionContext
    let onQuote: (String) -> Void

    var body: some View {
        let visible = comments.filter { comment in
            if comment.attachmentId != nil { return true }
            return !comment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("Comments")
                    .scaledFont(.headline)
                ForEach(visible) { comment in
                    CommentBlock(
                        bugID: bugID,
                        comment: comment,
                        attachment: comment.attachmentId.flatMap { attachmentsByID[$0] },
                        mentionCompletionContext: mentionCompletionContext,
                        onQuote: onQuote
                    )
                }
            }
        }
    }
}

private struct DescriptionBlock: View {
    let bug: Bug
    let comment: Comment
    let attachments: [BugzillaKit.Attachment]
    let mentionCompletionContext: MentionCompletionContext

    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth
    @State private var isEditing = false
    @State private var editedText = ""
    @State private var saveError: String?

    var body: some View {
        let stripped = stripAttachmentHeader(comment.text, hasAttachment: comment.attachmentId != nil)
        let attachment = comment.attachmentId.flatMap { id in
            attachments.first(where: { $0.id == id })
        }
        if !stripped.isEmpty || attachment != nil {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                HStack {
                    Text("Description")
                        .scaledFont(.headline)
                    Spacer()
                    if isReporter, !isEditing {
                        Button {
                            editedText = comment.text
                            saveError = nil
                            isEditing = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .help("Edit description")
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    if let attachment, isImageAttachment(attachment) {
                        AttachmentImagePreview(attachment: attachment)
                    }
                    if isEditing {
                        MarkdownEditor(
                            text: $editedText,
                            minHeight: 160,
                            isDisabled: workspace.isUpdatingBug,
                            autolinksReferences: true,
                            mentionCompletionContext: mentionCompletionContext
                        )
                        HStack(spacing: 8) {
                            if let saveError {
                                Label(saveError, systemImage: "exclamationmark.triangle")
                                    .scaledFont(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Button("Cancel") {
                                isEditing = false
                                saveError = nil
                            }
                            .buttonStyle(.borderless)
                            .disabled(workspace.isUpdatingBug)
                            Button("Save") {
                                Task { await save() }
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(workspace.isUpdatingBug || !canSave)
                        }
                    } else if !stripped.isEmpty {
                        StructuredText(markdown: flattenBlockquotes(CommentMarkdown.autolinkReferences(in: stripped)))
                            .scaledFont(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var isReporter: Bool {
        guard let me = auth.currentUser?.name else { return false }
        return bug.creator == me || bug.reporter == me
    }

    private var canSave: Bool {
        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed != comment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveError = "Description can't be empty."
            return
        }
        if let error = await workspace.updateComment(
            bugID: bug.id,
            commentID: comment.id,
            newText: CommentMarkdown.autolinkReferences(in: trimmed),
            using: auth.client
        ) {
            saveError = error.localizedDescription
            return
        }
        isEditing = false
        saveError = nil
    }
}

private struct CommentBlock: View {
    let bugID: Bug.ID
    let comment: Comment
    let attachment: BugzillaKit.Attachment?
    let mentionCompletionContext: MentionCompletionContext
    let onQuote: (String) -> Void

    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth

    @State private var isEditing = false
    @State private var editedText = ""
    @State private var saveError: String?
    @State private var rowWidth: CGFloat = 800

    private static let narrowThreshold: CGFloat = 560

    private var isNarrow: Bool {
        rowWidth < Self.narrowThreshold
    }

    var body: some View {
        let stripped = stripAttachmentHeader(comment.text, hasAttachment: attachment != nil)
        Group {
            if isNarrow {
                narrowBody(stripped: stripped)
                    .padding(.vertical, 12)
            } else {
                expandedBody(stripped: stripped)
                    .padding(12)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newValue in
            rowWidth = newValue
        }
        .contextMenu {
            if !stripped.isEmpty {
                Button("Copy Comment Text") { copyToPasteboard(stripped) }
                Button("Quote in Reply") { onQuote(stripped) }
            }
            Button("Copy Permalink") {
                copyToPasteboard("https://bugzilla.mozilla.org/show_bug.cgi?id=\(bugID)#c\(comment.count ?? 0)")
            }
            if isAuthor, !isEditing {
                Divider()
                Button("Edit Comment") {
                    editedText = comment.text
                    saveError = nil
                    isEditing = true
                }
            }
        }
    }

    private func expandedBody(stripped: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            UserAvatar(email: comment.creator, size: 28)
            VStack(alignment: .leading, spacing: 6) {
                headerLine
                bodyContent(stripped: stripped, narrow: false)
            }
            Spacer(minLength: 0)
        }
    }

    private func narrowBody(stripped: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                UserAvatar(email: comment.creator, size: 22)
                headerLine
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            bodyContent(stripped: stripped, narrow: true)
        }
    }

    private var headerLine: some View {
        HStack(spacing: 6) {
            Text(User.displayName(for: comment.creator))
                .scaledFont(.callout, weight: .semibold)
                .help(comment.creator)
            Text(verbatim: "·")
                .foregroundStyle(.tertiary)
            Text(comment.creationTime, format: .relative(presentation: .named))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func bodyContent(stripped: String, narrow: Bool) -> some View {
        if let attachment, isImageAttachment(attachment) {
            AttachmentImagePreview(attachment: attachment, cornerRadius: narrow ? 0 : 6)
        } else if let attachment {
            AttachmentInlineLink(attachment: attachment)
                .padding(.horizontal, narrow ? 12 : 0)
        }
        if isEditing {
            VStack(alignment: .leading, spacing: 8) {
                MarkdownEditor(
                    text: $editedText,
                    minHeight: 120,
                    isDisabled: workspace.isUpdatingBug,
                    autolinksReferences: true,
                    mentionCompletionContext: mentionCompletionContext
                )
                HStack(spacing: 8) {
                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .scaledFont(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Cancel") {
                        isEditing = false
                        saveError = nil
                    }
                    .buttonStyle(.borderless)
                    .disabled(workspace.isUpdatingBug)
                    Button("Save") {
                        Task { await save() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(workspace.isUpdatingBug || !canSave)
                }
            }
            .padding(.horizontal, narrow ? 12 : 0)
        } else if !stripped.isEmpty {
            StructuredText(markdown: flattenBlockquotes(CommentMarkdown.autolinkReferences(in: stripped)))
                .scaledFont(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, narrow ? 12 : 0)
        }
    }

    private var isAuthor: Bool {
        guard let me = auth.currentUser?.name else { return false }
        return comment.creator == me
    }

    private var canSave: Bool {
        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed != comment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveError = "Comment can't be empty."
            return
        }
        if let error = await workspace.updateComment(
            bugID: bugID,
            commentID: comment.id,
            newText: CommentMarkdown.autolinkReferences(in: trimmed),
            using: auth.client
        ) {
            saveError = error.localizedDescription
            return
        }
        isEditing = false
        saveError = nil
    }
}

private func flattenBlockquotes(_ markdown: String) -> String {
    markdown
        .components(separatedBy: "\n")
        .map { line -> String in
            guard line.first == ">" else { return line }
            var rest = Substring(line)
            while rest.first == ">" {
                rest = rest.dropFirst()
                if rest.first == " " { rest = rest.dropFirst() }
            }
            return rest.isEmpty ? ">" : "> \(rest)"
        }
        .joined(separator: "\n")
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
    var cornerRadius: CGFloat = 6

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
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .failure:
                        failure
                    @unknown default:
                        failure
                    }
                }
            }
            .buttonStyle(.plain)
            .linkPointerStyle()
            .help("Open attachment in Bugzilla")
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.12))
            ProgressView()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
    }

    private var failure: some View {
        Label("Couldn't load image", systemImage: "photo.badge.exclamationmark")
            .scaledFont(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: cornerRadius))
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
                        .scaledFont(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .linkPointerStyle()
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
                    .scaledFont(.headline)
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
                    .scaledFont(.headline)
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
    @Environment(Workspace.self) private var workspace
    @Environment(\.openURL) private var openURLAction
    let attachment: BugzillaKit.Attachment

    var body: some View {
        Group {
            if let id = phabRevisionInt {
                Button {
                    workspace.navigate(to: .revision(id))
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .linkPointerStyle()
                .help("Open D\(String(id)) in Zilla")
                .contextMenu {
                    Button("Open D\(String(id)) in Phabricator") {
                        openURLAction(openURL)
                    }
                }
            } else {
                Link(destination: openURL) {
                    rowContent
                }
                .buttonStyle(.plain)
                .linkPointerStyle()
                .help("Open patch in Bugzilla")
            }
        }
        .padding(12)
        .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var rowContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(accentColor)
                .imageScale(.large)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .scaledFont(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    ForEach(approvalChannels, id: \.self) { channel in
                        MetaPill(label: channel, color: .green)
                    }
                }
                HStack(spacing: 6) {
                    Text(User.displayName(for: attachment.creator))
                        .lineLimit(1)
                        .help(attachment.creator)
                    Text(verbatim: "·")
                    Text(attachment.creationTime, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    Text(verbatim: "·")
                    if let revision = phabRevision {
                        Text(revision)
                            .scaledFont(.caption, weight: .semibold, design: .monospaced)
                            .foregroundStyle(accentColor)
                    } else {
                        Text("Patch")
                    }
                }
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !isPhabricator {
                Image(systemName: "chevron.right")
                    .scaledFont(.caption, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
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

    private var phabRevisionInt: Int? {
        guard let r = phabRevision else { return nil }
        return Int(r.dropFirst())
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
                        .scaledFont(.headline)
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
                            .scaledFont(.caption)
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
            .linkPointerStyle()
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
                        .truncationMode(.head)
                    if isPhabricator {
                        MetaPill(label: "Phab", color: .blue)
                    } else if attachment.isPatch {
                        MetaPill(label: "Patch", color: .indigo)
                    }
                }
                HStack(spacing: 6) {
                    Text(User.displayName(for: attachment.creator))
                        .lineLimit(1)
                        .help(attachment.creator)
                    Text(verbatim: "·")
                    Text(attachment.creationTime, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    if let size = attachment.size, size > 0, !isPhabricator {
                        Text(verbatim: "·")
                        Text(formattedSize(size))
                    }
                }
                .scaledFont(.caption)
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
    let isPosting: Bool
    let error: String?
    let mentionCompletionContext: MentionCompletionContext
    let onPost: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a comment")
                .scaledFont(.headline)
            MarkdownEditor(
                text: $text,
                isDisabled: isPosting,
                autolinksReferences: true,
                mentionCompletionContext: mentionCompletionContext
            )

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .scaledFont(.caption)
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

// MARK: - Drag-and-drop bug linking

enum BlockDirection: Sendable {
    case dragBlocksTarget
    case targetBlocksDrag
}

private struct BugBlockDropModifier: ViewModifier {
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth

    let target: Bug.ID
    let fixed: BlockDirection?

    @State private var isTargeted: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                isTargeted ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .dropDestination(for: BugTransfer.self) { transfers, _ in
                let direction = fixed ?? Self.directionFromModifiers()
                let targetID = target
                let usable = transfers.filter { $0.id != targetID }
                guard !usable.isEmpty else { return false }
                let workspace = workspace
                let client = auth.client
                Task { @MainActor in
                    for transfer in usable {
                        let source: Bug.ID
                        let dst: Bug.ID
                        switch direction {
                        case .dragBlocksTarget:
                            source = transfer.id
                            dst = targetID
                        case .targetBlocksDrag:
                            source = targetID
                            dst = transfer.id
                        }
                        if let error = await workspace.linkBlocking(
                            source: source,
                            target: dst,
                            using: client
                        ) {
                            workspace.lastLinkError = error.localizedDescription
                            return
                        }
                    }
                }
                return true
            } isTargeted: { isTargeted = $0 }
    }

    private static func directionFromModifiers() -> BlockDirection {
        #if canImport(AppKit)
        if NSEvent.modifierFlags.contains(.option) {
            return .targetBlocksDrag
        }
        #endif
        return .dragBlocksTarget
    }
}

extension View {
    func bugBlockDrop(target: Bug.ID, fixed: BlockDirection? = nil) -> some View {
        modifier(BugBlockDropModifier(target: target, fixed: fixed))
    }

    func bugLinkDrop(target: Bug.ID) -> some View {
        modifier(BugLinkDropModifier(target: target))
    }

    @ViewBuilder
    func linkPointerStyle() -> some View {
        #if os(macOS)
        self.pointerStyle(.link)
        #else
        self
        #endif
    }
}

private struct BugLinkDropModifier: ViewModifier {
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth

    let target: Bug.ID

    @State private var isTargeted: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                isTargeted ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .dropDestination(for: BugLinkTransfer.self) { transfers, _ in
                let targetID = target
                let usable = transfers.filter { $0.id != targetID }
                guard !usable.isEmpty else { return false }
                let workspace = workspace
                let client = auth.client
                Task { @MainActor in
                    for transfer in usable {
                        if let error = await workspace.linkBlocking(
                            source: transfer.id,
                            target: targetID,
                            using: client
                        ) {
                            workspace.lastLinkError = error.localizedDescription
                            return
                        }
                    }
                }
                return true
            } isTargeted: { isTargeted = $0 }
    }
}
