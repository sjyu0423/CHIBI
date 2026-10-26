# Handoff

## Status

- Current milestone: M1A — Character System and Animation Foundation
- Branch: `milestone-1a-character-system`
- Repository: unborn (no commits exist); the complete M0 plus M1A working tree is untracked
- Commits/pushes: none
- Implementation status: code/build/tests/package checks complete; manual GUI review pending

The requested branch was created without discarding or stashing the untracked M0 files. Because
there is no M0 commit, Git cannot represent a historical M0 branch point; the previous unborn
branch name has no durable ref, and the current working tree is the only copy of the implementation.

## Completed

- Replaced the monolithic placeholder scene with a shared-root layered character:
  shadow, back/front hair, left/right legs, torso, left/right arms, head, face, left/right
  eyes, and mouth.
- Added a 210x250 normalized reference layout that scales to manifest render dimensions.
- Added a Codable/validated character manifest with identifier, display name, dimensions,
  optional PNG references, and animation configuration.
- Added module-bundle PNG texture loading with per-layer procedural fallback and a complete
  fallback manifest when the bundled manifest cannot be loaded.
- Added reusable, interruptible SpriteKit presentations for idle breathing/bobbing,
  randomized blinking, happy reaction, sleep, walk in place, and dance.
- Extended the pure state machine for walking/dancing preview states and deterministic drag
  interruption/restoration.
- Added an Animation Preview submenu to the existing flower menu.
- Preserved overlay scaling, positioning, approximate silhouette hit testing, direct dragging,
  settings persistence, and non-key/non-main behavior.
- Reduced continuous work to 30 fps, enabled non-visible-node culling, and paused both
  SpriteKit and the local hit-test timer while hidden.
- Added SwiftPM resources and fixed app packaging so the resource bundle is placed at
  `Contents/Resources`.
- Increased unit coverage from 7 to 14 tests.

## Decisions

- Behavior state remains independent of SpriteKit. The state machine chooses the exclusive pose;
  `CharacterAnimator` only presents it.
- A pose reset removes actions and restores baseline transforms before every transition.
- Each PNG is optional. Missing/unreadable files fall back only that layer, enabling incremental
  art integration.
- Resource paths are constrained to relative PNG paths inside `Bundle.module`; absolute paths,
  parent traversal, and other formats are rejected.
- The temporary character remains procedural and original. No external or copyrighted art was
  introduced.
- Walk and dance are preview-only M1A states. No music/audio capture or synchronization was added.

## Files modified

Existing files changed:

- `Package.swift`
- `README.md`
- `AGENTS.md`
- `Sources/CHIBIApp/Behavior/CharacterStateMachine.swift`
- `Sources/CHIBIApp/Character/CharacterRendering.swift`
- `Sources/CHIBIApp/Character/CharacterScene.swift`
- `Sources/CHIBIApp/MenuBar/MenuBarController.swift`
- `Sources/CHIBIApp/Overlay/CharacterOverlayWindowController.swift`
- `Tests/CHIBIAppTests/CharacterStateMachineTests.swift`
- `scripts/build-app.sh`
- `docs/ARCHITECTURE.md`
- `docs/MILESTONES.md`
- `docs/HANDOFF.md`

New files:

- `Sources/CHIBIApp/Character/CharacterAnimator.swift`
- `Sources/CHIBIApp/Character/CharacterAssetLoader.swift`
- `Sources/CHIBIApp/Character/CharacterManifest.swift`
- `Sources/CHIBIApp/Character/LayeredCharacterNode.swift`
- `Sources/CHIBIApp/Resources/temporary-character.json`
- `Tests/CHIBIAppTests/CharacterManifestTests.swift`

## Verification

Host on 2026-10-25:

- macOS 27.0.1 (build 26A434)
- Xcode 27.1 (build 27A9275)
- Swift 6.4 (`swiftlang-6.4.0.34.1`)

Exact results:

- `xcrun swift-format lint -r Sources Tests Package.swift`: passed with no findings.
- `swift build` in the managed execution sandbox: blocked before source compilation because the
  sandbox cannot write the default Clang cache and cannot create SwiftPM's nested sandbox.
