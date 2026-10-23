#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
xcrun swiftc -module-cache-path "$BUILD/cache" "$ROOT/HotMessClip/ClipLink.swift" "$ROOT/HotMessClip/ClipTipAmounts.swift" "$ROOT/HotMessClipTests/main.swift" -o "$BUILD/clip-tests"
"$BUILD/clip-tests"
