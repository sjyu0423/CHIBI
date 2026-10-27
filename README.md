# CHIBI

CHIBI is a native macOS desktop companion. The default **Sleepy Coder** presentation uses a
faithful transparent cutout of the approved complete front-facing illustration. The earlier
part-by-part assembly remains available as an experimental manifest mode; the procedural
character remains the final fallback.

`sleepy-coder.json` selects either `fullBody` or `layered` rendering and defines artwork layout
and animation timing. A missing full-body image falls back to the layered/procedural path.

## Requirements

- macOS 13 or newer
- Xcode 27.1 or matching Command Line Tools
- Swift 6.4
- No third-party packages

The application has no runtime dependencies. Regenerating artwork requires Python with Pillow
and NumPy.

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

The flower menu-bar item controls visibility, Small/Medium/Large size, music reaction, animation
previews, position reset, and quitting. Drag the character itself to move it; click it for a happy
reaction. Transparent pixels outside the approximate character silhouette pass mouse input
through to the application below.

## Music reactive dancing

**Music Reactive › Start Listening** lets the character dance to whatever the Mac is playing.
Nothing listens until you choose Start; listening always begins off after launch.

- **Privacy:** CHIBI measures loudness and rhythm locally, in memory. It never records, saves,
  or uploads audio, never uses the microphone, and ignores the tiny video stream ScreenCaptureKit
  requires.
- **Permission:** macOS groups system audio with screen recording. The first Start shows the
  system prompt; allow CHIBI under System Settings › Privacy & Security › Screen & System Audio
  Recording, then quit and reopen CHIBI. If access is missing, the menu says so and offers
  **Open Privacy Settings…**. Ad-hoc rebuilds can invalidate the grant; remove and re-add CHIBI
  in that list if Start keeps reporting a permission problem.
- **Dancing:** quiet music → gentle sway; moderate, rhythmic music → sway with a dip on the
  beat; loud music with a steady beat → hop dance that follows the tempo. Beats add small
  squash accents. When the music stops, the character settles back to idle after about 1.5 s.
- **Sensitivity** (Low/Normal/High) shifts how loud audio must be; **Auto Dance** off keeps
  listening without dancing. Both are remembered.
- Dragging, clicking, sleep, and the Animation Preview menu always take priority; choose
  **Animation Preview › Idle** to hand control back to the music.

Testing with real music: start playback in any app at normal volume, choose Start Listening, and
watch the status line change from "waiting for music" to "Hearing music (~N BPM)". Try a quiet
ballad (gentle sway), a mid-tempo pop song (rhythmic sway with accents), a dance track (hop
dance), pause and resume quickly (no restart), then stop playback (settles within ~2 s).

## Animation preview

Open **Animation Preview** from the flower menu and choose Idle, Happy, Sleep, Walk in
Place, Sway Dance, or Hop Dance. Selecting another animation interrupts the current pose cleanly.
Dragging temporarily interrupts a looping preview and restores it on release; dragging during
the one-shot happy reaction returns to idle.

The **Developer** submenu offers session-only Slow Motion (¼×) and a toggle for the experimental
head-tilt and hair warp, which is available when the manifest defines a `fullBodyRig`.

Render offscreen animation previews (GIFs, filmstrips, warp review sheets, and a
`music-reactive` clip driven by a synthetic soundtrack) into `assets/previews/animation` with a
Python that has Pillow and NumPy:

```sh
PYTHON=.build/artvenv/bin/python scripts/render-animation-previews.sh
```

## Manual smoke checklist

1. Launch `.build/CHIBI.app`; confirm the character and flower menu item appear without
   focusing the overlay.
2. Preview Idle, Happy, Sleep, Walk in Place, Sway Dance, and Hop Dance; confirm each switches
   cleanly.
3. Confirm the default full-body idle has subtle breathing, sway, and head/hair motion without
   visual distortion.
4. Click the character; confirm the happy hop completes and returns to idle.
5. Drag during Idle, Sleep, Walk, and both dances; confirm the prior looping pose resumes.
6. Drag between displays if available and confirm the character remains reachable.
7. Click through the window's transparent corners into an app underneath.
8. Exercise Show/Hide, all three sizes, and Reset Position.
9. Quit and relaunch; confirm visibility, size, and last dragged position persist.
10. Confirm Music Reactive shows "Not listening" after launch. Start Listening with music
    playing; confirm the permission flow, dancing, drag override, and settling after Stop.
11. Choose Quit CHIBI (or press Command-Q while the menu is open) and confirm exit.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for component boundaries and
[docs/HANDOFF.md](docs/HANDOFF.md) for current verification status.

## Character assets

The original flattened sheets are in `assets/source/sleepy-coder`. Rebuild the approved
full-character sprite and its transparent, dark-background, and source-comparison previews with:

```sh
python3 scripts/generate-sleepy-coder-full-sprite.py
```

### Small-size display

The overlay draws the sprite 5–10× smaller than its source. The manifest's `fullBodyDisplay`
block resamples it with Lanczos filtering to the exact on-screen pixel size (`displayResampled`),
and selects the `soft` variant. That variant has gentler hair gloss and shadows; the eyes, face,
hoodie, outlines, and alpha are unchanged. Regenerate it after the main sprite with:

```sh
python3 scripts/generate-sleepy-coder-soft-sprite.py
```

To revert, set `"variant": "original"` (original art, still resampled). To restore the previous
rendering exactly, also set `"sampling": "direct"`, or remove the block. Compare all options at
every size, 1× and 2×, with:

```sh
PYTHON=.build/artvenv/bin/python scripts/render-display-previews.sh   # assets/previews/display
```

The experimental part rig can still be regenerated separately with:

```sh
python3 scripts/generate-sleepy-coder-assets.py
```

Generated PNGs live in `Sources/CHIBIApp/Resources/Characters/sleepy-coder`. The full-character
script cleans the single-figure RGBA export `base_character_transparent.png`: it keeps only the
connected character silhouette, drops the faint matte halo, and does not reshape or reconstruct
the artwork.

To add another character, provide original or licensed artwork, create a validated manifest,
place transparent PNGs under `Resources/Characters/<identifier>`, and add a reproducible export
script when needed. For `fullBody`, register one PNG plus its position, normalized anchor, and
scale. For `layered`, also provide per-layer placement, pivots, draw order, and scale. Add
registration, fallback, and alpha-resource tests before switching defaults.
