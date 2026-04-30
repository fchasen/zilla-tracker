#!/usr/bin/env bash
#
# Regenerate the tree-sitter-remarkup parser from grammar.js.
#
# Run this after editing
#   Packages/Marginalia/Vendor/tree-sitter-remarkup/grammar.js
# to refresh the committed parser.c. Requires Node.js / npm — uses npx so
# the tree-sitter CLI doesn't need to be installed globally.
#
set -euo pipefail
cd "$(dirname "$0")/../Packages/Marginalia/Vendor/tree-sitter-remarkup"
npx --yes tree-sitter-cli generate
echo "Generated src/parser.c — commit it alongside the grammar.js change."
