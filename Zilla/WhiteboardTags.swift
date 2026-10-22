//
//  WhiteboardTags.swift
//  Zilla
//

import Foundation
import Observation

struct Whiteboard: Equatable, Sendable {
    enum Segment: Equatable, Sendable {
        case tag(String)
        case text(String)
    }

    private(set) var segments: [Segment]

    init(_ raw: String?) {
        segments = Self.parse(raw ?? "")
    }

    var tags: [String] {
        segments.compactMap { segment in
            if case .tag(let value) = segment { return value }
            return nil
        }
    }

    var freeText: String {
        let joined = segments
            .compactMap { segment -> String? in
                if case .text(let value) = segment { return value }
                return nil
            }
            .joined(separator: " ")
        return Self.tidy(joined)
    }

    var rawValue: String {
        var out = ""
        var previous: Segment?
        for segment in segments {
            if Self.needsSeparator(after: previous, before: segment) { out += " " }
            switch segment {
            case .tag(let value): out += "[\(value)]"
            case .text(let value): out += value
            }
            previous = segment
        }
        return Self.tidy(out)
    }

    var isEmpty: Bool { rawValue.isEmpty }

    func contains(_ tag: String) -> Bool {
        let value = Self.normalize(tag)
        return tags.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }

    mutating func add(_ input: String) {
        for tag in Self.tokenize(input) where !contains(tag) {
            segments.append(.tag(tag))
        }
    }

    mutating func remove(_ tag: String) {
        guard let index = index(of: tag) else { return }
        segments.remove(at: index)
    }

    mutating func replace(_ tag: String, with input: String) {
        guard let index = index(of: tag) else { return }
        let replacements = Self.tokenize(input).filter { candidate in
            candidate.caseInsensitiveCompare(tag) == .orderedSame || !contains(candidate)
        }
        segments.replaceSubrange(index...index, with: replacements.map { Segment.tag($0) })
    }

    mutating func setFreeText(_ text: String) {
        let value = Self.tidy(text)
        var textIndices = segments.indices.filter { index in
            if case .text = segments[index] { return true }
            return false
        }
        if value.isEmpty {
            for index in textIndices.reversed() { segments.remove(at: index) }
            return
        }
        guard let first = textIndices.first else {
            segments.append(.text(value))
            return
        }
        segments[first] = .text(value)
        textIndices.removeFirst()
        for index in textIndices.reversed() { segments.remove(at: index) }
    }

    private func index(of tag: String) -> Int? {
        let value = Self.normalize(tag)
        return segments.firstIndex { segment in
            guard case .tag(let candidate) = segment else { return false }
            return candidate.caseInsensitiveCompare(value) == .orderedSame
        }
    }

    private static func needsSeparator(after previous: Segment?, before next: Segment) -> Bool {
        switch (previous, next) {
        case (.text(let text), .tag):
            return text.last.map { !$0.isWhitespace } ?? false
        case (.tag, .text(let text)):
            return text.first.map { !$0.isWhitespace } ?? false
        default:
            return false
        }
    }

    static func tokenize(_ input: String) -> [String] {
        let parsed = parse(input)
        var tags: [String] = []
        for segment in parsed {
            switch segment {
            case .tag(let value):
                tags.append(value)
            case .text(let value):
                let normalized = normalize(value)
                if !normalized.isEmpty { tags.append(normalized) }
            }
        }
        var seen: Set<String> = []
        return tags.filter { seen.insert($0.lowercased()).inserted }
    }

    static func normalize(_ value: String) -> String {
        tidy(value.replacingOccurrences(of: "[", with: " ").replacingOccurrences(of: "]", with: " "))
    }

    private static func tidy(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func parse(_ raw: String) -> [Segment] {
        var segments: [Segment] = []
        var text = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            if raw[index] == "[", let close = raw[index...].firstIndex(of: "]") {
                if !text.isEmpty {
                    segments.append(.text(text))
                    text = ""
                }
                let inner = normalize(String(raw[raw.index(after: index)..<close]))
                if !inner.isEmpty { segments.append(.tag(inner)) }
                index = raw.index(after: close)
            } else {
                text.append(raw[index])
                index = raw.index(after: index)
            }
        }
        if !text.isEmpty { segments.append(.text(text)) }
        return segments
    }
}

@MainActor
@Observable
final class WhiteboardTagHistory {
    static let storageKey = "zilla.whiteboard.tagHistory"
    static let limit = 500

    private(set) var tags: [String]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.tags = defaults.stringArray(forKey: Self.storageKey) ?? []
    }

    func record(_ input: String) {
        let used = Whiteboard.tokenize(input)
        guard !used.isEmpty else { return }
        let lowered = Set(used.map { $0.lowercased() })
        let updated = used + tags.filter { !lowered.contains($0.lowercased()) }
        store(updated)
    }

    func observe(_ whiteboards: [String]) {
        var known = Set(tags.map { $0.lowercased() })
        var updated = tags
        for raw in whiteboards {
            for tag in Whiteboard(raw).tags where known.insert(tag.lowercased()).inserted {
                updated.append(tag)
            }
        }
        guard updated.count != tags.count else { return }
        store(updated)
    }

    private func store(_ updated: [String]) {
        let capped = Array(updated.prefix(Self.limit))
        guard capped != tags else { return }
        tags = capped
        defaults.set(capped, forKey: Self.storageKey)
    }
}
