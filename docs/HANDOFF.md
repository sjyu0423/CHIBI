# Handoff

## Status

- Current work: M2A checkpoint finalized. The animation foundation and small-size rendering are
  committed on `milestone-2a-animation` and are under review in a pull request.
- M2A commit: `2660740aabb789023360dfdc3f02c6bc2afdb014` ("feat: M2A full-body animation
  foundation and small-size rendering"; 59 files). This handoff update follows it as a docs-only
  commit.
- Pull request: https://github.com/sjyu0423/CHIBI/pull/1 (`milestone-2a-animation` → `main`).
  It's open and not merged; merging waits for the manual desktop review checklist.
- Stable baseline: `fde39eae0bcd28e5eae072286a2164fbd0284b65`
  - `main`, `milestone-1b-character-integration`, and annotated tag `v0.1-character-baseline`
    (tag object `234b831d`) all point at it
- Remote: `origin` = https://github.com/sjyu0423/CHIBI (public; the owner chose to keep it public)
  - `main` (tracking `origin/main`) and the tag are pushed and verified with `git ls-remote`
  - `milestone-2a-animation` is pushed and tracks `origin/milestone-2a-animation`
  - The M1A and M1B milestone branches exist only locally
- Commits:
  - M1B baseline `fde39ea` plus the tag
  - M2A `2660740` plus this handoff update
- Nothing was force-pushed. `main` and `v0.1-character-baseline` are unchanged on the remote.
  Do not merge M2A into `main` without approval.
- Final checks before the M2A commit:
  - `xcrun swift-format lint -r Sources Tests Package.swift`: no findings
  - `swift build`: passed
  - `swift test`: 46/46 passed
- Before committing, verified that no caches, captures, or secrets were included. The harness
  output and the Python venv stay in the ignored `.build/`. The committed review previews total
  18 MB, and the largest file is 2 MB.
- Source artwork under `assets/source/sleepy-coder` is unmodified. The approved sprite
  (`full-body.png`, SHA-256 `07df50ae...`) is unchanged.

## Small-size visual optimization (2026-10-26)

Problem: at desktop size the sprite looked shiny and noisy. The hair highlights, facial details,
and thin outlines were distracting.

### Root cause: texture minification aliasing

The 955×1599 sprite is drawn at these heights:

| Preset | Points | Pixels at 1× | Pixels at 2× | Minification (1× / 2×) |
| --- | --- | --- | --- | --- |
| Small | 154 | 154 | 307 | 10.4× / 5.2× |
| Medium | 215 | 215 | 430 | 7.4× / 3.7× |
| Large | 292 | 292 | 584 | 5.5× / 2.7× |

SpriteKit samples bilinearly: each screen pixel reads only 4 of the 7–100 source pixels behind
it. So the thin ink lines break into dotted, stair-stepped runs, and the bright hair gloss bands
sparkle. `head-zoom-1x.png` shows broken outlines in the `original-direct` column.

### Rendering comparison

Done first, before any artwork change, using an offscreen harness through the real node at
exact preset pixel sizes. Lower detail energy means less pixel noise; it's the mean absolute
Laplacian on a light background, measured at Medium 1× / 2×.

| Option | Energy | Result |
| --- | --- | --- |
| Current: linear, full-res texture | 26.9 / 17.9 | broken outlines, sparkle |
| `nearest` filtering | 28.1 / 19.1 | worse; rejected |
| `usesMipmaps` | identical to current | SpriteKit ignores it for this non-power-of-two texture; rejected |
| Core Graphics high-quality downsample to exact size | 9.7 / 7.4 | clean, but softer and greys the ink outline |
| vImage Lanczos downsample to exact size | 11.0 / 8.3 | clean, keeps outline weight and eye detail; **chosen** |
| Fixed 2× texture on a 1× display | 21.6 | still aliased; resolution must follow the backing scale |

### Implementation

- `SpriteResampler` performs an Accelerate `vImageScale_ARGB8888` with
  `kvImageHighQualityResampling` on premultiplied sRGB RGBA. It then clamps each color
  channel to alpha, because Lanczos overshoot would otherwise draw a bright fringe.
- `FullBodyCharacterNode.prepareTexture(pixelsPerSceneUnit:)` swaps in a texture matching the
  sprite's on-screen pixel height, and only when that height changes. The sprite's size and
  frame in scene units are unchanged, so layout, hit testing, warps, and animations are
  unaffected.
- `CharacterScene.fitRenderArea(to:backingScale:)` computes pixels per scene unit.
  `CharacterView` refits on `setFrameSize` and `viewDidChangeBackingProperties`, which covers
  size presets and moving between 1× and 2× displays. The backing scale only selects texture
  resolution; positions stay in points.
- GPU texture memory drops from 6.1 MB (the full-resolution texture) to 0.1–0.8 MB. The source
  image is decoded once and kept for re-resampling.

### Soft art variant: selective hair tone pass

`scripts/generate-sleepy-coder-soft-sprite.py` writes `full-body-soft.png` (955×1599, same
alpha) from `full-body.png`.

- Measured hair palette:
  - base (224, 220, 228)
  - gloss highlight (244, 245, 252), about 49k pixels
  - cel shadow (171, 164, 178), about 48k pixels
- A continuous, monotonic luminance curve changes only neutral hair pixels:
  - highlights compress about halfway toward the base (L 244 → 235)
  - shadows lift slightly (L 165 → 177)
  - ink below L 120 and the base tone are unchanged
- The weights are feathered by saturation (skin and blush excluded), by a hair line at 55.5% of
  the height (excluding the hoodie, drawstrings, socks, and shoes), and by the eye boxes (eye
  whites and catchlights excluded).
- Changed pixels: 7.8%; maximum channel change: 15. The eyes, face, blush, hoodie, outlines,
  and alpha are byte-identical (unit-tested), and there's no blur or sharpening.
- Rerunning the script is byte-reproducible (`f86160ca...`).
- At actual size the top gloss band and strand highlights read calmer. The silver hair keeps its
  cel-shaded look and her identity is unchanged. The effect is deliberately modest; most of the
  improvement comes from resampling.

### Selection and revert

The bundled manifest contains:

```json
"fullBodyDisplay": {
  "sampling": "displayResampled",
  "variant": "soft",
  "variants": { "soft": "Characters/sleepy-coder/full-body-soft.png" }
}
```

- Original art, resampled: set `"variant": "original"`.
- Exact previous behavior: also set `"sampling": "direct"`, or delete the `fullBodyDisplay` block.
- A missing or unreadable variant falls back to `full-body.png`. Validation rejects unknown
  variants, a variant named `original`, and unsafe or non-PNG paths.
- `generate-sleepy-coder-assets.py` writes the same block.

### Recommendation

Use the soft variant with display resampling (now the default). Resampling alone fixes the noise.
The soft variant additionally tames the gloss without visible change to the face. Original with
resampling is a faithful fallback if the hair should keep full gloss.

### Previews

Run `PYTHON=.build/artvenv/bin/python scripts/render-display-previews.sh`. It writes to
`assets/previews/display/`, rendering through the real `CharacterScene` with pixels shown 1:1:

- `display-1x.png` and `display-2x.png`: Small, Medium, and Large on light and dark backgrounds,
  with columns `original-direct`, `original-resampled`, and `soft-resampled`
- `head-zoom-1x.png` (3× nearest) and `head-zoom-2x.png` (2× nearest)
- `summary.json`: bounds, edge alpha, clipping, and detail energy for all 18 stills

### Verification

Automated:

- Detail energy, original-direct → soft-resampled:

  | Preset | 1× | 2× |
  | --- | --- | --- |
  | Small | 30.7 → 14.6 | 22.3 → 12.4 |
  | Medium | 26.9 → 10.9 | 17.9 → 8.2 |
  | Large | 22.6 → 8.9 | 13.3 → 6.9 |

- Bounds match within 1 px across options, so size and position are unchanged.
- Every still has fully transparent window edges (`edgeAlphaMax` 0), so there's no clipping and
  no letterbox bars.
- Animation previews were re-rendered (now soft and resampled at 2×). All 8 clips pass the
  clipping check, and 1:1 crops of tilted and warped frames are clean.

Visual (agent, offscreen renders): reviewed the head zooms and full sheets at all sizes, and
crops of frames in motion. The live desktop overlay still wasn't inspected, because Screen
Recording permission isn't available.

## Git checkpoint (Phase 1)

- `swift build` and `swift test` (25 tests) passed on the M1B tree before committing.
- `.gitignore` was rewritten to cover macOS metadata, `.build/`, `.swiftpm/`, Xcode user data,
  Python caches and venvs, editor folders, `.env*`, and signing material (`*.p12`, `*.pem`,
  `*.key`, `*.cer`, provisioning profiles).
- Committed M1B on `milestone-1b-character-integration` and fast-forwarded `main` to it.
- Created the annotated tag `v0.1-character-baseline`.
- The GitHub repository already existed and was public rather than private. The owner chose to
  keep it public.
- Pushed `main` and the tag without force. The remote `main` history contains only `a6cad3e`
  and `fde39ea`, so nothing was overwritten.
- Created `milestone-2a-animation` from `main`.

## M2A animation changes

All motion keeps the approved sprite intact. Nothing is redrawn, cut up, or reconstructed.

### Pure choreography

`FullBodyMotion.swift` contains `FullBodyChoreography.motion(for:configuration:)`, which describes
each state as absolute keyframe tracks. Each track has an optional intro followed by a loop, so
repeated loops cannot drift. The tracks are plain values and are tested without SpriteKit:

- body track: translation, rotation, and squash/stretch
- optional breath track
- optional expression track: head tilt and hair sway

### SpriteKit presentation

`FullBodyCharacterNode` uses this node hierarchy:

- `bodyPivot`: at the feet; rotation and squash keep the shoes planted
- `breathPivot`: breathing scale
- `spriteRoot`, then `sprite`: the sprite carries the optional warp
- `effectsRoot`: sleep "z" bubbles

`FullBodyCharacterAnimator`:

- uses one action key per channel
- always calls `resetPose()` before presenting a state, which removes every action and restores
  baseline transforms and the rest warp
- schedules the completion callback for finite reactions only

### States

| State | Motion |
| --- | --- |
| Idle | slow breathing, a ±0.6° sway over 6.4 s, occasional small head tilt and hair drift |
| Happy | anticipation crouch, hop, landing squash, smaller rebound hop, settle; returns to idle |
| Sleep | droops and nods off, catches itself, settles into slow deep breathing; drowsy head droop and floating "z" bubbles |
| Walk in place | alternating half-steps with bob, lean, and squash |
| Sway Dance (renamed from Dance) | gentle side-to-side sway with a dip on each beat |
| Hop Dance (new) | crouch, four alternating side hops, one big center hop; synced head and hair |
| Dragging | lift, then a slow dangling sway |

Hop Dance is a new `CharacterState.hopDancing` and `CharacterAnimation.hopDance`. It follows
the same drag, sleep, and replacement rules as the other looping previews. The layered
fallback animator got a matching root-hop implementation.

### Manifest and layout

- `fullBodyLayout.position.y` changed from −8 to −24 to give the hops headroom. Scale and anchor
  are unchanged.
- `idleCycleDuration` changed from 2.6 to 3.2, which slows the idle.
- `happyHopHeight` changed from 38 to 30.
- New optional `fullBodyRig` (neck point, head blend height, maximum tilt, hair band, maximum
  sway). It's validated and rejected with `invalidFullBodyRig` when out of range.
- `scripts/generate-sleepy-coder-assets.py` writes the same values, so regenerating the manifest
  keeps them.

### Developer controls

The menu bar has a new Developer submenu, which is session-only and not persisted:

- Slow Motion (¼×): sets `CharacterScene.speed`.
- Head Tilt & Hair Motion (Experimental): toggles the warp. It's available only when the
  manifest has a rig.

### CPU

The view already runs at 30 fps. Measured idle on the relaunched release app:

- CPU averaged 4.5% (peak 6.5%) over 20 s, sampled with `ps`
- RSS was 58 MB

There are no timers or physics. Sleep bubbles are short-lived label nodes, one every ~2 s.

## Experiments

### Head tilt and hair secondary motion: accepted (default on, toggleable)

Implemented as an `SKWarpGeometryGrid` (8×16) on the single sprite (`FullBodyWarp.swift`):

- Head: rotates about the neck point (0.48, 0.46). The rotation weight is blended with a
  smoothstep across 7% of the height, so there's no hard boundary.
- Hair: only the outer side bands between y 0.46 and 0.72 sway, fading to zero toward the face
  and at the tips.
- Below the neck, vertices are mathematically unchanged (unit-tested). Proportions are
  preserved.
- Extremes: ±2° tilt and ±1.4% width hair sway. 1:1 crops at the extremes show no tearing,
  seams, or doubled lines. Previews: `assets/previews/animation/warp-extremes.png`,
  `warp-neck.png`, and `warp-hair-tips.png`.
- Trade-off: warped pixels are resampled, so the head and hair are very slightly softer than the
  rigid sprite while moving. At rest the warp is identity.

### Blinking with registered eye overlays: rejected

`scripts/preview-blink-overlay-experiment.py` composites skin-colored lids plus the scaled
`eye-*-closed.png` overlays onto the approved sprite
(`assets/previews/experiments/blink-overlay-experiment.png`). It fails visually:

- the lid patches show oval edges across hair strands
- the black lash wings and white eye corners leak out
- the thin brown overlay line style clashes with the sprite's bold black linework

The face reads as altered even at Medium size. The eyes therefore stay as illustrated, which
means they also stay open while sleeping. Real blinking needs artist-drawn closed-eye art
registered to `full-body.png`.

## Preview tooling

```sh
.build/artvenv/bin/pip install pillow numpy   # once; system Pythons lack Pillow
PYTHON=.build/artvenv/bin/python scripts/render-animation-previews.sh
```

`scripts/render-animation-previews.sh` compiles `scripts/AnimationPreviewRenderer.swift` together
with the Behavior, Character, and Settings sources. It renders the real `CharacterScene` offscreen
with `SKRenderer` at 2× Medium (420×500), 24 fps, into `.build/animation-preview/`. Then
`scripts/assemble-animation-previews.py` writes:

- 1× 12 fps GIFs and filmstrips for idle, idle-rigid (warp off), happy, sleep, walk, sway-dance,
  hop-dance, and dragging
- the warp review sheets
- `summary.json`, including a clipping check

All of these go to `assets/previews/animation/` (~14 MB).

SKRenderer does not advance actions near time 0, so the renderer starts its clock at 10,000 s.

## Verification (2026-10-26, small-size optimization)

- `xcrun swift-format lint -r Sources Tests Package.swift`: passed with no findings.
- `swift build` (debug): passed.
- `swift test`: 46/46 tests passed in 5 suites. New `FullBodyDisplayTests` cover:
  - bundled selection and fallback order
  - original and direct sampling when the block is absent or reverted
  - rejection of invalid display settings
  - fallback for a missing variant
  - the soft variant changes only hair, with identical dimensions and alpha
  - resampler size, color never above alpha, and faint edges
  - texture height for every preset at 1× and 2×, with sprite size and frame unchanged
  - direct sampling keeps the 1599 px texture
  - a real `NSWindow` plus `CharacterView` resamples for the window's backing scale and on resize
- `scripts/build-app.sh` (release): passed. `codesign --verify --deep --strict` and
  `plutil -lint` passed. The packaged `full-body.png` (`07df50ae...`) and `full-body-soft.png`
  (`f86160ca...`, 955×1599, alpha) match the sources, and the packaged manifest is
  byte-identical.
- Launch: relaunched `.build/CHIBI.app`, and it stayed running. Idle CPU averaged 4.2% (peak
  5.2%) over 20 s, with 57 MB RSS (4.5% before this change).

## Verification (2026-10-26, M2A)

Automated:

- `xcrun swift-format lint -r Sources Tests Package.swift`: passed with no findings.
- `swift build` (debug): passed. `swift build` and `swift test` must run outside the agent
  sandbox.
- `swift test`: 37/37 tests passed in 4 suites. New coverage:
  - Hop Dance state transitions, and a distinct state for every preview
  - valid keyframes for every state; only Happy finishes, and it ends at rest
  - expression loops stay in sync with body loops
  - every pose keeps the sprite inside the render area
  - rig registration and rejection of invalid rigs
  - the rest warp is identity and nothing below the neck moves; tilt direction
  - the feet pivot preserves the layout position
  - playing a state replaces actions, and the expressive toggle controls the warp
  - scene speed clamping and respect for rig support
- `scripts/build-app.sh` (release): passed. `codesign --verify --deep --strict` passed and
  `plutil -lint Info.plist` passed. The packaged `full-body.png` hash matches the source
  (`07df50ae...`), the packaged manifest is byte-identical to the source (including the rig), and
  all 18 character PNGs are present.
- Launch: quit the old instance, opened `.build/CHIBI.app`, and it stayed running (CPU above).
- Preview render: all 8 clips passed the clipping check (`edgeAlphaMax` 0). Measured at 2×:

  | Clip | Top edge rows | Feet rows | Largest per-frame top change |
  | --- | --- | --- | --- |
  | Idle | 47–52 | 479 | 1 px |
  | Happy | 18–75 | 460–479 | 23 px (take-off) |
  | Hop Dance | 15–85 | 463–479 | 22 px (take-off) |
  | Sleep | 41–54 | 478–481 | 7 px |
  | Walk | 39–63 | 476–479 | 9 px |
  | Sway Dance | 43–64 | 478–480 | 8 px |
  | Dragging | 34–52 | 476–479 | 6 px |

  The squash/stretch range in Happy and Hop Dance was softened once (take-off peak was 25 px).

Visual review (agent): the filmstrips, GIF frames, and warp crops were inspected. They are
rendered by the real SpriteKit pipeline, but offscreen.

- The sprite keeps its proportions in every state.
- Happy returns to rest.
- The sleep bubbles are legible beside the head.
- No warp seams.

The live desktop overlay was not inspected, because Screen Recording and Accessibility
permissions are not granted to the agent.

## Files touched (small-size optimization)

- `Sources/CHIBIApp/Character/SpriteResampler.swift` (new)
- `Sources/CHIBIApp/Character/CharacterManifest.swift` (`FullBodyDisplay`,
  `fullBodyImageCandidates`, `allAssetFiles`, `invalidFullBodyDisplay`)
- `Sources/CHIBIApp/Character/CharacterAssetLoader.swift` (`image(named:)`)
- `Sources/CHIBIApp/Character/FullBodyCharacterNode.swift` (variant loading, `prepareTexture`)
- `Sources/CHIBIApp/Character/CharacterScene.swift` (`init(manifest:assetLoader:)`,
  `fitRenderArea(to:backingScale:)`)
- `Sources/CHIBIApp/Character/CharacterRendering.swift`
- `Sources/CHIBIApp/Overlay/CharacterView.swift` (backing-change refit)
- `Sources/CHIBIApp/Resources/sleepy-coder.json`
- `Sources/CHIBIApp/Resources/Characters/sleepy-coder/full-body-soft.png` (new, generated)
- `scripts/generate-sleepy-coder-soft-sprite.py`, `scripts/render-display-previews.sh`, and
  `scripts/assemble-display-previews.py` (new)
- `scripts/AnimationPreviewRenderer.swift` (`display` mode, backing scale)
- `scripts/generate-sleepy-coder-assets.py` (manifest block)
- `Tests/CHIBIAppTests/FullBodyDisplayTests.swift` (new), `CharacterManifestTests.swift`
- `assets/previews/display/` (new), `assets/previews/animation/` (re-rendered)
- `AGENTS.md` (backing-scale clarification), `README.md`, `docs/ARCHITECTURE.md`, this handoff

## Files touched (M2A)

- `Sources/CHIBIApp/Behavior/CharacterStateMachine.swift` (Hop Dance state, Sway Dance title)
- `Sources/CHIBIApp/Character/FullBodyMotion.swift` (new)
- `Sources/CHIBIApp/Character/FullBodyWarp.swift` (new)
- `Sources/CHIBIApp/Character/FullBodyCharacterNode.swift`
- `Sources/CHIBIApp/Character/FullBodyCharacterAnimator.swift`
- `Sources/CHIBIApp/Character/CharacterAnimator.swift`
- `Sources/CHIBIApp/Character/CharacterManifest.swift`
- `Sources/CHIBIApp/Character/CharacterRendering.swift`
- `Sources/CHIBIApp/Character/CharacterScene.swift`
- `Sources/CHIBIApp/Overlay/CharacterOverlayWindowController.swift`
- `Sources/CHIBIApp/MenuBar/MenuBarController.swift`
- `Sources/CHIBIApp/Resources/sleepy-coder.json`
- `scripts/generate-sleepy-coder-assets.py`
- `scripts/AnimationPreviewRenderer.swift`, `scripts/render-animation-previews.sh`,
  `scripts/assemble-animation-previews.py`, `scripts/preview-blink-overlay-experiment.py` (new)
- `Tests/CHIBIAppTests/CharacterStateMachineTests.swift`
- `Tests/CHIBIAppTests/FullBodyAnimationTests.swift` (new)
- `assets/previews/animation/`, `assets/previews/experiments/` (generated)
- `README.md`, `docs/ARCHITECTURE.md`, `docs/MILESTONES.md`, this handoff

## Known limitations

- Eyes never blink or close, including during sleep (the overlay experiment was rejected).
- There are no articulated limbs. Walk and both dances are whole-sprite transforms; the feet
  don't step independently.
- Warped head and hair pixels are marginally softer while moving.
- At 1×, ink lines thinner than a screen pixel render as continuous grey lines rather than solid
  black. That's correct downsampling. Sharpening was deliberately not applied.
- The soft variant's tone curve is tuned to this sprite's palette and eye positions. Rerun and
  re-check the script whenever `full-body.png` is regenerated.
- Happy and Hop Dance take-off frames move about 11 pt per frame at 30 fps by design. Judge
  whether they feel snappy or jarring on screen.
- Sleep "z" bubbles use the system AvenirNext-Heavy font rather than drawn art.
- Per-pixel alpha hit testing is not implemented. The approximate silhouette doesn't follow hops
  or sway.
- The app is ad-hoc signed only.

## M1B history (summary)

- The full-body sprite is cleaned from `base_character_transparent.png` by
  `scripts/generate-sleepy-coder-full-sprite.py`:
  - keeps the largest silhouette
  - alpha ≤16 becomes 0 and ≥240 becomes 255
  - contour pixels are recolored from adjacent ink
  - opaque pixels stay byte-identical
  - 955×1599 at scale 0.41
- The overlay black lines were SpriteKit `.aspectFit` letterbox bars, which `SKView` paints
  opaque. `RenderDimensions.sceneSize(fitting:)` matches the scene to the window aspect, and
  `CharacterView.setFrameSize` refits on resize.

## Manual review checklist

0. Small-size readability: at Small, Medium, and Large, on a Retina display and on a 1× external
   display if available, check that hair outlines are continuous with no sparkle. Check that the
   face, teal eyes, blush, and navy hoodie look as before. To compare, set
   `"variant": "original"`, then also `"sampling": "direct"`, in
   `Sources/CHIBIApp/Resources/sleepy-coder.json`, rebuild with `scripts/build-app.sh`, and
   relaunch. Drag the overlay between displays with different scales and confirm it stays sharp.
1. On light and dark wallpapers at Small, Medium, and Large, confirm idle breathing and sway look
   natural, with no black edge lines, and that the hair tuft and shoes are never clipped.
2. Preview Happy (and click the character): the hop should feel bouncy, not jarring, and should
   return to idle.
3. Preview Sleep: check the nod-off timing and the "z" bubble placement and legibility. Decide
   whether open eyes while asleep are acceptable until closed-eye art exists.
4. Preview Walk in Place, Sway Dance, and Hop Dance: check the rhythm, and that the feet land
   believably and the sprite doesn't drift over a minute.
5. Developer > Slow Motion: inspect the head tilt and hair sway near the neck and hair tips for
   seams or wobble. Toggle Head Tilt & Hair Motion off and on to compare softness.
6. Switch animations rapidly and drag mid-hop: each switch should reset cleanly, and looping
   states should resume after a drag.
7. Confirm transparent-corner click-through and that the overlay never takes focus.

## Recommended next step

Run the manual review checklist on `open .build/CHIBI.app`, starting with item 0 (choose soft or
original on the real desktop), then items 2, 4, and 5 (hop feel and warp quality). Record the
results on https://github.com/sjyu0423/CHIBI/pull/1. Merge into `main` only after approval.
Music and audio work stays out of scope until then.
