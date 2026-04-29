//
//  DiffWebViewEvent.swift
//  PierreDiffsSwift
//
//  Created by James Rochabrun on 1/6/26.
//

import Foundation

/// Events sent from the JavaScript diff renderer to Swift.
enum DiffWebViewEvent {
  /// The JavaScript bridge is ready to receive commands
  case bridgeReady

  /// The diff has been rendered and is ready for interaction
  case ready

  /// A line was clicked (includes position for UI overlay positioning)
  case lineClicked(lineNumber: Int, side: String, lineY: CGFloat, lineHeight: CGFloat)

  /// Text selection changed
  case selectionChanged(startLine: Int, endLine: Int, side: String)

  /// System theme changed
  case systemThemeChanged(isDark: Bool)

  /// An annotation was clicked
  case annotationClicked(id: String, side: String, lineNumber: Int)

  /// An annotation delete was requested
  case annotationDeleteRequested(id: String, side: String, lineNumber: Int)

  /// A user pressed Save in an inline comment composer/editor. `commentID` is
  /// the per-comment identifier (e.g. the synthetic id assigned to the draft);
  /// `annotationID` identifies the parent thread/annotation.
  case annotationDraftSubmitted(annotationID: String, commentID: String, body: String, side: String, lineNumber: Int)

  /// A user pressed Cancel in an inline comment composer/editor.
  case annotationDraftCancelled(annotationID: String, commentID: String, side: String, lineNumber: Int)

  /// The rendered document content height changed. Hosts can size their
  /// container to this value to avoid an inner scrollbar.
  case contentHeightChanged(height: CGFloat)

  /// An error occurred in the JavaScript layer
  case error(message: String)
}
