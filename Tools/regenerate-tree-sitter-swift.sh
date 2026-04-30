#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../Packages/Sliver/Vendor/tree-sitter-swift"
npx --yes tree-sitter-cli generate
echo "Regenerated tree-sitter-swift parser.c. Re-copy queries/highlights.scm to Sources/SliverHighlight/Queries/swift-highlights.scm if grammar changes affected them."
