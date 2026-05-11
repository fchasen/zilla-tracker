import XCTest
import FolioModel
@testable import FolioCodeView

final class FolioRenderArtifactCacheTests: XCTestCase {
    func testCacheReturnsStoredArtifactForSameContent() async {
        let cache = FolioRenderArtifactCache(limit: 2)
        let content = FolioContent.code("let value = 1;", startLine: 3)
        let key = FolioRenderArtifactCacheKey(
            content: content,
            path: "example.js",
            theme: .light,
            contextLines: 3
        )
        let artifact = FolioRenderArtifactBuilder.full(
            content: content,
            contextLines: 3,
            path: "example.js",
            theme: .light
        )

        await cache.store(artifact, for: key)

        let cached = await cache.artifact(for: key)
        XCTAssertEqual(cached, artifact)
    }

    func testCacheDistinguishesMiddleContentChanges() async {
        let cache = FolioRenderArtifactCache(limit: 2)
        let original = FolioContent.code("let first = 1;\nlet second = 2;\nlet third = 3;", startLine: 1)
        let changed = FolioContent.code("let first = 1;\nlet second = 20;\nlet third = 3;", startLine: 1)
        let originalKey = FolioRenderArtifactCacheKey(
            content: original,
            path: "example.js",
            theme: .light,
            contextLines: 3
        )
        let changedKey = FolioRenderArtifactCacheKey(
            content: changed,
            path: "example.js",
            theme: .light,
            contextLines: 3
        )
        let artifact = FolioRenderArtifactBuilder.full(
            content: original,
            contextLines: 3,
            path: "example.js",
            theme: .light
        )

        await cache.store(artifact, for: originalKey)

        let cached = await cache.artifact(for: changedKey)
        XCTAssertNil(cached)
    }

    func testCacheEvictsLeastRecentlyUsedArtifact() async {
        let cache = FolioRenderArtifactCache(limit: 2)
        let first = FolioContent.code("let first = 1;", startLine: 1)
        let second = FolioContent.code("let second = 2;", startLine: 1)
        let third = FolioContent.code("let third = 3;", startLine: 1)
        let firstKey = key(for: first)
        let secondKey = key(for: second)
        let thirdKey = key(for: third)

        await cache.store(artifact(for: first), for: firstKey)
        await cache.store(artifact(for: second), for: secondKey)
        _ = await cache.artifact(for: firstKey)
        await cache.store(artifact(for: third), for: thirdKey)

        let cachedFirst = await cache.artifact(for: firstKey)
        let cachedSecond = await cache.artifact(for: secondKey)
        let cachedThird = await cache.artifact(for: thirdKey)
        XCTAssertNotNil(cachedFirst)
        XCTAssertNil(cachedSecond)
        XCTAssertNotNil(cachedThird)
    }

    func testCacheEvictsLeastRecentlyUsedArtifactWhenCostLimitIsExceeded() async {
        let first = FolioContent.code(String(repeating: "let first = 1;\n", count: 80), startLine: 1)
        let second = FolioContent.code(String(repeating: "let second = 2;\n", count: 80), startLine: 1)
        let firstArtifact = artifact(for: first)
        let secondArtifact = artifact(for: second)
        let cache = FolioRenderArtifactCache(
            limit: 10,
            costLimit: firstArtifact.estimatedByteCost + secondArtifact.estimatedByteCost - 1
        )
        let firstKey = key(for: first)
        let secondKey = key(for: second)

        await cache.store(firstArtifact, for: firstKey)
        await cache.store(secondArtifact, for: secondKey)

        let cachedFirst = await cache.artifact(for: firstKey)
        let cachedSecond = await cache.artifact(for: secondKey)
        XCTAssertNil(cachedFirst)
        XCTAssertNotNil(cachedSecond)
    }

    func testCacheSkipsOversizedArtifact() async {
        let content = FolioContent.code(String(repeating: "let value = 1;\n", count: 80), startLine: 1)
        let artifact = artifact(for: content)
        let cache = FolioRenderArtifactCache(limit: 10, costLimit: artifact.estimatedByteCost - 1)
        let key = key(for: content)

        await cache.store(artifact, for: key)

        let cached = await cache.artifact(for: key)
        XCTAssertNil(cached)
    }

    func testTaskKeyIgnoresDiffPresentationValues() {
        let hunk = DiffHunk(
            oldStart: 1,
            newStart: 1,
            lines: [
                DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "let value = 1;")
            ]
        )
        let anchored = FolioRenderArtifactTaskKey(
            content: .diff(
                hunk,
                anchor: AnchorRange(line: 1, length: 1, side: .newFile),
                mode: .unified
            ),
            path: "example.swift",
            theme: .light,
            contextLines: 3
        )
        let split = FolioRenderArtifactTaskKey(
            content: .diff(hunk, anchor: nil, mode: .split),
            path: "example.swift",
            theme: .light,
            contextLines: 3
        )

        XCTAssertEqual(anchored, split)
    }

    func testTaskKeyDistinguishesMiddleDiffLineChanges() {
        let original = diffContent(middle: "let second = 2;")
        let changed = diffContent(middle: "let second = 20;")
        let originalKey = FolioRenderArtifactTaskKey(
            content: original,
            path: "example.swift",
            theme: .light,
            contextLines: 3
        )
        let changedKey = FolioRenderArtifactTaskKey(
            content: changed,
            path: "example.swift",
            theme: .light,
            contextLines: 3
        )

        XCTAssertNotEqual(originalKey, changedKey)
    }

    private func key(for content: FolioContent) -> FolioRenderArtifactCacheKey {
        FolioRenderArtifactCacheKey(
            content: content,
            path: "example.js",
            theme: .light,
            contextLines: 3
        )
    }

    private func artifact(for content: FolioContent) -> FolioRenderArtifact {
        FolioRenderArtifactBuilder.full(
            content: content,
            contextLines: 3,
            path: "example.js",
            theme: .light
        )
    }

    private func diffContent(middle: String) -> FolioContent {
        .diff(
            DiffHunk(
                oldStart: 1,
                newStart: 1,
                lines: [
                    DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "let first = 1;"),
                    DiffLine(kind: .context, oldNumber: 2, newNumber: 2, text: middle),
                    DiffLine(kind: .context, oldNumber: 3, newNumber: 3, text: "let third = 3;")
                ]
            ),
            anchor: nil,
            mode: .unified
        )
    }
}
