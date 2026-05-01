# FolioCodeView

A SwiftUI diff and code viewer with syntax highlighting, split / unified layouts, intra-line diffing, and inline comment marks. FolioCodeView renders directly in TextKit-backed `Text` views — no `WKWebView`, no JavaScript bundle.

FolioCodeView was built for Zilla's revision-detail screen but is generic: it takes either a parsed diff hunk or a plain string and produces a list view of rows with comment hooks, expandable context, and selection callbacks.

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
| `FolioHighlighter` | Runs a highlight query against source text and returns `HighlightRuns` (token ranges with colors). |
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

- `FolioModelTests` — diff parsing, intra-line diffing, split-row building, folding.
- `FolioHighlightTests` — language registry lookup and highlight query execution.

`FolioView` itself has no XCTest coverage; it's exercised in the Zilla app's `ChangesetView` via `FolioActivityIntegration.swift`.

## License

FolioCodeView is released under the Mozilla Public License, v. 2.0. See <https://www.mozilla.org/MPL/2.0/> for the full text.
