import Foundation
import Observation

@Observable
final class EditorHosting {
    struct ToolbarState: Equatable {
        var active: Set<String> = []
        var disabled: Set<String> = []
    }

    private(set) var toolbarState = ToolbarState()

    @ObservationIgnored private(set) var controller: MarkdownEditorController?
    @ObservationIgnored private var observerTokens: [MarkdownEditorController.ObserverToken] = []
    @ObservationIgnored private var refreshScheduled = false
    @ObservationIgnored var trackedActions: [EditorAction] = []

    init() {}

    deinit {
        if let controller {
            for token in observerTokens { controller.removeObserver(token) }
        }
    }

    @discardableResult
    func ensureController(
        markdown: String,
        theme: MarkdownEditorTheme,
        inlineContentRules: [InlineContentRule],
        inlineContentProvider: InlineContentProvider?,
        allowsCheckboxToggle: Bool
    ) -> MarkdownEditorController {
        if let controller { return controller }
        let created = MarkdownEditorController(
            markdown: markdown,
            theme: theme,
            inlineContentRules: inlineContentRules,
            inlineContentProvider: inlineContentProvider
        )
        created.allowsCheckboxToggle = allowsCheckboxToggle
        controller = created
        observerTokens = [
            created.addOnSelectionChanged { [weak self] _ in self?.scheduleToolbarRefresh() },
            created.addOnDocumentChange { [weak self] _ in self?.scheduleToolbarRefresh() }
        ]
        scheduleToolbarRefresh()
        return created
    }

    func applyInlineContent(rules: [InlineContentRule], provider: InlineContentProvider?) {
        guard let controller else { return }
        let sameRules = controller.inlineContentRules.map(\.id) == rules.map(\.id)
        let sameProvider = (controller.inlineContentProvider == nil) == (provider == nil)
        guard !sameRules || !sameProvider else { return }
        controller.setInlineContent(rules: rules, provider: provider)
    }

    func scheduleToolbarRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refreshToolbarState()
        }
    }

    func refreshToolbarState() {
        guard let controller else { return }
        let next = ToolbarState(
            active: controller.activeActionIDs(),
            disabled: Set(trackedActions.filter { !controller.canPerform($0) }.map(\.stableID))
        )
        if next != toolbarState { toolbarState = next }
    }

    func isActive(_ action: EditorAction) -> Bool {
        toolbarState.active.contains(action.stableID)
    }

    func canPerform(_ action: EditorAction) -> Bool {
        !toolbarState.disabled.contains(action.stableID)
    }
}
