# searchfox-bridge

UniFFI bridge that wraps [`searchfox-lib`](https://crates.io/crates/searchfox-lib) so the
Zilla app can call Mozilla Searchfox directly from Swift instead of shelling out to
`searchfox-cli`. The output is a Swift Package at `../../Packages/SearchfoxKit`.

## Regenerating the Swift package

```sh
# one-time
cargo install cargo-swift
rustup target add aarch64-apple-darwin x86_64-apple-darwin \
                  aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios \
                  aarch64-apple-visionos aarch64-apple-visionos-sim

# from this directory
cargo swift package \
  --platforms macos --platforms ios --platforms visionos \
  --name SearchfoxKit -y --release
rm -rf ../../Packages/SearchfoxKit
mv SearchfoxKit ../../Packages/SearchfoxKit
```

`Packages/SearchfoxKit/Package.swift` and the generated Swift bindings are committed.
The xcframework (~240 MB) is gitignored — run the regenerate command above once after
cloning before opening the Xcode project.
