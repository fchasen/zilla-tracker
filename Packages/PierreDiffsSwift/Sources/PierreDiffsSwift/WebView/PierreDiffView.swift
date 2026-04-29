//
//  PierreDiffView.swift
//  PierreDiffsSwift
//
//  Created by James Rochabrun on 1/6/26.
//

import SwiftUI
import WebKit

/// A SwiftUI view that renders code diffs using the @pierre/diffs JavaScript library.
///
/// This view wraps a WKWebView that loads a bundled JavaScript library for rendering
/// rich, syntax-highlighted diffs with features like:
/// - Split and unified view modes
/// - Syntax highlighting via Shiki
/// - Inline word-level change highlighting
/// - Dark/light theme support
public struct PierreDiffView: NSViewRepresentable {

  // MARK: - Properties

  /// The original file content (before changes)
  let oldContent: String

  /// The updated file content (after changes)
  let newContent: String

  /// The name of the file being diffed (used for syntax highlighting detection)
  let fileName: String

  /// The current diff view style
  @Binding var diffStyle: DiffStyle

  /// The current overflow mode (scroll or wrap)
  @Binding var overflowMode: OverflowMode

  /// Callback when the user clicks on a line
  var onLineClick: ((Int, String) -> Void)?

  /// Callback when the user clicks on a line, with position data for UI overlay positioning
  var onLineClickWithPosition: ((LineClickPosition, CGPoint) -> Void)?

  /// Callback when a range of lines is selected via drag
  var onLineSelectionChange: ((LineSelectionRange) -> Void)?

  /// Callback when the view requests expansion to full screen
  var onExpandRequest: (() -> Void)?

  /// Inline annotations to display on the diff
  var annotations: [DiffAnnotation]?

  /// Callback when an annotation is clicked (id, side, lineNumber, localPoint)
  var onAnnotationClick: ((String, String, Int, CGPoint) -> Void)?

  /// Callback when an annotation delete is requested (id, side, lineNumber)
  var onAnnotationDelete: ((String, String, Int) -> Void)?

  /// Callback when the user submits a draft via an in-diff composer.
  /// Args: (annotationID, commentID, body, side, lineNumber).
  var onAnnotationDraftSubmit: ((String, String, String, String, Int) -> Void)?

  /// Callback when the user cancels an in-diff composer.
  /// Args: (annotationID, commentID, side, lineNumber).
  var onAnnotationDraftCancel: ((String, String, String, Int) -> Void)?

  /// Callback when the rendered content height changes. Hosts can use this to
  /// size their containing view so the diff renders at full intrinsic height
  /// without an inner scrollbar.
  var onContentHeightChange: ((CGFloat) -> Void)?

  /// Callback when the WebView is ready to display content
  var onReady: (() -> Void)?

  // MARK: - Environment

  @Environment(\.colorScheme) private var colorScheme

  // MARK: - Initialization

  public init(
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
    onAnnotationDraftSubmit: ((String, String, String, String, Int) -> Void)? = nil,
    onAnnotationDraftCancel: ((String, String, String, Int) -> Void)? = nil,
    onContentHeightChange: ((CGFloat) -> Void)? = nil,
    onExpandRequest: (() -> Void)? = nil,
    onReady: (() -> Void)? = nil
  ) {
    self.oldContent = oldContent
    self.newContent = newContent
    self.fileName = fileName
    self._diffStyle = diffStyle
    self._overflowMode = overflowMode
    self.annotations = annotations
    self.onLineClick = onLineClick
    self.onLineClickWithPosition = onLineClickWithPosition
    self.onLineSelectionChange = onLineSelectionChange
    self.onAnnotationClick = onAnnotationClick
    self.onAnnotationDelete = onAnnotationDelete
    self.onAnnotationDraftSubmit = onAnnotationDraftSubmit
    self.onAnnotationDraftCancel = onAnnotationDraftCancel
    self.onContentHeightChange = onContentHeightChange
    self.onExpandRequest = onExpandRequest
    self.onReady = onReady
  }

  // MARK: - NSViewRepresentable

  public func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()

    // Set up message handler for JavaScript to Swift communication
    configuration.userContentController.add(
      context.coordinator,
      name: "diffBridge"
    )

    // Configure preferences
    configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

    // We size the host to the diff's intrinsic content height (see
    // `onContentHeightChange`), so the WebView never needs to scroll
    // internally. Use a subclass that always forwards scroll events to its
    // parent responder — without this, the WKWebView swallows wheel events
    // and the surrounding ScrollView can't scroll while the cursor is over
    // the diff.
    let webView = ScrollPassThroughWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.allowsMagnification = true

