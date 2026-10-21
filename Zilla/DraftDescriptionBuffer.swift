//
//  DraftDescriptionBuffer.swift
//  Zilla
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class DraftDescriptionBuffer {
    private(set) var text: String

    @ObservationIgnored private let draft: BugDraft
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(draft: BugDraft, delay: Duration = .milliseconds(500)) {
        self.draft = draft
        self.delay = delay
        self.text = draft.bugDescription
    }

    var hasPendingCommit: Bool { pending != nil }

    func edit(_ newText: String) {
        guard newText != text else { return }
        text = newText
        pending?.cancel()
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    func commit() {
        pending?.cancel()
        pending = nil
        guard draft.modelContext != nil, !draft.isDeleted, draft.bugDescription != text else { return }
        draft.bugDescription = text
        draft.updatedAt = .now
    }

    func discard() {
        pending?.cancel()
        pending = nil
    }

    func adopt(_ stored: String) {
        guard pending == nil, stored != text else { return }
        text = stored
    }
}
