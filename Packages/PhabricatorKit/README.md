# PhabricatorKit

A Swift client for [Phabricator](https://www.phacility.com/phabricator/)'s [Conduit](https://secure.phabricator.com/book/phabricator/article/conduit/) API. Lets Swift apps search and interact with Differential revisions, diffs, transactions, projects, users, and inline comments.

PhabricatorKit was built against [phabricator.services.mozilla.com](https://phabricator.services.mozilla.com), but the surface is generic and tolerant of variations across Phabricator forks.

## Features

- `actor`-based ``PhabricatorClient`` with async/await throughout
- Strongly-typed models for revisions, diffs, hunks, changesets, reviewers, transactions, inline comments, projects, and users
- Cursor-paginated search APIs for revisions, diffs, transactions, and projects
- Full diff retrieval (`differential.querydiffs`) with file changesets, hunks, and unified-diff corpora
- Revision editing (accept, reject, abandon, request review, comment, project tags) via a typed transaction builder
- First-class inline-comment support: create, list, classify drafts vs. published, delete drafts
- Robust transaction decoding that tolerates the ad-hoc fields different Phabricator forks emit
- Built-in [Remarkup → CommonMark](https://secure.phabricator.com/book/phabricator/article/remarkup/) conversion with auto-linking for `T123`, `D45678`, `bug 1234567`, `@username`, and `{F1234}`
- Pluggable `URLSession` for testing
- Zero external dependencies

## Requirements

- Swift 5.10+
- macOS 14.0+ / iOS 17.0+
- A Phabricator instance with Conduit enabled and an API token (User → Settings → Conduit API Tokens)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/your-org/PhabricatorKit.git", from: "1.0.0")
]
```

```swift
.target(name: "MyApp", dependencies: ["PhabricatorKit"])
```

In Xcode: *File → Add Package Dependencies…* and paste the repository URL.

## Quick Start

### Sign in and identify yourself

```swift
import PhabricatorKit

let client = PhabricatorClient(
    baseURL: URL(string: "https://phabricator.services.mozilla.com")!,
    authentication: .apiToken("cli-xxxxxxxxxxxxxxxxxxxxxxxxx")
)

let me = try await client.whoami()
print(me.userName, me.realName ?? "")
```

### Find revisions you need to review

```swift
let result = try await client.searchRevisions(
    .reviewing(responsiblePHID: me.phid)
)

for r in result.data {
    print("D\(r.id): \(r.fields.title) — \(r.fields.status.name)")
}
```

### Read the most recent diff for a revision

```swift
let revisionPHID = "PHID-DREV-abc123"

let diffs = try await client.searchDiffs(.forRevision(revisionPHID, limit: 1))
guard let head = diffs.data.first else { return }

let detail = try await client.getDiffs(ids: [head.id]).first!
for changeset in detail.changesets {
    print("\(changeset.currentPath) — +\(changeset.addLines)/-\(changeset.delLines)")
}
```

### Comment on, accept, or reject a revision

```swift
_ = try await client.editRevision(
    objectIdentifier: revisionPHID,
    transactions: [
        .action(.accept),
        .comment("Looks good. Landing.")
    ]
)
```

### Walk a revision's activity, including inline comments

```swift
let txns = try await client.searchTransactions(
    TransactionQuery(objectIdentifier: revisionPHID)
)

for inline in PhabricatorClient.inlineComments(from: txns.data) {
    print("\(inline.path):\(inline.line)  \(inline.content)")
}
```

### Convert Remarkup summaries to Markdown for display

```swift
let cm = Remarkup.toCommonMark(revision.fields.summary ?? "")
// Pass to your CommonMark renderer.
```

## API Reference

### Client

```swift
public init(
    baseURL: URL,
    authentication: PhabricatorAuthentication = .none,
    session: URLSession? = nil
)

func setAuthentication(_ authentication: PhabricatorAuthentication)

// Identity
func whoami() async throws -> PhabricatorUser

// Search
func searchRevisions(_ query: RevisionQuery) async throws -> RevisionSearchResult
func searchDiffs(_ query: DiffQuery) async throws -> DiffSearchResult
func searchTransactions(_ query: TransactionQuery) async throws -> TransactionSearchResult
func searchProjects(_ query: ProjectQuery) async throws -> ProjectSearchResult
func searchUsers(phids: [String]) async throws -> [PhabricatorUser]

// Diff detail
func getDiffs(ids: [Int]) async throws -> [DiffDetail]

// Editing
func editRevision(
    objectIdentifier: String,
    transactions: [RevisionEditTransaction]
) async throws -> RevisionEditResult

// Inline comments
func createInlineComment(
    diffID: Int,
    path: String,
    line: Int,
    length: Int,
    isNewFile: Bool,
    content: String,
    replyToCommentPHID: String? = nil
) async throws -> InlineComment

func deleteDraftInline(phid: String) async throws

// File contents
func getFileContent(repositoryPHID: String, commit: String, path: String) async throws -> String?
func downloadFile(phid: String) async throws -> Data

// Helpers
nonisolated static func inlineComments(from transactions: [RevisionTransaction]) -> [InlineComment]
```

### Authentication

```swift
public enum PhabricatorAuthentication: Sendable, Equatable {
    case none
    case apiToken(String)
}
```

PhabricatorKit injects the API token into each Conduit call as `__conduit__.token` inside the `params` JSON, *not* as an HTTP header. `.none` only works for endpoints that don't require auth.

### Queries

| Type | Purpose |
|------|---------|
| ``RevisionQuery`` | Search revisions by author, reviewer, status, full text, modification date. Factories: `.active(authorPHID:)`, `.reviewing(responsiblePHID:)`, `.landed(authorPHID:since:)`. |
| ``DiffQuery`` | Search diffs by id, PHID, or revision PHID. Factory: `.forRevision(_:limit:)`. |
| ``TransactionQuery`` | Fetch a revision's activity history (comments, status changes, inline diffs, reviewer actions). |
| ``ProjectQuery`` | Search projects by name, slug, PHID, or full text. Factories: `.byName(_:limit:)`, `.byPHIDs(_:)`. |

All search results carry a `cursor` for keyset pagination (`after`/`before`).

### Editing

```swift
public enum RevisionAction: String {
    case comment, accept, reject, resign, abandon, reclaim, reopen, close
    case planChanges     = "plan-changes"
    case requestReview   = "request-review"
}

public struct RevisionEditTransaction {
    public static func action(_ action: RevisionAction) -> RevisionEditTransaction
    public static func comment(_ body: String) -> RevisionEditTransaction
    public static func projectsAdd(_ phids: [String]) -> RevisionEditTransaction
    public static func projectsRemove(_ phids: [String]) -> RevisionEditTransaction
    public static func projectsSet(_ phids: [String]) -> RevisionEditTransaction
}
```

Pass any combination of these to ``PhabricatorClient/editRevision(objectIdentifier:transactions:)``.

### Models

| Type | Notes |
|------|-------|
| ``Revision`` | Top-level revision; `fields` holds title/author/status/dates, `attachments` holds optional reviewers/subscribers/projects. |
| ``RevisionStatus`` | `value` ("needs-review", "accepted", …), `name`, `closed`. `RevisionStatus.Value` has constants and an `openValues` array. |
| ``Diff`` / ``DiffDetail`` | `Diff` is the search result (metadata + `baseCommit`/`branch` derived from refs). `DiffDetail` adds the file changesets and hunks. |
| ``Changeset`` | One file in a diff; carries `type`, `fileType`, line counts, `hunks`. |
| ``Hunk`` | Unified-diff hunk: `oldOffset`, `oldLen`, `newOffset`, `newLen`, `corpus`. |
| ``Reviewer`` | `reviewerPHID`, `status`, `isBlocking`. `Reviewer.Status` has constants for "added", "accepted", "rejected", … |
| ``InlineComment`` | A comment anchored to a file/line on a specific diff. `isDraft` is true when `transactionPHID` is `nil`. |
| ``RevisionTransaction`` | One activity entry. Use `isComment` and `inlineComment()` to interpret it. |
| ``PhabricatorUser`` | `phid`, `userName`, `realName`, `primaryEmail`, `image`. |
| ``PhabricatorProject`` | `phid`, `id`, `name`, `slug`, `icon`, `color`. |

### Errors

```swift
public enum PhabricatorError: Error, LocalizedError, Sendable {
    case network(URLError)
    case decoding(String)
    case api(code: String, info: String)   // e.g. ERR-CONDUIT-CORE
    case unauthorized
    case invalidResponse
    case missingToken                      // .none auth used on a protected endpoint
}
```

## Conduit transport details

PhabricatorKit hides this from callers, but it's worth knowing what's on the wire:

- All requests are `POST` with `Content-Type: application/x-www-form-urlencoded`.
- The body has two fields: `api.token=<token>` (sent separately) and `params=<json>`.
- The `<json>` payload **also** carries the token under `__conduit__.token` — both the legacy form param and the modern in-params token are sent for compatibility.
- Successful responses always come back as HTTP 200 with `{ "result": …, "error_code": null, "error_info": null }`.
- Errors return HTTP 200 too, with non-null `error_code`/`error_info`. The client surfaces these as ``PhabricatorError/api(code:info:)``.

## Remarkup → CommonMark

```swift
public enum Remarkup {
    public static let phabricatorProductionURL: URL    // mozilla phab base
    public static let bugzillaProductionURL: URL       // BMO base

    public static func toCommonMark(
        _ source: String,
        phabricatorBaseURL: URL = phabricatorProductionURL,
        bugzillaBaseURL: URL = bugzillaProductionURL
    ) -> String
}
```

| Remarkup | CommonMark |
|----------|------------|
| `//italic//` | `*italic*` |
| `##mono##` | `` `mono` `` |
| `__under__` | `<u>under</u>` |
| `!!high!!` | `**high**` |
| `= H1 =` … `====== H6 ======` | `# H1` … `###### H6` |
| `NOTE:` / `WARNING:` / `IMPORTANT:` | Block-quoted callout |
| `T123`, `D45678`, `{F1234}` | Auto-links to the configured Phabricator base URL |
| `@username` | Auto-link to `/p/username/` |
| `bug 1234567` | Auto-link to the configured Bugzilla base URL |

URLs inside text and content inside fenced code blocks are protected from transformation.

## Testing

`PhabricatorClient` accepts any `URLSession`, including one driven by a custom `URLProtocol`. The package's own tests use this to assert request shape and decode canned responses for `differential.revision.search`, `differential.diff.search`, `transaction.search`, and `differential.revision.edit`.

The static helper `PhabricatorClient.makeEncoder()` is exposed so you can match the encoding pipeline used inside the actor (sorted keys, custom date strategy) when building expected request bodies in tests.

## License

PhabricatorKit is released under the Mozilla Public License, v. 2.0. See <https://www.mozilla.org/MPL/2.0/> for the full text.
