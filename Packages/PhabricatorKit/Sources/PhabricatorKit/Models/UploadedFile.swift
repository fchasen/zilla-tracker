import Foundation

public struct UploadedFile: Sendable, Hashable, Identifiable {
    public let id: Int
    public let phid: String

    public init(id: Int, phid: String) {
        self.id = id
        self.phid = phid
    }

    public var monogram: String { "F\(id)" }
}
