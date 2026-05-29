import SwiftUI
import PhabricatorKit

struct RemarkupText: View {
    let source: String

    var body: some View {
        ZillaMarkdownText(markdown: CommentMarkdown.autolinkReferences(in: Remarkup.toCommonMark(source)))
    }
}
