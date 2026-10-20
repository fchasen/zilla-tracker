import Foundation
import CoreGraphics
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public final class TableAttachment: NSTextAttachment, MarkdownSourceAttachment {
    public var markdownSource: String
    public var contentKind: String = AtomKind.table
    public let rows: [[NSAttributedString]]
    public let alignments: [PresentationIntent.TableColumn.Alignment]
    public var font: PlatformFont { didSet { invalidateLayout() } }
    public var monospaceFont: PlatformFont { didSet { invalidateLayout() } }
    public var textColor: PlatformColor { didSet { invalidateLayout() } }
    public var palette: MarkdownEditorTheme.TablePalette { didSet { invalidateLayout() } }

    static let cellPadding = CGSize(width: 8, height: 4)
    static let minimumColumnWidth: CGFloat = 48

    private var cachedLayout: Layout?

    public init(
        markdownSource: String,
        rows: [[NSAttributedString]],
        alignments: [PresentationIntent.TableColumn.Alignment],
        theme: MarkdownEditorTheme = .default
    ) {
        self.markdownSource = markdownSource
        self.rows = rows
        self.alignments = alignments
        self.font = theme.bodyFont
        self.monospaceFont = theme.monospaceFont
        self.textColor = theme.foregroundColor
        self.palette = theme.tablePalette
        super.init(data: nil, ofType: nil)
    }

    public required init?(coder: NSCoder) {
        let theme = MarkdownEditorTheme.default
        self.markdownSource = ""
        self.rows = []
        self.alignments = []
        self.font = theme.bodyFont
        self.monospaceFont = theme.monospaceFont
        self.textColor = theme.foregroundColor
        self.palette = theme.tablePalette
        super.init(coder: coder)
    }

    public func apply(theme: MarkdownEditorTheme) {
        font = theme.bodyFont
        monospaceFont = theme.monospaceFont
        textColor = theme.foregroundColor
        palette = theme.tablePalette
    }

    public var columnCount: Int { rows.map(\.count).max() ?? 0 }

    struct Layout {
        let availableWidth: CGFloat
        let columnWidths: [CGFloat]
        let rowHeights: [CGFloat]
        let cells: [[NSAttributedString]]

        var size: CGSize {
            CGSize(width: columnWidths.reduce(0, +), height: rowHeights.reduce(0, +))
        }
    }

    private func invalidateLayout() {
        cachedLayout = nil
    }

    func layout(availableWidth: CGFloat) -> Layout {
        let width = max(availableWidth, Self.minimumColumnWidth)
        if let cachedLayout, cachedLayout.availableWidth == width { return cachedLayout }
        let count = columnCount
        let cells = rows.enumerated().map { rowIndex, row in
            (0..<count).map { column in
                styledCell(column < row.count ? row[column] : NSAttributedString(), header: rowIndex == 0, column: column)
            }
        }
        let padding = Self.cellPadding
        var natural = [CGFloat](repeating: Self.minimumColumnWidth, count: count)
        for row in cells {
            for (column, cell) in row.enumerated() {
                let size = cell.boundingRect(
                    with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin],
                    context: nil
                ).size
                natural[column] = max(natural[column], ceil(size.width) + padding.width * 2)
            }
        }
        let total = natural.reduce(0, +)
        let widths = total > width ? Self.fit(natural, into: width) : natural
        let heights = cells.map { row in
            row.enumerated().reduce(ceil(font.lineHeightForTable) + padding.height * 2) { tallest, entry in
                let constrained = max(1, widths[entry.offset] - padding.width * 2)
                let height = entry.element.boundingRect(
                    with: CGSize(width: constrained, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin],
                    context: nil
                ).height
                return max(tallest, ceil(height) + padding.height * 2)
            }
        }
        let layout = Layout(availableWidth: width, columnWidths: widths, rowHeights: heights, cells: cells)
        cachedLayout = layout
        return layout
    }

    static func fit(_ natural: [CGFloat], into width: CGFloat) -> [CGFloat] {
        var widths = natural
        var flexible = Set(natural.indices)
        var budget = width
        while !flexible.isEmpty {
            let flexibleTotal = flexible.reduce(CGFloat(0)) { $0 + natural[$1] }
            guard flexibleTotal > 0 else { break }
            let scale = max(0, budget) / flexibleTotal
            let clamped = flexible.filter { natural[$0] * scale < min(natural[$0], minimumColumnWidth) }
            guard !clamped.isEmpty else {
                for column in flexible {
                    widths[column] = floor(natural[column] * scale)
                }
                break
            }
            for column in clamped {
                widths[column] = min(natural[column], minimumColumnWidth)
                budget -= widths[column]
                flexible.remove(column)
            }
        }
        return widths
    }

    private func styledCell(_ cell: NSAttributedString, header: Bool, column: Int) -> NSAttributedString {
        let styled = NSMutableAttributedString(attributedString: cell)
        let paragraph = NSMutableParagraphStyle()
        switch column < alignments.count ? alignments[column] : .left {
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        default: paragraph.alignment = .natural
        }
        paragraph.lineBreakMode = .byWordWrapping
        let full = NSRange(location: 0, length: styled.length)
        styled.addAttributes([.paragraphStyle: paragraph, .foregroundColor: textColor], range: full)
        styled.removeAttribute(.link, range: full)
        for index in 0..<styled.length {
            let intent = styled.markdownInlineIntent(at: index)
            var traits: FontTraits = header ? [.bold] : []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            let base = intent.contains(.code) ? monospaceFont : font
            var attributes: [NSAttributedString.Key: Any] = [
                .font: traits.isEmpty ? base : base.withFontTraits(traits)
            ]
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            styled.addAttributes(attributes, range: NSRange(location: index, length: 1))
        }
        styled.removeAttribute(.markdownInlineIntent, range: full)
        return styled
    }

    public override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        attachmentBounds(for: textContainer, proposedLineFragment: proposedLineFragment, glyphPosition: position, characterIndex: 0)
    }

    public override func image(
        for bounds: CGRect,
        attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> PlatformImage? {
        image(forBounds: bounds, textContainer: textContainer, characterIndex: 0)
    }

    public override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let size = layout(availableWidth: Self.availableWidth(lineFrag: lineFrag, textContainer: textContainer)).size
        return CGRect(origin: .zero, size: CGSize(width: ceil(size.width) + 1, height: ceil(size.height) + 1))
    }

    public override func image(
        forBounds imageBounds: CGRect,
        textContainer: NSTextContainer?,
        characterIndex charIndex: Int
    ) -> PlatformImage? {
        let layout = layout(availableWidth: max(1, imageBounds.width - 1))
        return Self.renderImage(size: imageBounds.size) { rect in
            self.draw(layout, in: rect)
        }
    }

    static func availableWidth(lineFrag: CGRect, textContainer: NSTextContainer?) -> CGFloat {
        if lineFrag.width > 0, lineFrag.width < .greatestFiniteMagnitude / 2 { return lineFrag.width }
        if let width = textContainer?.size.width, width > 0, width < .greatestFiniteMagnitude / 2 { return width }
        return 480
    }

    static func renderImage(size: CGSize, _ draw: @escaping (CGRect) -> Void) -> PlatformImage {
        #if canImport(AppKit) && os(macOS)
        return NSImage(size: size, flipped: true) { rect in
            draw(rect)
            return true
        }
        #else
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(CGRect(origin: .zero, size: size))
        }
        #endif
    }

    private func draw(_ layout: Layout, in rect: CGRect) {
        let size = layout.size
        let frame = CGRect(x: rect.minX + 0.5, y: rect.minY + 0.5, width: size.width, height: size.height)
        var y = frame.minY
        for (rowIndex, height) in layout.rowHeights.enumerated() {
            let rowRect = CGRect(x: frame.minX, y: y, width: frame.width, height: height)
            if rowIndex == 0 {
                palette.headerBackground.setFill()
                Self.fill(rowRect)
            } else if rowIndex % 2 == 0 {
                palette.bodyAltBackground.setFill()
                Self.fill(rowRect)
            }
            var x = frame.minX
            for (column, width) in layout.columnWidths.enumerated() {
                let cellRect = CGRect(x: x, y: y, width: width, height: height)
                    .insetBy(dx: Self.cellPadding.width, dy: Self.cellPadding.height)
                layout.cells[rowIndex][column].draw(
                    with: cellRect,
                    options: [.usesLineFragmentOrigin],
                    context: nil
                )
                x += width
            }
            y += height
        }
        palette.separator.setStroke()
        var x = frame.minX
        for width in layout.columnWidths.dropLast() {
            x += width
            Self.line(from: CGPoint(x: x, y: frame.minY), to: CGPoint(x: x, y: frame.maxY))
        }
        y = frame.minY
        for height in layout.rowHeights.dropLast() {
            y += height
            Self.line(from: CGPoint(x: frame.minX, y: y), to: CGPoint(x: frame.maxX, y: y))
        }
        palette.border.setStroke()
        Self.stroke(frame)
    }

    private static func fill(_ rect: CGRect) {
        #if canImport(AppKit) && os(macOS)
        NSBezierPath(rect: rect).fill()
        #else
        UIBezierPath(rect: rect).fill()
        #endif
    }

    private static func stroke(_ rect: CGRect) {
        #if canImport(AppKit) && os(macOS)
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        path.stroke()
        #else
        let path = UIBezierPath(rect: rect)
        path.lineWidth = 1
        path.stroke()
        #endif
    }

    private static func line(from start: CGPoint, to end: CGPoint) {
        #if canImport(AppKit) && os(macOS)
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 1
        path.stroke()
        #else
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        path.lineWidth = 1
        path.stroke()
        #endif
    }
}

extension PlatformFont {
    var lineHeightForTable: CGFloat {
        ascender - descender + leading
    }
}
