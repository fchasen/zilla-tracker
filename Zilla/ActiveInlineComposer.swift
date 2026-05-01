import Foundation

struct ActiveInlineComposer: Equatable {
    let path: String
    let line: Int
    let length: Int
    let isNewFile: Bool
    let replyTo: String?
    let editingPHID: String?

    init(
        path: String,
        line: Int,
        length: Int,
        isNewFile: Bool,
        replyTo: String?,
        editingPHID: String? = nil
    ) {
        self.path = path
        self.line = line
        self.length = length
        self.isNewFile = isNewFile
        self.replyTo = replyTo
        self.editingPHID = editingPHID
    }

    var syntheticID: String {
        "compose-\(path)-\(line)-\(replyTo ?? "")-\(editingPHID ?? "")"
    }
}
