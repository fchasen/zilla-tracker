import SwiftUI
import BugzillaKit
import SwiftProse
import PhabricatorKit
import SearchfoxKit
import FolioCodeView
import FolioHighlight
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum MarkdownEditorMode: String, CaseIterable {
    case rich
    case source
}

struct MarkdownEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 96
    var isDisabled: Bool = false
    var bordered: Bool = true
    var showToolbar: Bool = true
    var autoFocus: Bool = false
    var autolinksReferences: Bool = false
    var mentionCompletionContext: MentionCompletionContext = .none

    @Environment(\.zillaFontScale) private var fontScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AuthStore.self) private var auth
    @Environment(PhabricatorAuthStore.self) private var phab

    @AppStorage("zilla.markdown.mode") private var mode: MarkdownEditorMode = .rich

    @State private var controller: EditorController?
    @State private var completionPlugin: CompletionPlugin?
    @State private var completionSession: CompletionSession?
    @State private var completionItems: [MentionCompletionItem] = []
    @State private var completionFetchTask: Task<Void, Never>?
    @State private var completionCoordinates = CompletionCoordinateState()
    @State private var showingLinkPicker = false
    @State private var showingSearchfoxPicker = false
    @State private var showingLinkInsert = false
    @State private var didAutoFocus = false
    @State private var pendingInsertionSelection: NSRange?

    var body: some View {
        Group {
            switch mode {
            case .rich:
                richEditor
            case .source:
                sourceEditor
            }
        }
        .disabled(isDisabled)
        .sheet(isPresented: $showingLinkPicker) {
            QuickSearchSheet(
                onPickBug: { bugID in insertBugLink(bugID) },
                onPickUser: { user in insertUserMention(user) }
            )
        }
        .sheet(isPresented: $showingSearchfoxPicker) {
            SearchfoxPickerSheet { hit, symbol in
                insertSearchfoxLink(hit, symbol: symbol)
            }
        }
        .sheet(isPresented: $showingLinkInsert) {
            LinkInsertSheet { label, url in
                insertMarkdownLink(label: label, url: url)
            }
        }
    }

    private var richEditor: some View {
        SwiftProseEditor(text: $text)
            .theme(.default(fontScale: fontScale))
            .configuration(SwiftProseEditor.Configuration(toolbar: showToolbar ? richToolbar : [], minHeight: minHeight))
            .onProseControllerReady { c in
                configureController(c)
                if autoFocus { focusHostTextView() }
            }
            .frame(minHeight: minHeight)
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
            }
            .background {
                CompletionCoordinateReader(controller: controller) { coordinates in
                    completionCoordinates = coordinates
                }
            }
            .overlay(alignment: .topLeading) {
                completionPopup
            }
            .onChange(of: mentionCompletionContext) { _, _ in
                guard let controller else { return }
                configureController(controller)
                if let completionSession, let completionPlugin {
                    fetchMentionCompletions(for: completionSession.context, plugin: completionPlugin, controller: controller)
                }
            }
    }

    private var sourceEditor: some View {
        VStack(spacing: 0) {
            if showToolbar {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Spacer()
                        ControlGroup {
                            Button {
                                mode = .rich
                            } label: {
                                Image(systemName: "eye")
                                    .frame(width: toolbarButtonWidth, height: toolbarButtonHeight)
                            }
                            .help("Switch to rich editor")
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(6)
            }
            CodeEditorRepresentable(
                text: $text,
                language: .markdown,
                theme: colorScheme == .dark ? .dark : .light,
                font: sourceFont,
                fitsContent: true,
                minHeight: minHeight
            )
        }
        .overlay {
            if bordered {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            }
        }
    }

    private var toolbarButtonWidth: CGFloat {
        #if os(iOS)
        return 36
        #else
        return 28
        #endif
    }

    private var toolbarButtonHeight: CGFloat {
        #if os(iOS)
        return 32
        #else
        return 24
        #endif
    }

    private var sourceFont: PlatformFont {
        let size = PlatformFont.systemFontSize * max(fontScale, 0.1)
        return PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private var richToolbar: [SwiftProseEditor.ToolbarItem] {
        let leading: [SwiftProseEditor.ToolbarItem] = [
            .custom(
                id: "searchfoxPicker",
                label: "Searchfox",
                systemImage: "magnifyingglass",
                shortcut: KeyboardShortcut("f", modifiers: .command),
                topLevel: true,
                action: {
                    capturePendingSelection()
                    showingSearchfoxPicker = true
                }
            ),
            .custom(
                id: "bugPicker",
                label: "Insert Bug",
                systemImage: "ant",
                shortcut: KeyboardShortcut("k", modifiers: .command),
                topLevel: true,
                action: {
                    capturePendingSelection()
                    showingLinkPicker = true
                }
            ),
            .divider,
        ]

        let linkInsert: SwiftProseEditor.ToolbarItem = .custom(
            id: "linkInsert",
            label: "Insert Link",
            systemImage: "link",
            action: {
                capturePendingSelection()
                showingLinkInsert = true
            }
        )

        let modeToggle: SwiftProseEditor.ToolbarItem = .custom(
            id: "modeToggle",
            label: "Source",
            systemImage: "chevron.left.forwardslash.chevron.right",
            topLevel: true,
            action: {
                if let md = controller?.markdown() { text = md }
                mode = .source
            }
        )

        return leading
            + SwiftProseEditor.Configuration.defaultToolbar.replacing(.link, with: linkInsert)
            + [.spacer, modeToggle]
    }

    private func insertBugLink(_ bugID: Bug.ID) {
        let url = "https://bugzilla.mozilla.org/show_bug.cgi?id=\(bugID)"
        restorePendingSelection()
        controller?.insertLink(label: "bug \(bugID)", url: url)
        pushMarkdownToBinding()
    }

    private func insertMarkdownLink(label: String, url: String) {
        restorePendingSelection()
        controller?.insertLink(label: label, url: url)
        pushMarkdownToBinding()
    }

    private func insertUserMention(_ user: User) {
        restorePendingSelection()
        controller?.insert(text: ":\(mentionHandle(for: user))")
        pushMarkdownToBinding()
    }

    private func mentionHandle(for user: User) -> String {
        if let nick = user.nick, !nick.isEmpty { return nick }
        let local = user.name.split(separator: "@").first.map(String.init) ?? user.name
        return local
    }

    private func focusHostTextView() {
        #if canImport(UIKit)
        guard !didAutoFocus else { return }
        Task { @MainActor in
            for _ in 0..<10 {
                if let view = controller?.hostTextView as? UIView, view.window != nil {
                    view.becomeFirstResponder()
                    didAutoFocus = true
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        #endif
    }

    private func insertSearchfoxLink(_ hit: SearchHit, symbol: String? = nil) {
        let label: String
        if let symbol, !symbol.isEmpty {
            label = symbol
        } else {
            label = (hit.path as NSString).lastPathComponent
        }
        restorePendingSelection()
        controller?.insertLink(label: label, url: hit.url)
        pushMarkdownToBinding()
    }

    private func capturePendingSelection() {
        pendingInsertionSelection = controller?.currentSelection
    }

    private func restorePendingSelection() {
        guard let selection = pendingInsertionSelection else { return }
        controller?.setSelection(selection)
        pendingInsertionSelection = nil
    }

    private func pushMarkdownToBinding() {
        guard let md = controller?.markdown(), md != text else { return }
        text = md
    }

    @ViewBuilder
    private var completionPopup: some View {
        if let completionSession, let controller, !completionItems.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(completionItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            applyMentionCompletion(item, session: completionSession, controller: controller)
                        } label: {
                            completionRow(item, isHighlighted: index == completionSession.highlightedIndex)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 280)
            .frame(maxHeight: completionPopupHeight)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .offset(completionPopupOffset(for: completionSession, controller: controller))
            .transition(.opacity)
        }
    }

    private func completionRow(_ item: MentionCompletionItem, isHighlighted: Bool) -> some View {
        HStack(spacing: 8) {
            UserAvatar(email: item.avatarEmail, size: 24, imageURL: item.avatarURL)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.handle)
                    .scaledFont(.callout, weight: .semibold)
                    .lineLimit(1)
                Text(item.displayName)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(item.detail)
                .scaledFont(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHighlighted ? Color.accentColor.opacity(0.18) : .clear)
    }

    private func completionPopupOffset(
        for session: CompletionSession,
        controller: EditorController
    ) -> CGSize {
        guard let rect = completionAnchorRect(for: session, controller: controller) else {
            return .zero
        }
        let gap: CGFloat = 4
        let width: CGFloat = 280
        let origin = CompletionPopupPlacement.origin(
            anchorRect: rect,
            menuSize: CGSize(width: width, height: completionPopupHeight),
            containerBounds: completionCoordinates.effectivePlacementBounds,
            gap: gap
        )
        return CGSize(width: origin.x, height: origin.y)
    }

    private var completionPopupHeight: CGFloat {
        min(240, max(40, CGFloat(completionItems.count) * 44))
    }

    private func triggerRect(for session: CompletionSession, controller: EditorController) -> CGRect? {
        rectForCharacter(at: session.context.range.location, controller: controller)
    }

    private func completionAnchorRect(for session: CompletionSession, controller: EditorController) -> CGRect? {
        guard var rect = triggerRect(for: session, controller: controller) ?? session.context.caretRect ?? controller.caretRect() else {
            return nil
        }
        if let hostFrame = completionCoordinates.hostTextViewFrame {
            rect.origin.x += hostFrame.minX
            rect.origin.y += hostFrame.minY
        }
        return rect
    }

    private func rectForCharacter(at characterIndex: Int, controller: EditorController) -> CGRect? {
        let total = controller.textStorage.length
        guard characterIndex >= 0, characterIndex <= total else { return nil }
        let docStart = controller.contentStorage.documentRange.location
        guard let location = controller.contentStorage.location(docStart, offsetBy: characterIndex) else { return nil }
        let textRange = NSTextRange(location: location)
        var rect: CGRect?
        controller.layoutManager.enumerateTextSegments(
            in: textRange,
            type: .standard,
            options: [.upstreamAffinity, .rangeNotRequired]
        ) { _, frame, _, _ in
            rect = frame
            return false
        }
        guard var result = rect else { return nil }
        #if canImport(AppKit) && os(macOS)
        if let textView = controller.hostTextView as? NSTextView {
            result.origin.x += textView.textContainerInset.width
            result.origin.y += textView.textContainerInset.height
        }
        #elseif canImport(UIKit)
        if let textView = controller.hostTextView as? UITextView {
            result.origin.x += textView.textContainerInset.left
            result.origin.y += textView.textContainerInset.top
        }
        #endif
        return result
    }

    private func configureController(_ c: EditorController) {
        controller = c
        if autolinksReferences {
            c.registerZillaAutoLinkPluginIfNeeded()
        }
        guard mentionCompletionContext.source != nil else {
            completionPlugin?.cancel(controller: c)
            completionItems = []
            return
        }

        let plugin: CompletionPlugin
        if let existing = completionPlugin {
            plugin = existing
        } else {
            plugin = CompletionPlugin(triggers: [
                CompletionTrigger(id: "mention", prefix: "@")
            ])
            completionPlugin = plugin
        }

        plugin.onSessionChanged = { newSession in
            Task { @MainActor in
                let previousContext = completionSession?.context
                completionSession = newSession
                guard let newSession else {
                    completionFetchTask?.cancel()
                    completionItems = []
                    return
                }
                guard previousContext != newSession.context else { return }
                if previousContext?.range.location != newSession.context.range.location
                    || previousContext?.triggerID != newSession.context.triggerID {
                    completionItems = []
                }
                fetchMentionCompletions(for: newSession.context, plugin: plugin, controller: c)
            }
        }
        plugin.onCommit = { c, session in
            Task { @MainActor in
                guard !completionItems.isEmpty,
                      session.highlightedIndex >= 0,
                      session.highlightedIndex < completionItems.count else { return }
                applyMentionCompletion(completionItems[session.highlightedIndex], session: session, controller: c)
            }
        }
        if !c.plugins.contains(where: { $0.key.name == plugin.key.name }) {
            c.register(plugin: plugin)
        }
        plugin.attach(to: c)
    }

    private func fetchMentionCompletions(
        for context: CompletionContext,
        plugin: CompletionPlugin,
        controller: EditorController
    ) {
        completionFetchTask?.cancel()
        let query = context.query
        let mentionContext = mentionCompletionContext
        let bugzillaClient = auth.isSignedIn ? auth.client : nil
        let phabricatorClient = phab.isSignedIn ? phab.client : nil
        let currentBugzillaUser = auth.currentUser
        let currentPhabricatorUser = phab.currentUser
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultItems = MentionCompletionRanker.excludingCurrentUser(
            mentionContext.defaultItems,
            bugzillaUser: currentBugzillaUser,
            phabricatorUser: currentPhabricatorUser
        )
        let defaults = MentionCompletionRanker.ranked(defaultItems, query: query, limit: 8)
        guard !trimmed.isEmpty else {
            completionItems = defaults
            plugin.updateItemCount(defaults.count, controller: controller)
            return
        }
        completionFetchTask = Task {
            var items = defaultItems
            if mentionContext.source == .phabricator, let phabricatorClient {
                if let users = try? await phabricatorClient.searchUsers(query: trimmed, limit: 12) {
                    items.append(contentsOf: users.map(MentionCompletionItem.init(user:)))
                }
            }
            if mentionContext.source == .bugzilla, let bugzillaClient {
                if let users = try? await bugzillaClient.searchUsers(match: trimmed, limit: 12) {
                    items.append(contentsOf: users.map(MentionCompletionItem.init(user:)))
                }
            }
            let filtered = MentionCompletionRanker.excludingCurrentUser(
                items,
                bugzillaUser: currentBugzillaUser,
                phabricatorUser: currentPhabricatorUser
            )
            let ranked = MentionCompletionRanker.ranked(filtered, query: query, limit: 8)
            if Task.isCancelled { return }
            await MainActor.run {
                completionItems = ranked
                plugin.updateItemCount(ranked.count, controller: controller)
            }
        }
    }

    private func applyMentionCompletion(
        _ item: MentionCompletionItem,
        session: CompletionSession,
        controller: EditorController
    ) {
        controller.apply(Transaction(steps: [
            .replaceText(range: session.context.range, with: NSAttributedString(string: item.replacementText))
        ]))
        completionPlugin?.cancel(controller: controller)
        pushMarkdownToBinding()
    }
}

struct CompletionCoordinateState: Equatable {
    var bounds: CGRect = .zero
    var placementBounds: CGRect = .zero
    var hostTextViewFrame: CGRect?

    var effectivePlacementBounds: CGRect {
        placementBounds.isEmpty ? bounds : placementBounds
    }
}

enum CompletionPopupPlacement {
    static func origin(
        anchorRect: CGRect,
        menuSize: CGSize,
        containerBounds: CGRect,
        gap: CGFloat = 4,
        edgeInset: CGFloat = 24
    ) -> CGPoint {
        let horizontalInset = min(edgeInset, max(0, (containerBounds.width - menuSize.width) / 2))
        let verticalInset = min(edgeInset, max(0, containerBounds.height / 4))
        let effectiveBounds = containerBounds.insetBy(dx: horizontalInset, dy: verticalInset)
        let maxX = max(effectiveBounds.minX, effectiveBounds.maxX - menuSize.width)
        let x = min(max(anchorRect.minX, effectiveBounds.minX), maxX)
        let belowY = anchorRect.maxY + gap
        let aboveY = anchorRect.minY - menuSize.height - gap
        let availableBelow = effectiveBounds.maxY - belowY
        let availableAbove = anchorRect.minY - effectiveBounds.minY - gap
        let y: CGFloat
        if availableBelow >= menuSize.height {
            y = belowY
        } else if availableAbove >= menuSize.height {
            y = aboveY
        } else if availableBelow >= availableAbove {
            y = belowY
        } else {
            y = aboveY
        }
        return CGPoint(x: x, y: y)
    }
}

#if canImport(AppKit) && os(macOS)
private struct CompletionCoordinateReader: NSViewRepresentable {
    let controller: EditorController?
    let onChange: (CompletionCoordinateState) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.controller = controller
        nsView.onChange = onChange
        nsView.schedulePublish()
    }

    final class ProbeView: NSView {
        weak var controller: EditorController?
        var onChange: ((CompletionCoordinateState) -> Void)?
        private var lastState = CompletionCoordinateState()

        override var isFlipped: Bool { true }

        override func layout() {
            super.layout()
            schedulePublish()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            schedulePublish()
        }

        func schedulePublish() {
            DispatchQueue.main.async { [weak self] in
                self?.publish()
            }
        }

        private func publish() {
            let hostFrame: CGRect?
            if let host = controller?.hostTextView as? NSView {
                hostFrame = host.convert(host.bounds, to: self)
            } else {
                hostFrame = nil
            }
            let next = CompletionCoordinateState(
                bounds: bounds,
                placementBounds: visiblePlacementBounds() ?? bounds,
                hostTextViewFrame: hostFrame
            )
            guard next != lastState else { return }
            lastState = next
            onChange?(next)
        }

        private func visiblePlacementBounds() -> CGRect? {
            var visible: CGRect?
            if let contentView = window?.contentView {
                visible = contentView.convert(contentView.bounds, to: self)
            }
            if let window, let screen = window.screen {
                let screenRect = convert(window.convertFromScreen(screen.visibleFrame), from: nil)
                if let current = visible {
                    let intersection = current.intersection(screenRect)
                    visible = intersection.isNull || intersection.isEmpty ? current : intersection
                } else {
                    visible = screenRect
                }
            }
            return visible
        }
    }
}
#elseif canImport(UIKit)
private struct CompletionCoordinateReader: UIViewRepresentable {
    let controller: EditorController?
    let onChange: (CompletionCoordinateState) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.controller = controller
        uiView.onChange = onChange
        uiView.schedulePublish()
    }

    final class ProbeView: UIView {
        weak var controller: EditorController?
        var onChange: ((CompletionCoordinateState) -> Void)?
        private var lastState = CompletionCoordinateState()

        override func layoutSubviews() {
            super.layoutSubviews()
            schedulePublish()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            schedulePublish()
        }

        func schedulePublish() {
            DispatchQueue.main.async { [weak self] in
                self?.publish()
            }
        }

        private func publish() {
            let hostFrame: CGRect?
            if let host = controller?.hostTextView as? UIView {
                hostFrame = host.convert(host.bounds, to: self)
            } else {
                hostFrame = nil
            }
            let next = CompletionCoordinateState(
                bounds: bounds,
                placementBounds: visiblePlacementBounds() ?? bounds,
                hostTextViewFrame: hostFrame
            )
            guard next != lastState else { return }
            lastState = next
            onChange?(next)
        }

        private func visiblePlacementBounds() -> CGRect? {
            guard let window else { return nil }
            let safeBounds = window.bounds.inset(by: window.safeAreaInsets)
            return window.convert(safeBounds, to: self)
        }
    }
}
#endif
