import Foundation
import SwiftUI
import Textual

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ZillaMarkdownText: View {
    let markdown: String

    var body: some View {
        StructuredText(markdown, parser: ZillaLinkMarkdownParser())
            .textual.textSelection(.enabled)
    }
}

@MainActor
struct ZillaLinkMarkdownParser: MarkupParser {
    func attributedString(for input: String) throws -> AttributedString {
        let parser = AttributedStringMarkdownParser(baseURL: nil)
        return ZillaLinkChipTarget.replacingLinks(in: try parser.attributedString(for: input))
    }
}

struct ZillaLinkChipTarget: Hashable, Sendable {
    let url: URL
    let label: String
    let systemImage: String
    let kind: Kind

    enum Kind: Hashable, Sendable {
        case searchfox
        case bug
        case attachment
    }

    static func target(for url: URL) -> Self? {
        if let target = searchfoxTarget(for: url) {
            return target
        }
        return bugzillaTarget(for: url)
    }

    static func replacingLinks(in attributedString: AttributedString) -> AttributedString {
        var output = AttributedString()

        for run in attributedString.runs {
            if let link = run.link, let target = target(for: link) {
                output.append(attachmentString(for: target, attributes: run.attributes))
                continue
            }

            if run.link == nil, !run.isZillaPreformatted {
                let text = String(attributedString[run.range].characters)
                let replacements = inlineReplacements(in: text)
                if !replacements.isEmpty {
                    appendReplacingPlainTextMatches(
                        in: text,
                        replacements: replacements,
                        attributes: run.attributes,
                        into: &output
                    )
                    continue
                }
            }

            output.append(attributedString[run.range])
        }

        return output
    }

    private static func attachmentString(for target: ZillaLinkChipTarget, attributes: AttributeContainer) -> AttributedString {
        var replacement = AttributedString("\u{FFFC}", attributes: attributes)
        replacement.link = target.url
        replacement.textual.attachment = AnyAttachment(ZillaLinkChipAttachment(target: target))
        return replacement
    }

    private static func attachmentString(
        for target: ZillaCommentLabelTarget,
        attributes: AttributeContainer
    ) -> AttributedString {
        var replacement = AttributedString("\u{FFFC}", attributes: attributes)
        replacement.textual.attachment = AnyAttachment(ZillaCommentLabelAttachment(target: target))
        return replacement
    }

    private static func appendReplacingPlainTextMatches(
        in text: String,
        replacements: [(range: NSRange, replacement: ZillaInlineReplacement)],
        attributes: AttributeContainer,
        into output: inout AttributedString
    ) {
        let nsText = text as NSString
        var cursor = 0

        for replacement in replacements {
            guard replacement.range.location >= cursor else { continue }
            if replacement.range.location > cursor {
                let prefixRange = NSRange(location: cursor, length: replacement.range.location - cursor)
                output.append(AttributedString(nsText.substring(with: prefixRange), attributes: attributes))
            }

            switch replacement.replacement {
            case .chip(let target):
                output.append(attachmentString(for: target, attributes: attributes))
            case .commentLabel(let target):
                output.append(attachmentString(for: target, attributes: attributes))
            }
            cursor = replacement.range.location + replacement.range.length
        }

        if cursor < nsText.length {
            output.append(AttributedString(nsText.substring(from: cursor), attributes: attributes))
        }
    }

    /// `appendReplacingPlainTextMatches` walks a single forward cursor, so the
    /// two scanners' results have to be merged in ascending order.
    private static func inlineReplacements(
        in text: String
    ) -> [(range: NSRange, replacement: ZillaInlineReplacement)] {
        let chips = supportedURLMatches(in: text).map { ($0.range, ZillaInlineReplacement.chip($0.target)) }
        let labels = CommentLabels.matches(in: text).map {
            ($0.range, ZillaInlineReplacement.commentLabel(
                ZillaCommentLabelTarget(icon: $0.icon, name: $0.name)
            ))
        }
        return (chips + labels)
            .sorted { $0.0.location < $1.0.location }
            .map { (range: $0.0, replacement: $0.1) }
    }

