import Foundation

public struct DiffDetail: Sendable, Hashable, Identifiable {
    public let id: Int
    public let phid: String?
    public let revisionPHID: String?
    public let repositoryPHID: String?
    public let baseCommit: String?
    public let dateCreated: Date?
    public let dateModified: Date?
    public let changesets: [Changeset]

    public init(
        id: Int,
        phid: String?,
        revisionPHID: String?,
        repositoryPHID: String?,
        baseCommit: String?,
        dateCreated: Date?,
        dateModified: Date?,
        changesets: [Changeset]
    ) {
        self.id = id
        self.phid = phid
        self.revisionPHID = revisionPHID
        self.repositoryPHID = repositoryPHID
        self.baseCommit = baseCommit
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.changesets = changesets
    }
}

struct QueryDiffsRaw: Decodable, Sendable {
    let id: Int
    let phid: String?
    let revisionID: String?
    let revisionPHID: String?
    let repositoryPHID: String?
    let sourceControlBaseRevision: String?
    let dateCreated: Date?
    let dateModified: Date?
    let changes: [Changeset]

    enum CodingKeys: String, CodingKey {
        case id, phid
        case revisionID
        case revisionPHID
        case repositoryPHID
        case sourceControlBaseRevision
        case dateCreated, dateModified
        case changes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decodeIfPresent(Int.self, forKey: .id) {
            self.id = i
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .id), let i = Int(s) {
            self.id = i
        } else {
            self.id = 0
        }
        self.phid = try c.decodeIfPresent(String.self, forKey: .phid)
        self.revisionID = try c.decodeIfPresent(String.self, forKey: .revisionID)
        self.revisionPHID = try c.decodeIfPresent(String.self, forKey: .revisionPHID)
        self.repositoryPHID = try c.decodeIfPresent(String.self, forKey: .repositoryPHID)
        self.sourceControlBaseRevision = try c.decodeIfPresent(String.self, forKey: .sourceControlBaseRevision)
        self.dateCreated = try? c.decodeIfPresent(Date.self, forKey: .dateCreated)
        self.dateModified = try? c.decodeIfPresent(Date.self, forKey: .dateModified)
        self.changes = try c.decodeIfPresent([Changeset].self, forKey: .changes) ?? []
    }

    func toDetail() -> DiffDetail {
        DiffDetail(
            id: id,
            phid: phid,
            revisionPHID: revisionPHID,
            repositoryPHID: repositoryPHID,
            baseCommit: sourceControlBaseRevision,
            dateCreated: dateCreated,
            dateModified: dateModified,
            changesets: changes
        )
    }
}
