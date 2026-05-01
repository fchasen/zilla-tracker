import SwiftUI

func revisionTitleAttributed(_ title: String) -> AttributedString {
    var attributed = AttributedString(title)
    if let match = title.firstMatch(of: #/^Bug \d+/#) {
        let prefix = String(title[match.range])
        if let range = attributed.range(of: prefix) {
            attributed[range].foregroundColor = .secondary
        }
    }
    return attributed
}
