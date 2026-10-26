# CHIBI

CHIBI is a native macOS desktop companion. Milestone 1A adds a replaceable, layered
character renderer and expressive animation foundation while retaining the transparent,
non-activating overlay from M0.

The bundled character is original procedural placeholder art. A validated JSON manifest
can reference transparent PNG layers for hair, legs, torso, arms, head, face, eyes, and
mouth. Missing images fall back to the procedural layer, so an incomplete art set remains
usable during development.

## Requirements

- macOS 13 or newer
- Xcode 27.1 or matching Command Line Tools
- Swift 6.4
- No third-party packages

## Build and run

```sh
swift build
swift test
chmod +x scripts/build-app.sh
scripts/build-app.sh
open .build/CHIBI.app
```

In restricted execution environments, SwiftPM may need `--disable-sandbox` and writable
Clang/SwiftPM module-cache paths. This is an environment workaround, not an application
requirement.

The flower menu-bar item controls visibility, Small/Medium/Large size, animation previews,
position reset, and quitting. Drag the character itself to move it; click it for a happy
reaction. Transparent pixels outside the approximate character silhouette pass mouse input
through to the application below.

## Animation preview

Open **Animation Preview** from the flower menu and choose Idle, Happy, Sleep, Walk in
Place, or Dance. Selecting another animation interrupts the current pose cleanly. Dragging
temporarily interrupts a looping preview and restores it on release; dragging during the
one-shot happy reaction returns to idle.

## Manual smoke checklist

1. Launch `.build/CHIBI.app`; confirm the character and flower menu item appear without
   focusing the overlay.
2. Preview Idle, Happy, Sleep, Walk in Place, and Dance; confirm each switches cleanly.
3. Confirm idle has subtle breathing, independent head/hair motion, and varied blink timing.
4. Click the character; confirm the happy hop completes and returns to idle.
5. Drag during Idle, Sleep, Walk, and Dance; confirm the prior looping pose resumes.
6. Drag between displays if available and confirm the character remains reachable.
7. Click through the window's transparent corners into an app underneath.
8. Exercise Show/Hide, all three sizes, and Reset Position.
9. Quit and relaunch; confirm visibility, size, and last dragged position persist.
10. Choose Quit CHIBI (or press Command-Q while the menu is open) and confirm exit.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for component boundaries and
[docs/HANDOFF.md](docs/HANDOFF.md) for current verification status.
