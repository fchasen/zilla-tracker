//
//  SeenStore.swift
//  Zilla
//

import Foundation

struct SeenMark: Codable, Hashable {
    let seenThrough: Date?
    let recordedAt: Date

    var isViewed: Bool { seenThrough != nil }

    init(seenThrough: Date?, recordedAt: Date) {
        self.seenThrough = seenThrough.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.up)) }
        self.recordedAt = Date(timeIntervalSince1970: recordedAt.timeIntervalSince1970.rounded(.down))
    }

    func supersedes(_ other: SeenMark) -> Bool {
        if recordedAt != other.recordedAt { return recordedAt > other.recordedAt }
        return (seenThrough ?? .distantFuture) > (other.seenThrough ?? .distantFuture)
    }

    private enum CodingKeys: String, CodingKey {
        case seenThrough = "s"
        case recordedAt = "r"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let seen = try c.decodeIfPresent(Int.self, forKey: .seenThrough)
        let recorded = try c.decode(Int.self, forKey: .recordedAt)
        self.init(
            seenThrough: seen.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            recordedAt: Date(timeIntervalSince1970: TimeInterval(recorded))
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(seenThrough.map { Int($0.timeIntervalSince1970) }, forKey: .seenThrough)
        try c.encode(Int(recordedAt.timeIntervalSince1970), forKey: .recordedAt)
    }
}

protocol SeenStoreKind {
    static var storageKey: String { get }
    static var legacyStorageKey: String { get }
}

enum SeenBugs: SeenStoreKind {
    static let storageKey = "seenBugMarks"
    static let legacyStorageKey = "viewedBugIDs"
}

enum SeenRevisions: SeenStoreKind {
    static let storageKey = "seenRevisionMarks"
    static let legacyStorageKey = "viewedRevisionIDs"
}

typealias ViewedBugsStore = SeenStore<SeenBugs>
typealias ViewedRevisionsStore = SeenStore<SeenRevisions>

@Observable
final class SeenStore<Kind: SeenStoreKind> {
    static var retention: TimeInterval { 180 * 24 * 60 * 60 }
    static var maxEntries: Int { 8000 }

    private(set) var marks: [Int: SeenMark]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        cloud: NSUbiquitousKeyValueStore? = .default,
        now: Date = .now
    ) {
        self.defaults = defaults
        self.cloud = cloud
        let stored = Self.decode(defaults.data(forKey: Kind.storageKey))
        let remote = Self.decode(cloud?.data(forKey: Kind.storageKey)) ?? [:]
        var loaded = Self.merged(stored ?? [:], with: remote, now: now)
        if stored == nil {
            for id in Self.legacyIDs(defaults: defaults, cloud: cloud) where loaded[id] == nil {
                loaded[id] = SeenMark(seenThrough: now, recordedAt: now)
            }
        }
        marks = Self.pruned(loaded, now: now)
        if marks != stored {
            save()
        }
        if let cloud {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloud,
                queue: .main
            ) { [weak self] note in
                self?.handleExternalChange(note)
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var ids: Set<Int> {
        Set(marks.compactMap { $0.value.isViewed ? $0.key : nil })
    }

    func mark(for id: Int) -> SeenMark? {
        marks[id]
    }

    func contains(_ id: Int) -> Bool {
        marks[id]?.isViewed == true
    }

    func markViewed(_ id: Int, through date: Date = .now) {
        let seenThrough = max(date, marks[id]?.seenThrough ?? date)
        marks[id] = SeenMark(seenThrough: seenThrough, recordedAt: .now)
        scheduleSave()
    }

    func advanceIfViewed(_ id: Int, through date: Date) {
        guard let seenThrough = marks[id]?.seenThrough, seenThrough < date else { return }
        marks[id] = SeenMark(seenThrough: date, recordedAt: .now)
        scheduleSave()
    }

    func markUnviewed(_ id: Int) {
        marks[id] = SeenMark(seenThrough: nil, recordedAt: .now)
        scheduleSave()
    }

    static func merged(
        _ local: [Int: SeenMark],
        with remote: [Int: SeenMark],
        now: Date
    ) -> [Int: SeenMark] {
        var result = local
        for (id, mark) in remote where result[id].map(mark.supersedes) ?? true {
            result[id] = mark
        }
        return pruned(result, now: now)
    }

    static func pruned(_ marks: [Int: SeenMark], now: Date) -> [Int: SeenMark] {
        let cutoff = now.addingTimeInterval(-retention)
        let live = marks.filter { $0.value.recordedAt >= cutoff }
        guard live.count > maxEntries else { return live }
        let newest = live
            .sorted { ($0.value.recordedAt, $0.key) > ($1.value.recordedAt, $1.key) }
            .prefix(maxEntries)
        return Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
    }

    private func handleExternalChange(_ note: Notification) {
        if let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
           reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            return
        }
        guard let remote = Self.decode(cloud?.data(forKey: Kind.storageKey)) else { return }
        let merged = Self.merged(marks, with: remote, now: .now)
        if merged != marks {
            marks = merged
            defaults.set(Self.encode(merged), forKey: Kind.storageKey)
        }
        if merged != remote {
            scheduleSave()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        guard let data = Self.encode(marks) else { return }
        defaults.set(data, forKey: Kind.storageKey)
        cloud?.set(data, forKey: Kind.storageKey)
        cloud?.synchronize()
    }

    private static func decode(_ data: Data?) -> [Int: SeenMark]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([Int: SeenMark].self, from: data)
    }

    private static func encode(_ marks: [Int: SeenMark]) -> Data? {
        try? JSONEncoder().encode(marks)
    }

    private static func legacyIDs(defaults: UserDefaults, cloud: NSUbiquitousKeyValueStore?) -> Set<Int> {
        let local = defaults.array(forKey: Kind.legacyStorageKey) as? [Int] ?? []
        let remote = cloud?.array(forKey: Kind.legacyStorageKey) as? [Int] ?? []
        return Set(local).union(remote)
    }
}
