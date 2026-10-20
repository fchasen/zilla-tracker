#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Zilla

@MainActor
@Suite struct MarkdownEditorToolbarTests {
    private func toolbarButtons(allowsImages: Bool) -> [String] {
        UserDefaults.standard.set(MarkdownEditorMode.rich.rawValue, forKey: "zilla.markdown.mode")
        let editor = MarkdownEditor(text: .constant(""), allowsImages: allowsImages)
            .environment(AuthStore())
            .environment(PhabricatorAuthStore())
        let host = NSHostingView(rootView: editor)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        defer { window.close() }

        var buttons: [String] = []
        func walk(_ view: NSView) {
            if let control = view as? NSSegmentedControl {
                buttons += (0..<control.segmentCount).compactMap { control.toolTip(forSegment: $0) }
            }
            view.subviews.forEach(walk)
        }
        walk(host)
        return buttons
    }

    @Test func toolbarOffersInsertImageWhenImagesAreAllowed() {
        let buttons = toolbarButtons(allowsImages: true)
        #expect(Array(buttons.prefix(3)) == ["Searchfox", "Insert Bug", "Insert Image"])
    }

    @Test func toolbarOmitsInsertImageWhenImagesAreNotAllowed() {
        let buttons = toolbarButtons(allowsImages: false)
        #expect(buttons.contains("Insert Bug"))
        #expect(!buttons.contains("Insert Image"))
    }
}
#endif
