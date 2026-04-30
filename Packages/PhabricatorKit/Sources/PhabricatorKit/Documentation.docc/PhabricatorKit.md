# ``PhabricatorKit``

A Swift client for the Phabricator Conduit API.

## Overview

PhabricatorKit talks to a Phabricator instance via [Conduit](https://secure.phabricator.com/book/phabricator/article/conduit/), Phabricator's RPC layer. It exposes the Differential and supporting endpoints needed to power a code-review client: search and inspect revisions, fetch diffs and changesets, walk activity history, post comments and review actions, and manage inline comments.

```swift
import PhabricatorKit

let client = PhabricatorClient(
    baseURL: URL(string: "https://phabricator.services.mozilla.com")!,
    authentication: .apiToken(token)
)

let me = try await client.whoami()
let toReview = try await client.searchRevisions(
    .reviewing(responsiblePHID: me.phid)
)
```

The library is `Sendable` end-to-end, has no external dependencies, and tolerates the ad-hoc transaction shapes that different Phabricator forks emit.

## Topics

### Essentials

- ``PhabricatorClient``
- ``PhabricatorAuthentication``
- ``PhabricatorError``
- <doc:ConduitTransport>

### Searching

- ``RevisionQuery``
- ``DiffQuery``
- ``TransactionQuery``
- ``ProjectQuery``
- ``RevisionSearchResult``
- ``DiffSearchResult``
- ``TransactionSearchResult``
- ``ProjectSearchResult``

### Revisions and reviewers

- ``Revision``
- ``RevisionStatus``
- ``Reviewer``

### Diffs

- ``Diff``
- ``DiffDetail``
- ``Changeset``
- ``ChangesetType``
- ``FileType``
- ``Hunk``

### Activity and comments

- ``RevisionTransaction``
- ``InlineComment``

### Editing revisions

- ``RevisionAction``
- ``RevisionEditTransaction``
- ``RevisionEditRequest``
- ``RevisionEditResult``

### Users and projects

- ``PhabricatorUser``
- ``PhabricatorProject``

### Markup

- ``Remarkup``
