# BugzillaKit

A modern, type-safe Swift client for the [Bugzilla REST API](https://bmo.readthedocs.io/en/latest/api/index.html). Built on Swift concurrency (`actor`, `async/await`), with no third-party dependencies.

BugzillaKit was developed against [bugzilla.mozilla.org](https://bugzilla.mozilla.org) (BMO), but the public surface is generic and should work against any modern Bugzilla deployment that exposes the standard REST endpoints.

## Features

- Single `actor`-based client — safe to share across tasks
- Full async/await API; no completion handlers
- Strongly-typed models for bugs, comments, attachments, products, components, users, and flags
- Fluent `BugQuery` builder with preset queries (`.myBugs`, `.reportedByMe`, `.needsReviewFromMe`, `.recentlyChanged`, `.openIn(component:)`, `.blockedBy(metaBug:)`)
- Boolean-chart query support for advanced searches that BMO's flat query string can't express
- Bug create and update flows, including duplicate-marking, dependency edits, see-also lists, and flag changes
- Comment fetch / add / edit with private-flag and Markdown support
- Pluggable `URLSession` for credential injection and test-time mocking via `URLProtocol`
- Specific error cases for unauthorized, not-found, rate-limited, and server-reported API errors
- Zero external dependencies — Foundation only

## Requirements

- Swift 5.10+
- macOS 14.0+ / iOS 17.0+
- A Bugzilla server with the REST API enabled (e.g. `https://bugzilla.mozilla.org`)

## Installation

### Swift Package Manager

Add BugzillaKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/BugzillaKit.git", from: "1.0.0")
]
```

Then add it as a dependency to your target:

```swift
.target(name: "MyApp", dependencies: ["BugzillaKit"])
```

In Xcode: *File → Add Package Dependencies…* and paste the repository URL.

## Quick Start

### Sign in and look up a bug

```swift
import BugzillaKit

let client = BugzillaClient(
    baseURL: URL(string: "https://bugzilla.mozilla.org")!
)

// Trade an API key for a session token. The client stores the
// resulting authentication on itself for subsequent requests.
_ = try await client.login(name: "you@example.com", apiKey: secretAPIKey)

let bug = try await client.getBug(id: 1_234_567)
print(bug.summary, bug.status, bug.assignedTo ?? "unassigned")
```

### Search "my open bugs"

```swift
let me = try await client.whoami()

let result = try await client.searchBugs(
    BugQuery.myBugs.substitutingMe(with: me.name)
)

for bug in result.bugs {
    print("\(bug.id): \(bug.summary)")
}
```

> [!IMPORTANT]
> The preset queries use the `@me` sentinel (`BugQuery.me`). BMO's REST API does **not** expand `@me` the way the web UI does — you must call `substitutingMe(with:)` with the real login email before sending the query. Calling `whoami()` once at startup is the recommended pattern.

### Update a bug

```swift
_ = try await client.updateBug(
    id: 1_234_567,
    BugUpdate(
        status: "RESOLVED",
        resolution: "FIXED",
        comment: "Landed in https://hg.mozilla.org/...",
        commentIsPrivate: false
    )
)
```

### File a new bug

```swift
let id = try await client.createBug(
    BugCreate(
        product: "Firefox",
        component: "General",
        summary: "Tab strip flickers when closing pinned tabs",
        version: "unspecified",
        description: "Steps to reproduce…",
        type: "defect",
        severity: "S2"
    )
)
print("Filed bug \(id)")
```

### Fetch and post comments

```swift
let comments = try await client.comments(bugID: 1_234_567)
for c in comments {
    print("#\(c.count ?? 0) \(c.creator): \(c.text)")
}

let newCommentID = try await client.addComment(
    bugID: 1_234_567,
    text: "**Confirmed** on Nightly 134.",
    isMarkdown: true
)
```

## API Reference

### Client

| Type | Description |
|------|-------------|
| `BugzillaClient` | The single entry point. An `actor` that owns a `URLSession` and the current `Authentication`. |

```swift
public init(
    baseURL: URL,
    authentication: Authentication = .none,
    session: URLSession = .shared
)
```

#### Authentication

```swift
func setAuthentication(_ authentication: Authentication)
func login(name: String, apiKey: String, restrictToIP: Bool = true) async throws -> Authentication
func validLogin() async throws -> Bool
func logout() async throws
func whoami() async throws -> User
```

#### Bug retrieval and search

```swift
func getBug(id: Bug.ID) async throws -> Bug
func getBugs(ids: [Bug.ID]) async throws -> [Bug]
func searchBugs(_ query: BugQuery) async throws -> BugSearchResult
```

#### Bug mutation

```swift
func updateBug(id: Bug.ID, _ update: BugUpdate) async throws -> [BugChangeResult]
func createBug(_ create: BugCreate) async throws -> Bug.ID
```

#### Comments

```swift
func comments(bugID: Bug.ID) async throws -> [Comment]
func addComment(bugID: Bug.ID, text: String, isPrivate: Bool = false, isMarkdown: Bool = false) async throws -> Comment.ID
func updateComment(bugID: Bug.ID, commentID: Comment.ID, newText: String, isMarkdown: Bool = true) async throws
```

#### Products, components, users

```swift
func selectableProducts() async throws -> [Product]
func products(ids: [Int]) async throws -> [Product]
func products(names: [String]) async throws -> [Product]
func searchUsers(match: String, limit: Int = 20) async throws -> [User]
```

#### Misc

```swift
func version() async throws -> String
```

### Authentication

```swift
public enum Authentication: Sendable, Equatable {
    case none
    case apiKey(String)
    case token(String, userID: Int)
}
```

| Case | Header sent | Use when |
|------|-------------|----------|
| `.none` | — | Anonymous read-only access |
| `.apiKey(key)` | `X-BUGZILLA-API-KEY: key` | You hold a long-lived API key and don't need a session |
| `.token(token, userID:)` | `X-BUGZILLA-TOKEN: token` | Returned by `login(name:apiKey:)`; tied to the requesting IP when `restrictToIP` is true |

BugzillaKit does not persist credentials; that's your application's responsibility (e.g. Keychain).

### Querying

`BugQuery` is a value-type query builder. Set fields directly, or start from a preset:

| Preset | Filter |
|--------|--------|
| `BugQuery.myBugs` | `assignedTo = @me` |
| `BugQuery.reportedByMe` | `reporter = @me` |
| `BugQuery.needsReviewFromMe` | `flag.requestee = @me` (any flag type) |
| `BugQuery.recentlyChanged(involving:daysBack:)` | Boolean chart matching `assigned_to OR reporter OR cc OR commenter` against a user, `changed_after` filter applied |
| `BugQuery.openIn(component:)` | `product`, `component`, `resolution = ---` |
| `BugQuery.blockedBy(metaBug:)` | `blocks = <metaBug>` |

All presets that mention "me" produce the literal sentinel `BugQuery.me` (`"@me"`). Resolve it before sending:

```swift
let resolved = BugQuery.myBugs.substitutingMe(with: "you@example.com")
let result = try await client.searchBugs(resolved)
```

`BugQuery` also supports paging (`limit`, `offset`), ordering (`order`, e.g. `"changeddate DESC"`), and field projection (`includeFields`, `excludeFields`).

### Errors

```swift
public enum BugzillaError: Error, Sendable {
    case network(URLError)
    case decoding(String)
    case api(code: Int, message: String)
    case unauthorized
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case invalidResponse
    case notImplemented
}
```

`api(code:message:)` carries Bugzilla's own error envelope — for example, code `306` is "the API key is invalid". `rateLimited` reports the server's `Retry-After` header when present.

## Testing Against a Mock Server

BugzillaKit's `BugzillaClient` accepts any `URLSession`. The test target uses a `URLProtocol` subclass to inspect outgoing requests and return canned responses:

```swift
final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?
    // …
}

let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockURLProtocol.self]
let session = URLSession(configuration: config)

MockURLProtocol.handler = { request in
    XCTAssertEqual(request.url?.path, "/rest/bug/1234567")
    let body = #"{"bugs":[{"id":1234567,"summary":"Hello","status":"NEW","resolution":"","product":"Firefox","component":"General"}]}"#.data(using: .utf8)!
    return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
}

let client = BugzillaClient(baseURL: baseURL, session: session)
let bug = try await client.getBug(id: 1_234_567)
```

See `Tests/BugzillaKitTests/MockURLProtocol.swift` for the full pattern used by the package's own tests.

## Conventions

- BMO returns `snake_case` JSON; the client translates to/from idiomatic `camelCase` Swift via `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase`.
- All dates are decoded from the ISO 8601 timestamps Bugzilla emits.
- `Bug`, `BugUpdate`, `BugCreate`, `Comment`, `Attachment`, `Product`, and `User` are `Sendable` and `Hashable`.

## License

BugzillaKit is released under the Mozilla Public License, v. 2.0. See <https://www.mozilla.org/MPL/2.0/> for the full text.
