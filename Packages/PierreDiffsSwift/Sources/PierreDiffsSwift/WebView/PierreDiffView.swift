//
//  PierreDiffView.swift
//  PierreDiffsSwift
//
//  Created by James Rochabrun on 1/6/26.
//

import SwiftUI
import WebKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// A SwiftUI view that renders code diffs using the @pierre/diffs JavaScript library.
///
/// This view wraps a WKWebView that loads a bundled JavaScript library for rendering
/// rich, syntax-highlighted diffs with features like:
/// - Split and unified view modes
/// - Syntax highlighting via Shiki
/// - Inline word-level change highlighting
/// - Dark/light theme support
///
/// Conforms to `NSViewRepresentable` on macOS and `UIViewRepresentable` on iOS /
/// iPadOS / visionOS via conditional extensions below.
@MainActor
public struct PierreDiffView {

  // MARK: - Properties

  let oldContent: String
  let newContent: String
  let fileName: String
  @Binding var diffStyle: DiffStyle
  @Binding var overflowMode: OverflowMode
  var onLineClick: ((Int, String) -> Void)?
  var onLineClickWithPosition: ((LineClickPosition, CGPoint) -> Void)?
  var onLineSelectionChange: ((LineSelectionRange) -> Void)?
  var onExpandRequest: (() -> Void)?
  var annotations: [DiffAnnotation]?
  var onAnnotationClick: ((String, String, Int, CGPoint) -> Void)?
  var onAnnotationDelete: ((String, String, Int) -> Void)?
  var onAnnotationDraftSubmit: ((String, String, String, String, Int) -> Void)?
  var onAnnotationDraftCancel: ((String, String, String, Int) -> Void)?
  var onContentHeightChange: ((CGFloat) -> Void)?
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

  // MARK: - Coordinator

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

  // MARK: - Shared WebView setup

  fileprivate func makeWebView(coordinator: DiffWebViewCoordinator) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.add(coordinator, name: "diffBridge")

    #if os(macOS)
    configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
    let webView = ScrollPassThroughWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = coordinator
    webView.allowsMagnification = true
    webView.setValue(false, forKey: "drawsBackground")
    #else
    let webView = IntrinsicHeightWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = coordinator
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.scrollView.isScrollEnabled = false
    #endif

    coordinator.webView = webView
    loadHTML(into: webView)
    return webView
  }

  fileprivate func updateWebView(_ webView: WKWebView, coordinator: DiffWebViewCoordinator) {
    let contentChanged = coordinator.lastOldContent != oldContent ||
                         coordinator.lastNewContent != newContent ||
                         coordinator.lastFileName != fileName

    let styleChanged = coordinator.lastDiffStyle != diffStyle
    let overflowChanged = coordinator.lastOverflowMode != overflowMode
    let currentTheme = themeForColorScheme
    let themeChanged = coordinator.lastTheme != currentTheme
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

  // MARK: - Private Helpers

  private var themeForColorScheme: String {
    colorScheme == .dark ? "dark" : "light"
  }

  private func loadHTML(into webView: WKWebView) {
    let html = DiffHTMLTemplate.generateHTML()
    webView.loadHTMLString(html, baseURL: nil)
  }
}

// MARK: - Platform conformances

#if os(macOS)
extension PierreDiffView: NSViewRepresentable {

  public func makeNSView(context: Context) -> WKWebView {
    makeWebView(coordinator: context.coordinator)
  }

  public func updateNSView(_ webView: WKWebView, context: Context) {
    updateWebView(webView, coordinator: context.coordinator)
  }

  public static func dismantleNSView(_ nsView: WKWebView, coordinator: DiffWebViewCoordinator) {
    coordinator.cleanup()
  }
}
#else
extension PierreDiffView: UIViewRepresentable {

  public func makeUIView(context: Context) -> WKWebView {
    makeWebView(coordinator: context.coordinator)
  }

  public func updateUIView(_ webView: WKWebView, context: Context) {
    updateWebView(webView, coordinator: context.coordinator)
  }

  public static func dismantleUIView(_ uiView: WKWebView, coordinator: DiffWebViewCoordinator) {
    coordinator.cleanup()
  }
}
#endif

// MARK: - Intrinsic-height WebView subclasses

#if os(macOS)
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
#else
/// iOS / iPadOS / visionOS counterpart to `ScrollPassThroughWebView`. Inner
/// scrolling is disabled in `makeWebView`, so the only job here is to expose
/// the painted height via `intrinsicContentSize` so SwiftUI's `.fixedSize`
/// can size the host correctly.
final class IntrinsicHeightWebView: WKWebView {
  private var contentHeight: CGFloat = 0

  override var intrinsicContentSize: CGSize {
    CGSize(
      width: UIView.noIntrinsicMetric,
      height: contentHeight > 0 ? contentHeight : UIView.noIntrinsicMetric
    )
  }

  func setContentHeight(_ newHeight: CGFloat) {
    let resolved = max(0, newHeight)
    guard abs(contentHeight - resolved) > 0.5 else { return }
    contentHeight = resolved
    invalidateIntrinsicContentSize()
  }
}
#endif
