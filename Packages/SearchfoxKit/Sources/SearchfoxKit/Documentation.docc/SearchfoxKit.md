# ``SearchfoxKit``

Native Swift bindings for Mozilla's [Searchfox](https://searchfox.org/) source-code search.

## Overview

SearchfoxKit lets a Swift application run path and identifier searches against `mozilla-central` without depending on the `searchfox-cli` binary. The package is a thin UniFFI wrapper over a Rust crate (`searchfox-bridge`) that itself wraps the upstream [`searchfox-lib`](https://crates.io/crates/searchfox-lib).

Two async functions cover the entire surface:

```swift
import SearchfoxKit

let files = try await searchFiles(path: "HTMLElement.cpp", limit: 10)
let symbols = try await searchIdentifiers(identifier: "AudioStream", limit: 25)
```

Each call returns up to `limit` ``SearchHit`` values containing the file path, line number, the line of source text that matched, and a deep link to `searchfox.org`.

### How it works

1. Swift calls one of the async free functions.
2. UniFFI marshals the arguments to a Tokio task on the Rust side.
3. `searchfox-lib` runs the search against the Searchfox HTTP backend.
4. The results are converted to ``SearchHit`` values, with `https://searchfox.org/mozilla-central/source/<path>#<lineNumber>` URLs constructed for each hit.
5. UniFFI lifts the result back into Swift's structured concurrency, completing the `await`.

The Swift thread is never blocked — long-running I/O happens on Tokio's worker pool.

### Repository

The bridge is hard-coded to search `mozilla-central`. To target a different Searchfox tree, change the `REPO` constant in `Tools/searchfox-bridge/src/lib.rs` and regenerate.

## Topics

### Searching

- ``searchFiles(path:limit:)``
- ``searchIdentifiers(identifier:limit:)``

### Results

- ``SearchHit``

### Errors

- ``SearchfoxError``