- `env CLANG_MODULE_CACHE_PATH=/tmp/chibi-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/chibi-swiftpm-cache swift build --disable-sandbox`:
  passed.
- The same environment plus `swift test --disable-sandbox`: 14/14 tests passed in 3 suites.
- `env CHIBI_DISABLE_SWIFTPM_SANDBOX=1 CLANG_MODULE_CACHE_PATH=/tmp/chibi-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/chibi-swiftpm-cache scripts/build-app.sh`:
  release app build passed.
- `plutil -lint Support/Info.plist .build/CHIBI.app/Contents/Info.plist`: passed.
- `codesign --verify --deep --strict --verbose=2 .build/CHIBI.app`: passed.
- Mach-O inspection: arm64 executable.
- Resource check: bundled `temporary-character.json` exists under the packaged
  `CHIBI_CHIBIApp.bundle`.
- Launch smoke: `open .build/CHIBI.app` succeeded, the packaged CHIBI process remained running,
  and it was stopped after the check.
- Manual visual/menu/input behavior: not performed. The launch check confirms process viability,
  not rendering quality or interaction correctness.

## Manual GUI checklist

1. Launch the packaged app and confirm the layered chibi and flower menu item appear without
   making the overlay key or main.
2. Confirm Idle is subtle: smooth bob/breath, independent head/hair movement, and varied but
   synchronized blinking.
3. Preview Happy, Sleep, Walk in Place, and Dance; switch rapidly between them and confirm no
   transforms/actions leak between poses.
4. Confirm Happy completes back to Idle.
5. Drag during Sleep, Walk, and Dance and confirm the prior looping pose resumes; drag during
   Happy and confirm release returns to Idle.
6. Confirm transparent corners click through while the approximate character silhouette remains
   draggable/clickable.
7. Test Show/Hide and confirm the character resumes cleanly after being paused.
8. Test all sizes, Reset Position, saved position/visibility/size after relaunch, and multi-display
   clamping if multiple displays are available.
9. Confirm Quit CHIBI exits normally.

## Production artwork requirements

No production artwork is present. Supply original or properly licensed transparent PNG layers for
the manifest fields below:

- `hairBack`
- `leftLeg`, `rightLeg`
- `torso`
- `leftArm`, `rightArm`
- `head`
- optional non-eye facial detail layer `face`
- `leftEye`, `rightEye`
- `mouth`
- `hairFront`

Artwork contract:

- Design against the manifest's render dimensions (the temporary manifest is 210x250).
- Use transparent backgrounds and tightly cropped layer images.
- Center each cropped image on its layer registration point in the reference coordinate space:
  hair back (0,35), legs (-22,-88)/(22,-88), torso (0,-55), arms (-46,-55)/(46,-55),
  head (0,34), face (0,0), eyes (-31,31)/(31,31), mouth (0,7), front hair (0,74).
- Keep neutral-pose limb/head art compatible with small translations/scales; current animation
  does not require sprite sheets.
- Add each PNG to `Sources/CHIBIApp/Resources`, set its relative path in the manifest, and run
  the package/resource/GUI checks above.
- Provide visual design review for silhouette, pivots, cropping, expression alignment, and all
  three overlay sizes.

## Known limitations

- The procedural layers are intentionally temporary and are not production-quality anime art.
- No actual PNG character set was available, so PNG decoding/registration still needs an
  end-to-end visual check when real art is added.
- Layer registration points are currently code-defined; the manifest controls references,
  dimensions, and animation timing but not per-layer offsets/pivots.
- Mouse hit testing remains an approximate head/body silhouette rather than per-pixel alpha.
- Preview selection is a development control and is not persisted.
- GUI appearance, menu interaction, click-through, dragging, multi-display behavior, and visual
  animation quality require the manual checklist.
- The app is ad-hoc signed for local development only; distribution signing/notarization is out
  of scope.

## Exact next step

Perform the manual GUI checklist on the packaged app. If it passes, source or create the licensed
PNG layer set above and validate it through the manifest pipeline before accepting M1A. Do not
begin M1B music synchronization.
