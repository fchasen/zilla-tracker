import CryptoKit
import Foundation
import FolioHighlight
import FolioModel

struct FolioRenderArtifactCacheKey: Sendable, Hashable {
    let path: String
    let themeSignature: Int
    let contextLines: Int
    let content: FolioContentFingerprint

    init(
        content: FolioContent,
        path: String,
        theme: HighlightTheme,
        contextLines: Int
    ) {
        self.path = path
        self.themeSignature = theme.paletteSignature
        self.contextLines = contextLines
        self.content = FolioContentFingerprint(content)
    }
}

struct FolioContentFingerprint: Sendable, Hashable {
    let digest: [UInt8]

    init(_ content: FolioContent) {
        var hasher = SHA256()
        switch content {
        case let .diff(hunk, _, _):
            append(0, to: &hasher)
            append(hunk.oldStart, to: &hasher)
            append(hunk.newStart, to: &hasher)
            append(hunk.lines.count, to: &hasher)
            for line in hunk.lines {
                append(line.kind, to: &hasher)
                append(line.oldNumber, to: &hasher)
                append(line.newNumber, to: &hasher)
                append(line.text, to: &hasher)
            }
        case let .code(text, startLine):
            append(1, to: &hasher)
            append(startLine, to: &hasher)
            append(text, to: &hasher)
        }
        digest = Array(hasher.finalize())
    }
}

actor FolioRenderArtifactCache {
    static let shared = FolioRenderArtifactCache()

    private var storage: [FolioRenderArtifactCacheKey: FolioRenderArtifact] = [:]
    private var order: [FolioRenderArtifactCacheKey] = []
    private let limit: Int

    init(limit: Int = 8) {
        self.limit = max(1, limit)
    }

    func artifact(for key: FolioRenderArtifactCacheKey) -> FolioRenderArtifact? {
        guard let artifact = storage[key] else { return nil }
        touch(key)
        return artifact
    }

    func store(_ artifact: FolioRenderArtifact, for key: FolioRenderArtifactCacheKey) {
        storage[key] = artifact
        touch(key)
        trim()
    }

    private func touch(_ key: FolioRenderArtifactCacheKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func trim() {
        while storage.count > limit, let key = order.first {
            order.removeFirst()
            storage[key] = nil
        }
    }
}

private func append(_ value: DiffLine.Kind, to hasher: inout SHA256) {
    switch value {
    case .context: append(0, to: &hasher)
    case .addition: append(1, to: &hasher)
    case .deletion: append(2, to: &hasher)
    case .noNewline: append(3, to: &hasher)
    }
}

private func append(_ value: Int?, to hasher: inout SHA256) {
    if let value {
        append(1, to: &hasher)
        append(value, to: &hasher)
    } else {
        append(0, to: &hasher)
    }
}

private func append(_ value: Int, to hasher: inout SHA256) {
    var bigEndian = Int64(value).bigEndian
    withUnsafeBytes(of: &bigEndian) { bytes in
        hasher.update(bufferPointer: UnsafeRawBufferPointer(bytes))
    }
}

private func append(_ value: String, to hasher: inout SHA256) {
    append(value.utf8.count, to: &hasher)
    if value.utf8.withContiguousStorageIfAvailable({ bytes in
        hasher.update(bufferPointer: UnsafeRawBufferPointer(bytes))
    }) == nil {
        hasher.update(data: Data(value.utf8))
    }
}
