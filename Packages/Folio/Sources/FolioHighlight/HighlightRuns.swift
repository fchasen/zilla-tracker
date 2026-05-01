import Foundation

public extension FolioHighlighter {
    static func attributed(
        text: String,
        lineRange: NSRange,
        runs: [Run],
        defaultColor: PlatformColor
    ) -> AttributedString {
        var attributed = AttributedString(text)
        let nsText = text as NSString
        if !runs.isEmpty {
            for run in runs {
                let intersection = NSIntersectionRange(run.range, lineRange)
                guard intersection.length > 0 else { continue }
                let local = NSRange(
                    location: intersection.location - lineRange.location,
                    length: intersection.length
                )
                guard local.location >= 0,
                      local.location + local.length <= nsText.length else { continue }
                guard let lower = AttributedString.Index(
                    String.Index(utf16Offset: local.location, in: text),
                    within: attributed
                ),
                let upper = AttributedString.Index(
                    String.Index(utf16Offset: local.location + local.length, in: text),
                    within: attributed
                ) else { continue }
                attributed[lower..<upper].foregroundColor = run.color
            }
        }
        return attributed
    }
}