    private static func supportedURLMatches(in text: String) -> [(range: NSRange, target: ZillaLinkChipTarget)] {
        let pattern = #"https?://(?:searchfox\.org|bugzilla\.mozilla\.org)[^\s<>\]\)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            var urlRange = match.range
            while urlRange.length > 0 {
                let lastIndex = urlRange.location + urlRange.length - 1
                let scalar = nsText.character(at: lastIndex)
                if scalar == 46 || scalar == 44 || scalar == 59 || scalar == 58 {
                    urlRange.length -= 1
                } else {
                    break
                }
            }
            guard urlRange.length > 0,
                  let url = URL(string: nsText.substring(with: urlRange)),
                  let target = target(for: url) else {
                return nil
            }
            return (urlRange, target)
        }
    }

    private static func searchfoxTarget(for url: URL) -> Self? {
        guard url.host?.lowercased() == "searchfox.org",
              let fileName = searchfoxFileName(for: url) else {
            return nil
        }

        let line = searchfoxLineLabel(from: url.fragment)
        let label = line.map { "\(fileName):\($0)" } ?? fileName
        return Self(url: url, label: label, systemImage: "doc.text.magnifyingglass", kind: .searchfox)
    }

    private static func searchfoxFileName(for url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        let pathStart: Int?

        if let sourceIndex = components.firstIndex(of: "source"), sourceIndex + 1 < components.count {
            pathStart = sourceIndex + 1
        } else if let revIndex = components.firstIndex(of: "rev"), revIndex + 2 < components.count {
            pathStart = revIndex + 2
        } else {
            pathStart = nil
        }

        guard let pathStart else { return nil }
        let pathComponents = components[pathStart...].map { $0.removingPercentEncoding ?? $0 }
        return pathComponents.last?.nilIfEmpty
    }

    private static func searchfoxLineLabel(from fragment: String?) -> String? {
        guard let fragment = fragment?.removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines),
              let match = fragment.firstMatch(of: #/^[Ll]?(\d+)(?:-[Ll]?(\d+))?$/#) else {
            return nil
        }

        let start = String(match.output.1)
        guard let end = match.output.2.map(String.init), end != start else {
            return start
        }
        return "\(start)-\(end)"
    }

    private static func bugzillaTarget(for url: URL) -> Self? {
        guard url.host?.lowercased() == "bugzilla.mozilla.org" else { return nil }

        switch url.path {
        case "/show_bug.cgi":
            guard let id = queryItem("id", in: url)?.digitsOnly else { return nil }
            return Self(url: url, label: "Bug \(id)", systemImage: "ant", kind: .bug)
        case "/attachment.cgi":
            guard let id = queryItem("id", in: url)?.digitsOnly else { return nil }
            return Self(url: url, label: "Attachment \(id)", systemImage: "paperclip", kind: .attachment)
        default:
            return nil
        }
    }

    private static func queryItem(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}

/// A conventional-comment label. Rendered as a bare glyph — no capsule, no
/// text — because the icon alone reads as the label, and the nine of them are
/// distinguishable at a glance. Bug and Searchfox chips keep their capsules,
/// where an ant on its own would say nothing.
nonisolated struct ZillaCommentLabelTarget: Hashable, Sendable {
    let icon: String
    let name: String

    var systemImage: String { PhabricatorIcons.systemImage(for: icon) }
}

private enum ZillaInlineReplacement {
    case chip(ZillaLinkChipTarget)
    case commentLabel(ZillaCommentLabelTarget)
}

private struct ZillaCommentLabelAttachment: Attachment {
    let target: ZillaCommentLabelTarget

    var description: String {
        target.name
    }

    var selectionStyle: AttachmentSelectionStyle {
        .text
    }

    var body: some View {
        ZillaCommentLabelView(target: target)
    }

    func baselineOffset(in _: TextEnvironmentValues) -> CGFloat {
        -1
    }

    func sizeThatFits(_: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
        // Textual scales the drawn symbol into exactly this rect, so the ratio
        // has to match the glyph's own or it distorts.
        CGSize(width: 15, height: 13)
    }
}

private struct ZillaCommentLabelView: View {
    let target: ZillaCommentLabelTarget

    var body: some View {
        Image(systemName: target.systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .help(target.name)
    }
}

private struct ZillaLinkChipAttachment: Attachment {
    let target: ZillaLinkChipTarget

    var description: String {
        target.label
    }

    var selectionStyle: AttachmentSelectionStyle {
        .text
    }

    var body: some View {
        ZillaLinkChipView(target: target)
    }

    func baselineOffset(in _: TextEnvironmentValues) -> CGFloat {
        -2
    }

    func sizeThatFits(_: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
        let labelWidth = Self.labelWidth(target.label)
        return CGSize(width: ceil(labelWidth + 31), height: 18)
    }

    private static func labelWidth(_ label: String) -> CGFloat {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        #else
        let font = UIFont.systemFont(ofSize: 11, weight: .medium)
        #endif
        return (label as NSString).size(withAttributes: [.font: font]).width
    }
}

private struct ZillaLinkChipView: View {
    let target: ZillaLinkChipTarget

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: target.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(target.label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(height: 18)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }

    private var tint: Color {
        switch target.kind {
        case .searchfox:
            return .blue
        case .bug:
            return .orange
        case .attachment:
            return .secondary
        }
    }
}

private extension AttributedString.Runs.Run {
    var isZillaPreformatted: Bool {
        if let intent = self.inlinePresentationIntent,
           intent.contains(.code) || intent.contains(.inlineHTML) || intent.contains(.blockHTML) {
            return true
        }

        if case .codeBlock = self.presentationIntent?.components.first?.kind {
            return true
        }
        return false
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var digitsOnly: String? {
        guard !isEmpty, allSatisfy(\.isNumber) else { return nil }
        return self
    }
}
