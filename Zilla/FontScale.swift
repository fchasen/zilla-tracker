import SwiftUI

enum FontScale {
    static let storageKey = "fontScaleStep"
    static let minStep = -3
    static let maxStep = 3
    static let defaultStep = 0

    static func clamp(_ step: Int) -> Int {
        min(max(step, minStep), maxStep)
    }

    static func dynamicTypeSize(for step: Int) -> DynamicTypeSize {
        switch clamp(step) {
        case -3: return .xSmall
        case -2: return .small
        case -1: return .medium
        case  0: return .large
        case  1: return .xLarge
        case  2: return .xxLarge
        case  3: return .xxxLarge
        default: return .large
        }
    }

    static func multiplier(for step: Int) -> Double {
        switch clamp(step) {
        case -3: return 0.823
        case -2: return 0.882
        case -1: return 0.941
        case  0: return 1.0
        case  1: return 1.117
        case  2: return 1.235
        case  3: return 1.353
        default: return 1.0
        }
    }
}

private struct ZillaFontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var zillaFontScale: Double {
        get { self[ZillaFontScaleKey.self] }
        set { self[ZillaFontScaleKey.self] = newValue }
    }
}

extension Font.TextStyle {
    var zillaBaseSize: CGFloat {
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
        modifier(ScaledFontModifier(style: style, weight: weight, design: design))
    }
}

private struct ScaledFontModifier: ViewModifier {
    @Environment(\.zillaFontScale) private var scale
    let style: Font.TextStyle
    let weight: Font.Weight?
    let design: Font.Design

    func body(content: Content) -> some View {
        var font = Font.system(size: style.zillaBaseSize * scale, design: design)
        if let weight {
            font = font.weight(weight)
        } else if style == .headline {
            font = font.weight(.semibold)
        }
        return content.font(font)
    }
}
