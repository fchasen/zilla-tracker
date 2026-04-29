import Testing
import Foundation
@testable import Zilla
@testable import PhabricatorKit

struct ChangesetSynthesizerTests {
    @Test func synthesisConcatenatesHunksWithoutPadding() {
        let hunkA = makeHunk(oldOffset: 1, oldLen: 3, newOffset: 1, newLen: 4, corpus: " a\n+inserted\n b\n c\n")
        let hunkB = makeHunk(oldOffset: 10, oldLen: 2, newOffset: 11, newLen: 1, corpus: "-removed\n d\n")
        let changeset = makeChangeset(hunks: [hunkA, hunkB])

        let (oldString, newString) = ChangesetSynthesizer.synthesize(changeset: changeset)
        let oldLines = oldString.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = newString.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        #expect(oldLines == ["a", "b", "c", "removed", "d"])
        #expect(newLines == ["a", "inserted", "b", "c", "d"])
    }

    @Test func applyHunksRebuildsNewContent() {
        let original = "alpha\nbeta\ngamma\ndelta\n"
        let hunk = makeHunk(oldOffset: 2, oldLen: 2, newOffset: 2, newLen: 3, corpus: "-beta\n-gamma\n+inserted\n+gamma\n+epsilon\n")
        let result = ChangesetSynthesizer.applyHunks(to: original, hunks: [hunk])
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[0] == "alpha")
        #expect(lines[1] == "inserted")
        #expect(lines[2] == "gamma")
        #expect(lines[3] == "epsilon")
        #expect(lines[4] == "delta")
    }

    @Test func applyHunksHandlesNoNewlineAtEOFMarker() {
        let original = "alpha\nbeta\n"
        let hunk = makeHunk(oldOffset: 2, oldLen: 1, newOffset: 2, newLen: 1, corpus: "-beta\n+gamma\n\\ No newline at end of file\n")
        let result = ChangesetSynthesizer.applyHunks(to: original, hunks: [hunk])
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[0] == "alpha")
        #expect(lines[1] == "gamma")
    }

    private func makeHunk(oldOffset: Int, oldLen: Int, newOffset: Int, newLen: Int, corpus: String) -> Hunk {
        Hunk(oldOffset: oldOffset, oldLen: oldLen, newOffset: newOffset, newLen: newLen, corpus: corpus)
    }

    private func makeChangeset(hunks: [Hunk]) -> Changeset {
        let json = """
        {
          "id": "1",
          "oldFile": "src/foo.swift",
          "currentFile": "src/foo.swift",
          "awayPaths": [],
          "changeType": 2,
          "fileType": 1,
          "oldFileType": 1,
          "addLines": "0",
          "delLines": "0",
          "metadata": {},
          "hunks": []
        }
        """.data(using: .utf8)!
        let decoder = PhabricatorClient.makeDecoder()
        let stub = try! decoder.decode(Changeset.self, from: json)
        return Changeset(
            decoded: stub,
            hunks: hunks
        )
    }
}

extension Changeset {
    fileprivate init(decoded: Changeset, hunks: [Hunk]) {
        let json = """
        {
          "id": "\(decoded.id)",
          "oldFile": "\(decoded.oldPath ?? decoded.currentPath)",
          "currentFile": "\(decoded.currentPath)",
          "awayPaths": [],
          "changeType": \(decoded.type.rawValue),
          "fileType": \(decoded.fileType.rawValue),
          "oldFileType": \(decoded.oldFileType.rawValue),
          "addLines": "\(decoded.addLines)",
          "delLines": "\(decoded.delLines)",
          "metadata": {},
          "hunks": \(Self.hunksJSON(hunks))
        }
        """.data(using: .utf8)!
        let decoder = PhabricatorClient.makeDecoder()
        self = try! decoder.decode(Changeset.self, from: json)
    }

    private static func hunksJSON(_ hunks: [Hunk]) -> String {
        var pieces: [String] = []
        for h in hunks {
            let escaped = h.corpus
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            pieces.append("""
            {
              "oldOffset": "\(h.oldOffset)",
              "oldLen": "\(h.oldLen)",
              "newOffset": "\(h.newOffset)",
              "newLen": "\(h.newLen)",
              "corpus": "\(escaped)"
            }
            """)
        }
        return "[\(pieces.joined(separator: ","))]"
    }
}
