//
//  DiffAnnotation.swift
//  PierreDiffsSwift
//
//  Created by James Rochabrun on 4/7/26.
//

import Foundation

/// Which side of the diff an annotation belongs to.
public enum AnnotationSide: String, Codable, Sendable {
  case deletions
  case additions
}

/// An annotation attached to a specific line in a diff.
/// Matches @pierre/diffs DiffLineAnnotation<T>.
public struct DiffAnnotation: Codable, Sendable, Equatable {
  public let side: AnnotationSide
  public let lineNumber: Int
  public let metadata: AnnotationMetadata

  public init(side: AnnotationSide, lineNumber: Int, metadata: AnnotationMetadata) {
    self.side = side
    self.lineNumber = lineNumber
    self.metadata = metadata
  }
}

/// Metadata for an inline comment annotation.
public struct AnnotationMetadata: Codable, Sendable, Equatable {
  public let id: String
  public let author: String
  public let body: String
  public let avatarURL: String?
  public let subtitle: String?
  /// Editor mode for this annotation when no `comments` array is provided.
  /// Use `"display"` for a static comment (default), `"compose"` to render a
  /// textarea + Save/Cancel for a new draft, or `"edit"` to render a textarea
  /// pre-filled with `body` for editing an existing draft.
  public let mode: String?
  /// Optional thread of comments. When provided and non-empty, the annotation
  /// renders as a stack of avatar + author + body rows in this order — the
  /// first entry is the parent comment, subsequent entries are replies.
  /// When `nil`, falls back to rendering the single (author, body) on this
  /// metadata.
  public let comments: [Comment]?
  /// When `true`, the X delete affordance is rendered on the root row.
  /// Defaults to `false`/`nil` so consumers must opt in per annotation.
  public let deletable: Bool?

  public struct Comment: Codable, Sendable, Equatable {
    public let id: String
    public let author: String
    public let body: String
    public let avatarURL: String?
    public let subtitle: String?
    /// `"display"`, `"compose"`, or `"edit"`. See `AnnotationMetadata.mode`.
    public let mode: String?

    public init(
      id: String = UUID().uuidString,
      author: String,
      body: String,
      avatarURL: String? = nil,
      subtitle: String? = nil,
      mode: String? = nil
    ) {
      self.id = id
      self.author = author
      self.body = body
      self.avatarURL = avatarURL
      self.subtitle = subtitle
      self.mode = mode
    }
  }

  public init(
    id: String = UUID().uuidString,
    author: String,
    body: String,
    avatarURL: String? = nil,
    subtitle: String? = nil,
    mode: String? = nil,
    comments: [Comment]? = nil,
    deletable: Bool? = nil
  ) {
    self.id = id
    self.author = author
    self.body = body
    self.avatarURL = avatarURL
    self.subtitle = subtitle
    self.mode = mode
    self.comments = comments
    self.deletable = deletable
  }
}
