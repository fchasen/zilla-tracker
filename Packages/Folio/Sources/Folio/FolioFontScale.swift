import SwiftUI

private struct FolioFontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    public var folioFontScale: Double {
        get { self[FolioFontScaleKey.self] }
        set { self[FolioFontScaleKey.self] = newValue }
    }
}

extension Font.TextStyle {
    var folioBaseSize: CGFloat {
        #if os(macOS)
        switch self {
        case .largeTitle:  return 26
        case .title:       return 22
        case .title2:      return 17
        case .title3:      return 15
        case .headline:    return 13
        case .body:        return 13
        case .callout:     return 12
        case .subheadline: return 11
        case .footnote:    return 10
        case .caption:     return 10
        case .caption2:    return 10
        @unknown default:  return 13
        }
        #else
        switch self {
        case .largeTitle:  return 34
        case .title:       return 28
        case .title2:      return 22
        case .title3:      return 20
        case .headline:    return 17
        case .body:        return 17
        case .callout:     return 16
        case .subheadline: return 15
        case .footnote:    return 13
        case .caption:     return 12
        case .caption2:    return 11
        @unknown default:  return 17
        }
        #endif
    }
}

extension View {
    func scaledFont(
        _ style: Font.TextStyle,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> some View {
        modifier(FolioScaledFontModifier(style: style, weight: weight, design: design))
    }
}

private struct FolioScaledFontModifier: ViewModifier {
    @Environment(\.folioFontScale) private var scale
    let style: Font.TextStyle
    let weight: Font.Weight?
    let design: Font.Design

    func body(content: Content) -> some View {
        var font = Font.system(size: style.folioBaseSize * scale, design: design)
        if let weight {
            font = font.weight(weight)
        } else if style == .headline {
            font = font.weight(.semibold)
        }
        return content.font(font)
    }
}
