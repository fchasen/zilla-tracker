import Foundation
import ImageIO
import UniformTypeIdentifiers
import BugzillaKit
import PhabricatorKit

struct PendingUpload: Hashable, Sendable {
    let id: UUID
    let name: String
    let fileURL: URL

    var contentType: UTType {
        UTType(filenameExtension: fileURL.pathExtension) ?? .data
    }

    var mimeType: String {
        contentType.preferredMIMEType ?? "application/octet-stream"
    }

    var fileName: String {
        let ext = fileURL.pathExtension
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "image" : trimmed
        guard !ext.isEmpty, (base as NSString).pathExtension.lowercased() != ext.lowercased() else { return base }
        return "\(base).\(ext)"
    }

    func data() throws -> Data {
        try Data(contentsOf: fileURL)
    }
}

enum PendingUploadError: LocalizedError, Equatable {
    case missingFile(name: String)
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .missingFile(let name):
            "The image “\(name)” is no longer available on this device. Remove it and add it again."
        case .unreadableImage:
            "The image could not be read."
        }
    }
}

enum PendingUploadReferences {
    static let scheme = "zilla-upload"

    struct Match: Equatable {
        let range: Range<String.Index>
        let alt: String
        let id: UUID
    }

    static func snippet(alt: String, id: UUID) -> String {
        "![\(escapeAlt(alt))](\(scheme):\(id.uuidString))"
    }

    static func escapeAlt(_ alt: String) -> String {
        var result = ""
        for character in alt {
            switch character {
            case "\\", "[", "]":
                result.append("\\")
                result.append(character)
            case "\n", "\r":
                result.append(" ")
            default:
                result.append(character)
            }
        }
        return result
    }

