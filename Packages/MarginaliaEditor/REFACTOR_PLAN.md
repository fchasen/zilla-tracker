# Marginalia Refactor Plan: BlockSpec + Steps + Decoration Layer

## Why this matters (the bugs we're fixing)

The correctness bugs all share one root cause: **there is no canonical record of "what kind of block is this paragraph?"**. The truth is scattered across:

- `marginaliaBlock` on each character of the paragraph
- `marginaliaListItem` on list-item paragraphs
- `marginaliaListMarker` on the marker prefix only
- `paragraphStyle` (NSParagraphStyle) on the paragraph
- An attachment object on the marker character
- Sometimes encoded into the BlockTag (`heading`, `unorderedListItem`), sometimes into auxiliary fields (`blockquoteDepth`, `level`, `language`)

These have to stay perfectly synchronized. They don't. Visible failures:

1. Typing into a blockquote sometimes loses depth on new chars (`BlockquoteFlowTests.typingIntoBlockquotePreservesDepth`). `normalizeEditedLineAttrs` is a fire-after-the-fact patch that propagates the *first* attr it finds in the line to the whole line; it runs only on edits via `didProcessEditingNotification` with `applyingMarkdown == false`, so any programmatic mutation that fails to set attrs uniformly leaks through.
2. Blockquote rendering is gated on character 0's `blockquoteDepth` (`LayoutManagerDelegate.swift:96-117`). If char 0 has depth=0 but char 1+ has depth=1, the fragment is built as plain.
3. `appendInlineBlock` never emits `BlockTag.blockquote`; it falls into `default: BlockAttribute(tag: .paragraph, ..., blockquoteDepth: segment.blockquoteDepth)`. So `paragraphStyleFor(.blockquote, …)` is dead code in rich mode.
4. List operations round-trip through markdown (`Operations.mutateBlocks`): serialize the affected line(s) back to markdown, mutate the string with regexes, recompile via tree-sitter, replace. Fragile — tree-sitter parse of one paragraph in isolation loses parent context.
5. Cursor placement after `injectEmptyBlockquoteIfNeeded`/`injectEmptyListIfNeeded` is `lineRange.location + line.length - 1`. Correct only by accident.
6. No invariant enforcement. Anywhere code calls `storage.addAttribute(.marginaliaBlock, value: x, range: …)`, it can drift from the rest. The codebase relies on convention.
7. Decorations are baked into storage as character attributes or attachments. Decorative things that shouldn't survive markdown round-trip (search highlights, lint squiggles, comment threads) have nowhere to live.

## Design

### Piece 1 — `BlockSpec` as canonical block identity

```swift
public struct BlockSpec: Equatable, Hashable {
    public let kind: Kind
    public let blockquoteDepth: Int  // 0 = not in a quote
    public let listLevel: Int        // 0 = not nested

    public enum Kind: Equatable, Hashable {
        case paragraph
        case heading(level: Int)
        case unorderedListItem
        case orderedListItem(index: Int)
        case taskListItem(checked: Bool)
        case fencedCode(language: String?)
        case indentedCode
        case horizontalRule
        case htmlBlock
        case linkReferenceDefinition
        case pipeTable
    }
}
```

Stored as a single attribute key `.marginaliaBlockSpec`, applied to every character in the paragraph. `marginaliaBlock` and `marginaliaListItem` go away.

### Piece 2 — `Step` value type + `Transaction`

```swift
public enum Step {
    case replaceText(range: NSRange, with: NSAttributedString)
    case setAttributes(range: NSRange, attrs: [NSAttributedString.Key: Any], replacing: Bool)
    case setBlockSpec(lineRange: NSRange, BlockSpec)
    case toggleInlineMark(range: NSRange, InlineMark)
    case insertParagraph(at: Int, BlockSpec, content: String)
    case demoteToParagraph(lineRange: NSRange)
}

public struct AppliedStep {
    public let inverse: Step
    public let mappedRange: NSRange
    public let affectedLineRange: NSRange
}

public extension Step {
    func apply(to storage: NSTextStorage, env: StepEnvironment) -> AppliedStep
}

public struct Transaction {
    public var steps: [Step]
    public var selectionAfter: NSRange?
    public var label: String?
}

public extension EditorController {
    @discardableResult
    func apply(_ transaction: Transaction) -> AppliedTransaction
}
```

