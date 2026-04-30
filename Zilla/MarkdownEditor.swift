//
//  MarkdownEditor.swift
//  Zilla
//
//  Thin wrapper around `Marginalia` that preserves the prior `MarkdownEditor`
//  call sites — header label, min height, disabled flag, empty preview label,
//  dialect — while delegating editing, syntax highlighting, and the toolbar
//  to the Marginalia package.
//

import SwiftUI
import BugzillaKit
import Marginalia
import PhabricatorKit

enum TextDialect {
    case commonMark
    case remarkup
}

struct MarkdownEditor: View {
    @Binding var text: String
    var headerLabel: String? = nil
    var minHeight: CGFloat = 96
    var isDisabled: Bool = false
    var emptyPreviewLabel: String = "Nothing to preview yet."
    var dialect: TextDialect = .commonMark

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let headerLabel {
                Text(headerLabel)
                    .font(.headline)
            }
            Marginalia(text: $text)
                .marginaliaDialect(marginaliaDialect)
                .marginaliaPreviewRenderer(previewRenderer)
                .frame(minHeight: minHeight)
                .disabled(isDisabled)
        }
    }

    private var marginaliaDialect: Highlighter.Dialect {
        switch dialect {
        case .commonMark: return .commonMark
        case .remarkup:   return .remarkup
        }
    }

    private var previewRenderer: MarginaliaPreviewRenderer {
        { source, dialect in
            let normalized: String
            switch dialect {
            case .commonMark: normalized = source
            case .remarkup:   normalized = Remarkup.toCommonMark(source)
            }
            if let attr = try? AttributedString(markdown: normalized) {
                return attr
            }
            return AttributedString(normalized)
        }
    }
}
