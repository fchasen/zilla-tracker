#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../Packages/Sliver/Vendor/tree-sitter-html"
npx --yes tree-sitter-cli generate
echo "Regenerated tree-sitter-html parser.c. Re-copy queries/highlights.scm to Sources/SliverHighlight/Queries/html-highlights.scm if grammar changes affected them."
