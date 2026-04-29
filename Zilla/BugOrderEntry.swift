//
//  BugOrderEntry.swift
//  Zilla
//

import Foundation
import SwiftData

@Model
final class BugOrderEntry {
    var endpointKey: String = ""
    var bugId: Int = 0
    var position: Int = 0
    var addedAt: Date = Date()

    init(endpointKey: String, bugId: Int, position: Int = 0, addedAt: Date = .now) {
        self.endpointKey = endpointKey
        self.bugId = bugId
        self.position = position
        self.addedAt = addedAt
    }
}

extension BugOrderEntry {
    static let todoKey = "todo"
}
