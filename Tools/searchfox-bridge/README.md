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

# Preserve hand-written docs across the regeneration
cp ../../Packages/SearchfoxKit/README.md /tmp/SearchfoxKit-README.md 2>/dev/null || true
cp -R ../../Packages/SearchfoxKit/Sources/SearchfoxKit/Documentation.docc /tmp/SearchfoxKit-docc 2>/dev/null || true

rm -rf ../../Packages/SearchfoxKit
mv SearchfoxKit ../../Packages/SearchfoxKit

cp /tmp/SearchfoxKit-README.md ../../Packages/SearchfoxKit/README.md 2>/dev/null || true
cp -R /tmp/SearchfoxKit-docc ../../Packages/SearchfoxKit/Sources/SearchfoxKit/Documentation.docc 2>/dev/null || true
```

`Packages/SearchfoxKit/Package.swift`, the generated Swift bindings, and the
xcframework (~240 MB) are all committed, so the app target links straight after a
fresh clone. Re-run the regenerate command above whenever the bridge changes.

`README.md` and `Sources/SearchfoxKit/Documentation.docc/` are hand-written and not
part of the UniFFI output — the snippet above stashes and restores them so they
survive a regeneration.
