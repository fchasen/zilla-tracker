import Foundation
import SwiftData

typealias InlineDraftBuffer = ZillaSchemaV2.InlineDraftBuffer

struct InlineDraftKey: Hashable {
    let revisionID: Int
    let diffID: Int
    let path: String
    let line: Int
    let isNewFile: Bool
    let replyTo: String?
}

extension ModelContext {
    func loadInlineDraft(_ key: InlineDraftKey) -> InlineDraftBuffer? {
        let revisionID = key.revisionID
        let diffID = key.diffID
        let path = key.path
        let line = key.line
        let isNewFile = key.isNewFile
        let replyTo = key.replyTo
        let predicate = #Predicate<InlineDraftBuffer> { buffer in
            buffer.revisionID == revisionID
                && buffer.diffID == diffID
                && buffer.path == path
                && buffer.line == line
                && buffer.isNewFile == isNewFile
                && buffer.replyTo == replyTo
        }
        var descriptor = FetchDescriptor<InlineDraftBuffer>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? fetch(descriptor))?.first
    }

    func saveInlineDraft(_ key: InlineDraftKey, length: Int, content: String) {
        if let existing = loadInlineDraft(key) {
            if content.isEmpty {
                delete(existing)
            } else {
                existing.content = content
                existing.length = length
                existing.updatedAt = .now
            }
            return
        }
        guard !content.isEmpty else { return }
        let buffer = InlineDraftBuffer(
            revisionID: key.revisionID,
            diffID: key.diffID,
            path: key.path,
            line: key.line,
            length: length,
            isNewFile: key.isNewFile,
            replyTo: key.replyTo,
            content: content
        )
        insert(buffer)
    }

    func clearInlineDraft(_ key: InlineDraftKey) {
        if let existing = loadInlineDraft(key) {
            delete(existing)
        }
    }
}
