//
//  BugStore.swift
//  Zilla
//

import Foundation
import BugzillaKit

struct PendingBugEdit: Identifiable, Equatable {
    let id: Int
    let update: BugUpdate
    let users: [User]
    var confirmedAt: Int?
}

struct PendingComment: Identifiable, Equatable {
    let id: Int
    let bugID: Bug.ID
    let author: String
    let text: String
    let createdAt: Date
    var confirmedAt: Int?

    var comment: Comment {
        Comment(
            id: -id,
            bugId: bugID,
            creator: author,
            text: text,
            creationTime: createdAt,
            isPrivate: false,
            count: nil
        )
    }
}

struct PendingCommentEdit: Identifiable, Equatable {
    let id: Int
    let commentID: Comment.ID
    let text: String
    var confirmedAt: Int?
}

struct BugStore {
    struct Ticket: Hashable {
        let bugID: Bug.ID
        let sequence: Int
    }

    static let retainedBugLimit = 128
    static let retainedCommentLimit = 8

    private(set) var bugs: [Bug.ID: Bug] = [:]
    private(set) var comments: [Bug.ID: [Comment]] = [:]
    private(set) var errors: [Bug.ID: String] = [:]
    private(set) var edits: [Bug.ID: [PendingBugEdit]] = [:]
    private(set) var pendingComments: [Bug.ID: [PendingComment]] = [:]
    private(set) var commentEdits: [Bug.ID: [PendingCommentEdit]] = [:]

    private var sequence = 0
    private var activeFetches: [Bug.ID: Set<Int>] = [:]
    private var latestFetch: [Bug.ID: Int] = [:]
    private var appliedBugFetch: [Bug.ID: Int] = [:]
    private var appliedCommentsFetch: [Bug.ID: Int] = [:]
    private var presentedCounts: [Bug.ID: Int] = [:]
    private var unpresentedOrder: [Bug.ID] = []

    private mutating func advance() -> Int {
        sequence += 1
        return sequence
    }

    // MARK: Reading

    func bug(_ id: Bug.ID) -> Bug? {
        bugs[id].map { applyingEdits(to: $0) }
    }

    func comments(_ id: Bug.ID) -> [Comment] {
        var result = comments[id] ?? []
        if let edits = commentEdits[id], !edits.isEmpty {
            result = result.map { comment in
                guard let edit = edits.last(where: { $0.commentID == comment.id }) else { return comment }
                return comment.replacingText(edit.text)
            }
        }
        if let pending = pendingComments[id] {
            result.append(contentsOf: pending.map(\.comment))
        }
        return result
    }

    func hasComments(_ id: Bug.ID) -> Bool {
        comments[id] != nil
    }

    func error(_ id: Bug.ID) -> String? {
        errors[id]
    }

    func isFetching(_ id: Bug.ID) -> Bool {
        activeFetches[id] != nil
    }

    func isWriting(_ id: Bug.ID) -> Bool {
        !(edits[id]?.isEmpty ?? true)
            || !(pendingComments[id]?.allSatisfy { $0.confirmedAt != nil } ?? true)
            || !(commentEdits[id]?.isEmpty ?? true)
    }

    func applyingEdits(to bug: Bug) -> Bug {
        guard let edits = edits[bug.id], !edits.isEmpty else { return bug }
        return edits.reduce(bug) { $0.applying($1.update, users: $1.users, editID: $1.id) }
    }

    func displayed(_ bug: Bug) -> Bug {
        let base: Bug
        if let record = bugs[bug.id], !Self.isNewer(bug, than: record) {
            base = record
        } else {
            base = bug
        }
        return applyingEdits(to: base)
    }

    private static func isNewer(_ lhs: Bug, than rhs: Bug) -> Bool {
        guard let left = lhs.lastChangeTime, let right = rhs.lastChangeTime else { return false }
        return left > right
    }

    // MARK: Fetching

    mutating func beginFetch(_ id: Bug.ID) -> Ticket {
        let sequence = advance()
        activeFetches[id, default: []].insert(sequence)
        latestFetch[id] = sequence
        return Ticket(bugID: id, sequence: sequence)
    }

