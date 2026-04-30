#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../Packages/Sliver/Vendor/tree-sitter-rust"
npx --yes tree-sitter-cli generate
echo "Regenerated tree-sitter-rust parser.c. Re-copy queries/highlights.scm to Sources/SliverHighlight/Queries/rust-highlights.scm if grammar changes affected them."
