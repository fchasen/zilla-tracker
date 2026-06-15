//
//  BugIndexStore.swift
//  Zilla
//

import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import BugzillaKit

struct IndexedBugRecord: Codable, Hashable, Identifiable {
    let id: Int
    var summary: String
    var product: String
    var component: String
    var status: String
    var type: String?
    var lastChange: Date?
    var sources: Set<String>
}

enum BugIndexSource: Hashable {
    case seen
    case component(product: String, component: String)

    var tag: String {
        switch self {
        case .seen:
            return "seen"
        case let .component(product, component):
            return "component:\(product)::\(component)"
        }
    }
}

@MainActor
@Observable
final class BugIndexStore {
    private(set) var records: [Int: IndexedBugRecord] = [:]

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let index: CSSearchableIndex?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static let domain = "bugs"
    private static let backfillCap = 500
    private static let backfillBatch = 100

    init(filename: String = "bug-index.json") {
        let fm = FileManager.default
        let dir = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        fileURL = dir?.appendingPathComponent(filename)
        index = CSSearchableIndex.isIndexingAvailable() ? .default() : nil
        load()
    }

    func record(for id: Int) -> IndexedBugRecord? {
        records[id]
    }

    func record(_ bug: Bug, source: BugIndexSource) {
        guard bug.groups.isEmpty else {
            remove(id: bug.id)
            return
        }
        let updated = upsert(bug, source: source)
        indexItems([updated])
        scheduleSave()
    }

    func record(_ bugs: [Bug], source: BugIndexSource) {
        var changed: [IndexedBugRecord] = []
        var restricted: [Int] = []
        for bug in bugs {
            guard bug.groups.isEmpty else {
                if records.removeValue(forKey: bug.id) != nil { restricted.append(bug.id) }
                continue
            }
            changed.append(upsert(bug, source: source))
        }
        if !changed.isEmpty { indexItems(changed) }
        if !restricted.isEmpty { deindexIDs(restricted) }
        scheduleSave()
    }

    func remove(id: Int) {
        guard records.removeValue(forKey: id) != nil else { return }
        deindexIDs([id])
        scheduleSave()
    }

    func removeSource(_ source: BugIndexSource) {
        let tag = source.tag
        var orphaned: [Int] = []
        for (id, var rec) in records where rec.sources.contains(tag) {
            rec.sources.remove(tag)
            if rec.sources.isEmpty {
                records.removeValue(forKey: id)
                orphaned.append(id)
            } else {
                records[id] = rec
            }
        }
        if !orphaned.isEmpty { deindexIDs(orphaned) }
        scheduleSave()
    }

    func localMatches(for rawQuery: String, limit: Int = 25) -> [IndexedBugRecord] {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        let tokens = trimmed.split(separator: " ").map(String.init)
        var scored: [(record: IndexedBugRecord, score: Int)] = []
        for rec in records.values {
            var score = 0
            let idString = String(rec.id)
            if idString == trimmed {
                score += 2000
            } else if idString.hasPrefix(trimmed) {
                score += 1000
            }
            let summary = rec.summary.lowercased()
            let haystack = "\(summary) \(rec.product.lowercased()) \(rec.component.lowercased())"
            if tokens.allSatisfy({ haystack.contains($0) }) {
                score += 100
                if summary.contains(trimmed) { score += 50 }
                if summary.hasPrefix(trimmed) { score += 25 }
            }
            if score > 0 { scored.append((rec, score)) }
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return (lhs.record.lastChange ?? .distantPast) > (rhs.record.lastChange ?? .distantPast)
            }
            .prefix(limit)
            .map(\.record)
    }

    func backfill(viewedIDs: Set<Int>, using client: BugzillaClient) async {
        let missing = Array(viewedIDs.subtracting(records.keys).prefix(Self.backfillCap))
        guard !missing.isEmpty else { return }
        for batch in stride(from: 0, to: missing.count, by: Self.backfillBatch) {
            let slice = Array(missing[batch..<min(batch + Self.backfillBatch, missing.count)])
            guard let fetched = try? await client.getBugs(ids: slice) else { continue }
            record(fetched, source: .seen)
        }
    }

    private func upsert(_ bug: Bug, source: BugIndexSource) -> IndexedBugRecord {
        var rec = records[bug.id] ?? IndexedBugRecord(
            id: bug.id,
            summary: bug.summary,
            product: bug.product,
            component: bug.component,
            status: bug.status,
            type: bug.type,
            lastChange: bug.lastChangeTime,
            sources: []
        )
        rec.summary = bug.summary
        rec.product = bug.product
        rec.component = bug.component
        rec.status = bug.status
        rec.type = bug.type
        rec.lastChange = bug.lastChangeTime
        rec.sources.insert(source.tag)
        records[bug.id] = rec
        return rec
    }

    private func indexItems(_ recs: [IndexedBugRecord]) {
        guard let index else { return }
        let items = recs.map { rec -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = "Bug \(rec.id): \(rec.summary)"
            attrs.contentDescription = "\(rec.product) :: \(rec.component) — \(rec.status.bugzillaTitleCased)"
            attrs.keywords = [rec.product, rec.component, "bugzilla", String(rec.id)]
            attrs.identifier = Self.identifier(for: rec.id)
            return CSSearchableItem(
                uniqueIdentifier: Self.identifier(for: rec.id),
                domainIdentifier: Self.domain,
                attributeSet: attrs
            )
        }
        index.indexSearchableItems(items, completionHandler: nil)
    }

    private func deindexIDs(_ ids: [Int]) {
        guard let index, !ids.isEmpty else { return }
        index.deleteSearchableItems(withIdentifiers: ids.map(Self.identifier(for:)), completionHandler: nil)
    }

    static func identifier(for id: Int) -> String { "bug:\(id)" }

    static func bugID(from identifier: String) -> Int? {
        guard identifier.hasPrefix("bug:") else { return nil }
        return Int(identifier.dropFirst(4))
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([IndexedBugRecord].self, from: data) else { return }
        records = Dictionary(decoded.map { ($0.id, $0) }, uniquingKeysWith: { lhs, _ in lhs })
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard let fileURL else { return }
        let snapshot = Array(records.values)
        saveTask = Task { [fileURL] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
