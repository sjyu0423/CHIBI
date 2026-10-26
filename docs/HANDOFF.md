# Handoff

## Status

- Current work: M1B overlay black-line fix (SpriteKit letterbox); full-body sprite previously
  replaced from `base_character_transparent.png`
- Branch: `milestone-1b-character-integration`
- Baseline: committed M1A at `a6cad3e`; all M1B work remains uncommitted
- Commits/pushes this session: none
- Source artwork under `assets/source/sleepy-coder` remains unmodified
  (`base_character_transparent.png` SHA-256 `10d0adcb...7118eaa3`, unchanged after generation)
- Default renderer: `fullBody`; prior layered assembly retained as experimental fallback

## Overlay black lines (2026-10-26)

Symptom: thin black horizontal lines at the top and bottom edges of the desktop overlay.

Root cause: SpriteKit `.aspectFit` letterboxing, not the image or AppKit. The scene was the
manifest's 640×760 (aspect 0.8421), but the overlay windows are 150×180, 210×250 and 285×340
(aspects 0.8333, 0.8400, 0.8382). Each window is slightly taller than the scene, so `.aspectFit`
left bars at the top and bottom of 0.94 pt (Small), 0.31 pt (Medium) and 0.78 pt (Large).
`SKView` paints those bars opaque black even with `allowsTransparency = true` and a clear scene
background.

How it was isolated before changing code:

- Packaged PNG: 4 px fully transparent margin on every side, and the sprite spans only scene
  y −336…320 of ±380, so it cannot reach the window edges.
- AppKit: borderless, `isOpaque = false`, clear background, no shadow, `SKView` as the content
  view; no borders, boxes, layers, or separators are drawn.
- SpriteKit: no debug overlays (`shows*`), no `SKShapeNode` in full-body mode, no cropping or
  effect nodes; scene background is clear.
- Screen Recording permission is not granted, so the live app window could not be captured
  (`screencapture -l` failed; computer-use is waiting for permission). Instead, a harness
  (`.build/overlay-capture/harness.swift`, not part of the app) reproduced the exact window,
  `SKView`, and scene configuration with the packaged sprite and captured its own windows using
  `CGWindowListCreateImage`. Before the fix: Small and Large had one full-width row of opaque
  black (alpha 255, RGB 0) at both the first and last pixel row; all rows between them and the
  character were fully transparent. Medium's 0.31 pt bar rounded away at the harness's 1×
  capture but covers ~0.6 px on a 2× display.

Fix (no artwork, size, position, or animation changes):

- `CharacterManifest.RenderDimensions.sceneSize(fitting:)` expands the render area to the view's
  exact aspect ratio, never shrinking either dimension (640×768, 640×761.9, 640×763.5).
- `CharacterScene.didMove(to:)` and new `fitRenderArea(to:)` apply it; `CharacterView`
  overrides `setFrameSize` so Small/Medium/Large changes refit. `fitRenderArea(to:)` was added to
  the `CharacterRendering` seam.
- After the fix, the harness shows every edge row and column fully transparent at all three
  sizes, both when presented at a size and when resized from Medium via `window.setFrame`. The
  character's pixels are identical to the letterboxed rendering (max diff 0), so size and
  position are unchanged. Character bounds leave clear margins (Small: rows 15–167 of 180;
  Large: rows 28–318 of 340), and the taller scene adds a little headroom for the happy hop.

## Renderer recovery

- Added `renderingMode` to the manifest with `layered` as the decoding default for compatibility.
- Added full-body asset metadata: PNG path, position, normalized anchor, and positive scale.
- Added `FullBodyCharacterNode` and `FullBodyCharacterAnimator`.
- `CharacterScene` selects the requested renderer and falls back to layered/procedural rendering
  when a registered full-body image cannot load.
- Introduced the real `CharacterAnimating` substitution seam shared by both animators.
- The full-body animator presents idle, happy, dragging, sleep, walking in place, and dance using
  only whole-sprite bobbing, small rotations, and squash-and-stretch. It does not independently
  animate limbs, hair, eyes, or mouth.

## Artwork process and results

Run (requires Pillow and NumPy; neither system Python has them, so this session used a throwaway
venv at `.build/artvenv`):

```sh
/opt/homebrew/bin/python3 -m venv .build/artvenv && .build/artvenv/bin/pip install pillow numpy
.build/artvenv/bin/python scripts/generate-sleepy-coder-full-sprite.py
```

