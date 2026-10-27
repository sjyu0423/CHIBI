#!/bin/sh
# Renders animation previews from the real character code into assets/previews/animation.
# Requires the Xcode toolchain plus Python with Pillow and NumPy (PYTHON overrides python3).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build/animation-preview"
PYTHON="${PYTHON:-python3}"

cd "$ROOT"
swift build
mkdir -p "$WORK"
swiftc -swift-version 6 -parse-as-library -O \
  Sources/CHIBIApp/Audio/*.swift \
  Sources/CHIBIApp/Behavior/*.swift \
  Sources/CHIBIApp/Character/*.swift \
  Sources/CHIBIApp/Settings/*.swift \
  scripts/AnimationPreviewRenderer.swift \
  -o "$WORK/renderer"
CHIBI_RESOURCE_BUNDLE="$ROOT/.build/debug/CHIBI_CHIBIApp.bundle" "$WORK/renderer" "$WORK"
"$PYTHON" scripts/assemble-animation-previews.py "$WORK" assets/previews/animation
