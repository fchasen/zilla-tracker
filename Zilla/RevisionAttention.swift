//
//  RevisionAttention.swift
//  Zilla
//

import Foundation
import PhabricatorKit

struct RevisionActivity: Hashable {
    let dateModified: Date
    let latestFromViewer: Date?
    let latestFromOthers: Date?
    var latestNotifiable: RevisionEvent? = nil
}

enum RevisionAttention {
    static func activity(
        of revision: Revision,
        transactions: [RevisionTransaction],
        viewerPHID: String
    ) -> RevisionActivity {
        var fromViewer: Date?
        var fromOthers: Date?
        var notifiable: RevisionEvent?
        for transaction in transactions {
            guard let author = transaction.authorPHID else { continue }
            let date = transaction.dateCreated
            if author == viewerPHID {
                fromViewer = max(fromViewer ?? date, date)
            } else if author.hasPrefix("PHID-USER-") {
                if isAttentionWorthy(transaction) {
                    fromOthers = max(fromOthers ?? date, date)
                }
                if let kind = notifiableKind(of: transaction) {
                    let event = RevisionEvent(actorPHID: author, kind: kind, date: date)
                    if notifiable.map({ event.supersedes($0) }) ?? true {
                        notifiable = event
                    }
                }
            }
        }
        return RevisionActivity(
            dateModified: revision.fields.dateModified,
            latestFromViewer: fromViewer,
            latestFromOthers: fromOthers,
            latestNotifiable: notifiable
        )
    }

    static func notifiableKind(of transaction: RevisionTransaction) -> RevisionEventKind? {
        switch transaction.kind {
        case .verb(.accept): return .accepted
        case .verb(.requestChanges), .verb(.reject): return .requestedChanges
        case .verb(.resign): return .resigned
        case .verb(.commandeer): return .commandeered
        case .verb(.close): return .landed
        case .verb(.abandon): return .abandoned
        case .verb(.reclaim): return .reclaimed
        case .verb(.reopen): return .reopened
        case .statusChange(_, let new): return .statusChanged(new)
        case .inline: return .inlineCommented
        case .comment: return .commented
        default: return nil
        }
    }

    static func isAttentionWorthy(_ transaction: RevisionTransaction) -> Bool {
        switch transaction.kind {
        case .comment, .inline, .diffUpdate, .statusChange, .reviewersChanged:
            return true
        case .verb(let verb):
            return verb != .mfaConfirmed
        default:
            return false
        }
    }

    static func needsAttention(
        in list: RevisionList,
        mark: SeenMark?,
        activity: RevisionActivity?
    ) -> Bool {
        if let mark, !mark.isViewed { return true }
        if mark == nil, list == .reviews { return true }
        guard let latest = activity?.latestFromOthers else { return false }
        if let seenThrough = mark?.seenThrough, seenThrough >= latest { return false }
        if let own = activity?.latestFromViewer, own >= latest { return false }
        return true
    }

    static func notifiableEvent(mark: SeenMark?, activity: RevisionActivity?) -> RevisionEvent? {
        guard let event = activity?.latestNotifiable else { return nil }
        if let seenThrough = mark?.seenThrough, seenThrough >= event.date { return nil }
        if let own = activity?.latestFromViewer, own >= event.date { return nil }
        return event
    }

    static func needsActivity(_ revision: Revision, in list: RevisionList, mark: SeenMark?) -> Bool {
        guard let mark else { return list == .patches }
        guard let seenThrough = mark.seenThrough else { return false }
        return revision.fields.dateModified > seenThrough
    }
}

private extension RevisionEvent {
    func supersedes(_ other: RevisionEvent) -> Bool {
        if date != other.date { return date > other.date }
        return kind.precedence > other.kind.precedence
    }
}

private extension RevisionEventKind {
    var precedence: Int {
        switch self {
        case .accepted, .requestedChanges, .resigned, .commandeered: return 4
        case .landed, .abandoned, .reclaimed, .reopened: return 3
        case .statusChanged: return 2
        case .inlineCommented: return 1
        case .commented: return 0
        }
    }
}

@Observable
final class RevisionActivityStore {
    private(set) var activity: [Revision.ID: RevisionActivity] = [:]

    @ObservationIgnored private var inFlight: Set<Revision.ID> = []

    private static let maxConcurrentFetches = 4
    private static let transactionLimit = 50

    func refresh(_ revisions: [Revision], viewerPHID: String, using client: PhabricatorClient) async {
        let pending = revisions.filter {
            activity[$0.id]?.dateModified != $0.fields.dateModified && !inFlight.contains($0.id)
        }
        guard !pending.isEmpty else { return }
        let ids = Set(pending.map(\.id))
        inFlight.formUnion(ids)
        defer { inFlight.subtract(ids) }

        var queue = pending[...]
        await withTaskGroup(of: (Revision, [RevisionTransaction]?).self) { group in
            for _ in 0..<Self.maxConcurrentFetches {
                guard let next = queue.popFirst() else { break }
                group.addTask { await Self.transactions(for: next, using: client) }
            }
            for await (revision, transactions) in group {
                if let transactions {
                    activity[revision.id] = RevisionAttention.activity(
                        of: revision,
                        transactions: transactions,
                        viewerPHID: viewerPHID
                    )
                }
                if let next = queue.popFirst() {
                    group.addTask { await Self.transactions(for: next, using: client) }
                }
            }
        }
    }

    func clear() {
        activity = [:]
    }

    private nonisolated static func transactions(
        for revision: Revision,
        using client: PhabricatorClient
    ) async -> (Revision, [RevisionTransaction]?) {
        let result = try? await client.searchTransactions(
            TransactionQuery(objectIdentifier: revision.phid, limit: transactionLimit)
        )
        return (revision, result?.data)
    }
}
