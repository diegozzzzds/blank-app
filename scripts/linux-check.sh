#!/usr/bin/env bash
# Checks what can be checked without a Mac:
#   1. Syntax of every Swift file (swiftc -parse; imports are not resolved).
#   2. Builds MusicApp/Core as a SwiftPM package and runs the unit tests.
# Core must only depend on Foundation, so any UIKit/SwiftUI/AVFoundation import fails this build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK_DIR:-$(mktemp -d)}"
PKG="$WORK/pkg"

echo "==> Parsing all Swift files"
find "$ROOT/MusicApp" "$ROOT/MusicAppTests" -name '*.swift' -print0 | xargs -0 swiftc -parse

echo "==> Assembling package in $PKG"
rm -rf "$PKG"
mkdir -p "$PKG/Sources" "$PKG/Tests"
cp "$ROOT/scripts/linux/Package.swift" "$PKG/Package.swift"
cp -R "$ROOT/MusicApp/Core" "$PKG/Sources/MusicApp"
cp -R "$ROOT/MusicAppTests" "$PKG/Tests/MusicAppTests"

echo "==> swift build"
(cd "$PKG" && swift build --build-tests)

echo "==> swift test"
(cd "$PKG" && swift test "$@")
