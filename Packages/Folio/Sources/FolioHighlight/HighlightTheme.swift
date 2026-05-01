import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
public typealias PlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
#endif

public struct HighlightTheme: Sendable {
    public var keyword: PlatformColor
    public var type: PlatformColor
    public var function: PlatformColor
    public var variable: PlatformColor
    public var parameter: PlatformColor
    public var string: PlatformColor
    public var number: PlatformColor
    public var comment: PlatformColor
    public var punctuation: PlatformColor
    public var attribute: PlatformColor
    public var constant: PlatformColor
    public var foreground: PlatformColor

    public var addedRow: PlatformColor
    public var removedRow: PlatformColor
    public var contextRow: PlatformColor
    public var addedGutter: PlatformColor
    public var removedGutter: PlatformColor
    public var contextGutter: PlatformColor

    public var lineNumber: PlatformColor
    public var marker: PlatformColor
    public var headerBackground: PlatformColor
    public var border: PlatformColor

    public var emptyMirror: PlatformColor
    public var emptyMirrorHatch: PlatformColor
    public var commentMark: PlatformColor
    public var commentMarkBackground: PlatformColor
    public var selectionFill: PlatformColor

    public var addedAccent: PlatformColor
    public var removedAccent: PlatformColor
    public var addedLineNumber: PlatformColor
    public var removedLineNumber: PlatformColor
    public var intralineAdded: PlatformColor
    public var intralineRemoved: PlatformColor

    public init(
        keyword: PlatformColor,
        type: PlatformColor,
        function: PlatformColor,
        variable: PlatformColor,
        parameter: PlatformColor,
        string: PlatformColor,
        number: PlatformColor,
        comment: PlatformColor,
        punctuation: PlatformColor,
        attribute: PlatformColor,
        constant: PlatformColor,
        foreground: PlatformColor,
        addedRow: PlatformColor,
        removedRow: PlatformColor,
        contextRow: PlatformColor,
        addedGutter: PlatformColor,
        removedGutter: PlatformColor,
        contextGutter: PlatformColor,
        lineNumber: PlatformColor,
        marker: PlatformColor,
        headerBackground: PlatformColor,
        border: PlatformColor,
        emptyMirror: PlatformColor,
        emptyMirrorHatch: PlatformColor,
        commentMark: PlatformColor,
        commentMarkBackground: PlatformColor,
        selectionFill: PlatformColor,
        addedAccent: PlatformColor,
        removedAccent: PlatformColor,
        addedLineNumber: PlatformColor,
        removedLineNumber: PlatformColor,
        intralineAdded: PlatformColor,
        intralineRemoved: PlatformColor
    ) {
        self.keyword = keyword
        self.type = type
        self.function = function
        self.variable = variable
        self.parameter = parameter
        self.string = string
        self.number = number
        self.comment = comment
        self.punctuation = punctuation
        self.attribute = attribute
        self.constant = constant
        self.foreground = foreground
        self.addedRow = addedRow
        self.removedRow = removedRow
        self.contextRow = contextRow
        self.addedGutter = addedGutter
        self.removedGutter = removedGutter
        self.contextGutter = contextGutter
        self.lineNumber = lineNumber
        self.marker = marker
        self.headerBackground = headerBackground
        self.border = border
        self.emptyMirror = emptyMirror
        self.emptyMirrorHatch = emptyMirrorHatch
        self.commentMark = commentMark
        self.commentMarkBackground = commentMarkBackground
        self.selectionFill = selectionFill
        self.addedAccent = addedAccent
        self.removedAccent = removedAccent
        self.addedLineNumber = addedLineNumber
        self.removedLineNumber = removedLineNumber
        self.intralineAdded = intralineAdded
        self.intralineRemoved = intralineRemoved
    }
}

