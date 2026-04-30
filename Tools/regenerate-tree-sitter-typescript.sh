#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../Packages/Sliver/Vendor/tree-sitter-typescript"
npx --yes tree-sitter-cli generate
echo "Regenerated tree-sitter-typescript parser.c. Re-copy queries/highlights.scm to Sources/SliverHighlight/Queries/typescript-highlights.scm if grammar changes affected them."
