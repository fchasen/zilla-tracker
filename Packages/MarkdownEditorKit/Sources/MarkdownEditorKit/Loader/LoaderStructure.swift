import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct LoaderStructure {
    let source: MarkdownSourceText
    private(set) var leaves: [LoaderLeaf] = []
    private(set) var recoveredLines: [Int] = []
    private var covered: Set<Int> = []
    private var quoteTokens: [Int: GroupToken] = [:]
    private var lists: [Int: NSTextList] = [:]
    private var items: [Int: LoaderItem] = [:]
    private var firstItemOfList: [ObjectIdentifier: Int] = [:]
    private var syntheticKey = -1

    init(source: MarkdownSourceText, runs: [LoaderRun]) {
        self.source = source
        group(runs)
        extendTables()
        coverSetextUnderlines()
        for leaf in leaves {
            if let lines = leaf.lines { covered.formUnion(lines) }
        }
        placeThematicBreaks()
        resolveChains()
        recoverUncoveredLines()
    }

    private mutating func group(_ runs: [LoaderRun]) {
        var fallbackKey = Int.min
        for run in runs {
            if run.inline.contains(.blockHTML) {
                let path = Self.containerPath(of: run.intent, stoppingAtLeaf: false)
                let key = run.intent?.components.first?.identity ?? 0
                if let last = leaves.last, case .html = last.kind, last.key == key,
                   let lastLines = last.lines, let span = run.lineSpan, span.lowerBound <= lastLines.upperBound + 1 {
                    last.runs.append(run)
                    last.extend(with: span)
                } else {
                    leaves.append(LoaderLeaf(kind: .html, key: key, path: path, runs: [run]))
                }
                continue
            }
            guard let intent = run.intent, let leafComponent = Self.leafComponent(of: intent) else {
                if let last = leaves.last, last.key == fallbackKey {
                    last.runs.append(run)
                    last.extend(with: run.lineSpan)
                } else {
                    fallbackKey += 1
                    leaves.append(LoaderLeaf(kind: .paragraph, key: fallbackKey, path: [], runs: [run]))
                }
                continue
            }
            let key = leafComponent.identity
            if let last = leaves.last, last.key == key, !Self.isHTML(last.kind) {
                last.runs.append(run)
                last.extend(with: run.lineSpan)
                continue
            }
            let kind: LoaderLeafKind
            switch leafComponent.kind {
            case .header(let level): kind = .heading(level)
            case .codeBlock(let hint): kind = .code(hint.flatMap { $0.isEmpty ? nil : $0 })
            case .thematicBreak: kind = .thematicBreak
            case .table(let columns): kind = .table(columns)
            default: kind = .paragraph
            }
            leaves.append(LoaderLeaf(
                kind: kind,
                key: key,
                path: Self.containerPath(of: intent, stoppingAtLeaf: true),
                runs: [run]
            ))
        }
    }

    private static func isHTML(_ kind: LoaderLeafKind) -> Bool {
        if case .html = kind { return true }
        return false
    }

    private static func leafComponent(of intent: PresentationIntent) -> PresentationIntent.IntentType? {
        if let table = intent.components.first(where: {
            if case .table = $0.kind { return true }
            return false
        }) {
            return table
        }
        return intent.components.first
    }

    static func containerPath(of intent: PresentationIntent?, stoppingAtLeaf: Bool) -> [PresentationIntent.IntentType] {
        guard let intent else { return [] }
        var outer = Array(intent.components.reversed())
        if let tableIndex = outer.firstIndex(where: {
            if case .table = $0.kind { return true }
            return false
        }) {
            outer = Array(outer[..<tableIndex])
        } else if stoppingAtLeaf, !outer.isEmpty {
            outer.removeLast()
        }
        return outer.filter {
            switch $0.kind {
            case .blockQuote, .orderedList, .unorderedList, .listItem: true
            default: false
            }
        }
    }

    private mutating func extendTables() {
        for (index, leaf) in leaves.enumerated() {
            guard case .table = leaf.kind, let lines = leaf.lines else { continue }
            let limit = nextStartLine(after: index) ?? (source.lineCount + 1)
            var end = lines.upperBound
            while end + 1 < limit, !source.isBlank(end + 1), source.lineBytes(end + 1).contains(UInt8(ascii: "|")) {
                end += 1
            }
            leaf.lines = lines.lowerBound...end
        }
    }

    private func nextStartLine(after index: Int) -> Int? {
        leaves[(index + 1)...].lazy.compactMap { $0.lines?.lowerBound }.first
    }

    private func previousEndLine(before index: Int) -> Int? {
        leaves[..<index].reversed().lazy.compactMap { $0.lines?.upperBound }.first
    }

    private mutating func coverSetextUnderlines() {
        for (index, leaf) in leaves.enumerated() {
            guard case .heading = leaf.kind, let lines = leaf.lines else { continue }
            let rest = ContainerPrefix.tokenize(source.lineBytes(lines.lowerBound)).trimmedRest
            guard !rest.hasPrefix("#") else { continue }
            let underline = lines.upperBound + 1
            guard underline <= source.lineCount, underline < (nextStartLine(after: index) ?? Int.max) else { continue }
            let underlineRest = String(source.line(underline).drop { $0 == " " || $0 == "\t" || $0 == ">" })
            if ContainerPrefix.isSetextUnderline(underlineRest) {
                leaf.lines = lines.lowerBound...underline
            }
        }
    }

    private mutating func placeThematicBreaks() {
        for (index, leaf) in leaves.enumerated() {
            guard case .thematicBreak = leaf.kind, leaf.lines == nil else { continue }
            let lower = (previousEndLine(before: index) ?? 0) + 1
            let upper = (nextStartLine(after: index) ?? (source.lineCount + 1)) - 1
            guard lower <= upper else { continue }
            for line in lower...upper where !covered.contains(line) {
                let prefix = ContainerPrefix.tokenize(source.lineBytes(line))
                guard !prefix.restIsBlank, ContainerPrefix.isThematicBreak(prefix.rest) else { continue }
                leaf.lines = line...line
                leaf.thematicSource = prefix.trimmedRest
                covered.insert(line)
                break
            }
        }
    }

    private mutating func resolveChains() {
        var seenItems: Set<Int> = []
        var previousEnd = 0
        for leaf in leaves {
            defer { previousEnd = max(previousEnd, leaf.lines?.upperBound ?? 0) }
            var chain: [LoaderLink] = []
            var newItems: Set<Int> = []
            var pendingList: (identity: Int, ordered: Bool)?
            var listDepth = 0
            var deepestItem: Int?
            for component in leaf.path {
                switch component.kind {
                case .blockQuote:
                    let token = quoteTokens[component.identity] ?? GroupToken.mint()
                    quoteTokens[component.identity] = token
                    chain.append(.quote(token))
                case .orderedList:
                    pendingList = (component.identity, true)
                    listDepth += 1
                case .unorderedList:
                    pendingList = (component.identity, false)
                    listDepth += 1
                case .listItem(let ordinal):
                    let item: LoaderItem
                    if let existing = items[component.identity] {
                        item = existing
                    } else {
                        let listInfo = pendingList ?? (identity: Int.min + component.identity, ordered: false)
                        let list = lists[listInfo.identity] ?? Self.makeList(
                            ordered: listInfo.ordered,
                            start: ordinal,
                            depth: listDepth
                        )
                        lists[listInfo.identity] = list
                        item = LoaderItem(key: component.identity, list: list)
                        items[component.identity] = item
                        if firstItemOfList[ObjectIdentifier(list)] == nil {
                            firstItemOfList[ObjectIdentifier(list)] = component.identity
                        }
                    }
                    if !seenItems.contains(component.identity) {
                        newItems.insert(component.identity)
                    }
                    deepestItem = component.identity
                    chain.append(.item(item))
                default:
                    break
                }
            }
            leaf.chain = chain
            leaf.newItemKeys = newItems
            if let deepestItem {
                leaf.isContinuation = seenItems.contains(deepestItem)
            }
            seenItems.formUnion(newItems)
            if !newItems.isEmpty {
                detectMarkers(for: leaf, floor: previousEnd + 1)
            }
        }
    }

    static func makeList(ordered: Bool, start: Int, depth: Int) -> NSTextList {
        if ordered {
            let list = NSTextList(markerFormat: .decimal, options: 0)
            list.startingItemNumber = start
            return list
        }
        let formats: [NSTextList.MarkerFormat] = [.disc, .circle, .square]
        return NSTextList(markerFormat: formats[max(0, depth - 1) % formats.count], options: 0)
    }

    private mutating func detectMarkers(for leaf: LoaderLeaf, floor: Int) {
        guard let start = leaf.lines?.lowerBound else { return }
        var line = start
        while line >= max(1, floor) {
            let prefix = ContainerPrefix.tokenize(source.lineBytes(line))
            if let assignments = Self.match(chain: leaf.chain, newItems: leaf.newItemKeys, tokens: prefix.tokens) {
                for (item, token) in assignments {
                    item.marker = token.kind
                    item.markerColumn = token.column
                    item.contentColumn = token.contentColumn
                }
                if line < start { covered.insert(line) }
                return
            }
            line -= 1
        }
    }

    private static func match(
        chain: [LoaderLink],
        newItems: Set<Int>,
        tokens: [PrefixToken]
    ) -> [(LoaderItem, PrefixToken)]? {
        var t = 0
        var assignments: [(LoaderItem, PrefixToken)] = []
        for link in chain {
            switch link {
            case .quote:
                if t < tokens.count, tokens[t].kind == .quote { t += 1 }
            case .item(let item):
                guard newItems.contains(item.key) else { continue }
                guard t < tokens.count, tokens[t].kind.isItem else { return nil }
                assignments.append((item, tokens[t]))
                t += 1
            }
        }
        return assignments
    }

    private mutating func recoverUncoveredLines() {
        guard source.lineCount > 0 else { return }
        var line = 1
        while line <= source.lineCount {
            defer { line += 1 }
            guard !covered.contains(line), !source.isBlank(line) else { continue }
            let prefix = ContainerPrefix.tokenize(source.lineBytes(line))
            let rest = prefix.restString
            let kind: LoaderLeafKind
            var lastLine = line
            if prefix.restIsBlank {
                guard prefix.tokens.last?.kind.isItem == true else { continue }
                kind = .paragraph
            } else if let level = ContainerPrefix.emptyHeadingLevel(rest) {
                kind = .heading(level)
            } else if let fence = ContainerPrefix.fenceOpening(rest) {
                var close = line + 1
                var found = false
                while close <= source.lineCount, !covered.contains(close) {
                    let closeRest = ContainerPrefix.tokenize(source.lineBytes(close)).restString
                    if ContainerPrefix.isFenceClosing(closeRest, marker: fence.marker, length: fence.length) {
                        found = true
                        break
                    }
                    guard source.isBlank(close) else { break }
                    close += 1
                }
                lastLine = found ? close : line
                kind = .code(fence.info.isEmpty ? nil : fence.info)
            } else {
                continue
            }
            insertRecovered(kind: kind, line: line, lastLine: lastLine, prefix: prefix)
            covered.formUnion(line...lastLine)
            recoveredLines.append(line)
            line = lastLine
        }
    }

    private mutating func insertRecovered(kind: LoaderLeafKind, line: Int, lastLine: Int, prefix: LinePrefix) {
        let insertIndex = leaves.firstIndex { ($0.lines?.lowerBound ?? Int.max) > line } ?? leaves.count
        let previous = leaves[..<insertIndex].last
        let next = leaves[insertIndex...].first { !$0.isRecovered }
        let reference = previous?.chain ?? []

        var chain: [LoaderLink] = []
        var t = 0
        var r = 0
        matching: while r < reference.count {
            switch reference[r] {
            case .quote:
                guard t < prefix.tokens.count, prefix.tokens[t].kind == .quote else { break matching }
                t += 1
            case .item(let item):
                guard let contentColumn = item.contentColumn else { break matching }
                let column = t < prefix.tokens.count ? prefix.tokens[t].column : Self.indentColumn(of: prefix)
                guard column >= contentColumn else { break matching }
            }
            chain.append(reference[r])
            r += 1
        }

        var newItem: LoaderItem?
        while t < prefix.tokens.count {
            let token = prefix.tokens[t]
            t += 1
            let depth = chain.count
            guard token.kind.isItem else {
                chain.append(reusableQuote(at: depth, candidates: [reference, next?.chain ?? []], prefix: chain)
                    ?? .quote(GroupToken.mint()))
                continue
            }
            let list = siblingList(for: token, at: depth, reference: reference, matchedPrefix: chain)
                ?? followingList(for: token, at: depth, next: next, matchedPrefix: chain)
                ?? Self.makeList(
                    ordered: token.kind.isOrdered,
                    start: token.kind.ordinal ?? 1,
                    depth: chain.reduce(0) { if case .item = $1 { return $0 + 1 } else { return $0 } } + 1
                )
            syntheticKey -= 1
            let item = LoaderItem(key: syntheticKey, list: list)
            item.marker = token.kind
            item.markerColumn = token.column
            item.contentColumn = token.contentColumn
            if firstItemOfList[ObjectIdentifier(list)] == nil {
                firstItemOfList[ObjectIdentifier(list)] = item.key
            }
            chain.append(.item(item))
            newItem = item
        }

        let leaf = LoaderLeaf(kind: kind, key: syntheticKey, path: [], runs: [])
        syntheticKey -= 1
        leaf.lines = line...lastLine
        leaf.chain = chain
        leaf.isRecovered = true
        if let newItem {
            leaf.newItemKeys = [newItem.key]
        } else {
            leaf.isContinuation = chain.contains {
                if case .item = $0 { return true }
                return false
            }
        }
        leaves.insert(leaf, at: insertIndex)
    }

    private static func indentColumn(of prefix: LinePrefix) -> Int {
        var column = prefix.restColumn
        for byte in prefix.rest {
            if byte == 0x20 {
                column += 1
            } else if byte == 0x09 {
                column += 4 - (column % 4)
            } else {
                break
            }
        }
        return column
    }

    private static func sharesPrefix(_ candidate: [LoaderLink], _ prefix: [LoaderLink]) -> Bool {
        guard candidate.count > prefix.count else { return false }
        return zip(prefix, candidate).allSatisfy { $0.isSame(as: $1) }
    }

    private func reusableQuote(at depth: Int, candidates: [[LoaderLink]], prefix: [LoaderLink]) -> LoaderLink? {
        for candidate in candidates where Self.sharesPrefix(candidate, prefix) {
            if case .quote = candidate[depth] { return candidate[depth] }
        }
        return nil
    }

    private func siblingList(
        for token: PrefixToken,
        at depth: Int,
        reference: [LoaderLink],
        matchedPrefix: [LoaderLink]
    ) -> NSTextList? {
        guard Self.sharesPrefix(reference, matchedPrefix), case .item(let item) = reference[depth],
              Self.sameMarkerFamily(item.marker, token.kind)
        else { return nil }
        return item.list
    }

    private mutating func followingList(
        for token: PrefixToken,
        at depth: Int,
        next: LoaderLeaf?,
        matchedPrefix: [LoaderLink]
    ) -> NSTextList? {
        guard let next, Self.sharesPrefix(next.chain, matchedPrefix),
              case .item(let item) = next.chain[depth],
              Self.sameMarkerFamily(item.marker, token.kind),
              item.markerColumn == token.column
        else { return nil }
        if firstItemOfList[ObjectIdentifier(item.list)] == item.key, let ordinal = token.kind.ordinal {
            item.list.startingItemNumber = ordinal
        }
        firstItemOfList[ObjectIdentifier(item.list)] = syntheticKey - 1
        return item.list
    }

    private static func sameMarkerFamily(_ a: PrefixToken.Kind?, _ b: PrefixToken.Kind) -> Bool {
        switch (a, b) {
        case (.bullet(let x), .bullet(let y)): x == y
        case (.ordered(_, let x), .ordered(_, let y)): x == y
        default: false
        }
    }

    func stripContinuationPrefix(_ line: Int, chain: [LoaderLink], markerLine: Bool) -> String {
        let bytes = Array(source.lineBytes(line))
        var p = 0
        var column = 0
        func advance() {
            column = bytes[p] == 0x09 ? column + 4 - (column % 4) : column + 1
            p += 1
        }
        let prefix = markerLine ? ContainerPrefix.tokenize(source.lineBytes(line)) : nil
        if let prefix, !prefix.tokens.isEmpty {
            return prefix.restString
        }
        for link in chain {
            switch link {
            case .quote:
                var q = p
                var spaces = 0
                while q < bytes.count, bytes[q] == 0x20, spaces < 3 {
                    q += 1
                    spaces += 1
                }
                guard q < bytes.count, bytes[q] == UInt8(ascii: ">") else { continue }
                while p < q { advance() }
                advance()
                if p < bytes.count, bytes[p] == 0x20 || bytes[p] == 0x09 { advance() }
            case .item(let item):
                guard let contentColumn = item.contentColumn else { continue }
                while p < bytes.count, column < contentColumn, bytes[p] == 0x20 || bytes[p] == 0x09 {
                    advance()
                }
            }
        }
        return String(decoding: bytes[p...], as: UTF8.self)
    }
}
