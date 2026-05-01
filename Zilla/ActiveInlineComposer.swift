import Foundation

struct ActiveInlineComposer: Equatable {
    let path: String
    let line: Int
    let length: Int
    let isNewFile: Bool
    let replyTo: String?

    var syntheticID: String {
        "compose-\(path)-\(line)-\(replyTo ?? "")"
    }
}
