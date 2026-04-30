#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../Packages/Sliver/Vendor/tree-sitter-javascript"
npx --yes tree-sitter-cli generate
echo "Regenerated tree-sitter-javascript parser.c. Re-copy queries/highlights.scm to Sources/SliverHighlight/Queries/javascript-highlights.scm if grammar changes affected them."
