#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../Packages/Sliver/Vendor/tree-sitter-c"
npx --yes tree-sitter-cli generate
echo "Regenerated tree-sitter-c parser.c. Re-copy queries/highlights.scm to Sources/SliverHighlight/Queries/c-highlights.scm if grammar changes affected them."
