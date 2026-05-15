//
//  BugOrderEntry.swift
//  Zilla
//

import Foundation
import SwiftData

typealias BugOrderEntry = ZillaSchemaV3.BugOrderEntry

extension BugOrderEntry {
    static let todoKey = "todo"
}

extension ModelContext {
    func upsertBugOrderEntry(endpointKey: String, bugId: Int, position: Int) {
        let key = endpointKey
        let id = bugId
        var descriptor = FetchDescriptor<BugOrderEntry>(
            predicate: #Predicate { $0.endpointKey == key && $0.bugId == id }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? fetch(descriptor))?.first {
            existing.position = position
            return
        }
        insert(BugOrderEntry(endpointKey: key, bugId: id, position: position))
    }
}
