//
//  NotificationPlanner.swift
//  Zilla
//

import Foundation

enum NotificationPlanner {
    static let retention: TimeInterval = 60 * 24 * 60 * 60

    static func plan(
        snapshot: NotificationSnapshot,
        ledger: NotificationLedger,
        delivered: Set<String>,
        enabled: Set<NotificationCategory>,
        suppressed: Set<String>,
        now: Date = .now
    ) -> NotificationPlan {
        let current = latestCandidates(in: snapshot)
        let unbaselined = snapshot.polled.subtracting(ledger.baselined)
        var ledger = ledger
        var post: [NotificationCandidate] = []

        for candidate in current.values {
            let entry = NotifiedEntry(eventDate: candidate.eventDate, recordedAt: now)
            if unbaselined.contains(candidate.category) {
                ledger.entries[candidate.identifier] = entry
                continue
            }
            if let existing = ledger.entries[candidate.identifier], candidate.eventDate <= existing.eventDate {
                continue
            }
            ledger.entries[candidate.identifier] = entry
            if enabled.contains(candidate.category), !suppressed.contains(candidate.identifier) {
                post.append(candidate)
            }
        }
        ledger.baselined.formUnion(unbaselined)

        let remove = delivered.filter { identifier in
            guard let parsed = NotificationCandidate.parse(identifier) else { return false }
            if !enabled.contains(parsed.category) { return true }
            return snapshot.polled.contains(parsed.category) && current[identifier] == nil
        }

        let cutoff = now.addingTimeInterval(-retention)
        ledger.entries = ledger.entries.filter { identifier, entry in
            guard entry.recordedAt < cutoff, current[identifier] == nil else { return true }
            guard let parsed = NotificationCandidate.parse(identifier) else { return false }
            return !snapshot.polled.contains(parsed.category)
        }

        return NotificationPlan(
            post: post.sorted { ($0.eventDate, $0.identifier) < ($1.eventDate, $1.identifier) },
            remove: remove.sorted(),
            ledger: ledger
        )
    }

    private static func latestCandidates(in snapshot: NotificationSnapshot) -> [String: NotificationCandidate] {
        var latest: [String: NotificationCandidate] = [:]
        for candidate in snapshot.candidates where snapshot.polled.contains(candidate.category) {
            if let kept = latest[candidate.identifier], kept.eventDate >= candidate.eventDate { continue }
            latest[candidate.identifier] = candidate
        }
        return latest
    }
}
