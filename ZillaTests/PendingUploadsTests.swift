import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Zilla

@MainActor
struct PendingUploadReferencesTests {
    private let first = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let second = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test func snippetEscapesTheAltText() {
        let snippet = PendingUploadReferences.snippet(alt: "shot [1]\\b\nc.png", id: first)
        #expect(snippet == #"![shot \[1\]\\b c.png](zilla-upload:11111111-2222-3333-4444-555555555555)"#)
        let match = PendingUploadReferences.matches(in: snippet).first
        #expect(match?.alt == #"shot [1]\b c.png"#)
        #expect(match?.id == first)
    }

    @Test func findsReferencesInOrder() {
        let markdown = """
        Before ![a.png](zilla-upload:\(first.uuidString)) middle
        ![b.png](zilla-upload:\(second.uuidString))
        """
        #expect(PendingUploadReferences.matches(in: markdown).map(\.id) == [first, second])
        #expect(PendingUploadReferences.ids(in: markdown) == [first, second])
    }

    @Test func skipsCodeSpansAndFencedBlocks() {
        let markdown = """
        `![a.png](zilla-upload:\(first.uuidString))`

        ```
        ![a.png](zilla-upload:\(first.uuidString))
        ```

        ~~~~
        ![a.png](zilla-upload:\(first.uuidString))
        ~~~~

        ![b.png](zilla-upload:\(second.uuidString))
        """
        #expect(PendingUploadReferences.matches(in: markdown).map(\.id) == [second])
    }

    @Test func ignoresOtherImagesAndMalformedIDs() {
        let markdown = "![x](https://example.com/x.png) ![y](zilla-upload:not-a-uuid)"
        #expect(PendingUploadReferences.matches(in: markdown).isEmpty)
    }

    @Test func replacesReferencesInPlace() async throws {
        let markdown = "A ![a.png](zilla-upload:\(first.uuidString)) B ![b.png](zilla-upload:\(second.uuidString)) C"
        let replaced = await PendingUploadReferences.replacing(markdown) { match in "<\(match.alt)>" }
        #expect(replaced == "A <a.png> B <b.png> C")
        #expect(PendingUploadReferences.replacingWithNames(markdown) == "A a.png B b.png C")
    }

    @Test func pendingUploadFileNameKeepsOneExtension() {
        let url = URL(fileURLWithPath: "/tmp/\(first.uuidString).png")
        #expect(PendingUpload(id: first, name: "shot.png", fileURL: url).fileName == "shot.png")
        #expect(PendingUpload(id: first, name: "shot", fileURL: url).fileName == "shot.png")
        #expect(PendingUpload(id: first, name: " ", fileURL: url).fileName == "image.png")
        #expect(PendingUpload(id: first, name: "shot.png", fileURL: url).mimeType == "image/png")
    }
}

@MainActor
struct PendingUploadStoreTests {
    private func makeStore() -> PendingUploadStore {
        PendingUploadStore(directory: FileManager.default.temporaryDirectory.appending(path: "pending-\(UUID().uuidString)"))
    }

    private func image(as type: UTType) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let cgImage = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func addStoresTheImageAndReturnsAReference() throws {
        let store = makeStore()
        let png = try image(as: .png)
        let snippet = try store.add(data: png, contentType: .png, suggestedName: "Screen Shot.png")
        let match = try #require(PendingUploadReferences.matches(in: snippet).first)
        #expect(match.alt == "Screen Shot.png")
        let upload = try store.upload(for: match)
        #expect(try upload.data() == png)
        #expect(upload.contentType == .png)
    }

    @Test func pastedImagesWithoutANameAreCalledImage() throws {
        let store = makeStore()
        let snippet = try store.add(data: try image(as: .png), contentType: .png, suggestedName: nil)
        #expect(PendingUploadReferences.matches(in: snippet).first?.alt == "image.png")
    }

    @Test func tiffIsConvertedToPNG() throws {
        let store = makeStore()
        let snippet = try store.add(data: try image(as: .tiff), contentType: .tiff, suggestedName: "capture.tiff")
        let match = try #require(PendingUploadReferences.matches(in: snippet).first)
        #expect(match.alt == "capture.png")
        let upload = try store.upload(for: match)
        #expect(upload.contentType == .png)
        let source = try #require(CGImageSourceCreateWithData(try upload.data() as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    }

    @Test func unreadableDataIsRejected() {
        let store = makeStore()
        #expect(throws: PendingUploadError.unreadableImage) {
            try store.add(data: Data([1, 2, 3]), contentType: .tiff, suggestedName: nil)
        }
    }

    @Test func missingFilesNameTheImage() throws {
        let store = makeStore()
        let markdown = PendingUploadReferences.snippet(alt: "gone.png", id: UUID())
        let match = try #require(PendingUploadReferences.matches(in: markdown).first)
        #expect(throws: PendingUploadError.missingFile(name: "gone.png")) {
            try store.upload(for: match)
        }
    }

    @Test func resolveUploadsOncePerDestination() async throws {
        let store = makeStore()
        let snippet = try store.add(data: try image(as: .png), contentType: .png, suggestedName: "a.png")
        let markdown = "See \(snippet) and \(snippet)"
        var uploads = 0

        let resolved = try await store.resolve(markdown, destination: "bugzilla:1") { upload in
            uploads += 1
            return "[\(upload.fileName)](attachment-\(uploads))"
        }
        #expect(resolved == "See [a.png](attachment-1) and [a.png](attachment-1)")

        let retried = try await store.resolve(markdown, destination: "bugzilla:1") { _ in
            uploads += 1
            return "unexpected"
        }
        #expect(retried == resolved)
        #expect(uploads == 1)

        _ = try await store.resolve(markdown, destination: "bugzilla:2") { _ in
            uploads += 1
            return "other"
        }
        #expect(uploads == 2)
    }

    @Test func failedUploadLeavesNothingCached() async throws {
        let store = makeStore()
        let snippet = try store.add(data: try image(as: .png), contentType: .png, suggestedName: "a.png")
        struct Failure: Error {}

        await #expect(throws: Failure.self) {
            _ = try await store.resolve(snippet, destination: "phabricator") { _ in throw Failure() }
        }
        let resolved = try await store.resolve(snippet, destination: "phabricator") { _ in "{F1}" }
        #expect(resolved == "{F1}")
    }

    @Test func pruneKeepsOnlyReferencedFiles() throws {
        let store = makeStore()
        let kept = try store.add(data: try image(as: .png), contentType: .png, suggestedName: "kept.png")
        let dropped = try store.add(data: try image(as: .png), contentType: .png, suggestedName: "dropped.png")
        let keptMatch = try #require(PendingUploadReferences.matches(in: kept).first)
        let droppedMatch = try #require(PendingUploadReferences.matches(in: dropped).first)

        store.prune(keeping: [keptMatch.id])

        #expect(throws: Never.self) { try store.upload(for: keptMatch) }
        #expect(throws: PendingUploadError.self) { try store.upload(for: droppedMatch) }
    }

    @Test func attachmentLinksUseBugzillaAttachmentURLs() {
        let url = PendingUploadStore.attachmentURL(9876, baseURL: URL(string: "https://bugzilla.mozilla.org")!)
        #expect(url == "https://bugzilla.mozilla.org/attachment.cgi?id=9876")
        #expect(ZillaLinkChipTarget.target(for: URL(string: url)!)?.kind == .attachment)
    }
}
