//
//  BugDetailView.swift
//  Zilla
//

import SwiftUI
import BugzillaKit

struct BugDetailView: View {
    @Environment(AuthStore.self) private var auth
    let bugID: Bug.ID?

    @State private var bug: Bug?
    @State private var comments: [Comment] = []
    @State private var isLoading = false
    @State private var loadError: String?

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
                BugContent(bug: bug, comments: comments, loadError: loadError)
            } else if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .toolbar {
            if let bugID, let url = bmoURL(for: bugID) {
                ToolbarItem(placement: .secondaryAction) {
                    Link(destination: url) {
                        Label("Open in Bugzilla", systemImage: "safari")
                    }
                }
            }
        }
        .task(id: bugID) { await load(id: bugID) }
    }

    private func bmoURL(for id: Int) -> URL? {
        URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=\(id)")
    }

    private func load(id: Int?) async {
        guard let id else {
            bug = nil
            comments = []
            loadError = nil
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let client = auth.client
        do {
            async let bugTask = client.getBug(id: id)
            async let commentsTask = client.comments(bugID: id)
            self.bug = try await bugTask
            self.comments = try await commentsTask
        } catch is CancellationError {
            return
        } catch {
            self.bug = nil
            self.comments = []
            self.loadError = error.localizedDescription
        }
    }
}

private struct BugContent: View {
    let bug: Bug
    let comments: [Comment]
    let loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BugHeader(bug: bug)
                Divider()
                BugMetadata(bug: bug)

                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if !comments.isEmpty {
                    Divider()
                    BugCommentsSection(comments: comments)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct BugHeader: View {
    let bug: Bug

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("#\(bug.id)")
                    .font(.headline.monospaced())
                    .foregroundStyle(.secondary)
                StatusPill(bug: bug)
            }
            Text(bug.summary)
                .font(.title2)
                .textSelection(.enabled)
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
            return bug.status
        }
        return "\(bug.status) · \(bug.resolution)"
    }

    private var color: Color {
        switch bug.status.uppercased() {
        case "RESOLVED", "VERIFIED", "CLOSED": return .green
        case "ASSIGNED", "IN_PROGRESS": return .blue
        default: return .orange
        }
    }
}

private struct BugMetadata: View {
    let bug: Bug

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
            row("Assignee", bug.assignedTo ?? "—")
            row("Reporter", bug.reporter ?? bug.creator ?? "—")
            row("Component", "\(bug.product) :: \(bug.component)")
            if let p = bug.priority, !p.isEmpty { row("Priority", p) }
            if let s = bug.severity, !s.isEmpty { row("Severity", s) }
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
}

private struct BugCommentsSection: View {
    let comments: [Comment]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comments")
                .font(.headline)
            ForEach(comments) { comment in
                CommentBlock(comment: comment)
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
                    Text("#\(count)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(comment.creationTime, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(comment.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
