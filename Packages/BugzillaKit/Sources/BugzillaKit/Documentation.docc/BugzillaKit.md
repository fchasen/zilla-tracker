# ``BugzillaKit``

A Swift client for the Bugzilla REST API.

## Overview

BugzillaKit wraps Bugzilla's REST API in a single `actor`-based client (``BugzillaClient``) with strongly-typed models and Swift concurrency. It targets the production API exposed at paths under `/rest/...` on any modern Bugzilla deployment.

The library is intentionally narrow: it covers authentication, bug retrieval and search, bug creation and updates, comments, products, components, and user lookup. Attachment fetching and history are stubs returning ``BugzillaError/notImplemented`` until they're needed by a consumer.

```swift
import BugzillaKit

let client = BugzillaClient(
    baseURL: URL(string: "https://bugzilla.mozilla.org")!
)
_ = try await client.login(name: "you@example.com", apiKey: apiKey)

let bug = try await client.getBug(id: 1_234_567)
print(bug.summary)
```

## Topics

### Essentials

- ``BugzillaClient``
- ``Authentication``
- ``BugzillaError``

### Querying bugs

- <doc:Querying>
- ``BugQuery``
- ``BugSearchResult``
- ``ComponentRef``

### Bug data

- ``Bug``
- ``Comment``
- ``Attachment``
- ``Flag``
- ``User``
- ``Product``
- ``Component``

### Mutating bugs

- ``BugCreate``
- ``BugUpdate``
- ``BugRelationUpdate``
- ``SeeAlsoUpdate``
- ``FlagUpdate``
- ``BugChangeResult``

### History

- ``HistoryEntry``
- ``Change``
