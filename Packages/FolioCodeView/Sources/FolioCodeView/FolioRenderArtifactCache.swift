import CryptoKit
import Foundation
import FolioHighlight
import FolioModel

struct FolioRenderArtifactTaskKey: Sendable, Equatable {
    enum Content: Sendable, Equatable {
        case diff(DiffHunk)
        case code(String, startLine: Int)

        init(_ content: FolioContent) {
            switch content {
            case let .diff(hunk, _, _):
                self = .diff(hunk)
            case let .code(text, startLine):
                self = .code(text, startLine: startLine)
            }
        }

        var folioContent: FolioContent {
            switch self {
            case let .diff(hunk):
                return .diff(hunk, anchor: nil, mode: .unified)
            case let .code(text, startLine):
                return .code(text, startLine: startLine)
            }
        }
    }

    let path: String
    let themeSignature: Int
    let contextLines: Int
    let content: Content

    init(
        content: FolioContent,
        path: String,
        theme: HighlightTheme,
        contextLines: Int
    ) {
        self.path = path
        self.themeSignature = theme.paletteSignature
        self.contextLines = contextLines
        self.content = Content(content)
    }
}

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

    init(_ taskKey: FolioRenderArtifactTaskKey) {
        self.path = taskKey.path
        self.themeSignature = taskKey.themeSignature
        self.contextLines = taskKey.contextLines
        self.content = FolioContentFingerprint(taskKey.content)
    }
}

struct FolioContentFingerprint: Sendable, Hashable {
    let digest: [UInt8]

    init(_ content: FolioContent) {
        self.init(FolioRenderArtifactTaskKey.Content(content))
    }

    init(_ content: FolioRenderArtifactTaskKey.Content) {
        var hasher = SHA256()
        switch content {
        case let .diff(hunk):
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

    private struct Entry {
        let artifact: FolioRenderArtifact
        let cost: Int
    }

    private var storage: [FolioRenderArtifactCacheKey: Entry] = [:]
    private var order: [FolioRenderArtifactCacheKey] = []
    private var totalCost: Int = 0
    private let limit: Int
    private let costLimit: Int

    init(limit: Int = 8, costLimit: Int = 12 * 1024 * 1024) {
        self.limit = max(1, limit)
        self.costLimit = max(1, costLimit)
    }

    func artifact(for key: FolioRenderArtifactCacheKey) -> FolioRenderArtifact? {
        guard let entry = storage[key] else { return nil }
        touch(key)
        return entry.artifact
    }

    func store(_ artifact: FolioRenderArtifact, for key: FolioRenderArtifactCacheKey) {
        let cost = artifact.estimatedByteCost
        guard cost <= costLimit else {
            remove(key)
            return
        }
        if let existing = storage[key] {
            totalCost -= existing.cost
        }
        storage[key] = Entry(artifact: artifact, cost: cost)
        totalCost += cost
        touch(key)
        trim()
    }

    private func touch(_ key: FolioRenderArtifactCacheKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func trim() {
        while (storage.count > limit || totalCost > costLimit), let key = order.first {
            remove(key)
        }
    }

    private func remove(_ key: FolioRenderArtifactCacheKey) {
        if let existing = storage.removeValue(forKey: key) {
            totalCost -= existing.cost
        }
        order.removeAll { $0 == key }
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
