import SwiftUI
import BugzillaKit
import MarkdownEditorKit
import PhabricatorKit
import SearchfoxKit
import FolioReview
import FolioHighlight
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif
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
    var allowsImages: Bool = false

    @Environment(\.zillaFontScale) private var fontScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AuthStore.self) private var auth
    @Environment(PhabricatorAuthStore.self) private var phab

    @AppStorage("zilla.markdown.mode") private var mode: MarkdownEditorMode = .rich

    @State private var controller: MarkdownEditorController?
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
    @State private var showingImageImporter = false
    @State private var imageError: String?
    #if os(iOS)
    @State private var showingPhotoPicker = false
    @State private var photoSelection: [PhotosPickerItem] = []
    #endif

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
            QuickSearchSheet { bugID in insertBugLink(bugID) }
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
        .fileImporter(
            isPresented: $showingImageImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            insertImageFiles(result)
        }
        #if os(iOS)
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $photoSelection,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            insertPhotos(items)
        }
        #endif
        .alert(
            "Couldn’t Add Image",
            isPresented: Binding(get: { imageError != nil }, set: { if !$0 { imageError = nil } }),
            actions: { Button("OK") { imageError = nil } },
            message: { Text(imageError ?? "") }
        )
    }

    private var richEditor: some View {
        MarkdownTextEditor(text: $text)
            .markdownEditorTheme(.default(fontScale: fontScale))
            .markdownEditorConfiguration(
                MarkdownTextEditor.Configuration(
                    toolbar: showToolbar ? richToolbar : [],
                    minHeight: minHeight,
                    isEditable: !isDisabled
                )
            )
            .inlineContentRules(CommentLabels.proseRules + mentionCompletionContext.inlineContentRules)
            .inlineContentProvider { content in
                guard case let .custom(kind, label, systemImage) = content,
                      kind == CommentLabels.inlineContentKind
                else { return ChipAttachment.make(for: content) }
                let attachment = CommentLabelAttachment()
                attachment.systemImage = systemImage
                attachment.name = label
                return attachment
            }
            .onMarkdownEditorReady { c in
                configureController(c)
                if autoFocus { focusHostTextView(disabled: isDisabled) }
            }
            .onChange(of: isDisabled) { _, nowDisabled in
                if autoFocus, !nowDisabled { focusHostTextView(disabled: nowDisabled) }
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

    private var richToolbar: [MarkdownTextEditor.ToolbarItem] {
        let leading: [MarkdownTextEditor.ToolbarItem] = [
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
        ]
        let images: [MarkdownTextEditor.ToolbarItem] = allowsImages ? [imageInsert] : []

        let labelMenu: [MarkdownTextEditor.ToolbarItem] = mentionCompletionContext.source == .phabricator
            ? [
                .menu(
                    id: "commentLabel",
                    label: "Label",
                    systemImage: "tag",
                    topLevel: true,
                    entries: CommentLabels.all.map { label in
                        MarkdownTextEditor.MenuEntry(
                            id: label.name,
                            title: label.name,
                            systemImage: label.systemImage,
                            action: { insertCommentLabel(label) }
                        )
                    }
                ),
                .divider,
            ]
            : []

        let linkInsert: MarkdownTextEditor.ToolbarItem = .custom(
            id: "linkInsert",
            label: "Insert Link",
            systemImage: "link",
            action: {
                capturePendingSelection()
                showingLinkInsert = true
            }
        )

        let modeToggle: MarkdownTextEditor.ToolbarItem = .custom(
            id: "modeToggle",
            label: "Source",
            systemImage: "chevron.left.forwardslash.chevron.right",
            topLevel: true,
            action: {
                if let md = controller?.markdown() { text = md }
                mode = .source
            }
        )

        return leading + images + [.divider] + labelMenu
            + MarkdownTextEditor.Configuration.defaultToolbar.replacing(.link, with: linkInsert)
            + [.spacer, modeToggle]
    }

    private var imageInsert: MarkdownTextEditor.ToolbarItem {
        #if os(iOS)
        .menu(
            id: "imageInsert",
            label: "Insert Image",
            systemImage: "photo",
            topLevel: true,
            entries: [
                MarkdownTextEditor.MenuEntry(id: "photoLibrary", title: "Photo Library", systemImage: "photo.on.rectangle") {
                    capturePendingSelection()
                    showingPhotoPicker = true
                },
                MarkdownTextEditor.MenuEntry(id: "chooseFile", title: "Choose File", systemImage: "folder") {
                    capturePendingSelection()
                    showingImageImporter = true
                },
            ]
        )
        #else
        .custom(
            id: "imageInsert",
            label: "Insert Image",
            systemImage: "photo",
            topLevel: true,
            action: {
                capturePendingSelection()
                showingImageImporter = true
            }
        )
        #endif
    }

    private func insertImageFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            insertImages(urls.map { url in { try PendingUploadStore.shared.addFile(at: url) } })
        case .failure(let error):
            pendingInsertionSelection = nil
            imageError = error.localizedDescription
        }
    }

    #if os(iOS)
    private func insertPhotos(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [(Data, UTType)] = []
            for item in items {
                let type = item.supportedContentTypes.first { $0.conforms(to: .image) } ?? .image
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        loaded.append((data, type))
                    }
                } catch {
                    imageError = error.localizedDescription
                }
            }
            insertImages(loaded.map { data, type in
                { try PendingUploadStore.shared.add(data: data, contentType: type, suggestedName: nil) }
            })
        }
    }
    #endif

    private func insertImages(_ makers: [() throws -> String]) {
        var snippets: [String] = []
        for make in makers {
            do {
                snippets.append(try make())
            } catch {
                imageError = error.localizedDescription
            }
        }
        restorePendingSelection()
        guard !snippets.isEmpty else { return }
        controller?.insertMarkdown(snippets.joined(separator: " "), label: "Insert Image")
    }

    private func pasteImages(_ event: PasteEvent, into controller: MarkdownEditorController) -> Bool {
        guard !event.images.isEmpty, !event.inCode else { return false }
        var snippets: [String] = []
        for image in event.images {
            do {
                snippets.append(try PendingUploadStore.shared.add(
                    data: image.data,
                    contentType: image.contentType,
                    suggestedName: image.suggestedName
                ))
            } catch {
                imageError = error.localizedDescription
            }
        }
        guard !snippets.isEmpty else { return event.text == nil }
        return controller.insertMarkdown(snippets.joined(separator: " "), replacing: event.selection, label: "Paste Image")
    }

    /// Labels lead their comment, so the token goes at the start of the
    /// paragraph the caret is in — replacing a label already there rather than
    /// stacking a second one.
    private func insertCommentLabel(_ label: CommentLabels.Label) {
        guard let controller else { return }
        controller.setSelection(existingLabelRange(in: controller))
        controller.insertMarkdown(CommentLabels.insertionText(for: label), label: "Insert Label")
    }

    /// The span the new token replaces: an existing leading label plus the
    /// space after it, or an empty range at the paragraph's start.
    private func existingLabelRange(in controller: MarkdownEditorController) -> NSRange {
        let text = controller.textStorage.string as NSString
        let caret = min(controller.currentSelection.location, text.length)
        let paragraph = text.paragraphRange(for: NSRange(location: caret, length: 0))
        let start = paragraph.location
        guard start < text.length,
              controller.inlineContentKind(at: start) == CommentLabels.inlineContentKind
        else { return NSRange(location: start, length: 0) }
        var length = 1
        if start + 1 < NSMaxRange(paragraph), text.character(at: start + 1) == 32 {
            length = 2
        }
        return NSRange(location: start, length: length)
    }

    private func insertBugLink(_ bugID: Bug.ID) {
        let url = "https://bugzilla.mozilla.org/show_bug.cgi?id=\(bugID)"
        restorePendingSelection()
        controller?.insertLink(label: "bug \(bugID)", url: url)
    }

    private func insertMarkdownLink(label: String, url: String) {
        restorePendingSelection()
        controller?.insertLink(label: label, url: url)
    }

    private func focusHostTextView(disabled: Bool) {
        #if canImport(UIKit)
        guard !didAutoFocus, !disabled else { return }
        Task { @MainActor in
            for _ in 0..<10 {
                if didAutoFocus { return }
                if let view = controller?.hostTextView, view.window != nil,
                   view.becomeFirstResponder() {
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
    }

    private func capturePendingSelection() {
        pendingInsertionSelection = controller?.currentSelection
    }

    private func restorePendingSelection() {
        guard let selection = pendingInsertionSelection else { return }
        controller?.setSelection(selection)
        pendingInsertionSelection = nil
    }

    @ViewBuilder
    private var completionPopup: some View {
        if let completionSession, let controller, !completionItems.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(completionItems.enumerated()), id: \.element.id) { index, item in
                            Button {
                                applyMentionCompletion(item, session: completionSession, controller: controller)
                            } label: {
                                completionRow(item, isHighlighted: index == completionSession.highlightedIndex)
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                        }
                    }
                }
                .onChange(of: completionSession.highlightedIndex) { _, newValue in
                    scrollToHighlighted(newValue, proxy: proxy)
                }
                .onChange(of: completionItems.map(\.id)) { _, _ in
                    scrollToHighlighted(completionSession.highlightedIndex, proxy: proxy)
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

    private func scrollToHighlighted(_ index: Int, proxy: ScrollViewProxy) {
        guard index >= 0, index < completionItems.count else { return }
        proxy.scrollTo(completionItems[index].id, anchor: .center)
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
        controller: MarkdownEditorController
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

    private func triggerRect(for session: CompletionSession, controller: MarkdownEditorController) -> CGRect? {
        rectForCharacter(at: session.context.range.location, controller: controller)
    }

    private func completionAnchorRect(for session: CompletionSession, controller: MarkdownEditorController) -> CGRect? {
        guard var rect = triggerRect(for: session, controller: controller) ?? session.context.caretRect ?? controller.caretRect() else {
            return nil
        }
        if let hostFrame = completionCoordinates.hostTextViewFrame {
            rect.origin.x += hostFrame.minX
            rect.origin.y += hostFrame.minY
        }
        return rect
    }

    private func rectForCharacter(at characterIndex: Int, controller: MarkdownEditorController) -> CGRect? {
        controller.rect(forCharacterAt: characterIndex)
    }

    private func configureController(_ c: MarkdownEditorController) {
        controller = c
        if autolinksReferences {
            c.registerZillaAutoLinkPluginIfNeeded()
        }
        if allowsImages, !c.plugins.contains(where: { $0.key.name == ImagePastePlugin.keyName }) {
            c.register(plugin: ImagePastePlugin { controller, event in
                pasteImages(event, into: controller)
            })
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
        controller: MarkdownEditorController
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
        controller: MarkdownEditorController
    ) {
        controller.insertInlineContent(
            item.inlineContent,
            markdownSource: item.markdownSource,
            replacing: session.context.range,
            label: "Insert Mention"
        )
        completionPlugin?.cancel(controller: controller)
    }
}

final class ImagePastePlugin: EditorPlugin {
    static let keyName = "zilla.imagePaste"

    let key = AnyPluginKey(name: keyName)
    private let onPaste: (MarkdownEditorController, PasteEvent) -> Bool

    init(onPaste: @escaping (MarkdownEditorController, PasteEvent) -> Bool) {
        self.onPaste = onPaste
    }

    var props: PluginProps {
        PluginProps(handlePaste: { [onPaste] controller, event in
            onPaste(controller, event)
        })
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

#if canImport(AppKit) && os(macOS)
private struct CompletionCoordinateReader: NSViewRepresentable {
    let controller: MarkdownEditorController?
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
        weak var controller: MarkdownEditorController?
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
            if let host = controller?.hostTextView {
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
    let controller: MarkdownEditorController?
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
        weak var controller: MarkdownEditorController?
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
            if let host = controller?.hostTextView {
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
