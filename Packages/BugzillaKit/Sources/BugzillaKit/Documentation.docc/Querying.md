# Querying bugs

Build flexible bug searches with `BugQuery` and the preset constructors.

## Overview

``BugQuery`` is the input to ``BugzillaClient/searchBugs(_:)``. It maps to the parameters accepted by Bugzilla's `GET /rest/bug` endpoint, with two extras:

1. Preset constructors for common queries.
2. Boolean-chart support, used internally to express OR-of-roles conditions that can't be encoded in flat query parameters.

## Preset queries

```swift
BugQuery.myBugs              // assigned_to = @me
BugQuery.reportedByMe        // reporter    = @me
BugQuery.needsReviewFromMe   // flag.requestee = @me

BugQuery.recentlyChanged(
    involving: BugQuery.me,
    daysBack: 7
)

BugQuery.openIn(
    component: ComponentRef(product: "Firefox", component: "General")
)

BugQuery.blockedBy(metaBug: 1_700_000)
```

## The `@me` sentinel

The web UI accepts `@me` as a placeholder for the signed-in user, but the BMO REST endpoints do not. BugzillaKit exposes the literal sentinel:

```swift
public extension BugQuery {
    static let me = "@me"
}
```

…and a method to resolve it:

```swift
public func substitutingMe(with login: String) -> BugQuery
```

You typically call ``BugzillaClient/whoami()`` once and use its result throughout the session:

```swift
let me = try await client.whoami()

let myOpen = try await client.searchBugs(
    BugQuery.myBugs.substitutingMe(with: me.name)
)
```

## Custom queries

Set fields directly on a `BugQuery`:

```swift
var query = BugQuery()
query.product = ["Firefox"]
query.component = ["General", "Tabbed Browser"]
query.status = ["NEW", "ASSIGNED", "REOPENED"]
query.changedAfter = .now.addingTimeInterval(-7 * 24 * 3600)
query.limit = 100
query.order = "changeddate DESC"
```

## Boolean charts

Some queries can't be expressed with flat parameters — for example, "any bug where the user is in *any* role". `BugQuery.recentlyChanged(involving:daysBack:)` and queries that set `userInvolved` emit Bugzilla's chart syntax (`f1=`, `o1=`, `v1=`, …) under the hood, producing the equivalent of:

```
(assigned_to OR reporter OR cc OR commenter) == <user>
AND changeddate > <cutoff>
```

You usually shouldn't need to construct charts manually; if you do, set the `extra` dictionary on `BugQuery` with the raw `chart`/`o`/`v`/`f` parameter names.

## Pitfalls

> [!IMPORTANT]
> Don't combine `flagtypes.name` with `requestees.login_name` in a single chart row — BMO drops needinfo bugs from the result. Use ``BugQuery/needsReviewFromMe`` for the canonical "review/feedback/needinfo requested from me" query.

## Pagination

```swift
var query = BugQuery.openIn(component: ref)
query.limit = 50
query.offset = 0
let firstPage = try await client.searchBugs(query)

query.offset = 50
let secondPage = try await client.searchBugs(query)
```

`BugSearchResult.totalMatches` reports the total result count when the server provides it.
