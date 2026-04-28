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
                    DescriptionBlock(comment: description)
                }
                BugCommentsSection(comments: threadComments)
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
        comments.filter { ($0.count ?? -1) != 0 }
    }
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
        let value = String(bug.id)
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = value
        #endif
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

private struct BugCommentsSection: View {
    let comments: [Comment]

    var body: some View {
        let visible = comments.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("Comments")
                    .font(.headline)
                ForEach(visible) { comment in
                    CommentBlock(comment: comment)
                }
            }
        }
    }
}

private struct DescriptionBlock: View {
    let comment: Comment

    var body: some View {
        let trimmed = comment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("Description")
                    .font(.headline)
                StructuredText(markdown: comment.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct CommentBlock: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            StructuredText(markdown: comment.text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
