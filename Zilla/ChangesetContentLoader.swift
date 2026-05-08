import Foundation
import PhabricatorKit

enum ChangesetContentSource: Sendable, Hashable {
    case hunks
    case binary
}

@MainActor
struct ChangesetContentLoader {
    let client: PhabricatorClient
    let cache: ResourceCache?

    func load(_ changeset: Changeset, diff: DiffDetail) async -> ChangesetContentSource {
        switch changeset.fileType {
        case .binary, .image:
            return .binary
        default:
            break
        }
        return .hunks
    }
}
