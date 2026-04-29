//
//  DiffHTMLTemplate.swift
//  PierreDiffsSwift
//
//  Created by James Rochabrun on 1/6/26.
//

import Foundation

/// Generates the HTML template for the Pierre Diff WebView.
enum DiffHTMLTemplate {

  /// Generates the complete HTML string with embedded JavaScript and CSS.
  static func generateHTML() -> String {
    let bundleJS = loadBundledJavaScript()

    return """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            \(styles)
        </style>
    </head>
    <body>
        <div id="diff-container"></div>
        <script>
            \(bundleJS)
        </script>
        <script>
            \(contentHeightObserverScript)
        </script>
    </body>
    </html>
    """
  }

  // MARK: - Private

  /// Loads the bundled JavaScript from the app resources.
  private static func loadBundledJavaScript() -> String {
    // Try to load from bundle resources
    // First try with subdirectory (for .copy with directory structure)
    var bundleURL = Bundle.module.url(
      forResource: "pierre-diffs-bundle",
      withExtension: "js",
      subdirectory: "Resources"
    )

    // If not found, try without subdirectory (for flattened resources)
    if bundleURL == nil {
      bundleURL = Bundle.module.url(
        forResource: "pierre-diffs-bundle",
        withExtension: "js"
      )
    }

    guard let bundleURL else {
      DiffLogger.error("DiffHTMLTemplate: Could not find pierre-diffs-bundle.js in bundle")
      return fallbackJavaScript
    }

    do {
      let content = try String(contentsOf: bundleURL, encoding: .utf8)
      return content
    } catch {
      DiffLogger.error("DiffHTMLTemplate: Failed to load pierre-diffs-bundle.js: \(error)")
      return fallbackJavaScript
    }
  }

  /// Posts the document content height to Swift whenever it changes. The host
  /// can size its containing view to match, so the diff never needs an inner
  /// scrollbar.
  ///
  /// Why this isn't `documentElement.scrollHeight`: Pierre renders into a
  /// `<diffs-container>` custom element with shadow DOM that may use internal
  /// overflow scroll regions. With `overflow: visible` on html/body those
  /// inner scrollHeights bubble up and dramatically overshoot the painted
  /// content. Measuring the bounding rect of body's children gives the actual
  /// painted bottom — what the user perceives as the diff's height.
  private static let contentHeightObserverScript = """
  (function() {
    const PADDING_BOTTOM = 8;
    const measure = () => {
      // Walk only direct children of <body>; Pierre's custom element + our
      // any sibling annotations all live there. The lowest bounding rect
      // bottom is the painted height.
      const body = document.body;
      if (!body) return 0;
      let max = 0;
      for (const el of body.children) {
        if (!(el instanceof HTMLElement)) continue;
        const rect = el.getBoundingClientRect();
        const bottom = rect.bottom + window.scrollY;
        if (bottom > max) max = bottom;
      }
      return max + PADDING_BOTTOM;
    };
    const send = () => {
      try {
        window.webkit.messageHandlers.diffBridge.postMessage({
          type: 'contentHeightChanged',
          height: measure()
        });
      } catch (e) {}
    };
    const observer = new ResizeObserver(send);
    if (document.documentElement) observer.observe(document.documentElement);
    if (document.body) observer.observe(document.body);
    const container = document.getElementById('diff-container');
    if (container) observer.observe(container);
    window.addEventListener('load', send);
    // Forward later DOM mutations (annotation cards expanding etc.) too.
    if (container) {
      const mo = new MutationObserver(send);
      mo.observe(container, { childList: true, subtree: true, attributes: true, characterData: true });
    }
    send();
  })();
  """

  /// Fallback JavaScript when bundle loading fails
  private static let fallbackJavaScript = """
  window.pierreBridge = {
    renderDiff: function(input) {
      const container = document.getElementById('diff-container');
      container.innerHTML = '<div style="color: red; padding: 20px;">Failed to load diff library. Please restart the application.</div>';
      if (window.webkit?.messageHandlers?.diffBridge) {
        window.webkit.messageHandlers.diffBridge.postMessage({ type: 'error', message: 'Bundle not loaded' });
      }
    },
    setTheme: function() {},
    setDiffStyle: function() {},
    scrollToLine: function() {},
    getSelection: function() { return ''; },
    cleanup: function() {}
  };
  """