    // Make background transparent to blend with SwiftUI
    webView.setValue(false, forKey: "drawsBackground")

    // Store reference in coordinator
    context.coordinator.webView = webView

    // Load the initial HTML
    loadHTML(into: webView)

    return webView
  }

  public func updateNSView(_ webView: WKWebView, context: Context) {
    let coordinator = context.coordinator

    // Check if content has changed
    let contentChanged = coordinator.lastOldContent != oldContent ||
                         coordinator.lastNewContent != newContent ||
                         coordinator.lastFileName != fileName

    // Check if style has changed
    let styleChanged = coordinator.lastDiffStyle != diffStyle

    // Check if overflow mode has changed
    let overflowChanged = coordinator.lastOverflowMode != overflowMode

    // Check if theme has changed
    let currentTheme = themeForColorScheme
    let themeChanged = coordinator.lastTheme != currentTheme

    // Check if annotations have changed
    let annotationsChanged = coordinator.lastAnnotations != annotations

    if contentChanged {
      coordinator.lastOldContent = oldContent
      coordinator.lastNewContent = newContent
      coordinator.lastFileName = fileName
      coordinator.lastOverflowMode = overflowMode
      coordinator.lastAnnotations = annotations
      coordinator.renderDiff(
        oldContent: oldContent,
        newContent: newContent,
        fileName: fileName,
        theme: currentTheme,
        diffStyle: diffStyle,
        overflowMode: overflowMode,
        annotations: annotations
      )
    } else if styleChanged {
      coordinator.lastDiffStyle = diffStyle
      coordinator.setDiffStyle(diffStyle)
    } else if overflowChanged {
      coordinator.lastOverflowMode = overflowMode
      coordinator.setOverflow(overflowMode)
    } else if themeChanged {
      coordinator.lastTheme = currentTheme
      coordinator.setTheme(currentTheme)
    }

    if !contentChanged && annotationsChanged {
      coordinator.lastAnnotations = annotations
      if let annotations, !annotations.isEmpty {
        coordinator.setAnnotations(annotations)
      } else {
        coordinator.removeAnnotations()
      }
    }
  }

  public func makeCoordinator() -> DiffWebViewCoordinator {
    DiffWebViewCoordinator(
      onLineClick: onLineClick,
      onLineClickWithPosition: onLineClickWithPosition,
      onLineSelectionChange: onLineSelectionChange,
      onExpandRequest: onExpandRequest,
      onReady: onReady,
      onAnnotationClick: onAnnotationClick,
      onAnnotationDelete: onAnnotationDelete,
      onAnnotationDraftSubmit: onAnnotationDraftSubmit,
      onAnnotationDraftCancel: onAnnotationDraftCancel,
      onContentHeightChange: onContentHeightChange
    )
  }

  public static func dismantleNSView(_ nsView: WKWebView, coordinator: DiffWebViewCoordinator) {
    coordinator.cleanup()
  }

  // MARK: - Private Helpers

  private var themeForColorScheme: String {
    colorScheme == .dark ? "dark" : "light"
  }

  private func loadHTML(into webView: WKWebView) {
    let html = DiffHTMLTemplate.generateHTML()
    webView.loadHTMLString(html, baseURL: nil)
  }
}

/// A WKWebView that
///   1. Always forwards scroll wheel events to the next responder, since the
///      page is sized to its intrinsic content height (nothing to scroll
///      inside the web view).
///   2. Reports its painted content height as `intrinsicContentSize`, so
///      SwiftUI/AutoLayout can size the host without an explicit `.frame`
///      tied to a `@State` binding. JS pushes a new height via
///      `contentHeightChanged` → coordinator → `setContentHeight(_:)`.
final class ScrollPassThroughWebView: WKWebView {
  private var contentHeight: CGFloat = 0

  override func scrollWheel(with event: NSEvent) {
    nextResponder?.scrollWheel(with: event)
  }

  override var intrinsicContentSize: NSSize {
    NSSize(
      width: NSView.noIntrinsicMetric,
      height: contentHeight > 0 ? contentHeight : NSView.noIntrinsicMetric
    )
  }

  func setContentHeight(_ newHeight: CGFloat) {
    let resolved = max(0, newHeight)
    guard abs(contentHeight - resolved) > 0.5 else { return }
    contentHeight = resolved
    invalidateIntrinsicContentSize()
  }
}
