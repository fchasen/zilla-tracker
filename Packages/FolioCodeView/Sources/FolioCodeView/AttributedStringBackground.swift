import SwiftUI
import FolioHighlight

extension AttributedString {
    mutating func applyBackground(on text: String, range: NSRange, color: PlatformColor) {
        let nsText = text as NSString
        guard range.location >= 0,
              range.location + range.length <= nsText.length else { return }
        guard let lower = AttributedString.Index(
            String.Index(utf16Offset: range.location, in: text),
            within: self
        ),
        let upper = AttributedString.Index(
            String.Index(utf16Offset: range.location + range.length, in: text),
            within: self
        ) else { return }
        self[lower..<upper].backgroundColor = Color(color)
    }
}
