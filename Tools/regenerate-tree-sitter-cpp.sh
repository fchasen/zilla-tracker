#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../Packages/Sliver/Vendor/tree-sitter-cpp"
npx --yes tree-sitter-cli generate
echo "Regenerated tree-sitter-cpp parser.c. Re-copy queries/highlights.scm to Sources/SliverHighlight/Queries/cpp-highlights.scm if grammar changes affected them."
