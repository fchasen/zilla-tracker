import Foundation

public enum CodeLanguageRegistry {
    public static let all: [CodeLanguage] = [
        .javascript,
        .typescript,
        .python,
        .rust
    ]

    public static func detect(path: String) -> CodeLanguage {
        let fileName = (path as NSString).lastPathComponent
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return .plain }
        return all.first { $0.extensions.contains(ext) } ?? .plain
    }
}
