import Foundation

public struct MarkdownWriter: DocumentWriter {
    public init() {}

    public func write(_ document: EditorDocument) -> String {
        lines(for: document.blocks, context: .top).joined(separator: "\n")
    }

    public func markdown(from storage: NSAttributedString) -> String {
        write(StorageReader().document(from: storage))
    }

    public func markdown(from storage: NSAttributedString, range: NSRange) -> String {
        write(StorageReader().document(from: storage, range: range))
    }

    private enum Context {
        case top
        case quote
        case item
    }

    private func lines(for blocks: [EditorDocument.Block], context: Context) -> [String] {
        var output: [String] = []
        var hasPrevious = false
        for block in blocks {
            var interrupts = false
            let rendered: [String]
            if case .list(let list) = block {
                let result = listLines(list)
                rendered = result.lines
                var startsAtOne = true
                if case .ordered(let start) = list.kind { startsAtOne = start == 1 }
                interrupts = startsAtOne && !result.startsWithEmptyItem
            } else {
                rendered = lines(for: block, isFirstInItem: context == .item && !hasPrevious)
            }
            guard !rendered.isEmpty else { continue }
            if hasPrevious, needsBlankLine(before: block, interrupts: interrupts, context: context) {
                output.append("")
            }
            output.append(contentsOf: rendered)
            hasPrevious = true
        }
        return output
    }

    private func needsBlankLine(before block: EditorDocument.Block, interrupts: Bool, context: Context) -> Bool {
        guard context == .item else { return true }
        switch block {
        case .list:
            return !interrupts
        case .code, .heading, .quote:
            return false
        case .paragraph, .thematicBreak, .atom:
            return true
        }
    }

    private func lines(for block: EditorDocument.Block, isFirstInItem: Bool) -> [String] {
        switch block {
        case .paragraph(let runs):
            let text = InlineSerializer.serialize(runs, inHeading: false)
            return text.isEmpty ? [] : Self.split(text)
        case .heading(let level, let runs):
            let marker = String(repeating: "#", count: max(1, min(6, level)))
            let text = InlineSerializer.serialize(runs, inHeading: true)
            return [text.isEmpty ? marker : marker + " " + text]
        case .code(let code):
            return codeLines(code)
        case .thematicBreak:
            return [isFirstInItem ? "***" : "---"]
        case .atom(let atom) where atom.kind == AtomKind.thematicBreak:
            return [Self.thematicBreak(source: atom.source, isFirstInItem: isFirstInItem)]
        case .atom(let atom):
            return Self.split(atom.source)
        case .quote(let blocks):
            let inner = lines(for: blocks, context: .quote)
            guard !inner.isEmpty else { return [">"] }
            return inner.map { $0.isEmpty ? ">" : "> " + $0 }
        case .list(let list):
            return listLines(list).lines
        }
    }

    private func listLines(_ list: EditorDocument.ListBlock) -> (lines: [String], startsWithEmptyItem: Bool) {
        var output: [String] = []
        var startsWithEmptyItem = false
        for (index, item) in list.items.enumerated() {
            let marker: String
            switch list.kind {
            case .bullet:
                marker = "-"
            case .ordered(let start):
                marker = "\(start + index)."
            }
            let indent = String(repeating: " ", count: marker.count + 1)
            let head: String
            switch item.task {
            case .none: head = marker
            case .unchecked?: head = marker + " [ ]"
            case .checked?: head = marker + " [x]"
            }
            let content = lines(for: item.blocks, context: .item)
            guard let first = content.first else {
                if index == 0 { startsWithEmptyItem = true }
                output.append(head)
                continue
            }
            output.append(head + " " + first)
            for line in content.dropFirst() {
                output.append(line.isEmpty ? "" : indent + line)
            }
        }
        return (output, startsWithEmptyItem)
    }

    private func codeLines(_ code: EditorDocument.CodeBlock) -> [String] {
        let info = code.language ?? ""
        let fenceCharacter: Character = info.contains("`") ? "~" : "`"
        var longest = 0
        for line in code.lines {
            longest = max(longest, Self.longestRun(of: fenceCharacter, in: line))
        }
        let fence = String(repeating: fenceCharacter, count: max(3, longest + 1))
        let body = code.lines == [""] ? [] : code.lines
        return [fence + info] + body + [fence]
    }

