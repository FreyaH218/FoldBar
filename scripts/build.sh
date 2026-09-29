#!/bin/bash
set -euo pipefail

FOLDBAR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FOLDBAR_BUILD="${FOLDBAR_BUILD_DIR:-$FOLDBAR_ROOT/.build-local}"
FOLDBAR_OUTPUT="${FOLDBAR_OUTPUT_DIR:-$FOLDBAR_ROOT/dist}"
mkdir -p "$FOLDBAR_BUILD" "$FOLDBAR_OUTPUT"
export CLANG_MODULE_CACHE_PATH="$FOLDBAR_BUILD/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$FOLDBAR_BUILD/module-cache"

swift build -c release --package-path "$FOLDBAR_ROOT" --scratch-path "$FOLDBAR_BUILD/spm" \
    --cache-path "$FOLDBAR_BUILD/cache" --config-path "$FOLDBAR_BUILD/config" \
    --security-path "$FOLDBAR_BUILD/security" --manifest-cache none --disable-sandbox
FOLDBAR_BIN="$(swift build -c release --package-path "$FOLDBAR_ROOT" --scratch-path "$FOLDBAR_BUILD/spm" --show-bin-path --disable-sandbox)"
FOLDBAR_APP="$FOLDBAR_OUTPUT/FoldBar.app"
mkdir -p "$FOLDBAR_APP/Contents/MacOS" "$FOLDBAR_APP/Contents/Resources"
cp "$FOLDBAR_BIN/FoldBar" "$FOLDBAR_APP/Contents/MacOS/FoldBar"
cp "$FOLDBAR_ROOT/Resources/Info.plist" "$FOLDBAR_APP/Contents/Info.plist"
swift "$FOLDBAR_ROOT/scripts/make-icon.swift" "$FOLDBAR_BUILD/AppIcon.iconset"
cp "$FOLDBAR_BUILD/AppIcon.icns" "$FOLDBAR_APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.foldbar.app "$FOLDBAR_APP"
codesign --verify --strict "$FOLDBAR_APP"
printf 'Built: %s\n' "$FOLDBAR_APP"
