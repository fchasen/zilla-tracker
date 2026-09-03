//
//  RevisionListFilters.swift
//  Zilla
//

import Foundation
import PhabricatorKit

enum RevisionList: String, CaseIterable, Hashable, Identifiable {
    case reviews
    case patches

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reviews: return "Reviews"
        case .patches: return "Patches"
        }
    }

    var systemImage: String {
        switch self {
        case .reviews: return "checkmark.seal"
        case .patches: return "doc.text"
        }
    }
}

enum PatchScope: String, CaseIterable, Hashable, Identifiable {
    case active
    case landed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active"
        case .landed: return "Landed"
        }
    }

    var systemImage: String {
        switch self {
        case .active: return "doc.text"
        case .landed: return "shippingbox"
        }
    }
}

enum ReviewerScope: Hashable, Identifiable {
    case direct
    case project(String)
    case other

    var id: String {
        switch self {
        case .direct: return "me"
        case .project(let phid): return phid
        case .other: return "other"
        }
    }

    var sortRank: Int {
        switch self {
        case .direct: return 0
        case .project: return 1
        case .other: return 2
        }
    }

    func title(resolving name: (String) -> String?) -> String {
        switch self {
        case .direct: return "Assigned to Me"
        case .project(let phid): return name(phid) ?? phid
        case .other: return "Other"
        }
    }

    /// Owner-package reviewers (`PHID-OPKG-*`) reach the viewer through `responsiblePHIDs`
    /// without intersecting their user or project PHIDs; `.other` keeps those filterable
    /// rather than permanently invisible.
    static func scopes(
        for revision: Revision,
        viewerPHID: String,
        viewerProjectPHIDs: Set<String>
    ) -> Set<ReviewerScope> {
        var result: Set<ReviewerScope> = []
        for reviewer in revision.attachments?.reviewers?.reviewers ?? [] {
            if reviewer.reviewerPHID == viewerPHID {
                result.insert(.direct)
            } else if viewerProjectPHIDs.contains(reviewer.reviewerPHID) {
                result.insert(.project(reviewer.reviewerPHID))
            }
        }
        return result.isEmpty ? [.other] : result
    }

    static func present(
        in revisions: [Revision],
        viewerPHID: String,
        viewerProjectPHIDs: Set<String>,
        name: (String) -> String?
    ) -> [(scope: ReviewerScope, title: String)] {
        var seen: Set<ReviewerScope> = []
        for revision in revisions {
            seen.formUnion(
                scopes(for: revision, viewerPHID: viewerPHID, viewerProjectPHIDs: viewerProjectPHIDs)
            )
        }
        return seen
            .map { (scope: $0, title: $0.title(resolving: name)) }
            .sorted {
                if $0.scope.sortRank != $1.scope.sortRank {
                    return $0.scope.sortRank < $1.scope.sortRank
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }
}

func revisionMatches(_ revision: Revision, search: String) -> Bool {
    let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return true }
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    var haystack = [revision.fields.title, revision.revisionLabel, String(revision.id)]
    if let bug = revision.fields.bugzillaBugID, !bug.isEmpty {
        haystack.append(bug)
    }
    return haystack.contains { $0.range(of: needle, options: options) != nil }
}
