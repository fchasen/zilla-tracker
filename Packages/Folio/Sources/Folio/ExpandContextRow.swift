import SwiftUI
import FolioHighlight

public struct ExpandContextRow: View {
    public let label: String
    public let theme: HighlightTheme
    public let leadingGutterWidth: CGFloat
    public let trailingGutterWidth: CGFloat?
    public let onExpandFromTop: (() -> Void)?
    public let onExpandFromBottom: (() -> Void)?

    @ScaledMetric(relativeTo: .caption2) private var chevronSize: CGFloat = 11

    public init(
        label: String,
        theme: HighlightTheme,
        leadingGutterWidth: CGFloat = 0,
        trailingGutterWidth: CGFloat? = nil,
        onExpandFromTop: (() -> Void)? = nil,
        onExpandFromBottom: (() -> Void)? = nil
    ) {
        self.label = label
        self.theme = theme
        self.leadingGutterWidth = leadingGutterWidth
        self.trailingGutterWidth = trailingGutterWidth
        self.onExpandFromTop = onExpandFromTop
        self.onExpandFromBottom = onExpandFromBottom
    }

    public var body: some View {
        Group {
            if let trailingGutterWidth {
                splitLayout(trailing: trailingGutterWidth)
            } else {
                singleLayout
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var singleLayout: some View {
        HStack(spacing: 0) {
            chevronGutter
                .frame(width: max(leadingGutterWidth, 32))
                .background(Color(theme.contextGutter))
            labelArea
        }
    }

    private func splitLayout(trailing: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                chevronGutter
                    .frame(width: max(leadingGutterWidth, 32))
                    .background(Color(theme.contextGutter))
                labelArea
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Color(theme.border))
                .frame(width: 1)
            HStack(spacing: 0) {
                Color(theme.contextGutter)
                    .frame(width: max(trailing, 32))
                Color(theme.contextRow)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var chevronGutter: some View {
        switch (onExpandFromTop, onExpandFromBottom) {
        case let (top?, bottom?):
            VStack(spacing: 0) {
                chevronButton(systemName: "chevron.down", action: top)
                chevronButton(systemName: "chevron.up", action: bottom)
            }
        case let (top?, nil):
            chevronButton(systemName: "chevron.down", action: top)
        case let (nil, bottom?):
            chevronButton(systemName: "chevron.up", action: bottom)
        case (nil, nil):
            Color.clear
        }
    }

    private func chevronButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: chevronSize, weight: .semibold))
                .foregroundColor(Color(theme.lineNumber))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var labelArea: some View {
        let actions = [onExpandFromTop, onExpandFromBottom].compactMap { $0 }
        if actions.count == 1 {
            Button(action: actions[0]) { labelContent }
                .buttonStyle(.plain)
        } else {
            labelContent
        }
    }

    public static func unmodifiedLabel(count: Int) -> String {
        if count <= 0 { return "Show more" }
        return count == 1 ? "1 unmodified line" : "\(count) unmodified lines"
    }

    private var labelContent: some View {
        HStack(spacing: 0) {
            Text(label)
                .scaledFont(.caption2, design: .monospaced)
                .foregroundColor(Color(theme.lineNumber))
                .padding(.leading, 10)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(theme.contextRow))
        .contentShape(Rectangle())
    }
}
