#!/bin/bash
set -euo pipefail
FOLDBAR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FOLDBAR_BUILD="${FOLDBAR_BUILD_DIR:-$FOLDBAR_ROOT/.build-local}"
mkdir -p "$FOLDBAR_BUILD/module-cache"
swiftc -module-cache-path "$FOLDBAR_BUILD/module-cache" \
    "$FOLDBAR_ROOT"/Sources/FoldBarCore/*.swift \
    "$FOLDBAR_ROOT/Tests/CoreChecks/main.swift" -o "$FOLDBAR_BUILD/core-checks"
"$FOLDBAR_BUILD/core-checks"
