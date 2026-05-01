import SwiftUI
import FolioHighlight

struct DiagonalHatch: View {
    let color: PlatformColor
    let spacing: CGFloat
    let lineWidth: CGFloat

    init(color: PlatformColor, spacing: CGFloat = 6, lineWidth: CGFloat = 1) {
        self.color = color
        self.spacing = spacing
        self.lineWidth = lineWidth
    }

    var body: some View {
        Canvas { ctx, size in
            let h = size.height
            let w = size.width
            let strideStart = -h
            let strideEnd = w + h
            for x in stride(from: strideStart, to: strideEnd, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + h, y: h))
                ctx.stroke(path, with: .color(Color(color)), lineWidth: lineWidth)
            }
        }
    }
}
