import Foundation
import SwiftTreeSitter

public final class FolioHighlighter {
    public struct Run: Sendable, Hashable {
        public let range: NSRange
        public let color: PlatformColor

        public init(range: NSRange, color: PlatformColor) {
            self.range = range
            self.color = color
        }
    }

    public struct EditResult: Sendable {
        public let invalidatedRange: NSRange
        public let newRuns: [Run]

        public init(invalidatedRange: NSRange, newRuns: [Run]) {
            self.invalidatedRange = invalidatedRange
            self.newRuns = newRuns
        }
    }

    public var theme: HighlightTheme

    private var parser: Parser?
    private var tree: MutableTree?
    private var query: Query?
    private var configuredLanguage: CodeLanguage?
    private var currentText: String = ""

    public init(theme: HighlightTheme) {
        self.theme = theme
    }

    public func runs(for snippetText: String, language: CodeLanguage) -> [Run] {
        guard language.id != CodeLanguage.plain.id,
              let tsLanguage = language.language,
              let queryURL = queryURL(for: language) else {
            return []
        }

        let parser = Parser()
        do {
            try parser.setLanguage(tsLanguage)
        } catch {
            return []
        }

        guard let tree = parser.parse(snippetText) else { return [] }
        guard let root = tree.rootNode else { return [] }

        let query: Query
        do {
            query = try Query(language: tsLanguage, url: queryURL)
        } catch {
            return []
        }

        let cursor = query.execute(node: root, in: tree)
        let highlights = cursor.highlights()

        return highlights.compactMap { runFromHighlight($0) }
    }

    public func reset(text: String, language: CodeLanguage) -> [Run] {
        currentText = text
        configuredLanguage = language

        guard language.id != CodeLanguage.plain.id,
              let tsLanguage = language.language,
              let queryURL = queryURL(for: language) else {
            parser = nil
            tree = nil
            query = nil
            return []
        }

        let parser = Parser()
        do {
            try parser.setLanguage(tsLanguage)
        } catch {
            self.parser = nil
            self.tree = nil
            self.query = nil
            return []
        }

        guard let tree = parser.parse(text) else {
            self.parser = nil
            self.tree = nil
            self.query = nil
            return []
        }

        let query: Query
        do {
            query = try Query(language: tsLanguage, url: queryURL)
        } catch {
            self.parser = nil
            self.tree = nil
            self.query = nil
            return []
        }

        self.parser = parser
        self.tree = tree
        self.query = query

        guard let root = tree.rootNode else { return [] }
        let cursor = query.execute(node: root, in: tree)
        return cursor.highlights().compactMap { runFromHighlight($0) }
    }

    public func didEdit(replacedRange: NSRange, replacement: String, in newText: String) -> EditResult {
        guard let parser, let oldTree = tree, let query, let language = configuredLanguage else {
            currentText = newText
            return EditResult(
                invalidatedRange: NSRange(location: 0, length: (newText as NSString).length),
                newRuns: []
            )
        }

        let edit = makeInputEdit(replacing: replacedRange, with: replacement, in: currentText)
        oldTree.edit(edit)

        guard let newTree = parser.parse(tree: oldTree, string: newText) else {
            let runs = reset(text: newText, language: language)
            return EditResult(
                invalidatedRange: NSRange(location: 0, length: (newText as NSString).length),
                newRuns: runs
            )
        }

        let changedTSRanges = newTree.changedRanges(from: oldTree)
        tree = newTree
        currentText = newText

        let editStart = replacedRange.location
        let editEnd = replacedRange.location + (replacement as NSString).length
        var lower = editStart
        var upper = editEnd
        for r in changedTSRanges {
            let lo = Int(r.bytes.lowerBound) / 2
            let hi = Int(r.bytes.upperBound) / 2
            lower = Swift.min(lower, lo)
            upper = Swift.max(upper, hi)
        }
        let documentLength = (newText as NSString).length
        upper = Swift.min(upper, documentLength)
        lower = Swift.max(0, Swift.min(lower, upper))
        let invalidated = NSRange(location: lower, length: upper - lower)

        guard let root = newTree.rootNode else {
            return EditResult(invalidatedRange: invalidated, newRuns: [])
        }
        let cursor = query.execute(node: root, in: newTree)
        cursor.setByteRange(range: UInt32(lower * 2)..<UInt32(upper * 2))
        let runs = cursor.highlights().compactMap { runFromHighlight($0) }

        return EditResult(invalidatedRange: invalidated, newRuns: runs)
    }

    private func runFromHighlight(_ named: NamedRange) -> Run? {
        guard let color = colorForCaptureName(named.nameComponents) else { return nil }
        let lo = Int(named.tsRange.bytes.lowerBound) / 2
        let hi = Int(named.tsRange.bytes.upperBound) / 2
        guard hi >= lo else { return nil }
        return Run(range: NSRange(location: lo, length: hi - lo), color: color)
    }

    private func colorForCaptureName(_ components: [String]) -> PlatformColor? {
        let full = components.joined(separator: ".")
        if let color = CaptureMapping.color(for: full, theme: theme) { return color }
        guard let head = components.first else { return nil }
        return CaptureMapping.color(for: head, theme: theme)
    }

    private func queryURL(for language: CodeLanguage) -> URL? {
        guard let bundle = language.bundle, let resource = language.queryResource else { return nil }
        return bundle.url(forResource: resource, withExtension: "scm", subdirectory: "Queries")
            ?? bundle.url(forResource: resource, withExtension: "scm")
    }

    private func makeInputEdit(replacing nsRange: NSRange, with replacement: String, in oldText: String) -> InputEdit {
        let startByte = UInt32(nsRange.location * 2)
        let oldEndByte = UInt32((nsRange.location + nsRange.length) * 2)
        let replacementUtf16 = (replacement as NSString).length
        let newEndByte = startByte + UInt32(replacementUtf16 * 2)

        let startPoint = point(forUTF16: nsRange.location, in: oldText)
        let oldEndPoint = point(forUTF16: nsRange.location + nsRange.length, in: oldText)

        var newRow = startPoint.row
        var newColumn = startPoint.column
        for codeUnit in replacement.utf16 {
            if codeUnit == 0x0A {
                newRow += 1
                newColumn = 0
            } else {
                newColumn += 2
            }
        }
        let newEndPoint = Point(row: newRow, column: newColumn)

        return InputEdit(
            startByte: startByte,
            oldEndByte: oldEndByte,
            newEndByte: newEndByte,
            startPoint: startPoint,
            oldEndPoint: oldEndPoint,
            newEndPoint: newEndPoint
        )
    }

    private func point(forUTF16 utf16Offset: Int, in text: String) -> Point {
        var row: UInt32 = 0
        var lineStartUtf16 = 0
        var i = 0
        for codeUnit in text.utf16 {
            if i >= utf16Offset { break }
            if codeUnit == 0x0A {
                row += 1
                lineStartUtf16 = i + 1
            }
            i += 1
        }
        let column = UInt32((utf16Offset - lineStartUtf16) * 2)
        return Point(row: row, column: column)
    }
}
