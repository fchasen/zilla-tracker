# FolioCodeView

A SwiftUI diff and code viewer (and editor) with tree-sitter syntax highlighting, split / unified diff layouts, intra-line diffing, and inline comment marks. The read-only paths render in TextKit-backed `Text` rows; the editable path uses a TextKit 2 `NSTextView` / `UITextView` with live, incremental syntax highlighting. No `WKWebView`, no JavaScript bundle.

FolioCodeView was built for Zilla's revision-detail screen but is generic: it takes either a parsed diff hunk or a plain string and produces either a list view of rows with comment hooks, expandable context, and selection callbacks (read-only) or a live syntax-highlighted editor (editable).

## Modules

The package vends three libraries you can import individually:

| Library | What it provides |
|---------|------------------|
| `FolioModel` | Pure-Swift, no SwiftUI. Diff line / hunk types, unified-diff parser, intra-line diff, split-row builder, line selections, and the folder that collapses long context regions. |
| `FolioHighlight` | Tree-sitter–based syntax highlighting. Bundled grammars for Swift, JavaScript, TypeScript, Python, Rust, C, C++, JSON, HTML, CSS, and Markdown. `HighlightTheme` carries colors for tokens, gutter, intra-line ranges, and comment marks. |
| `FolioCodeView` | The `FolioView` SwiftUI component. Pulls in both of the above. |

## Requirements

- Swift 5.10+
- macOS 14.0+ / iOS 17.0+

## Installation

This package is consumed locally by Zilla via the Xcode project. To use it from another Swift package:

```swift
dependencies: [
    .package(path: "Packages/FolioCodeView")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "FolioCodeView", package: "FolioCodeView")
    ])
]
```

## Quick start

### Render a unified diff

```swift
import FolioCodeView
import FolioModel

let hunk = UnifiedDiffParser.parse(
    corpus: """
     context line
    -old line
    +new line
     more context
    """,
    oldStart: 10,
    newStart: 10
)

FolioView(
    path: "src/Foo.swift",
    content: .diff(hunk, anchor: nil, mode: .split),
    theme: .light
)
```

### Render a code snippet

```swift
FolioView(
    path: "Tools/regenerate-tree-sitter-swift.sh",
    content: .code(scriptText, startLine: 1)
)
```

### Render an editable code view

Pass `editable: true` and a `Binding<String>` to turn a `.code` view into a live, syntax-highlighted editor. Highlights repaint as you type; the language is picked from `path` via `CodeLanguageRegistry.detect(path:)`. The editor uses the same `HighlightTheme`, font scale, and gutter styling as the read-only `.code` mode, so toggling `editable` doesn't shift the layout.

```swift
import SwiftUI
import FolioCodeView

struct CodeEditor: View {
    @State private var source = """
    func greet(name: String) {
        print("Hello, \\(name)!")
    }
    """

    var body: some View {
        FolioView(
            path: "Greet.swift",
            content: .code(source),
            editable: true,
            text: $source
        )
    }
}
```

**Data flow.** Plain `String` in via the binding's initial value; plain `String` out via the binding. Highlights are display-only `.foregroundColor` attributes on the text storage and are never part of the returned string. The string in `.code(...)` seeds the initial buffer; once the editor is mounted, `text` is the source of truth — external writes to the binding are mirrored into the text view; the user's edits propagate back into the binding after each storage notification.

**Performance.** Highlighting is incremental. The first paint runs a full tree-sitter parse; each keystroke after that calls `Tree.edit()` → `parser.parse(tree:string:)` → `MutableTree.changedRanges(from:)`, and only the byte ranges that changed are re-highlighted. A retained parser, tree, and query live for the editor's lifetime — no per-keystroke object construction.

**Scope.** Editable mode applies only to `.code` content. `.diff` content is always read-only; if you need to capture user edits in a diff context, do that in your inline-comment composer, not here. Passing `editable: true` with a `.diff` content silently behaves as read-only; passing `editable: true` without a `text` binding emits an `assertionFailure` in debug builds and falls back to read-only.

**Platforms.** macOS uses `NSTextView(usingTextLayoutManager: true)`; iOS uses `UITextView(usingTextLayoutManager: true)`. Both run TextKit 2.

### Attach inline comment threads

