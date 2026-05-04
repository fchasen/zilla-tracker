import Foundation

enum CaptureMapping {
    static func color(for captureName: String, theme: HighlightTheme) -> PlatformColor? {
        let head = captureName.split(separator: ".").first.map(String.init) ?? captureName
        switch head {
        case "keyword": return theme.keyword
        case "type": return theme.type
        case "function", "method": return theme.function
        case "variable":
            if captureName.hasPrefix("variable.parameter") { return theme.parameter }
            return theme.variable
        case "parameter": return theme.parameter
        case "string": return theme.string
        case "number": return theme.number
        case "comment": return theme.comment
        case "punctuation": return theme.punctuation
        case "constant": return theme.constant
        case "attribute", "tag": return theme.attribute
        case "operator": return theme.punctuation
        case "property": return theme.variable
        case "label": return theme.attribute
        case "text":
            switch captureName {
            case "text.title": return theme.keyword
            case "text.literal": return theme.string
            case "text.uri": return theme.attribute
            case "text.reference": return theme.function
            default: return theme.attribute
            }
        default: return nil
        }
    }
}
