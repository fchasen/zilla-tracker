import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension FolioHighlighter {
    public func applyInitialAttributes(
        to storage: NSTextStorage,
        text: String,
        language: CodeLanguage,
        font: PlatformFont
    ) {
        let runs = reset(text: text, language: language)
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.removeAttribute(.foregroundColor, range: fullRange)
        storage.addAttributes(
            [.foregroundColor: theme.foreground, .font: font],
            range: fullRange
        )
        for run in runs {
            let clamped = NSIntersectionRange(run.range, fullRange)
            guard clamped.length > 0 else { continue }
            storage.addAttribute(.foregroundColor, value: run.color, range: clamped)
        }
    }

    public func applyEditAttributes(
        to storage: NSTextStorage,
        edit: EditResult,
        font: PlatformFont
    ) {
        let storageRange = NSRange(location: 0, length: storage.length)
        let invalidated = NSIntersectionRange(edit.invalidatedRange, storageRange)
        guard invalidated.length > 0 else { return }

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.removeAttribute(.foregroundColor, range: invalidated)
        storage.addAttributes(
            [.foregroundColor: theme.foreground, .font: font],
            range: invalidated
        )
        for run in edit.newRuns {
            let clamped = NSIntersectionRange(run.range, invalidated)
            guard clamped.length > 0 else { continue }
            storage.addAttribute(.foregroundColor, value: run.color, range: clamped)
        }
    }
}
