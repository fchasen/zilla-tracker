//
//  AttentionNotifications.swift
//  Zilla
//

import Foundation

enum NotificationCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case needinfo
    case review
    case patch
}

struct NotificationCandidate: Hashable, Sendable {
    let category: NotificationCategory
    let itemID: Int
    let eventDate: Date
    let title: String
    let subtitle: String
    let body: String
    let url: URL

    var identifier: String { Self.identifier(category, itemID) }

    static func identifier(_ category: NotificationCategory, _ itemID: Int) -> String {
        "\(category.rawValue)-\(itemID)"
    }

    static func parse(_ identifier: String) -> (category: NotificationCategory, itemID: Int)? {
        guard let dash = identifier.lastIndex(of: "-"),
              let category = NotificationCategory(rawValue: String(identifier[..<dash])),
              let itemID = Int(identifier[identifier.index(after: dash)...]) else { return nil }
        return (category, itemID)
    }
}

struct NotificationSnapshot: Hashable, Sendable {
    let candidates: [NotificationCandidate]
    let polled: Set<NotificationCategory>
}

struct NotifiedEntry: Codable, Hashable, Sendable {
    let eventDate: Date
    let recordedAt: Date
}

struct NotificationLedger: Codable, Hashable, Sendable {
    var entries: [String: NotifiedEntry] = [:]
    var baselined: Set<NotificationCategory> = []
}

struct NotificationPlan: Hashable, Sendable {
    var post: [NotificationCandidate]
    var remove: [String]
    var ledger: NotificationLedger
}

enum RevisionEventKind: Hashable, Sendable {
    case accepted
    case requestedChanges
    case resigned
    case commandeered
    case commented
    case inlineCommented
    case landed
    case abandoned
    case reclaimed
    case reopened
    case statusChanged(String?)
}

struct RevisionEvent: Hashable, Sendable {
    let actorPHID: String
    let kind: RevisionEventKind
    let date: Date
}