  /// CSS styles for the diff view
  private static let styles = """
  * {
    box-sizing: border-box;
  }

  :root {
    --diffs-font-family: ui-monospace, 'SF Mono', Menlo, Monaco, 'Cascadia Code', 'Roboto Mono', monospace;
    --diffs-font-size: 12px;
    --diffs-line-height: 1.5;
    --diffs-tab-size: 2;
    --diffs-header-font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
    --diffs-min-number-column-width: 4ch;
  }

  html, body {
    margin: 0;
    padding: 0;
    width: 100%;
    height: auto;
    min-height: 0;
    overflow: visible;
    font-family: var(--diffs-font-family);
    font-size: var(--diffs-font-size);
    line-height: var(--diffs-line-height);
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
  }

  body {
    background-color: transparent;
  }

  #diff-container {
    width: 100%;
    height: auto;
    min-height: 0;
    overflow: visible;
  }

  /* Scrollbar styling for macOS feel */
  ::-webkit-scrollbar {
    width: 8px;
    height: 8px;
  }

  ::-webkit-scrollbar-track {
    background: transparent;
  }

  ::-webkit-scrollbar-thumb {
    background-color: rgba(128, 128, 128, 0.3);
    border-radius: 4px;
  }

  ::-webkit-scrollbar-thumb:hover {
    background-color: rgba(128, 128, 128, 0.5);
  }

  /* Dark mode adjustments */
  @media (prefers-color-scheme: dark) {
    ::-webkit-scrollbar-thumb {
      background-color: rgba(255, 255, 255, 0.2);
    }

    ::-webkit-scrollbar-thumb:hover {
      background-color: rgba(255, 255, 255, 0.3);
    }
  }

  /* Selection styling */
  ::selection {
    background-color: rgba(59, 130, 246, 0.3);
  }

  /* Hide @pierre/diffs' built-in file headers — the host renders its own
     header row outside the WebView, so showing them again is redundant. */
  .diffs-header,
  .diff-header,
  .diff-file-header {
    display: none !important;
  }

  /* A top inset that matches Pierre's default side gap (--diffs-gap-fallback
     is 8px) so the first hunk doesn't butt up against the host's disclosure
     row and the spacing reads as symmetric with the left/right gutter. */
  #diff-container {
    padding-top: 8px;
  }

  /* Inline annotation styles */
  .pierre-annotation {
    margin: 6px 4px;
    padding: 10px 12px;
    border: 1px solid rgba(140, 140, 160, 0.18);
    border-radius: 8px;
    background-color: rgba(255, 255, 255, 0.9);
    font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
    font-size: 12px;
    cursor: pointer;
    transition: background-color 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06), 0 1px 3px rgba(0, 0, 0, 0.04);
  }

  .pierre-annotation:hover {
    background-color: rgba(255, 255, 255, 0.95);
    border-color: rgba(140, 140, 160, 0.3);
  }

  .pierre-annotation-row {
    display: flex;
    gap: 8px;
    align-items: flex-start;
  }

  .pierre-annotation-avatar {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    flex-shrink: 0;
    overflow: hidden;
    display: flex;
    align-items: center;
    justify-content: center;
    background-color: rgba(96, 165, 250, 0.15);
    color: rgba(96, 165, 250, 0.8);
    margin-top: 1px;
  }

  .pierre-annotation-avatar img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    border-radius: 50%;
  }

  .pierre-annotation-avatar svg {
    width: 14px;
    height: 14px;
  }

  .pierre-annotation-content {
    flex: 1;
    min-width: 0;
  }

  .pierre-annotation-header {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 2px;
  }

  .pierre-annotation-author {
    font-weight: 600;
    font-size: 12px;
    color: inherit;
  }

  .pierre-annotation-subtitle {
    font-weight: 500;
    font-size: 11px;
    color: inherit;
    opacity: 0.5;
  }

  .pierre-annotation-row + .pierre-annotation-row {
    margin-top: 10px;
    padding-top: 10px;
    border-top: 1px solid rgba(140, 140, 160, 0.16);
  }

  .pierre-annotation-reply {
    padding-left: 8px;
  }

  /* Push the delete button to the trailing edge of the header row. */
  .pierre-annotation-header .pierre-annotation-delete {
    margin-left: auto;
  }

  /* In-diff composer / editor */
  .pierre-annotation-textarea {
    width: 100%;
    margin-top: 4px;
    padding: 8px 10px;
    border: 1px solid rgba(140, 140, 160, 0.3);
    border-radius: 6px;
    background-color: rgba(255, 255, 255, 0.6);
    font-family: var(--diffs-font-family);
    font-size: 12px;
    line-height: 1.5;
    color: inherit;
    resize: none;
    box-sizing: border-box;
    min-height: 56px;
  }

  .pierre-annotation-textarea:focus {
    outline: none;
    border-color: rgba(120, 87, 255, 0.7);
    box-shadow: 0 0 0 2px rgba(120, 87, 255, 0.15);
  }

  .pierre-annotation-actions {
    display: flex;
    justify-content: flex-end;
    gap: 6px;
    margin-top: 8px;
  }

  .pierre-annotation-button {
    border: 1px solid transparent;
    border-radius: 6px;
    padding: 4px 10px;
    font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
    font-size: 12px;
    font-weight: 500;
    cursor: pointer;
    transition: background-color 0.12s ease, border-color 0.12s ease;
  }

  .pierre-annotation-button-primary {
    background-color: rgba(120, 87, 255, 0.85);
    color: #fff;
  }

  .pierre-annotation-button-primary:hover {
    background-color: rgba(120, 87, 255, 1);
  }

  .pierre-annotation-button-secondary {
    background-color: transparent;
    color: inherit;
    border-color: rgba(140, 140, 160, 0.3);
  }

  .pierre-annotation-button-secondary:hover {
    background-color: rgba(140, 140, 160, 0.12);
  }

  .pierre-annotation-row.pierre-annotation-editor {
    cursor: text;
  }

  .pierre-annotation:has(.pierre-annotation-editor) {
    cursor: default;
  }

  @media (prefers-color-scheme: dark) {
    .pierre-annotation-textarea {
      background-color: rgba(20, 20, 24, 0.5);
      border-color: rgba(255, 255, 255, 0.18);
    }
  }

  /* The delete button reserves layout space at all times — toggling
     `visibility` instead of `display` so it doesn't shift the header text
     left/right when the user hovers in/out. */
  .pierre-annotation-delete {
    visibility: hidden;
    border: none;
    background: none;
    color: inherit;
    font-size: 16px;
    line-height: 1;
    cursor: pointer;
    padding: 2px 4px;
    border-radius: 4px;
    opacity: 0.5;
    display: inline-flex;
    align-items: center;
    transition: opacity 0.15s ease, background-color 0.15s ease;
  }

  .pierre-annotation:hover .pierre-annotation-delete {
    visibility: visible;
  }

  .pierre-annotation-delete:hover {
    opacity: 1;
    background-color: rgba(239, 68, 68, 0.15);
    color: rgba(239, 68, 68, 0.9);
  }

  .pierre-annotation-body {
    color: inherit;
    opacity: 0.85;
    font-size: 12px;
    line-height: 1.5;
    white-space: pre-wrap;
    word-break: break-word;
  }

  @media (prefers-color-scheme: dark) {
    .pierre-annotation {
      border-color: rgba(200, 200, 220, 0.1);
      border-left-color: rgba(120, 87, 255, 0.7);
      background-color: rgba(30, 32, 38, 0.9);
      box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3), 0 1px 4px rgba(0, 0, 0, 0.2);
    }

    .pierre-annotation:hover {
      background-color: rgba(36, 38, 46, 0.95);
      border-color: rgba(200, 200, 220, 0.18);
      box-shadow: 0 4px 14px rgba(0, 0, 0, 0.35), 0 2px 6px rgba(0, 0, 0, 0.25);
    }

    .pierre-annotation-avatar {
      background-color: rgba(96, 165, 250, 0.12);
      color: rgba(96, 165, 250, 0.7);
    }
  }
  """
}
