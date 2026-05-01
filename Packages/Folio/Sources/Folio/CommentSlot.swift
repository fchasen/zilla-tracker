import SwiftUI
import FolioModel
import FolioHighlight

struct CommentSlot: View {
    let mark: FolioCommentMark?
    let theme: HighlightTheme
    let isHovered: Bool
    let onMarkTap: (() -> Void)?
    let onCreate: (() -> Void)?

    private let width: CGFloat = 18

    var body: some View {
        Color.clear
            .frame(width: width)
            .overlay(alignment: .center) {
                slotContent
            }
    }

    @ViewBuilder
    private var slotContent: some View {
        if let mark {
            Button { onMarkTap?() } label: {
                bubble(count: mark.count)
            }
            .buttonStyle(.plain)
            .help(mark.count > 1 ? "\(mark.count) comments" : "1 comment")
        } else if isHovered, let onCreate {
            Button(action: onCreate) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(theme.commentMark))
                    .frame(width: width - 2, height: 14)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(theme.commentMarkBackground))
                    )
            }
            .buttonStyle(.plain)
            .help("Add comment")
        }
    }

    @ViewBuilder
    private func bubble(count: Int) -> some View {
        if count > 1 {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(theme.commentMark))
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 12)
                    .padding(.horizontal, 2)
                    .background(
                        Capsule().fill(Color(theme.commentMark))
                    )
                    .offset(x: 6, y: -4)
            }
            .frame(width: width, height: 14)
        } else {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 10))
                .foregroundColor(Color(theme.commentMark))
                .frame(width: width, height: 14)
        }
    }
}
