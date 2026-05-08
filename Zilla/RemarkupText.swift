import SwiftUI
import PhabricatorKit
import Textual

struct RemarkupText: View {
    let source: String

    var body: some View {
        StructuredText(markdown: CommentMarkdown.autolinkReferences(in: Remarkup.toCommonMark(source)))
    }
}
