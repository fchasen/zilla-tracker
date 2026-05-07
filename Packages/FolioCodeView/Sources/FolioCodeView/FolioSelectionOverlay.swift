import SwiftUI
import FolioModel

struct FolioSelectableCell: Equatable, Hashable {
    let id: String
    let line: Int
    let side: AnchorRange.Side
    let frame: CGRect
}

struct FolioSelectableCellsPreference: PreferenceKey {
    static var defaultValue: [FolioSelectableCell] = []
    static func reduce(value: inout [FolioSelectableCell], nextValue: () -> [FolioSelectableCell]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func reportingFolioCell(
        id: String,
        line: Int?,
        side: AnchorRange.Side,
        in space: String,
        enabled: Bool = true
    ) -> some View {
        Group {
            if enabled {
                self.background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: FolioSelectableCellsPreference.self,
                            value: line.map { ln in
                                [FolioSelectableCell(id: id, line: ln, side: side, frame: proxy.frame(in: .named(space)))]
                            } ?? []
                        )
                    }
                )
            } else {
                self
            }
        }
    }
}

extension FolioSelectionMath {
    static let coordinateSpaceName = "folio-rows"
}

enum FolioSelectionMath {
    static func cell(at point: CGPoint, in cells: [FolioSelectableCell]) -> FolioSelectableCell? {
        cells.first { $0.frame.contains(point) }
    }

    static func selection(
        from start: CGPoint,
        to current: CGPoint,
        cells: [FolioSelectableCell]
    ) -> FolioLineSelection? {
        guard let startCell = cell(at: start, in: cells) else { return nil }
        let endCell = cells
            .filter { $0.side == startCell.side }
            .min(by: { abs($0.frame.midY - current.y) < abs($1.frame.midY - current.y) })
            ?? startCell
        return FolioLineSelection(
            startLine: startCell.line,
            endLine: endCell.line,
            side: startCell.side
        )
    }
}
