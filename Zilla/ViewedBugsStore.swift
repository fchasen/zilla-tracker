//
//  ViewedBugsStore.swift
//  Zilla
//

import Foundation

@Observable
final class ViewedBugsStore {
    private static let storageKey = "viewedBugIDs"
    private(set) var ids: Set<Int> = []
    private var observer: NSObjectProtocol?

    init() {
        if let stored = UserDefaults.standard.array(forKey: Self.storageKey) as? [Int] {
            ids = Set(stored)
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] note in
            self?.handleExternalChange(note)
        }
        mergeFromCloud()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func contains(_ id: Int) -> Bool {
        ids.contains(id)
    }

    func markViewed(_ id: Int) {
        guard !ids.contains(id) else { return }
        ids.insert(id)
        persist()
    }

    func markUnviewed(_ id: Int) {
        guard ids.contains(id) else { return }
        ids.remove(id)
        persist()
    }

    private func persist() {
        let array = Array(ids)
        UserDefaults.standard.set(array, forKey: Self.storageKey)
        NSUbiquitousKeyValueStore.default.set(array, forKey: Self.storageKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func handleExternalChange(_ note: Notification) {
        if let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
           reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            return
        }
        mergeFromCloud()
    }

    private func mergeFromCloud() {
        guard let remote = NSUbiquitousKeyValueStore.default.array(forKey: Self.storageKey) as? [Int] else {
            return
        }
        let merged = ids.union(remote)
        guard merged != ids else { return }
        ids = merged
        UserDefaults.standard.set(Array(merged), forKey: Self.storageKey)
    }
}
