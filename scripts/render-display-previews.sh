#!/bin/sh
# Renders the resting character at Small/Medium/Large, 1x and 2x, for each full-body display
# option, into assets/previews/display. Requires the Xcode toolchain plus Python with Pillow and
# NumPy (PYTHON overrides python3).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build/display-preview"
PYTHON="${PYTHON:-python3}"

cd "$ROOT"
swift build
mkdir -p "$WORK"
swiftc -swift-version 6 -parse-as-library -O \
  Sources/CHIBIApp/Behavior/*.swift \
  Sources/CHIBIApp/Character/*.swift \
  Sources/CHIBIApp/Settings/*.swift \
  scripts/AnimationPreviewRenderer.swift \
  -o "$WORK/renderer"
CHIBI_RESOURCE_BUNDLE="$ROOT/.build/debug/CHIBI_CHIBIApp.bundle" \
  "$WORK/renderer" "$WORK/stills" display
"$PYTHON" scripts/assemble-display-previews.py "$WORK/stills" assets/previews/display