```swift
let marks = [
    FolioCommentMark(id: "c1", side: .newFile, line: 12, count: 1),
    FolioCommentMark(id: "c2", side: .oldFile, line: 8, count: 3)
]

FolioView(
    path: "src/Foo.swift",
    content: .diff(hunk, anchor: nil, mode: .split),
    commentMarks: marks,
    onCommentMarkTap: { mark in showThread(mark.id) },
    onCreateComment: { line, side in startComposer(at: line, on: side) },
    threadSlot: { mark in AnyView(InlineThreadView(id: mark.id)) }
)
```

`threadSlot` is rendered inline below the matching diff line; `onCreateComment` fires when the user clicks the gutter on a context-free line.

### Drive your own editor with `FolioHighlighter`

If you're building a custom `NSTextView` / `UITextView` (or an `NSTextLayoutFragment` subclass for, e.g., a markdown code-block fragment), use `FolioHighlighter` directly. Each instance retains a tree-sitter parser, tree, and query for one language — call `applyInitialAttributes(...)` once on mount, then `applyEditAttributes(...)` after each storage edit. Both helpers paint foreground colors and a base font onto an `NSTextStorage` you already own.

```swift
import FolioHighlight
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

let highlighter = FolioHighlighter(theme: .light)
let font: PlatformFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
let language = CodeLanguageRegistry.detect(path: "Greet.swift")

// 1. Initial paint. Seeds the highlighter's retained parser / tree / query
//    and paints colors over the whole buffer.
highlighter.applyInitialAttributes(
    to: storage,
    text: storage.string,
    language: language,
    font: font
)

// 2. After each character-edit notification, derive (replacedRange, replacement)
//    from NSTextStorage.editedRange and changeInLength, then paint just the
//    changed region.
NotificationCenter.default.addObserver(
    forName: NSTextStorage.didProcessEditingNotification,
    object: storage,
    queue: .main
) { _ in
    guard storage.editedMask.contains(.editedCharacters) else { return }
    let editedRange = storage.editedRange
    let oldLength = max(0, editedRange.length - storage.changeInLength)
    let replacedRange = NSRange(location: editedRange.location, length: oldLength)
    let replacement = (storage.string as NSString).substring(with: editedRange)
    let edit = highlighter.didEdit(
        replacedRange: replacedRange,
        replacement: replacement,
        in: storage.string
    )
    highlighter.applyEditAttributes(to: storage, edit: edit, font: font)
}
```

The `editedMask.contains(.editedCharacters)` guard is important: `applyEditAttributes` itself emits an attribute-only edit notification, which would otherwise re-enter the observer.

If you'd rather paint attributes yourself, `reset(text:language:)` and `didEdit(...)` return raw `[FolioHighlighter.Run]` (each `Run` is `NSRange` + `PlatformColor`); ignore the helpers entirely. The `EditResult` returned from `didEdit` carries an `invalidatedRange` (the byte range you need to repaint) and `newRuns` (the runs that intersect that range).

The stateless `runs(for:language:)` is still available for one-shot rendering of immutable text — diff rows, snapshot views, anywhere the buffer never mutates.

**Theme changes.** Setting `highlighter.theme` is cheap — it doesn't reparse. The next `didEdit(...)` call returns runs whose colors reflect the new theme; if you want to repaint without an edit, call `applyInitialAttributes(...)` again.

**Wholesale text replacement.** If your storage is replaced with content the highlighter can't reconcile to a single edit (e.g. a programmatic `setString`), call `applyInitialAttributes(...)` again. It re-runs `reset(text:language:)` internally, throwing away the retained tree and re-seeding from the new buffer.

## Public API surface

### `FolioModel`

