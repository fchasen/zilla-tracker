//
//  BugAttention.swift
//  Zilla
//

import Foundation
import BugzillaKit

enum BugAttention {
    static let newBugWindow: TimeInterval = 7 * 24 * 60 * 60

    static func needsAttention(_ bug: Bug, mark: SeenMark?, now: Date = .now) -> Bool {
        if let mark {
            guard let seenThrough = mark.seenThrough else { return true }
            guard let changed = bug.lastChangeTime else { return false }
            return changed > seenThrough
        }
        guard !BugStatuses.isClosed(bug.status), let created = bug.creationTime else { return false }
        return now.timeIntervalSince(created) < newBugWindow
    }
}
