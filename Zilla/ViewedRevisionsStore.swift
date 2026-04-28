//
//  ViewedRevisionsStore.swift
//  Zilla
//

import Foundation

@Observable
final class ViewedRevisionsStore {
    private static let storageKey = "viewedRevisionIDs"
    private(set) var ids: Set<Int> = []

    init() {
        if let stored = UserDefaults.standard.array(forKey: Self.storageKey) as? [Int] {
            ids = Set(stored)
        }
    }

    func contains(_ id: Int) -> Bool {
        ids.contains(id)
    }

    func markViewed(_ id: Int) {
        guard !ids.contains(id) else { return }
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: Self.storageKey)
    }

    func markUnviewed(_ id: Int) {
        guard ids.contains(id) else { return }
        ids.remove(id)
        UserDefaults.standard.set(Array(ids), forKey: Self.storageKey)
    }
}
