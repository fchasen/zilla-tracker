import Foundation
import Testing
import PhabricatorKit
@testable import Zilla

private func inline(
    _ id: Int,
    line: Int,
    isNewFile: Bool = true,
    replyTo: String? = nil,
    at seconds: TimeInterval
) -> InlineComment {
    InlineComment(
        id: id,
        phid: "PHID-XCMT-\(id)",
        authorPHID: "PHID-USER-a",
        diffID: 1,
        path: "a.js",
        line: line,
        length: 1,
        isNewFile: isNewFile,
        isDeleted: false,
        replyToCommentPHID: replyTo,
        transactionPHID: nil,
        content: "c\(id)",
        dateCreated: Date(timeIntervalSince1970: seconds),
        dateModified: nil
    )
}

struct InlineThreadsTests {
    @Test func flatInlinesOnTheSameLineShareOneThread() {
        let threads = InlineThreads.group([
            inline(2, line: 10, at: 200),
            inline(1, line: 10, at: 100),
        ])

        #expect(threads.count == 1)
        #expect(threads["PHID-XCMT-1"]?.map(\.id) == [1, 2])
    }

    @Test func sidesAndLinesStaySeparate() {
        let threads = InlineThreads.group([
            inline(1, line: 10, at: 100),
            inline(2, line: 10, isNewFile: false, at: 200),
            inline(3, line: 11, at: 300),
        ])

        #expect(Set(threads.keys) == ["PHID-XCMT-1", "PHID-XCMT-2", "PHID-XCMT-3"])
    }

    @Test func repliesFollowTheirParentInDepthFirstOrder() {
        let threads = InlineThreads.group([
            inline(1, line: 10, at: 100),
            inline(2, line: 10, replyTo: "PHID-XCMT-1", at: 200),
            inline(3, line: 10, replyTo: "PHID-XCMT-1", at: 400),
            inline(4, line: 10, replyTo: "PHID-XCMT-2", at: 300),
            inline(5, line: 10, at: 500),
        ])

        #expect(threads.count == 1)
        #expect(threads["PHID-XCMT-1"]?.map(\.id) == [1, 2, 4, 3, 5])
    }

    @Test func replyWhoseParentIsHiddenBecomesARoot() {
        let threads = InlineThreads.group([
            inline(2, line: 12, replyTo: "PHID-XCMT-missing", at: 200),
        ])

        #expect(threads["PHID-XCMT-2"]?.map(\.id) == [2])
    }
}
