//
//  DiffModalView.swift
//  PierreDiffsSwift
//
//  Created on 1/10/25.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Full-screen modal view for displaying diffs with integrated approval controls
public struct DiffModalView: View {
  // MARK: - Properties

  let input: DiffInput
  let onDismiss: () -> Void

  @Environment(\.colorScheme) private var colorScheme

  // MARK: - Initialization

  public init(
    input: DiffInput,
    onDismiss: @escaping () -> Void
  ) {
    self.input = input
    self.onDismiss = onDismiss
  }

  // MARK: - Body

  public var body: some View {
    VStack(spacing: 0) {
      // Header bar
      HStack {
        Spacer()
        // Close button
        Button("Close") {
          onDismiss()
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(.escape, modifiers: [])
      }
      .padding()
      .background(headerBackground)
      Divider()

      // Diff content
      DiffEditsView(input: input)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 800, minHeight: 600)
  }

  private var headerBackground: Color {
    #if canImport(AppKit)
    Color(NSColor.controlBackgroundColor)
    #elseif canImport(UIKit)
    Color(UIColor.secondarySystemBackground)
    #else
    Color.gray.opacity(0.15)
    #endif
  }
}
