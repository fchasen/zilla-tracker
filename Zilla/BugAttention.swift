//
//  BugAttention.swift
//  Zilla
//

import Foundation
import BugzillaKit

enum BugAttention {
    static let newBugWindow: TimeInterval = 7 * 24 * 60 * 60

    static func needsAttention(_ bug: Bug, mark: SeenMark?, viewer: String?, now: Date = .now) -> Bool {
        if let viewer, hasUnseenRequest(bug, for: viewer, mark: mark) { return true }
        if let mark {
            guard let seenThrough = mark.seenThrough else { return true }
            guard let changed = bug.lastChangeTime else { return false }
            return changed > seenThrough
        }
        guard !BugStatuses.isClosed(bug.status), let created = bug.creationTime else { return false }
        return now.timeIntervalSince(created) < newBugWindow
    }

    static func hasUnseenRequest(_ bug: Bug, for viewer: String, mark: SeenMark?) -> Bool {
        guard let requested = latestRequest(in: bug, for: viewer) else { return false }
        guard let seenThrough = mark?.seenThrough else { return true }
        return requested > seenThrough
    }

    static func latestRequest(in bug: Bug, for viewer: String) -> Date? {
        bug.flags
            .filter { $0.status == "?" && $0.requestee?.caseInsensitiveCompare(viewer) == .orderedSame }
            .compactMap { $0.modificationDate ?? $0.creationDate }
            .max()
    }
}