The script now uses `assets/source/sleepy-coder/base_character_transparent.png`. (The request
named it `.jpeg`; the file on disk is a real 952×1652 8-bit RGBA PNG.) It contains only the single
front-facing character with no checkerboard, neighboring views, swatches, or printed ground line.
Its matte had three defects that the script fixes without touching the drawn artwork:

- The interior alpha was 253/254 rather than 255 (1,677 fully opaque pixels in total), so the
  character was very slightly see-through. Alpha is remapped linearly: ≤16 becomes 0, ≥240
  becomes 255.
- A faint low-alpha halo (~16k pixels at alpha 1–16, about 21% of them near-white) surrounded
  the ink outline and showed as a pale ring on dark desktops. It is removed by the remap.
- Near-invisible residue sat below the shoes and against the left canvas edge. Only the largest
  connected silhouette (source alpha ≥24, dilated 2 px for antialiasing) is kept.

Partially transparent contour pixels take their color from adjacent opaque artwork (the black ink
outline). Every fully opaque pixel is byte-identical to the source RGB (verified at offset
x −4, y +30). The cleaned image is cropped to its alpha bounds and padded 4 px on a transparent
canvas, which adds space on the left where the hair outline came within 1 px of the source edge.

Outputs:

- `Sources/CHIBIApp/Resources/Characters/sleepy-coder/full-body.png` — 955×1599 RGBA
- `assets/previews/sleepy-coder-full-body.png` — true transparent preview
- `assets/previews/sleepy-coder-full-body-dark.png` — solid dark (24, 24, 28) background preview
- `assets/previews/sleepy-coder-full-body-comparison.png` — source vs cleaned, both on dark

The old plum `sleepy-coder-full-body-contrast.png` showed the previous sprite and is no longer
produced, so it was deleted. `chibi_transparent.jpeg` is no longer used by any script.

Manifest `fullBodyLayout.scale` changed from 0.6 to 0.41 so the on-screen size stays the same
(old 1093 × 0.6 ≈ 656 pt tall; new 1599 × 0.41 ≈ 656 pt). Position (0, −8) and anchor are
unchanged, so the render-relative hit-test silhouette still lines up. The same scale is written by
`generate-sleepy-coder-assets.py` so regenerating the layered rig keeps it.

The older `generate-sleepy-coder-assets.py`, its layer PNGs, and assembly previews remain for the
experimental `layered` mode. That rig is not the visual default.

## Verification (2026-10-26, overlay black-line fix)

- `xcrun swift-format lint -r Sources Tests Package.swift`: passed with no findings.
- `swift build`: passed.
- `swift test`: 25/25 tests passed in 3 suites. New tests:
  `sceneSizeMatchesEveryOverlayAspectWithoutShrinkingRenderArea` (every `CharacterSize` gets an
  exact-aspect scene that contains the 640×760 render area) and
  `sceneFitsRenderAreaToViewWithoutChangingCharacterScale` (`CharacterScene.fitRenderArea`
  applies it and the effective view scale equals the old letterboxed scale).
- Harness captures (`.build/overlay-capture/`): before = black edge rows at Small and Large;
  after = transparent edges at all sizes, presented and resized; character pixels unchanged.
  Comparison image: `.build/overlay-capture/before-after.png`.
- `scripts/build-app.sh`: passed; `codesign --verify --deep --strict` passed; packaged sprite is
  unchanged (`07df50ae...`).
- Relaunched `.build/CHIBI.app` (quit the older instance); it stayed running. The live overlay
  window itself was not visually inspected because Screen Recording permission is unavailable to
  the agent — see the manual test below.

## Verification (2026-10-26, base_character_transparent replacement)

- Generator: passed; produced the sprite and three previews. A second run gave byte-identical
  output (SHA-256 `07df50ae...b738a6c`).
- Format: `file` and `sips` report PNG, 955×1599, 8-bit RGBA, `hasAlpha: yes`.
- Alpha: 507,553 pixels at 0 (33.2%), 1,009,197 at 255, 10,295 partial contour pixels; range
  0–255. No alpha-0 pixel has non-zero RGB, so no hidden background data remains.
- No background or rectangle: all four image borders and the 4 px margin are fully transparent.
  All visible pixels form one connected component, so there are no specks or neighboring figures.
- Fringe: 0 contour pixels have luminance >180; mean contour luminance is 4.9 (dark ink).
  Zoomed hair, ahoge, hand, and shoe edges on dark and white backgrounds show no pale halo.
- Bottom line: the lowest 25 visible rows contain exactly two separate runs (the two shoe soles'
  ink outlines), with nothing spanning the gap between the feet and nothing below them.