    mutating func endFetch(_ ticket: Ticket) {
        activeFetches[ticket.bugID]?.remove(ticket.sequence)
        if activeFetches[ticket.bugID]?.isEmpty == true {
            activeFetches[ticket.bugID] = nil
        }
    }

    @discardableResult
    mutating func receiveBug(_ bug: Bug, ticket: Ticket) -> Bool {
        let id = ticket.bugID
        guard ticket.sequence >= appliedBugFetch[id, default: 0] else { return false }
        appliedBugFetch[id] = ticket.sequence
        bugs[id] = bug
        errors[id] = nil
        edits[id] = edits[id]?.filter { !Self.isSettled($0.confirmedAt, by: ticket) }.nilIfEmpty
        noteStored(id)
        return true
    }

    @discardableResult
    mutating func receiveComments(_ received: [Comment], ticket: Ticket) -> Bool {
        let id = ticket.bugID
        guard ticket.sequence >= appliedCommentsFetch[id, default: 0] else { return false }
        appliedCommentsFetch[id] = ticket.sequence
        comments[id] = received
        pendingComments[id] = pendingComments[id]?.filter { !Self.isSettled($0.confirmedAt, by: ticket) }.nilIfEmpty
        commentEdits[id] = commentEdits[id]?.filter { !Self.isSettled($0.confirmedAt, by: ticket) }.nilIfEmpty
        noteStored(id)
        return true
    }

    mutating func failFetch(_ ticket: Ticket, message: String) {
        guard latestFetch[ticket.bugID] == ticket.sequence else { return }
        errors[ticket.bugID] = message
    }

    mutating func seed(_ bug: Bug, comments seeded: [Comment]?) {
        if bugs[bug.id] == nil {
            bugs[bug.id] = bug
        }
        if let seeded, comments[bug.id] == nil {
            comments[bug.id] = seeded
        }
        noteStored(bug.id)
    }

    private static func isSettled(_ confirmedAt: Int?, by ticket: Ticket) -> Bool {
        guard let confirmedAt else { return false }
        return confirmedAt < ticket.sequence
    }

    // MARK: Field edits

    mutating func beginEdit(_ id: Bug.ID, update: BugUpdate, users: [User] = []) -> Ticket {
        let sequence = advance()
        edits[id, default: []].append(PendingBugEdit(id: sequence, update: update, users: users))
        return Ticket(bugID: id, sequence: sequence)
    }

    mutating func confirmEdit(_ ticket: Ticket) {
        guard let index = edits[ticket.bugID]?.firstIndex(where: { $0.id == ticket.sequence }) else { return }
        let confirmedAt = advance()
        edits[ticket.bugID]?[index].confirmedAt = confirmedAt
    }

    mutating func discardEdit(_ ticket: Ticket) {
        edits[ticket.bugID] = edits[ticket.bugID]?.filter { $0.id != ticket.sequence }.nilIfEmpty
    }

    mutating func settleEdit(_ ticket: Ticket) {
        guard let edit = edits[ticket.bugID]?.first(where: { $0.id == ticket.sequence }),
              edit.confirmedAt != nil else { return }
        discardEdit(ticket)
        if let record = bugs[ticket.bugID] {
            bugs[ticket.bugID] = record.applying(edit.update, users: edit.users, editID: edit.id)
        }
    }

    // MARK: Comments

    mutating func beginComment(_ id: Bug.ID, author: String, text: String, at date: Date = .now) -> Ticket {
        let sequence = advance()
        let pending = PendingComment(id: sequence, bugID: id, author: author, text: text, createdAt: date)
        pendingComments[id, default: []].append(pending)
        return Ticket(bugID: id, sequence: sequence)
    }

    mutating func confirmComment(_ ticket: Ticket) {
        guard let index = pendingComments[ticket.bugID]?.firstIndex(where: { $0.id == ticket.sequence }) else { return }
        let confirmedAt = advance()
        pendingComments[ticket.bugID]?[index].confirmedAt = confirmedAt
    }

    mutating func discardComment(_ ticket: Ticket) {
        pendingComments[ticket.bugID] = pendingComments[ticket.bugID]?
            .filter { $0.id != ticket.sequence }
            .nilIfEmpty
    }

