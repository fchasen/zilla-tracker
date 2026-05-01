import SwiftUI
import FolioHighlight

struct ExpandContextRow: View {
    let direction: ExpandDirection
    let hiddenCount: Int
    let theme: HighlightTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: direction == .up ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(.caption2, design: .monospaced))
                Spacer(minLength: 0)
            }
            .foregroundColor(Color(theme.lineNumber))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(theme.contextGutter))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        if hiddenCount > 0 {
            return hiddenCount == 1 ? "1 hidden line" : "\(hiddenCount) hidden lines"
        }
        return direction == .up ? "Show more above" : "Show more below"
    }
}