- `xcrun swift-format lint -r Sources Tests Package.swift`: passed with no findings.
- `swift build`: passed (it must run outside the agent sandbox because SwiftPM's own
  `sandbox-exec` cannot nest).
- `swift test`: 23/23 tests passed in 3 suites. New test:
  `bundledFullBodySpriteFitsRenderDimensions` checks that the sprite fits inside the 640×760 render
  area at its manifest scale and position.
- `scripts/build-app.sh`: release build and ad-hoc signing passed; `codesign --verify --deep
  --strict` passed; packaged `Info.plist` passes `plutil -lint`.
- Packaged `full-body.png`: present, 955×1599, alpha on; SHA-256 matches the source resource.
  Packaged `sleepy-coder.json` contains scale 0.41.
- Launch smoke: quit an older running instance (still holding the previous sprite), relaunched
  `.build/CHIBI.app`, and it stayed running. No screenshot was taken because the Accessibility and
  Screen Recording permissions it needs were not granted, so on-screen appearance at each size has
  not been checked yet.

Tests cover renderer-mode backward compatibility, full-body metadata validation, required asset
registration, PNG alpha/resource presence, full-body sprite fit, full-body loading,
missing-sprite fallback, layered fallback, state transitions, and settings persistence.

## Files touched this session

Black-line fix:

- `Sources/CHIBIApp/Character/CharacterManifest.swift` (`RenderDimensions.sceneSize(fitting:)`)
- `Sources/CHIBIApp/Character/CharacterRendering.swift` (`fitRenderArea(to:)`)
- `Sources/CHIBIApp/Character/CharacterScene.swift` (`didMove(to:)`, `fitRenderArea(to:)`)
- `Sources/CHIBIApp/Overlay/CharacterView.swift` (`setFrameSize` refit)
- `Tests/CHIBIAppTests/CharacterManifestTests.swift` (two scene-fit tests)
- `docs/ARCHITECTURE.md`, this handoff

Earlier sprite replacement:

- `scripts/generate-sleepy-coder-full-sprite.py` (rewritten for the RGBA source)
- `scripts/generate-sleepy-coder-assets.py` (full-body scale 0.41)
- `Sources/CHIBIApp/Resources/sleepy-coder.json` (full-body scale 0.41)
- `Sources/CHIBIApp/Resources/Characters/sleepy-coder/full-body.png` (regenerated)
- `Tests/CHIBIAppTests/CharacterManifestTests.swift` (fit test)
- `assets/previews/sleepy-coder-full-body.png`, `-dark.png`, `-comparison.png` (regenerated/new);
  `-contrast.png` deleted
- `README.md`, `docs/ARCHITECTURE.md`, this handoff

## Known limitations

- Full-body mode cannot provide independent limb or secondary hair motion.
- Blink and mouth overlays are disabled in full-body mode because the available parts-sheet assets
  do not register accurately enough against the approved master. The eyes and neutral expression
  remain exactly as illustrated.
- Walk and dance are stylized whole-character in-place transforms, not articulated walk cycles.
- The runtime texture is 955×1599 and is drawn at 0.41 scale. That is sharp on Retina, but it uses
  more texture memory than a pre-downscaled export would.
- Per-pixel alpha hit testing is not implemented; the existing approximate silhouette is retained.
- The app is locally ad-hoc signed, not distribution signed/notarized.

## Remaining manual GUI checklist

1. Black-line check: on a light wallpaper (lines are most visible there), switch the menu size to
   Small, Medium, and Large. Zoom in on the overlay's top and bottom edges (Accessibility > Zoom or
   a screenshot at 400%). Expect no horizontal line at any size, and the hair tuft and shoe soles
   fully visible. Repeat on a Retina and a non-Retina display if both are available.
   Also inspect hair outline, hands, and shoe soles on a dark wallpaper.
2. Preview Happy, Sleep, Walk in Place, and Dance from the menu and confirm whole-sprite transforms
   interrupt and reset without clipping or cumulative drift.
3. Confirm click reaction returns to idle; confirm drag interruption/restoration for looping states.
4. Confirm approximate silhouette hit testing and transparent-corner pass-through.
5. Exercise Show/Hide, size, reset-position, persistence, multi-display clamping, and Quit.

## Recommended next step

Run manual checklist item 1 on the relaunched app (`open .build/CHIBI.app`) to confirm the black
lines are gone in the live overlay at all three sizes, then complete the animation/input items.
Keep music capture and AI work out of scope until this renderer is accepted.
