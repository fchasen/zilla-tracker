import Foundation
import PhabricatorKit

enum ChangesetContentSource: Sendable, Hashable {
    case hunks(old: String, new: String)
    case binary

    var lines: (old: String, new: String)? {
        switch self {
        case .hunks(let old, let new):
            return (old, new)
        case .binary:
            return nil
        }
    }
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
        let (old, new) = ChangesetSynthesizer.synthesize(changeset: changeset)
        return .hunks(old: old, new: new)
    }
}