    static func thematicBreak(source: String, isFirstInItem: Bool) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        let marks = trimmed.filter { $0 != " " && $0 != "\t" }
        guard let mark = marks.first, "-*_".contains(mark), marks.count >= 3,
              marks.allSatisfy({ $0 == mark }), !trimmed.contains("\n") else {
            return isFirstInItem ? "***" : "---"
        }
        return isFirstInItem && mark == "-" ? "***" : trimmed
    }

    static func longestRun(of character: Character, in text: String) -> Int {
        guard let target = character.asciiValue else { return 0 }
        var longest = 0
        var current = 0
        for byte in text.utf8 {
            if byte == target {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    private static func split(_ text: String) -> [String] {
        guard text.utf8.contains(0x0A) else { return [text] }
        return text.utf8.split(separator: 0x0A, omittingEmptySubsequences: false).map { String(Substring($0)) }
    }
}

enum InlineSerializer {
    typealias Run = EditorDocument.InlineRun
    typealias Marks = EditorDocument.InlineMarks

    static let nestingOrder: [Marks] = [.strikethrough, .strong, .emphasis]
    static let delimiterMarks: Marks = [.strikethrough, .strong, .emphasis]

    static func serialize(_ runs: [Run], inHeading: Bool) -> String {
        if runs.count == 1, case .text(let text) = runs[0].content, runs[0].marks.isEmpty, runs[0].link == nil {
            return text
        }
        var segments: [[Run]] = [[]]
        var breaks: [Bool] = []
        for run in runs {
            switch run.content {
            case .softBreak, .hardBreak:
                breaks.append(run.content == .hardBreak)
                segments.append([])
            default:
                segments[segments.count - 1].append(run)
            }
        }
        for index in segments.indices {
            if index > 0 { trimLeading(&segments[index]) }
            if index < segments.count - 1 { trimTrailing(&segments[index]) }
        }

        var output = ""
        var pendingBreak: Bool?
        var hasContent = false
        for index in 0..<segments.count {
            let segment = segments[index]
            if !segment.isEmpty {
                if let hard = pendingBreak, hasContent {
                    output += inHeading ? " " : (hard ? "  \n" : "\n")
                }
                output += render(segment)
                hasContent = true
                pendingBreak = nil
            }
            if index < breaks.count, hasContent {
                pendingBreak = (pendingBreak ?? false) || breaks[index]
            }
        }
        return output
    }

    private static func isTrimmable(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t"
    }

    private static func trimLeading(_ runs: inout [Run]) {
        while let first = runs.first, case .text(let text) = first.content, !first.marks.has(.code) {
            let trimmed = String(text.unicodeScalars.drop(while: isTrimmable))
            if trimmed.isEmpty {
                runs.removeFirst()
                continue
            }
            runs[0].content = .text(trimmed)
            return
        }
    }

    private static func trimTrailing(_ runs: inout [Run]) {
        while let last = runs.last, case .text(let text) = last.content, !last.marks.has(.code) {
            var trimmed = Substring(text).unicodeScalars
            while let scalar = trimmed.last, isTrimmable(scalar) { trimmed.removeLast() }
            if trimmed.isEmpty {
                runs.removeLast()
                continue
            }
            runs[runs.count - 1].content = .text(String(trimmed))
            return
        }
    }

    private static func render(_ segment: [Run]) -> String {
        if segment.allSatisfy({ $0.marks.isEmpty && $0.link == nil }) {
            var output = ""
            for run in segment { output += emittedText(of: run) }
            return output
        }
        var runs = merge(detachWhitespace(segment))
        bridgeWhitespaceGaps(&runs)
        runs = merge(runs)
        let items = group(runs)
        var emitter = PieceEmitter()
        emitter.emit(items)
        return emitter.render()
    }

    static func isWhitespaceOnly(_ run: Run) -> Bool {
        guard case .text(let text) = run.content, !run.marks.has(.code) else { return false }
        return !text.isEmpty && text.unicodeScalars.allSatisfy(isUnicodeWhitespace)
    }

    private static func detachWhitespace(_ runs: [Run]) -> [Run] {
        var output: [Run] = []
        output.reserveCapacity(runs.count)
        for run in runs {
            guard case .text(let text) = run.content,
                  !run.marks.has(.code),
                  run.marks.and(delimiterMarks).rawValue != 0 else {
                output.append(run)
                continue
            }
            let bare = run.marks.minus(delimiterMarks)
            let scalars = text.unicodeScalars
            guard let first = scalars.firstIndex(where: { !isUnicodeWhitespace($0) }),
                  let last = scalars.lastIndex(where: { !isUnicodeWhitespace($0) }) else {
                output.append(.text(text, marks: bare, link: run.link))
                continue
            }
            let coreEnd = scalars.index(after: last)
            if first > scalars.startIndex {
                output.append(.text(String(scalars[..<first]), marks: bare, link: run.link))
            }
            output.append(.text(String(scalars[first..<coreEnd]), marks: run.marks, link: run.link))
            if coreEnd < scalars.endIndex {
                output.append(.text(String(scalars[coreEnd...]), marks: bare, link: run.link))
            }
        }
        return output
    }

    private static func merge(_ runs: [Run]) -> [Run] {
        var output: [Run] = []
        output.reserveCapacity(runs.count)
        for run in runs {
            if case .text(let text) = run.content, text.isEmpty { continue }
            if let last = output.last,
               case .text(let previous) = last.content,
               case .text(let text) = run.content,
               last.marks == run.marks,
               last.link == run.link {
                output[output.count - 1].content = .text(previous + text)
            } else {
                output.append(run)
            }
        }
        return output
    }

    private static func bridgeWhitespaceGaps(_ runs: inout [Run]) {
        guard runs.count >= 3 else { return }
        for index in 1..<(runs.count - 1) where isWhitespaceOnly(runs[index]) {
            let before = runs[index - 1]
            let after = runs[index + 1]
            let shared = before.marks.and(after.marks).and(delimiterMarks)
            runs[index].marks = runs[index].marks.plus(shared)
            if runs[index].link == nil, let link = before.link, link == after.link {
                runs[index].link = link
            }
        }
    }

    enum Item {
        case run(Run, marks: Marks)
        case link(url: String, marks: Marks, runs: [Run], bare: String?)

        var marks: Marks {
            switch self {
            case .run(_, let marks), .link(_, let marks, _, _): return marks
            }
        }
    }

    private static func group(_ runs: [Run]) -> [Item] {
        var items: [Item] = []
        var index = 0
        while index < runs.count {
            let run = runs[index]
            guard let url = run.link else {
                items.append(.run(run, marks: run.marks.and(delimiterMarks)))
                index += 1
                continue
            }
            var end = index + 1
            while end < runs.count, runs[end].link == url { end += 1 }
            let members = Array(runs[index..<end])
            var shared = delimiterMarks
            for member in members { shared = shared.and(member.marks) }
            let previous = index > 0 ? lastCharacter(of: runs[index - 1]) : nil
            let next = end < runs.count ? firstCharacter(of: runs[end]) : nil
            let bare = bareAutolink(members, url: url, outer: shared, previous: previous, next: next)
            items.append(.link(url: url, marks: shared, runs: members, bare: bare))
            index = end
        }
        return items
    }

    private static func bareAutolink(_ members: [Run], url: String, outer: Marks, previous: Character?, next: Character?) -> String? {
        guard members.count == 1,
              case .text(let text) = members[0].content,
              members[0].marks.minus(outer).rawValue == 0,
              let last = text.last,
              !text.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" }),
              !".,:;!?*_~)'\"".contains(last) else { return nil }
        let matches = (text == url && (text.hasPrefix("http://") || text.hasPrefix("https://")))
            || (text.hasPrefix("www.") && "http://" + text == url)
            || (text.contains("@") && "mailto:" + text == url)
        guard matches else { return nil }
        if let previous, !previous.isWhitespace, !"*_~(".contains(previous) { return nil }
        if let next, !next.isWhitespace, !".,:;!?*_~)'\"".contains(next) { return nil }
        return text
    }

    static func emittedText(of run: Run) -> String {
        switch run.content {
        case .text(let text): return run.marks.has(.code) ? codeSpan(text) : text
        case .literal(_, let source): return source
        case .atom(let atom): return atom.source
        case .softBreak, .hardBreak: return ""
        }
    }

    private static func firstCharacter(of run: Run) -> Character? {
        emittedText(of: run).first
    }

    private static func lastCharacter(of run: Run) -> Character? {
        emittedText(of: run).last
    }

    static func codeSpan(_ text: String) -> String {
        let fence = String(repeating: "`", count: MarkdownWriter.longestRun(of: "`", in: text) + 1)
        let needsPadding = text.first == "`" || text.last == "`"
            || (text.first == " " && text.last == " " && text.contains { $0 != " " })
        let padding = needsPadding ? " " : ""
        return fence + padding + text + padding + fence
    }

    static func destination(_ url: String) -> String {
        var depth = 0
        var balanced = true
        for character in url {
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth < 0 { balanced = false }
            }
        }
        if depth != 0 { balanced = false }
        let needsAngle = !balanced || url.contains { $0 == " " || $0 == "\t" }
        if needsAngle, !url.contains("<"), !url.contains(">") {
            return "<" + url + ">"
        }
        return url
    }
}

private struct PieceEmitter {
    typealias Marks = EditorDocument.InlineMarks

    enum Piece {
        case text(String)
        case open(Marks, Int)
        case close(Marks, Int)
    }

    private var pieces: [Piece] = []
    private var nextID = 0
    private struct Span {
        let open: Int
        let close: Int
    }

    private struct OpenMark {
        let mark: Marks
        let id: Int
    }

    private var emphasisSpans: [Span] = []
    private var openEmphasis: [Int: Int] = [:]

    mutating func emit(_ items: [InlineSerializer.Item]) {
        let count = items.count
        var extents: [[Int]] = InlineSerializer.nestingOrder.map { _ in Array(repeating: 0, count: count + 1) }
        for slot in 0..<InlineSerializer.nestingOrder.count {
            let mark = InlineSerializer.nestingOrder[slot]
            var index = count - 1
            while index >= 0 {
                extents[slot][index] = items[index].marks.has(mark) ? extents[slot][index + 1] + 1 : 0
                index -= 1
            }
        }

        var stack: [OpenMark] = []
        for index in 0..<count {
            let item = items[index]
            let needed = item.marks
            if let firstStale = stack.firstIndex(where: { !needed.has($0.mark) }) {
                for entry in stack[firstStale...].reversed() { close(entry.mark, entry.id) }
                stack.removeSubrange(firstStale...)
            }
            var opened = Marks()
            for entry in stack { opened = opened.plus(entry.mark) }
            var missing: [Int] = []
            for slot in 0..<InlineSerializer.nestingOrder.count {
                let mark = InlineSerializer.nestingOrder[slot]
                if needed.has(mark), !opened.has(mark) { missing.append(slot) }
            }
            if missing.count > 1 {
                missing.sort { lhs, rhs in
                    let left = extents[lhs][index]
                    let right = extents[rhs][index]
                    return left != right ? left > right : lhs < rhs
                }
            }
            for slot in missing {
                let mark = InlineSerializer.nestingOrder[slot]
                stack.append(OpenMark(mark: mark, id: open(mark)))
            }
            emitContent(of: item)
        }
        for entry in stack.reversed() { close(entry.mark, entry.id) }
    }

    private mutating func emitContent(of item: InlineSerializer.Item) {
        switch item {
        case .run(let run, _):
            pieces.append(.text(InlineSerializer.emittedText(of: run)))
        case .link(let url, let outer, let runs, let bare):
            if let bare {
                pieces.append(.text(bare))
                return
            }
            pieces.append(.text("["))
            let inner = runs.map { run in
                InlineSerializer.Item.run(run, marks: run.marks.and(InlineSerializer.delimiterMarks).minus(outer))
            }
            emit(inner)
            pieces.append(.text("](" + InlineSerializer.destination(url) + ")"))
        }
    }

    private mutating func open(_ mark: Marks) -> Int {
        nextID += 1
        if mark == .emphasis { openEmphasis[nextID] = pieces.count }
        pieces.append(.open(mark, nextID))
        return nextID
    }

    private mutating func close(_ mark: Marks, _ id: Int) {
        if mark == .emphasis, let openIndex = openEmphasis.removeValue(forKey: id) {
            emphasisSpans.append(Span(open: openIndex, close: pieces.count))
        }
        pieces.append(.close(mark, id))
    }

    func render() -> String {
        var underscore = Set<Int>()
        for span in emphasisSpans where usesUnderscore(span) {
            underscore.insert(span.open)
            underscore.insert(span.close)
        }
        var output = ""
        for index in 0..<pieces.count {
            switch pieces[index] {
            case .text(let text):
                output += text
            case .open(let mark, _), .close(let mark, _):
                if mark == .emphasis {
                    output += underscore.contains(index) ? "_" : "*"
                } else {
                    output += Self.token(mark)
                }
            }
        }
        return output
    }

    private static func token(_ mark: Marks) -> String {
        switch mark {
        case .strong: return "**"
        case .strikethrough: return "~~"
        default: return "*"
        }
    }

    private func piece(_ index: Int) -> Piece? {
        pieces.indices.contains(index) ? pieces[index] : nil
    }

    private func usesUnderscore(_ span: Span) -> Bool {
        let before = piece(span.open - 1)
        let after = piece(span.close + 1)
        let innerFirst = piece(span.open + 1)
        let innerLast = piece(span.close - 1)

        if case .open(.strong, let a)? = before, case .close(.strong, let b)? = after, a == b {
            return false
        }
        let touchesStrong = [before, after, innerFirst, innerLast].contains { Self.isStrongToken($0) }
        let touchesStar = Self.lastCharacter(before) == "*" || Self.firstCharacter(after) == "*"
            || Self.firstCharacter(innerFirst) == "*" || Self.lastCharacter(innerLast) == "*"
        guard touchesStrong || touchesStar else { return false }

        let outerLeft = Self.lastCharacter(before)
        let outerRight = Self.firstCharacter(after)
        if let outerLeft, outerLeft.isLetter || outerLeft.isNumber || outerLeft == "_" { return false }
        if let outerRight, outerRight.isLetter || outerRight.isNumber || outerRight == "_" { return false }
        if Self.firstCharacter(innerFirst) == "_" || Self.lastCharacter(innerLast) == "_" { return false }
        return true
    }

    private static func isStrongToken(_ piece: Piece?) -> Bool {
        switch piece {
        case .open(.strong, _)?, .close(.strong, _)?: return true
        default: return false
        }
    }

    private static func firstCharacter(_ piece: Piece?) -> Character? {
        switch piece {
        case .text(let text)?: return text.first
        case .open(let mark, _)?, .close(let mark, _)?: return token(mark).first
        case nil: return nil
        }
    }

    private static func lastCharacter(_ piece: Piece?) -> Character? {
        switch piece {
        case .text(let text)?: return text.last
        case .open(let mark, _)?, .close(let mark, _)?: return token(mark).last
        case nil: return nil
        }
    }
}

extension EditorDocument.InlineMarks {
    @inline(__always) func has(_ mark: Self) -> Bool { rawValue & mark.rawValue != 0 }
    @inline(__always) func and(_ other: Self) -> Self { Self(rawValue: rawValue & other.rawValue) }
    @inline(__always) func minus(_ other: Self) -> Self { Self(rawValue: rawValue & ~other.rawValue) }
    @inline(__always) func plus(_ other: Self) -> Self { Self(rawValue: rawValue | other.rawValue) }
}

@inline(__always) func isUnicodeWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    if scalar.value < 0x80 {
        return scalar == " " || (scalar.value >= 0x09 && scalar.value <= 0x0D)
    }
    return scalar.properties.isWhitespace
}