`apply(_:)`:
1. Walks steps, applies each, accumulates inverses in reverse order.
2. Validates: every char has a `BlockSpec`, spec is consistent across the paragraph, marker characters' attachments match the spec's expected marker. Auto-repairs + emits diagnostic on violation.
3. Registers the inverse transaction with `UndoManager`.
4. Sets selection.
5. Notifies `BlockSpecDidChange` observer.

### Piece 3 — `DecorationLayer`

```swift
public protocol DecorationProvider: AnyObject {
    func decorations(in lineRange: NSRange, storage: NSTextStorage) -> [Decoration]
    var decorationsDidChange: ((NSRange) -> Void)? { get set }
}

public struct Decoration {
    public let range: NSRange
    public let kind: DecorationKind
    public let zIndex: Int
}

public enum DecorationKind {
    case blockquoteBar(depth: Int, position: RunPosition)
    case codeBackground(corners: CornerSet)
    case horizontalRule
    case lintMark(severity: Severity, message: String)
    case searchHighlight
    case commentThread(id: UUID)
}

public enum RunPosition { case start, middle, end, single }
```

`BlockSpecDecorationProvider` derives blockquote bars / code backgrounds / horizontal rules from `BlockSpec` walks. `LayoutManagerDelegate` consults the provider; `isFirstInRun`/`isLastInRun` plumbing in fragments goes away.

Inline widgets (bullets, checkboxes, ordered marker) **stay** as NSTextAttachments because they consume horizontal space.

## Phased rollout

**Phase 1** — Introduce `BlockSpec`, run alongside existing attrs.
- `BlockSpec` struct + helpers in `MarginaliaSyntax/BlockSpec.swift`.
- Compiler emits `marginaliaBlockSpec` *in addition to* legacy attrs.
- `EditorController.dump()` → structured snapshot.
- Invariant test: every paragraph has a `BlockSpec` agreeing with legacy `BlockAttribute`.
- No behavior change.

**Phase 2** — Rewire reads to `BlockSpec`, delete legacy.
- `LayoutManagerDelegate`, serializer, `normalizeEditedLineAttrs` read `BlockSpec`.
- Delete `BlockAttribute`, `ListItemAttribute`, `marginaliaBlock`, `marginaliaListItem`.

**Phase 3** — Add `Step` and `Transaction`. Rewrite `Operations` block-level paths.
- `Step.setBlockSpec` is the new path for heading/list/blockquote/code-block toggle.
- `transformList`/`transformBlockquote`/`transformHeading` become `BlockSpec` transformers.
- Markdown round-trip in `mutateBlocks` deleted.

**Phase 4** — Validation pass.
- `Transaction.apply` calls `validate(in:)` after each step.
- `scrubTypedAttributes`, `normalizeEditedLineAttrs`, `demoteEmptyStyledLines` fold into validation.

**Phase 5** — Decoration layer.
- `DecorationProvider` protocol + `BlockSpecDecorationProvider`.
- `LayoutManagerDelegate` consults the provider.

**Phase 6** — Embedder API.
- Public `EditorController.apply(_ transaction:)`.
- Public `Step` constructors. `Operations.toggleBold(...)` etc. become `Step.toggleInlineMark`.

## Files

**New:**
- `Sources/MarginaliaSyntax/BlockSpec.swift`
- `Sources/MarginaliaView/Step.swift`
- `Sources/MarginaliaView/Transaction.swift`
- `Sources/MarginaliaView/DecorationProvider.swift`
- `Sources/MarginaliaView/BlockSpecDecorationProvider.swift`
- `Sources/MarginaliaView/Diagnostics.swift`

**Rewritten:**
- `EditorController.swift` — shrinks to `apply(_:)` + small Step factories.
- `Operations.swift` — block-level becomes `Step.setBlockSpec` factories; inline becomes `Step.toggleInlineMark`.
- `LayoutManagerDelegate.swift` — driven by `DecorationProvider` and `BlockSpec`.
- `MarkdownAttributedCompiler.swift` — `appendInlineBlock` splits into `compileSegment(_:) -> (BlockSpec, NSAttributedString)` + `applyBlockSpec(_:to:)`.
- `AttributedMarkdownSerializer.swift` — reads `BlockSpec` directly.
- `MarginaliaSyntax/BlockSegmenter.swift` — emits `BlockSpec`.

**Deleted:**
- `BlockAttribute`, `ListItemAttribute`.
- `EditorController.normalizeEditedLineAttrs` / `scrubTypedAttributes` / `demoteEmptyStyledLines`.
- Markdown round-trip in `Operations.mutateBlocks` and its `transformList`/etc.