    mutating func beginCommentEdit(_ id: Bug.ID, commentID: Comment.ID, text: String) -> Ticket {
        let sequence = advance()
        commentEdits[id, default: []].append(PendingCommentEdit(id: sequence, commentID: commentID, text: text))
        return Ticket(bugID: id, sequence: sequence)
    }

    mutating func confirmCommentEdit(_ ticket: Ticket) {
        guard let index = commentEdits[ticket.bugID]?.firstIndex(where: { $0.id == ticket.sequence }) else { return }
        let confirmedAt = advance()
        commentEdits[ticket.bugID]?[index].confirmedAt = confirmedAt
    }

    mutating func discardCommentEdit(_ ticket: Ticket) {
        commentEdits[ticket.bugID] = commentEdits[ticket.bugID]?
            .filter { $0.id != ticket.sequence }
            .nilIfEmpty
    }

    mutating func settleCommentEdit(_ ticket: Ticket) {
        guard let edit = commentEdits[ticket.bugID]?.first(where: { $0.id == ticket.sequence }),
              edit.confirmedAt != nil else { return }
        discardCommentEdit(ticket)
        comments[ticket.bugID] = comments[ticket.bugID]?.map { comment in
            comment.id == edit.commentID ? comment.replacingText(edit.text) : comment
        }
    }

    // MARK: Retention

    mutating func present(_ id: Bug.ID) {
        presentedCounts[id, default: 0] += 1
        unpresentedOrder.removeAll { $0 == id }
    }

    mutating func dismiss(_ id: Bug.ID) {
        guard let count = presentedCounts[id] else { return }
        if count > 1 {
            presentedCounts[id] = count - 1
            return
        }
        presentedCounts[id] = nil
        noteStored(id)
    }

    func isPresented(_ id: Bug.ID) -> Bool {
        presentedCounts[id] != nil
    }

    private mutating func noteStored(_ id: Bug.ID) {
        guard presentedCounts[id] == nil else { return }
        unpresentedOrder.removeAll { $0 == id }
        unpresentedOrder.append(id)
        trim()
    }

    private mutating func trim() {
        var commentHolders = unpresentedOrder.filter { comments[$0] != nil }
        while commentHolders.count > Self.retainedCommentLimit,
              let index = commentHolders.firstIndex(where: isEvictable) {
            let id = commentHolders.remove(at: index)
            comments[id] = nil
            appliedCommentsFetch[id] = nil
        }
        while unpresentedOrder.count > Self.retainedBugLimit,
              let index = unpresentedOrder.firstIndex(where: isEvictable) {
            let id = unpresentedOrder.remove(at: index)
            bugs[id] = nil
            comments[id] = nil
            errors[id] = nil
            latestFetch[id] = nil
            appliedBugFetch[id] = nil
            appliedCommentsFetch[id] = nil
        }
    }

    private func isEvictable(_ id: Bug.ID) -> Bool {
        presentedCounts[id] == nil
            && activeFetches[id] == nil
            && edits[id] == nil
            && pendingComments[id] == nil
            && commentEdits[id] == nil
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}

extension Comment {
    func replacingText(_ text: String) -> Comment {
        Comment(
            id: id,
            bugId: bugId,
            creator: creator,
            text: text,
            creationTime: creationTime,
            isPrivate: isPrivate,
            count: count,
            attachmentId: attachmentId
        )
    }
}

extension Bug {
    func applying(_ update: BugUpdate, users: [User] = [], editID: Int = 0) -> Bug {
        let detail: (String) -> User? = { login in
            users.first { $0.name.caseInsensitiveCompare(login) == .orderedSame }
        }
        let newAssignee = update.assignedTo ?? assignedTo
        let newAssigneeDetail: User? = update.assignedTo.map(detail) ?? assignedToDetail
        return Bug(
            id: id,
            summary: update.summary ?? summary,
            status: update.status ?? status,
            resolution: update.resolution ?? (update.dupeOf != nil ? "DUPLICATE" : resolution),
            product: product,
            component: component,
            assignedTo: newAssignee,
            creator: creator,
            reporter: reporter,
            creationTime: creationTime,
            lastChangeTime: lastChangeTime,
            priority: update.priority ?? priority,
            severity: update.severity ?? severity,
            keywords: keywords,
            whiteboard: update.whiteboard ?? whiteboard,
            blocks: update.blocks.map { $0.applied(to: blocks) } ?? blocks,
            dependsOn: update.dependsOn.map { $0.applied(to: dependsOn) } ?? dependsOn,
            seeAlso: update.seeAlso.map { $0.applied(to: seeAlso) } ?? seeAlso,
            cc: cc,
            flags: update.flags.map { Self.applying($0, to: flags, editID: editID) } ?? flags,
            type: type,
            targetMilestone: update.targetMilestone ?? targetMilestone,
            points: update.points ?? points,
            accessibilitySeverity: accessibilitySeverity,
            rank: update.rank.map { $0 == 0 ? nil : $0 } ?? rank,
            assignedToDetail: newAssigneeDetail,
            creatorDetail: creatorDetail,
            attachments: attachments,
            groups: update.groups.map { $0.applied(to: groups) } ?? groups
        )
    }