public extension HighlightTheme {
    static let light = HighlightTheme(
        keyword:    .srgb(0xCF222E),
        type:       .srgb(0x953800),
        function:   .srgb(0x8250DF),
        variable:   .srgb(0x24292F),
        parameter:  .srgb(0x24292F),
        string:     .srgb(0x0A3069),
        number:     .srgb(0x0550AE),
        comment:    .srgb(0x6E7781),
        punctuation:.srgb(0x24292F),
        attribute:  .srgb(0x116329),
        constant:   .srgb(0x0550AE),
        foreground: .srgb(0x24292F),
        addedRow:   .srgb(0x1F883D, alpha: 0.12),
        removedRow: .srgb(0xCF222E, alpha: 0.10),
        contextRow: .srgb(0xFFFFFF, alpha: 0),
        addedGutter:   .srgb(0x1F883D, alpha: 0.20),
        removedGutter: .srgb(0xCF222E, alpha: 0.18),
        contextGutter: .srgb(0xF6F8FA),
        lineNumber: .srgb(0x57606A),
        marker:     .srgb(0x57606A),
        headerBackground: .srgb(0xF6F8FA),
        border:     .srgb(0xD0D7DE),
        emptyMirror:           .srgb(0xF6F8FA, alpha: 0.6),
        emptyMirrorHatch:      .srgb(0x57606A, alpha: 0.18),
        commentMark:           .srgb(0x0969DA),
        commentMarkBackground: .srgb(0xDDEEFF),
        selectionFill:         .srgb(0x0969DA, alpha: 0.12),
        addedAccent:           .srgb(0x1F883D),
        removedAccent:         .srgb(0xCF222E),
        addedLineNumber:       .srgb(0x1F883D),
        removedLineNumber:     .srgb(0xCF222E),
        intralineAdded:        .srgb(0x1F883D, alpha: 0.32),
        intralineRemoved:      .srgb(0xCF222E, alpha: 0.32)
    )

    static let dark = HighlightTheme(
        keyword:    .srgb(0xFF7B72),
        type:       .srgb(0xFFA657),
        function:   .srgb(0xD2A8FF),
        variable:   .srgb(0xC9D1D9),
        parameter:  .srgb(0xC9D1D9),
        string:     .srgb(0xA5D6FF),
        number:     .srgb(0x79C0FF),
        comment:    .srgb(0x8B949E),
        punctuation:.srgb(0xC9D1D9),
        attribute:  .srgb(0x7EE787),
        constant:   .srgb(0x79C0FF),
        foreground: .srgb(0xC9D1D9),
        addedRow:   .srgb(0x3FB950, alpha: 0.16),
        removedRow: .srgb(0xF85149, alpha: 0.16),
        contextRow: .srgb(0x000000, alpha: 0),
        addedGutter:   .srgb(0x3FB950, alpha: 0.25),
        removedGutter: .srgb(0xF85149, alpha: 0.25),
        contextGutter: .srgb(0x161B22),
        lineNumber: .srgb(0x8B949E),
        marker:     .srgb(0x8B949E),
        headerBackground: .srgb(0x161B22),
        border:     .srgb(0x30363D),
        emptyMirror:           .srgb(0x161B22, alpha: 0.6),
        emptyMirrorHatch:      .srgb(0x8B949E, alpha: 0.18),
        commentMark:           .srgb(0x58A6FF),
        commentMarkBackground: .srgb(0x1F2A3D),
        selectionFill:         .srgb(0x58A6FF, alpha: 0.18),
        addedAccent:           .srgb(0x3FB950),
        removedAccent:         .srgb(0xF85149),
        addedLineNumber:       .srgb(0x3FB950),
        removedLineNumber:     .srgb(0xF85149),
        intralineAdded:        .srgb(0x3FB950, alpha: 0.35),
        intralineRemoved:      .srgb(0xF85149, alpha: 0.35)
    )
}


extension PlatformColor {
    static func srgb(_ rgb: UInt32, alpha: CGFloat = 1) -> PlatformColor {
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        #if canImport(AppKit) && os(macOS)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
        #else
        return UIColor(red: r, green: g, blue: b, alpha: alpha)
        #endif
    }
}