| Type | Purpose |
|------|---------|
| `DiffHunk`, `DiffLine`, `AnchorRange` | Parsed unified-diff data. `DiffLine.Kind` is `context | addition | deletion | noNewline`. |
| `UnifiedDiffParser.parse(corpus:oldStart:newStart:)` | Turn a unified-diff `corpus` (the body of a hunk, lines starting with ` `, `+`, `-`, `\`) into a `DiffHunk`. |
| `SplitRow` / `SplitRowBuilder.build(_:)` | Pair deletions with additions for side-by-side rendering. |
| `IntralineDiff` | Word-level diff between two lines, used to colorize the changed substring inside an addition/deletion pair. |
| `DiffFolder.fold(_:contextLines:)` | Collapse runs of context longer than `contextLines` into expandable sections. |
| `FolioLineSelection` | Multi-line selection range with a side and `contains(_:)`. |

### `FolioHighlight`

| Type | Purpose |
|------|---------|
| `CodeLanguage` | A tree-sitter language descriptor (id, display name, extensions, comment markers, query resource, parser handle). |
| `CodeLanguageRegistry` | Looks up languages by file extension or path. |
| `FolioHighlighter` | Tree-sitter–based syntax highlighting. Two modes: stateless `runs(for:language:)` for one-shot static renders, and a stateful incremental path (`reset(text:language:)` + `didEdit(replacedRange:replacement:in:)`) for live editing surfaces — each instance retains a parser/tree/query and reports only the byte ranges that changed per edit via `Tree.edit()` + `MutableTree.changedRanges(from:)`. Companion `applyInitialAttributes(...)` / `applyEditAttributes(...)` helpers paint runs onto an `NSTextStorage`. Used by `FolioView`'s editable mode and intended for embedding in custom `NSTextLayoutFragment`s. |
| `HighlightTheme` | All the colors used by `FolioView` — token classes, gutter, row backgrounds, intra-line emphasis, comment marks. Ships `.light` and `.dark`. |

### `FolioCodeView`

`FolioView` (`FolioCodeView/FolioView.swift`) is the only SwiftUI entry point. It accepts:

- `path: String` — used both for the header and to pick a `CodeLanguage` for syntax highlighting.
- `content: FolioContent` — `.diff(DiffHunk, anchor: AnchorRange?, mode: DiffViewMode)` or `.code(String, startLine: Int)`.
- `theme: HighlightTheme` — defaults to `.light`.
- `commentMarks: [FolioCommentMark]` — gutter pins; clickable.
- `selection: Binding<FolioLineSelection?>?` — drag-select range with side info.
- `onPathTap`, `onCommentMarkTap`, `onCreateComment`, `onExpandContext`, `onLineSelectionChange` — interaction callbacks.
- `threadSlot: (FolioCommentMark) -> AnyView` — inline thread view below the line.
- `composerSlot: FolioComposerSlot?` — inline composer view at a specific `(line, side)`.
- `isExpandable`, `roundsBottomCorners`, `cornerRadius`, `showsHeader`, `initialContextLines` — layout knobs.
- `editable: Bool` — defaults to `false`. When `true` and `content` is `.code(...)`, the view renders a TextKit 2 editor with live syntax highlighting via `FolioHighlighter`. Ignored for `.diff` content.
- `text: Binding<String>?` — required when `editable` is `true`; the source of truth for the editor's contents. Ignored when `editable` is `false`.

`DiffViewMode` is `.split` or `.unified`. `ExpandDirection` is `.up` or `.down`, fed back through `onExpandContext` when the user clicks an "expand context" row.

## Vendored grammars

`Vendor/tree-sitter-*/` contains pre-generated `parser.c` (and `scanner.c` where applicable) plus the upstream `queries/` directories. They're built as plain C targets and linked into `FolioHighlight`. The `markdown` grammar comes from the SwiftPM dependency [`tree-sitter-grammars/tree-sitter-markdown`](https://github.com/tree-sitter-grammars/tree-sitter-markdown).

To regenerate a vendored grammar after upstream changes, run the matching script in `Tools/` from the repository root:

```sh
./Tools/regenerate-tree-sitter-swift.sh
./Tools/regenerate-tree-sitter-rust.sh
# etc.
```

Each script uses `npx tree-sitter-cli` and re-emits `src/parser.c` and headers in place.

## Testing

```sh
swift test --package-path Packages/FolioCodeView
```

Two test targets:

- `FolioModelTests` — diff parsing, intra-line diffing, split-row building, folding (XCTest).
- `FolioHighlightTests` — language registry lookup, stateless highlight query execution (XCTest), incremental `reset` + `didEdit` invariants including drift between incremental and full reparse, and `applyInitialAttributes` / `applyEditAttributes` correctness against `NSTextStorage` (Swift Testing).

`FolioView` itself has no XCTest coverage; it's exercised in the Zilla app's `ChangesetView` via `FolioActivityIntegration.swift`.

## License

FolioCodeView is released under the Mozilla Public License, v. 2.0. See <https://www.mozilla.org/MPL/2.0/> for the full text.
