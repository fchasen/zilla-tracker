# SearchfoxKit

A native Swift wrapper around [Searchfox](https://searchfox.org/), Mozilla's source-code search engine for `mozilla-central` and friends. SearchfoxKit lets macOS, iOS, and visionOS apps run path and identifier searches against `mozilla-central` without shelling out to a CLI tool.

The package is generated from a small Rust [`searchfox-bridge`](../../Tools/searchfox-bridge) crate that wraps the upstream [`searchfox-lib`](https://crates.io/crates/searchfox-lib), exposed to Swift through [UniFFI](https://mozilla.github.io/uniffi-rs/). The compiled `xcframework` is committed in-tree, so the package builds out of the box on a fresh clone — no Rust toolchain required to consume it.

## Features

- Two simple async functions: ``searchFiles(path:limit:)`` and ``searchIdentifiers(identifier:limit:)``
- Returns ``SearchHit`` values (path, line number, line text, deep link to searchfox.org) you can render in a list or insert as Markdown links
- Backed by Tokio + `searchfox-lib` on the Rust side; the Swift thread is never blocked
- Fully `Sendable`; works inside Swift Tasks, `actor`s, and SwiftUI views
- Localized errors via `LocalizedError` for direct display in alerts
- Pre-built `xcframework` for `arm64`/`x86_64` macOS, iOS device + simulator, and visionOS device + simulator

## Requirements

- Swift 5.9+
- macOS 10.15+ / iOS 13+ / visionOS 1+

The xcframework is platform- and arch-specific; consumers don't need a Rust toolchain.

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/your-org/SearchfoxKit.git", from: "1.0.0")
]
```

```swift
.target(name: "MyApp", dependencies: ["SearchfoxKit"])
```

In Xcode: *File → Add Package Dependencies…* and paste the repository URL.

## Quick Start

### Search by file path

```swift
import SearchfoxKit

let hits = try await searchFiles(path: "HTMLElement.cpp", limit: 10)
for hit in hits {
    print("\(hit.path) — \(hit.url)")
}
```

### Search by identifier

```swift
let hits = try await searchIdentifiers(identifier: "AudioStream", limit: 25)
for hit in hits {
    print("\(hit.path):\(hit.lineNumber)  \(hit.line)")
}
```

### Use it from SwiftUI

```swift
struct SearchView: View {
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var error: String?

    var body: some View {
        VStack {
            TextField("Path or @identifier", text: $query, onCommit: search)
            if let error { Text(error).foregroundStyle(.red) }
            List(results, id: \.url) { hit in
                Link(destination: URL(string: hit.url)!) {
                    VStack(alignment: .leading) {
                        Text(hit.path).font(.headline)
                        if hit.lineNumber > 0 {
                            Text(hit.line).font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
        }
    }

    private func search() {
        Task {
            do {
                if query.hasPrefix("@") {
                    let id = String(query.dropFirst())
                    results = try await searchIdentifiers(identifier: id, limit: 25)
                } else {
                    results = try await searchFiles(path: query, limit: 25)
                }
                error = nil
            } catch {
                self.error = error.localizedDescription
                results = []
            }
        }
    }
}
```

## API Reference

### Functions

```swift
public func searchFiles(path: String, limit: UInt32) async throws -> [SearchHit]
public func searchIdentifiers(identifier: String, limit: UInt32) async throws -> [SearchHit]
```

Both functions:

- Trim whitespace from their query and throw ``SearchfoxError/InvalidQuery(message:)`` if the input is empty.
- Send a request to `searchfox.org`'s public search backend (currently against `mozilla-central`).
- Return up to `limit` hits ordered by Searchfox's relevance scoring.

`searchFiles` matches on file paths (substring match). `searchIdentifiers` runs Searchfox's symbol search (`id:<name>` syntax) and returns declaration and use sites.

### `SearchHit`

```swift
public struct SearchHit: Equatable, Hashable, Sendable {
    public var path: String         // e.g. "dom/html/HTMLElement.cpp"
    public var lineNumber: UInt64   // 0 when the entire file is the match
    public var line: String         // the matching source line, for display
    public var url: String          // deep link to searchfox.org with #lineNumber
}
```

### `SearchfoxError`

```swift
public enum SearchfoxError: Swift.Error, LocalizedError, Equatable, Hashable, Sendable {
    case Network(message: String)        // network / HTTP failure
    case ClientInit(message: String)     // failed to initialize the underlying searchfox client
    case InvalidQuery(message: String)   // empty or malformed query
}
```

All cases conform to `LocalizedError`, so `.localizedDescription` is safe to display directly.

## Repository

SearchfoxKit hard-codes the `mozilla-central` repository inside the Rust bridge. If you need to search a different Searchfox tree (`comm-central`, `nss`, etc.), edit `Tools/searchfox-bridge/src/lib.rs` and regenerate the package.

## Regenerating the bindings

The Swift bindings, generated `searchfox_bridge.swift`, and pre-compiled `searchfox_bridgeFFI.xcframework` are all committed. They only need to change when the Rust bridge does.

Regenerate from a checkout:

```sh
# one-time
cargo install cargo-swift
rustup target add aarch64-apple-darwin x86_64-apple-darwin \
                  aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios \
                  aarch64-apple-visionos aarch64-apple-visionos-sim

# from Tools/searchfox-bridge/
cargo swift package \
  --platforms macos --platforms ios --platforms visionos \
  --name SearchfoxKit -y --release
rm -rf ../../Packages/SearchfoxKit
mv SearchfoxKit ../../Packages/SearchfoxKit
```

> [!IMPORTANT]
> `cargo swift package` overwrites the entire `SearchfoxKit/` directory. Before running it, copy `README.md` and `Sources/SearchfoxKit/Documentation.docc/` somewhere safe and restore them afterward. They are not part of the auto-generated output.

## Generated code

`Sources/SearchfoxKit/searchfox_bridge.swift` is auto-generated by UniFFI. Do not edit it by hand. Bug fixes belong in [`Tools/searchfox-bridge/src/lib.rs`](../../Tools/searchfox-bridge/src/lib.rs); a regeneration will produce a new bindings file.

## License

SearchfoxKit is released under the Mozilla Public License, v. 2.0. See <https://www.mozilla.org/MPL/2.0/> for the full text.
