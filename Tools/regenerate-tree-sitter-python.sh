#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../Packages/Sliver/Vendor/tree-sitter-python"
npx --yes tree-sitter-cli generate
echo "Regenerated tree-sitter-python parser.c. Re-copy queries/highlights.scm to Sources/SliverHighlight/Queries/python-highlights.scm if grammar changes affected them."
