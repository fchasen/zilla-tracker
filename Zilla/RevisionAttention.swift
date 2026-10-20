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
}

enum RevisionAttention {
    static func activity(
        of revision: Revision,
        transactions: [RevisionTransaction],
        viewerPHID: String
    ) -> RevisionActivity {
        var fromViewer: Date?
        var fromOthers: Date?
        for transaction in transactions {
            guard let author = transaction.authorPHID else { continue }
            let date = transaction.dateCreated
            if author == viewerPHID {
                fromViewer = max(fromViewer ?? date, date)
            } else if author.hasPrefix("PHID-USER-"), isAttentionWorthy(transaction) {
                fromOthers = max(fromOthers ?? date, date)
            }
        }
        return RevisionActivity(
            dateModified: revision.fields.dateModified,
            latestFromViewer: fromViewer,
            latestFromOthers: fromOthers
        )
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

    static func needsActivity(_ revision: Revision, in list: RevisionList, mark: SeenMark?) -> Bool {
        guard let mark else { return list == .patches }
        guard let seenThrough = mark.seenThrough else { return false }
        return revision.fields.dateModified > seenThrough
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
