//
//  Pasteboard.swift
//  Zilla
//

import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
func copyToPasteboard(_ value: String) {
    #if canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    #elseif canImport(UIKit)
    UIPasteboard.general.string = value
    #endif
}
