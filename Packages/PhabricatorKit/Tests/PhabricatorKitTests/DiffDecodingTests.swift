import XCTest
@testable import PhabricatorKit

final class DiffDecodingTests: XCTestCase {
    func testDecodesDiffSearchEnvelope() throws {
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 999000,
                "type": "DIFF",
                "phid": "PHID-DIFF-aaa",
                "fields": {
                  "revisionPHID": "PHID-DREV-rev",
                  "authorPHID": "PHID-USER-author",
                  "repositoryPHID": "PHID-REPO-mc",
                  "dateCreated": 1714000000,
                  "dateModified": 1714000100,
                  "refs": [
                    {"type": "base", "identifier": "abc123def456"},
                    {"type": "branch", "name": "main"}
                  ]
                },
                "attachments": {}
              }
            ],
            "cursor": {
              "limit": 50,
              "after": null,
              "before": null
            }
          },
          "error_code": null,
          "error_info": null
        }
        """.data(using: .utf8)!
        let decoder = PhabricatorClient.makeDecoder()
        let envelope = try decoder.decode(ConduitEnvelope<DiffSearchResult>.self, from: json)
        let result = try XCTUnwrap(envelope.result)
        XCTAssertEqual(result.data.count, 1)
        let diff = result.data[0]
        XCTAssertEqual(diff.id, 999000)
        XCTAssertEqual(diff.phid, "PHID-DIFF-aaa")
        XCTAssertEqual(diff.fields.revisionPHID, "PHID-DREV-rev")
        XCTAssertEqual(diff.fields.repositoryPHID, "PHID-REPO-mc")
        XCTAssertEqual(diff.baseCommit, "abc123def456")
        XCTAssertEqual(diff.branch, "main")
    }

    func testDecodesQueryDiffsWithChangesAndHunks() throws {
        let json = """
        {
          "result": {
            "999000": {
              "id": "999000",
              "phid": "PHID-DIFF-aaa",
              "revisionPHID": "PHID-DREV-rev",
              "repositoryPHID": "PHID-REPO-mc",
              "sourceControlBaseRevision": "abc123",
              "dateCreated": "1714000000",
              "dateModified": "1714000100",
              "changes": [
                {
                  "id": "1",
                  "oldFile": "src/foo.swift",
                  "currentFile": "src/foo.swift",
                  "awayPaths": [],
                  "changeType": 2,
                  "fileType": 1,
                  "oldFileType": 1,
                  "addLines": "3",
                  "delLines": "1",
                  "metadata": {"line:first": "1"},
                  "hunks": [
                    {
                      "oldOffset": "1",
                      "oldLen": "5",
                      "newOffset": "1",
                      "newLen": "7",
                      "corpus": " a\\n-b\\n+c\\n+d\\n"
                    }
                  ]
                },
                {
                  "id": "2",
                  "oldFile": "img/logo.png",
                  "currentFile": "img/logo.png",
                  "awayPaths": [],
                  "changeType": 2,
                  "fileType": 3,
                  "oldFileType": 3,
                  "addLines": 0,
                  "delLines": 0,
                  "metadata": {},
                  "hunks": []
                },
                {
                  "id": "3",
                  "oldFile": "old/path.swift",
                  "currentFile": "new/path.swift",
                  "awayPaths": [],
                  "changeType": 6,
                  "fileType": 1,
                  "oldFileType": 1,
                  "addLines": "0",
                  "delLines": "0",
                  "metadata": {},
                  "hunks": []
                }
              ]
            }
          },
          "error_code": null,
          "error_info": null
        }
        """.data(using: .utf8)!
        let decoder = PhabricatorClient.makeDecoder()
        let envelope = try decoder.decode(ConduitEnvelope<[String: QueryDiffsRaw]>.self, from: json)
        let raws = try XCTUnwrap(envelope.result)
        let raw = try XCTUnwrap(raws["999000"])
        let detail = raw.toDetail()
        XCTAssertEqual(detail.id, 999000)
        XCTAssertEqual(detail.revisionPHID, "PHID-DREV-rev")
        XCTAssertEqual(detail.baseCommit, "abc123")
        XCTAssertEqual(detail.changesets.count, 3)

        let textChange = detail.changesets[0]
        XCTAssertEqual(textChange.currentPath, "src/foo.swift")
        XCTAssertEqual(textChange.oldPath, "src/foo.swift")
        XCTAssertEqual(textChange.type, .change)
        XCTAssertEqual(textChange.fileType, .text)
        XCTAssertEqual(textChange.addLines, 3)
        XCTAssertEqual(textChange.delLines, 1)
        XCTAssertEqual(textChange.hunks.count, 1)
        XCTAssertEqual(textChange.hunks[0].oldOffset, 1)
        XCTAssertEqual(textChange.hunks[0].newLen, 7)
        XCTAssertEqual(textChange.hunks[0].corpus, " a\n-b\n+c\n+d\n")

        let binary = detail.changesets[1]
        XCTAssertEqual(binary.fileType, .binary)
        XCTAssertEqual(binary.hunks.count, 0)

        let renamed = detail.changesets[2]
        XCTAssertEqual(renamed.type, .moveHere)
        XCTAssertEqual(renamed.oldPath, "old/path.swift")
        XCTAssertEqual(renamed.currentPath, "new/path.swift")
    }
}
