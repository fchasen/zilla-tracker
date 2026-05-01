# Zilla Tracker

A native macOS and iOS client for Mozilla's [Bugzilla](https://bugzilla.mozilla.org) and [Phabricator](https://phabricator.services.mozilla.com), with deep linking into [Searchfox](https://searchfox.org/).

## Status

Targets only production:

- Bugzilla: `https://bugzilla.mozilla.org`
- Phabricator: `https://phabricator.services.mozilla.com`

There is no staging configuration; both hosts are hard-coded as defaults.

## Building

The project is an Xcode workspace (`Zilla.xcodeproj`) containing the app and five local Swift packages. The Rust UniFFI bridge for Searchfox is committed in-tree as a pre-built `xcframework`, so a fresh clone builds without a Rust toolchain.

```sh
# macOS app
xcodebuild -project Zilla.xcodeproj -scheme Zilla -destination 'platform=macOS' build

# iOS app (open the project in Xcode and pick a simulator destination)
xcodebuild -project Zilla.xcodeproj -scheme Zilla -destination 'generic/platform=iOS Simulator' build

# App-level XCTest target
xcodebuild -project Zilla.xcodeproj -scheme Zilla -destination 'platform=macOS' test

# Library tests (no Xcode required)
swift test --package-path Packages/BugzillaKit
swift test --package-path Packages/PhabricatorKit
swift test --package-path Packages/FolioCodeView
swift test --package-path Packages/MarginaliaEditor
```

## Repository layout

```
Zilla/                 The macOS/iOS app target
ZillaTests/            App-level XCTests
ZillaUITests/          UI tests
Packages/              Local Swift packages (linked by the app)
  BugzillaKit/         Bugzilla REST client
  PhabricatorKit/      Phabricator Conduit client
  SearchfoxKit/        Generated UniFFI bindings for searchfox-lib
  FolioCodeView/       Side-by-side and unified diff viewer with inline comments
  MarginaliaEditor/    TextKit 2 live Markdown / Remarkup editor
Tools/
  searchfox-bridge/    Rust crate that produces SearchfoxKit via cargo swift
  regenerate-tree-sitter-*.sh
                       Scripts that refresh the vendored tree-sitter grammars
  MakeIcon.swift       Renders the app icon into Assets.xcassets
```

Each package has its own README with API details and build instructions.

## Architecture overview

`ZillaApp` (`Zilla/ZillaApp.swift`) is the SwiftUI entry point. It instantiates four `@Observable` stores and injects them into the environment:

| Store | Owns |
|-------|------|
| `AuthStore` | `BugzillaClient`; Bugzilla API key in Keychain (`mozilla.Zilla.api-key`); login state machine. |
| `PhabricatorAuthStore` | `PhabricatorClient`; Conduit API token in Keychain (`mozilla.Zilla.phabricator-token`). |
| `Workspace` | Sidebar selection, current bug/revision, sort modes, dependency cache, inspector flags. Most views read it from the environment rather than holding their own copies. |
| `ViewedBugsStore` / `ViewedRevisionsStore` | Read/unread tracking. |

SwiftData persists `FollowedComponent`, `FollowedMetaBug`, `BugDraft`, and `BugOrderEntry`.

`ContentView` is a three-column `NavigationSplitView`:

1. **Sidebar** — fixed smart endpoints (`SmartEndpoint`: My Bugs / Reported / Needs Review / Recently Changed), Phabricator review lists, Drafts, then user-curated `FollowedComponent` and `FollowedMetaBug` rows.
2. **Content** — `BugListView` driven by `Workspace.bugQuery(for:)`, or `RevisionListView` for review selections.
3. **Detail** — `BugDetailView`, `RevisionDetailView`, or `DraftEditorView` based on the selection. The optional inspector column shows `BugInspector` or `DraftInspector`.

`SidebarSelection` (`smart | allDrafts | review | component | metaBug`) is mapped to a `BugQuery` in `Workspace.bugQuery(for:)` — that's the seam new sidebar destinations plug into.

### Bug ordering

The `ordered` sort mode is hybrid: the server query uses `changeddate DESC` (`BugListSort.bmoOrder`) and the user's manual order is reapplied client-side from `BugOrderEntry` rows keyed by `endpointKey`. BMO can't express user-defined order, so it stays local.

### Quick search

Shift+Space (when no text field is focused) opens `QuickSearchSheet`. The shortcut is installed via `NSEvent.addLocalMonitorForEvents` in `ContentView` (macOS only).

### Networking

`BugzillaClient` and `PhabricatorClient` are `actor`s holding their own `URLSession` and JSON coders. Both accept a custom `URLSession` for tests. Bugzilla errors come back either as HTTP status codes or as `{"error": true, "code": …, "message": …}` envelopes; Phabricator's Conduit always returns 200 and signals errors inside the envelope's `error_code` / `error_info`.

### Sandbox

Sandboxed app with `com.apple.security.network.client`. Keychain access uses generic password items scoped by service name.

## Conventions

- App deployment target is `MACOSX_DEPLOYMENT_TARGET = 26.4`. Local packages target macOS 14 / iOS 17 (BugzillaKit, PhabricatorKit, FolioCodeView, MarginaliaEditor) or macOS 10.15 / iOS 13 (SearchfoxKit).
- BMO and Conduit JSON use snake_case; both clients translate to/from idiomatic camelCase via `KeyDecodingStrategy.convertFromSnakeCase`.
- Reuse the rich UI primitives that already exist (the comment composer, the `MarginaliaEditor` markdown editor, `FolioView` for diffs) instead of building parallel inputs.

## License

Mozilla Public License, v. 2.0. See <https://www.mozilla.org/MPL/2.0/> for the full text.
