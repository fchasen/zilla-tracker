import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LinkInsertSheet: View {
    let onInsert: (_ label: String, _ url: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var label = ""
    @FocusState private var focused: Field?

    private enum Field { case url, label }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            fields
            previewRow
            Spacer(minLength: 8)
            Divider()
            buttonRow
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 240)
        #else
        .frame(minHeight: 280)
        #endif
        .onAppear {
            if let pasted = pasteboardURL() {
                url = pasted
                focused = .label
            } else {
                focused = .url
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
                .imageScale(.medium)
            Text("Insert Link")
                .font(.system(.headline, design: .default, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(label: "URL") {
                TextField("https://", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .url)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .onSubmit { focused = .label }
            }
            row(label: "Label") {
                TextField("link", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .label)
                    .onSubmit { insert() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func row(label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            content()
        }
    }

    @ViewBuilder
    private var previewRow: some View {
        if !trimmedURL.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Preview")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 50, alignment: .trailing)
                Text(preview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }

    private var buttonRow: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Insert", action: insert)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedURL.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var preview: String {
        let lab = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = lab.isEmpty ? "link" : lab
        return "[\(resolved)](\(trimmedURL))"
    }

    private func insert() {
        let resolvedURL = trimmedURL
        guard !resolvedURL.isEmpty else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = trimmedLabel.isEmpty ? "link" : trimmedLabel
        onInsert(resolvedLabel, resolvedURL)
        dismiss()
    }

    private func pasteboardURL() -> String? {
        #if os(macOS)
        let raw = NSPasteboard.general.string(forType: .string)
        #else
        let raw = UIPasteboard.general.string
        #endif
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else { return nil }
        return trimmed
    }
}
