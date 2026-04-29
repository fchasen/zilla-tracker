# PierreDiffsSwift

[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-048754?logo=buymeacoffee&style=for-the-badge)](https://buymeacoffee.com/jamesrochabrun)


A Swift package for rendering beautiful, syntax-highlighted code diffs in macOS applications using the [@pierre/diffs](https://www.npmjs.com/package/@pierre/diffs) JavaScript library.

This is how we use it in [Claw](https://github.com/jamesrochabrun/Claw)

## Dark Mode
<img width="859" height="990" alt="Image" src="https://github.com/user-attachments/assets/4eb8df72-308b-4f99-9bc9-acdb347a11e6" />
<img width="840" height="632" alt="Image" src="https://github.com/user-attachments/assets/5701be1a-55ee-4c53-9d81-1cfdb38c22fa" />

## Light Mode
<img width="852" height="984" alt="Image" src="https://github.com/user-attachments/assets/9c6a62c5-8ff5-465d-84b1-a025a9272bc1" />
<img width="832" height="612" alt="Image" src="https://github.com/user-attachments/assets/0ae99c27-8aba-4523-a7e9-031a8cf9b940" />

## Features

- Rich syntax highlighting via Shiki (supports 40+ languages)
- Split and unified diff view modes
- Inline word-level change highlighting
- Dark/light theme support (auto-detects system preference)
- Scroll or wrap overflow modes
- Line click callbacks with position data for overlay positioning
- Multi-line drag selection with range callbacks
- Inline annotations (comments) rendered inside the diff
- Annotation click and delete callbacks for interactive review flows
- SwiftUI-native views wrapping WKWebView

## Requirements

- macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## Installation

### Swift Package Manager

Add PierreDiffsSwift to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/jamesrochabrun/PierreDiffsSwift.git", from: "1.0.0")
]
```

Or in Xcode: File > Add Package Dependencies... and enter the repository URL.

## Quick Start

### Basic Diff Rendering

```swift
import SwiftUI
import PierreDiffsSwift

struct ContentView: View {
    @State private var diffStyle: DiffStyle = .split
    @State private var overflowMode: OverflowMode = .scroll

    var body: some View {
        PierreDiffView(
            oldContent: "let x = 1\nlet y = 2",
            newContent: "let x = 1\nlet y = 3\nlet z = 4",
            fileName: "example.swift",
            diffStyle: $diffStyle,
            overflowMode: $overflowMode
        )
        .frame(height: 400)
    }
}
```

## API Reference

### Views

#### `PierreDiffView`

Low-level SwiftUI view that renders diffs using WKWebView and the @pierre/diffs library.

```swift
PierreDiffView(
    oldContent: String,
    newContent: String,
    fileName: String,
    diffStyle: Binding<DiffStyle>,
    overflowMode: Binding<OverflowMode>,
    annotations: [DiffAnnotation]? = nil,
    onLineClick: ((Int, String) -> Void)? = nil,
    onLineClickWithPosition: ((LineClickPosition, CGPoint) -> Void)? = nil,
    onLineSelectionChange: ((LineSelectionRange) -> Void)? = nil,
    onAnnotationClick: ((String, String, Int, CGPoint) -> Void)? = nil,
    onAnnotationDelete: ((String, String, Int) -> Void)? = nil,
    onExpandRequest: (() -> Void)? = nil,
    onReady: (() -> Void)? = nil
)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `oldContent` | `String` | Original file content (before changes) |
| `newContent` | `String` | Updated file content (after changes) |
| `fileName` | `String` | Filename used for syntax highlighting detection |
| `diffStyle` | `Binding<DiffStyle>` | `.split` or `.unified` |
| `overflowMode` | `Binding<OverflowMode>` | `.scroll` or `.wrap` |
| `annotations` | `[DiffAnnotation]?` | Inline annotations rendered below diff lines |
| `onLineClick` | `((Int, String) -> Void)?` | Simple line click (lineNumber, side) |
| `onLineClickWithPosition` | `((LineClickPosition, CGPoint) -> Void)?` | Line click with position for overlay placement |
| `onLineSelectionChange` | `((LineSelectionRange) -> Void)?` | Multi-line drag selection range |
| `onAnnotationClick` | `((String, String, Int, CGPoint) -> Void)?` | Annotation clicked (id, side, lineNumber, localPoint) |
| `onAnnotationDelete` | `((String, String, Int) -> Void)?` | Annotation delete requested (id, side, lineNumber) |
| `onExpandRequest` | `(() -> Void)?` | View requests full-screen expansion |
| `onReady` | `(() -> Void)?` | WebView finished loading and rendered the diff |

#### `DiffEditsView`

High-level view that processes edit tool responses (Edit, MultiEdit, Write) and renders the resulting diff.

```swift
DiffEditsView(
    messageID: UUID,
    editTool: EditTool,
    toolParameters: [String: String],
    projectPath: String? = nil,
    onExpandRequest: (() -> Void)? = nil,
    diffStore: DiffStateManager? = nil,
    diffLifecycleState: DiffLifecycleState? = nil
)
```

#### `DiffModalView`

Full-screen modal wrapper for displaying diffs with a close button.

```swift
DiffModalView(
    messageID: UUID,
    editTool: EditTool,
    toolParameters: [String: String],
    projectPath: String? = nil,
    diffStore: DiffStateManager? = nil,
    diffLifecycleState: DiffLifecycleState? = nil,
    onDismiss: @escaping () -> Void
)
```

#### `CompactDiffStatusView`

Compact view showing that changes have been reviewed, with tap-to-expand.

```swift
CompactDiffStatusView(
    fileName: String,
    timestamp: Date?,
    onTapToExpand: @escaping () -> Void
)
```

### Types

#### `DiffStyle`

```swift
enum DiffStyle: String, CaseIterable {
    case split    // Side-by-side view
    case unified  // Single column view
}
```

#### `OverflowMode`

```swift
enum OverflowMode: String, CaseIterable {
    case scroll  // Horizontal scrolling for long lines
    case wrap    // Word wrap long lines
}
```

#### `DiffAnnotation`

An inline annotation attached to a specific line in the diff.

```swift
struct DiffAnnotation: Codable, Sendable, Equatable {
    let side: AnnotationSide    // .deletions or .additions
    let lineNumber: Int         // Line number to attach to
    let metadata: AnnotationMetadata
}
```

#### `AnnotationSide`

```swift
enum AnnotationSide: String, Codable, Sendable {
    case deletions   // Left side (old file)
    case additions   // Right side (new file)
}
```

#### `AnnotationMetadata`

```swift
struct AnnotationMetadata: Codable, Sendable, Equatable {
    let id: String         // Unique identifier (defaults to UUID)
    let author: String     // Display name (used for image alt text)
    let body: String       // Comment text
    let avatarURL: String? // Optional avatar image URL (SVG person icon when nil)
    let subtitle: String?  // Optional subtitle shown above body (e.g. "Code review: line 42")
}
```

#### `LineClickPosition`

Context about a clicked line in the diff view.

```swift
struct LineClickPosition {
    let lineNumber: Int     // The line number clicked
    let side: String        // "left", "right", or "unified"
    let lineY: CGFloat      // Y position in view coordinates
    let lineHeight: CGFloat // Estimated line height
}
```

#### `LineSelectionRange`

Data about a multi-line drag selection in the diff view.

```swift
struct LineSelectionRange {
    let startLine: Int  // First line in the selection
    let endLine: Int    // Last line in the selection
    let side: String    // "left", "right", or "unified"
}
```

#### `EditTool`

```swift
enum EditTool: String {
    case edit      // Single edit operation
    case multiEdit // Multiple edits in one file
    case write     // Write entire file content
}
```

#### `DiffResult`

```swift
struct DiffResult: Equatable, Codable {
    var filePath: String
    var fileName: String
    var original: String
    var updated: String
    var isInitial: Bool
}
```

### State Management

#### `DiffStateManager`

Observable class for managing diff state across your application.

```swift
@Observable
class DiffStateManager {
    func getState(for messageID: UUID) -> DiffState
    func process(diffs: [DiffResult], for messageID: UUID) async
    func removeState(for messageID: UUID)
    func clearAllStates()
}
```

### Processing

#### `DiffResultProcessor`

Processes edit tool responses to generate diff results.

```swift
struct DiffResultProcessor {
    init(fileDataReader: FileDataReader)

    func processEditTool(
        response: String,
        tool: EditTool
    ) async -> [DiffResult]?
}
```

### Protocols

#### `FileDataReader`

Protocol for reading file contents. Default implementation provided.

```swift
protocol FileDataReader {
    var projectPath: String? { get }
    func readFileContent(in paths: [String], maxTasks: Int) async throws -> [String: String]
    func cancelCurrentTask()
}

// Default implementation
class DefaultFileDataReader: FileDataReader
```

## Examples

### Line Click with Position

```swift
PierreDiffView(
    oldContent: oldText,
    newContent: newText,
    fileName: "example.swift",
    diffStyle: $diffStyle,
    overflowMode: $overflowMode,
    onLineClickWithPosition: { position, localPoint in
        // localPoint is in SwiftUI coordinates (origin top-left)
        // Use to position floating editors, popovers, tooltips, etc.
        print("Clicked line \(position.lineNumber) at \(localPoint)")
    }
)
```

### Multi-Line Drag Selection

```swift
PierreDiffView(
    oldContent: oldText,
    newContent: newText,
    fileName: "example.swift",
    diffStyle: $diffStyle,
    overflowMode: $overflowMode,
    onLineSelectionChange: { selection in
        // Fired when the user drags across line numbers to select a range
        print("Selected lines \(selection.startLine)-\(selection.endLine) on \(selection.side)")
    }
)
```

### Inline Annotations

```swift
let annotations = [
    DiffAnnotation(
        side: .additions,
        lineNumber: 5,
        metadata: AnnotationMetadata(author: "Alice", body: "Consider adding error handling here")
    ),
    DiffAnnotation(
        side: .deletions,
        lineNumber: 12,
        metadata: AnnotationMetadata(author: "Bob", body: "Why was this removed?")
    )
]

PierreDiffView(
    oldContent: oldText,
    newContent: newText,
    fileName: "example.swift",
    diffStyle: $diffStyle,
    overflowMode: $overflowMode,
    annotations: annotations,
    onAnnotationClick: { id, side, lineNumber, localPoint in
        // User clicked the annotation body — open editor overlay at localPoint
        print("Annotation \(id) clicked at \(localPoint)")
    },
    onAnnotationDelete: { id, side, lineNumber in
        // User clicked the X button on the annotation
        // Remove from your state — the annotation disappears reactively
        print("Delete annotation \(id)")
    }
)
```

### Interactive Code Review (Full Pattern)

Build a GitHub PR-style inline review experience:

```swift
@Observable class ReviewState {
    var comments: [String: ReviewComment] = [:]

    func annotations(for fileName: String) -> [DiffAnnotation] {
        comments.values
            .filter { $0.fileName == fileName }
            .map { comment in
                DiffAnnotation(
                    side: comment.side == "left" ? .deletions : .additions,
                    lineNumber: comment.lineNumber,
                    metadata: AnnotationMetadata(
                        id: comment.id.uuidString,
                        author: "You",
                        body: comment.text
                    )
                )
            }
    }
}

// In your view:
PierreDiffView(
    oldContent: oldText,
    newContent: newText,
    fileName: filePath,
    diffStyle: $diffStyle,
    overflowMode: $overflowMode,
    annotations: reviewState.annotations(for: filePath),
    onLineClickWithPosition: { position, localPoint in
        // Show editor overlay for new comment
        editorState.show(at: localPoint, lineNumber: position.lineNumber, side: position.side)
    },
    onAnnotationClick: { id, side, lineNumber, localPoint in
        // Show editor overlay for editing existing comment
        editorState.showEdit(at: localPoint, annotationId: id)
    },
    onAnnotationDelete: { id, side, lineNumber in
        // Remove comment — annotation disappears via SwiftUI reactivity
        reviewState.removeComment(id: id)
    }
)
```

### Processing Edit Tool Response

```swift
import PierreDiffsSwift

// Create processor with file reader
let processor = DiffResultProcessor(
    fileDataReader: DefaultFileDataReader(projectPath: "/path/to/project")
)

// Process an edit response
let toolResponse = """
{
    "file_path": "/path/to/file.swift",
    "old_string": "let x = 1",
    "new_string": "let x = 2"
}
"""

if let results = await processor.processEditTool(response: toolResponse, tool: .edit) {
    // Use results with DiffStateManager or display directly
}
```

### Using DiffEditsView with Parameters

```swift
DiffEditsView(
    messageID: UUID(),
    editTool: .edit,
    toolParameters: [
        "file_path": "/path/to/file.swift",
        "old_string": "let x = 1",
        "new_string": "let x = 2"
    ],
    projectPath: "/path/to/project"
)
```

### Managing Multiple Diffs

```swift
struct MyView: View {
    @State private var diffStore = DiffStateManager()

    var body: some View {
        ForEach(messages) { message in
            DiffEditsView(
                messageID: message.id,
                editTool: message.editTool,
                toolParameters: message.parameters,
                diffStore: diffStore
            )
        }
    }
}
```

## Rebuilding the JavaScript Bundle

The package includes a pre-built JavaScript bundle. To rebuild it:

```bash
cd scripts
npm install
npm run build
```

This generates `pierre-diffs-bundle.js` which should be copied to `Sources/PierreDiffsSwift/Resources/`.

## Supported Languages

The package supports syntax highlighting for 40+ languages including:
Swift, JavaScript, TypeScript, Python, Go, Rust, Java, Kotlin, C, C++, Ruby, PHP, SQL, HTML, CSS, JSON, YAML, Markdown, and more.

Language is auto-detected from the filename extension.

## License

MIT
