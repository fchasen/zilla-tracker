#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../Packages/Sliver/Vendor/tree-sitter-json"
npx --yes tree-sitter-cli generate
echo "Regenerated tree-sitter-json parser.c. Re-copy queries/highlights.scm to Sources/SliverHighlight/Queries/json-highlights.scm if grammar changes affected them."