    static func unescapeAlt(_ alt: String) -> String {
        alt.replacing(#/\\([\\\[\]])/#) { String($0.output.1) }
    }

    static func matches(in markdown: String) -> [Match] {
        let code = codeRanges(in: markdown)
        return markdown.matches(of: #/!\[((?:\\.|[^\]\\\n])*)\]\(zilla-upload:([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\)/#)
            .compactMap { match in
                guard !code.contains(where: { $0.overlaps(match.range) }),
                      let id = UUID(uuidString: String(match.output.2))
                else { return nil }
                return Match(range: match.range, alt: unescapeAlt(String(match.output.1)), id: id)
            }
    }

    static func ids(in markdown: String) -> Set<UUID> {
        Set(matches(in: markdown).map(\.id))
    }

    static func replacing(_ markdown: String, with replacement: (Match) async throws -> String) async rethrows -> String {
        var result = ""
        var cursor = markdown.startIndex
        for match in matches(in: markdown) {
            result += markdown[cursor..<match.range.lowerBound]
            result += try await replacement(match)
            cursor = match.range.upperBound
        }
        result += markdown[cursor...]
        return result
    }

    static func replacingWithNames(_ markdown: String) -> String {
        var result = ""
        var cursor = markdown.startIndex
        for match in matches(in: markdown) {
            result += markdown[cursor..<match.range.lowerBound]
            result += match.alt
            cursor = match.range.upperBound
        }
        result += markdown[cursor...]
        return result
    }

    static func codeRanges(in markdown: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var fence: (marker: Character, length: Int, start: String.Index)?
        var lineStart = markdown.startIndex
        while lineStart < markdown.endIndex {
            let lineEnd = markdown[lineStart...].firstIndex(of: "\n") ?? markdown.endIndex
            let line = markdown[lineStart..<lineEnd]
            let stripped = line.drop(while: { $0 == " " })
            let marker = stripped.first
            let run = marker.map { m in stripped.prefix(while: { $0 == m }).count } ?? 0
            let isFence = line.count - stripped.count < 4 && (marker == "`" || marker == "~") && run >= 3
            if let open = fence {
                if isFence, marker == open.marker, run >= open.length,
                   stripped.dropFirst(run).allSatisfy(\.isWhitespace) {
                    ranges.append(open.start..<lineEnd)
                    fence = nil
                }
            } else if isFence, let marker {
                fence = (marker, run, lineStart)
            } else {
                ranges.append(contentsOf: codeSpans(in: line))
            }
            lineStart = lineEnd < markdown.endIndex ? markdown.index(after: lineEnd) : markdown.endIndex
        }
        if let open = fence {
            ranges.append(open.start..<markdown.endIndex)
        }
        return ranges
    }

    private static func codeSpans(in line: Substring) -> [Range<String.Index>] {
        var spans: [Range<String.Index>] = []
        var index = line.startIndex
        while let open = line[index...].firstIndex(of: "`") {
            let openRun = line[open...].prefix(while: { $0 == "`" })
            var search = openRun.endIndex
            var closed = false
            while let close = line[search...].firstIndex(of: "`") {
                let closeRun = line[close...].prefix(while: { $0 == "`" })
                if closeRun.count == openRun.count {
                    spans.append(open..<closeRun.endIndex)
                    index = closeRun.endIndex
                    closed = true
                    break
                }
                search = closeRun.endIndex
            }
            if !closed { index = openRun.endIndex }
        }
        return spans
    }
}

@MainActor
final class PendingUploadStore {
    static let shared = PendingUploadStore()

    let directory: URL
    private var resolved: [ResolvedKey: String] = [:]
    private var hasPruned = false

    private struct ResolvedKey: Hashable {
        let id: UUID
        let destination: String
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "PendingUploads", directoryHint: .isDirectory)
    }

    func add(data: Data, contentType: UTType, suggestedName: String?) throws -> String {
        let (normalized, type) = try Self.normalize(data, contentType: contentType)
        let id = UUID()
        let ext = type.preferredFilenameExtension ?? "png"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try normalized.write(to: directory.appending(path: "\(id.uuidString).\(ext)"), options: .atomic)
        return PendingUploadReferences.snippet(alt: Self.displayName(suggestedName, ext: ext), id: id)
    }

    func addFile(at url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data
        return try add(data: Data(contentsOf: url), contentType: type, suggestedName: url.lastPathComponent)
    }

    func upload(for match: PendingUploadReferences.Match) throws -> PendingUpload {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        guard let file = files.first(where: { $0.deletingPathExtension().lastPathComponent == match.id.uuidString }) else {
            throw PendingUploadError.missingFile(name: match.alt)
        }
        return PendingUpload(id: match.id, name: match.alt, fileURL: file)
    }

    func resolve(
        _ markdown: String,
        destination: String,
        upload: (PendingUpload) async throws -> String
    ) async throws -> String {
        try await PendingUploadReferences.replacing(markdown) { match in
            let key = ResolvedKey(id: match.id, destination: destination)
            if let cached = resolved[key] { return cached }
            let replacement = try await upload(self.upload(for: match))
            resolved[key] = replacement
            return replacement
        }
    }

    func resolveForBugzilla(_ markdown: String, bugID: Bug.ID, using client: BugzillaClient) async throws -> String {
        guard !PendingUploadReferences.matches(in: markdown).isEmpty else { return markdown }
        let baseURL = await client.baseURL
        return try await resolve(markdown, destination: "bugzilla:\(bugID)") { upload in
            let id = try await client.createAttachment(
                bugID: bugID,
                data: upload.data(),
                fileName: upload.fileName,
                summary: upload.fileName,
                contentType: upload.mimeType
            )
            return "[\(PendingUploadReferences.escapeAlt(upload.fileName))](\(Self.attachmentURL(id, baseURL: baseURL)))"
        }
    }

    func resolveForPhabricator(_ markdown: String, using client: PhabricatorClient) async throws -> String {
        guard !PendingUploadReferences.matches(in: markdown).isEmpty else { return markdown }
        return try await resolve(markdown, destination: "phabricator") { upload in
            let file = try await client.uploadFile(data: upload.data(), name: upload.fileName)
            let url = Remarkup.phabricatorProductionURL.appending(path: file.monogram)
            return "![\(PendingUploadReferences.escapeAlt(upload.name))](\(url.absoluteString))"
        }
    }

    func remarkup(fromMarkdown markdown: String, using client: PhabricatorClient) async throws -> String {
        let resolved = try await resolveForPhabricator(markdown, using: client)
        return Markdown.toRemarkup(CommentMarkdown.autolinkReferences(in: resolved))
    }

    func pruneOnce(keeping referenced: @autoclosure () -> Set<UUID>) {
        guard !hasPruned else { return }
        hasPruned = true
        prune(keeping: referenced())
    }

    func prune(keeping referenced: Set<UUID>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
            if id.map(referenced.contains) != true {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    nonisolated static func attachmentURL(_ id: Attachment.ID, baseURL: URL) -> String {
        var components = URLComponents(url: baseURL.appending(path: "attachment.cgi"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "id", value: String(id))]
        return components?.url?.absoluteString ?? "\(baseURL.absoluteString)/attachment.cgi?id=\(id)"
    }

    nonisolated static func displayName(_ suggested: String?, ext: String) -> String {
        let trimmed = suggested?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = trimmed.isEmpty ? "image" : (trimmed as NSString).deletingPathExtension
        return "\(base.isEmpty ? "image" : base).\(ext)"
    }

    nonisolated static func normalize(_ data: Data, contentType: UTType) throws -> (Data, UTType) {
        if [UTType.png, .jpeg, .gif, .webP].contains(where: contentType.conforms(to:)) {
            return (data, [UTType.png, .jpeg, .gif, .webP].first(where: contentType.conforms(to:)) ?? contentType)
        }
        let target: UTType = contentType.conforms(to: .heic) || contentType.conforms(to: .heif) ? .jpeg : .png
        return (try transcode(data, to: target), target)
    }

    nonisolated static func transcode(_ data: Data, to type: UTType) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { throw PendingUploadError.unreadableImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw PendingUploadError.unreadableImage
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImageFromSource(destination, source, 0, options)
        guard CGImageDestinationFinalize(destination) else { throw PendingUploadError.unreadableImage }
        return output as Data
    }
}
