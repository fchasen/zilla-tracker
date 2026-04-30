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
        NavigationStack {
            Form {
                TextField("URL", text: $url, prompt: Text("https://"))
                    .focused($focused, equals: .url)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                TextField("Label", text: $label, prompt: Text("link"))
                    .focused($focused, equals: .label)
            }
            .navigationTitle("Insert Link")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert", action: insert)
                        .disabled(trimmedURL.isEmpty)
                        .keyboardShortcut(.return)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 440, minHeight: 160)
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

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
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