    private static func applying(_ updates: [FlagUpdate], to flags: [Flag], editID: Int) -> [Flag] {
        var result = flags
        for (offset, update) in updates.enumerated() {
            if let id = update.id {
                guard let index = result.firstIndex(where: { $0.id == id }) else { continue }
                if update.status == "X" {
                    result.remove(at: index)
                } else {
                    let flag = result[index]
                    result[index] = Flag(
                        id: flag.id,
                        name: flag.name,
                        status: update.status,
                        setter: flag.setter,
                        requestee: update.requestee ?? flag.requestee,
                        typeID: flag.typeID,
                        creationDate: flag.creationDate,
                        modificationDate: flag.modificationDate
                    )
                }
            } else if let name = update.name {
                if update.status == "X" {
                    result.removeAll { $0.name == name && (update.requestee == nil || $0.requestee == update.requestee) }
                } else {
                    result.append(Flag(
                        id: -(editID * 16 + offset + 1),
                        name: name,
                        status: update.status,
                        requestee: update.requestee
                    ))
                }
            }
        }
        return result
    }
}

private extension BugRelationUpdate {
    func applied(to ids: [Bug.ID]) -> [Bug.ID] {
        var result = set ?? ids
        for id in add ?? [] where !result.contains(id) {
            result.append(id)
        }
        if let remove {
            result.removeAll { remove.contains($0) }
        }
        return result
    }
}

private extension SeeAlsoUpdate {
    func applied(to urls: [String]) -> [String] {
        var result = urls
        for url in add ?? [] where !result.contains(url) {
            result.append(url)
        }
        if let remove {
            result.removeAll { remove.contains($0) }
        }
        return result
    }
}

private extension GroupsUpdate {
    func applied(to groups: [String]) -> [String] {
        var result = set ?? groups
        for group in add ?? [] where !result.contains(group) {
            result.append(group)
        }
        if let remove {
            result.removeAll { remove.contains($0) }
        }
        return result
    }
}

extension BugUpdate {
    func mirroredRelations(for id: Bug.ID) -> [Bug.ID: BugUpdate] {
        var result: [Bug.ID: BugUpdate] = [:]
        func mirror(_ others: [Bug.ID]?, _ apply: (inout BugUpdate) -> Void) {
            for other in others ?? [] where other != id {
                var update = result[other] ?? BugUpdate()
                apply(&update)
                result[other] = update
            }
        }
        mirror(blocks?.add) { $0.dependsOn = $0.dependsOn.adding(id) }
        mirror(blocks?.remove) { $0.dependsOn = $0.dependsOn.removing(id) }
        mirror(dependsOn?.add) { $0.blocks = $0.blocks.adding(id) }
        mirror(dependsOn?.remove) { $0.blocks = $0.blocks.removing(id) }
        return result
    }
}

private extension Optional where Wrapped == BugRelationUpdate {
    func adding(_ id: Bug.ID) -> BugRelationUpdate {
        var update = self ?? BugRelationUpdate()
        update.add = (update.add ?? []) + [id]
        return update
    }

    func removing(_ id: Bug.ID) -> BugRelationUpdate {
        var update = self ?? BugRelationUpdate()
        update.remove = (update.remove ?? []) + [id]
        return update
    }
}
