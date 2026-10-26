# Architecture

CHIBI is a dependency-free Swift Package executable packaged as a minimal agent-style
macOS application.

## Runtime flow

`CHIBIApplication` creates `AppSettings`, then the overlay and menu controllers.
`CharacterOverlayWindowController` owns a passive transparent `NSWindow` and a
`CharacterView`. The view presents `CharacterScene`, converts pointer coordinates
between screen, window, view, and scene spaces, and reports completed drags. The menu
mutates settings or requests a preview through the narrow overlay protocol.

`CharacterScene` owns behavior presentation only. It sends events to the pure-value
`CharacterStateMachine`, then asks the selected `CharacterAnimating` implementation to present
the resulting exclusive state. The manifest chooses the full-body renderer or experimental
layered renderer. A new state resets the selected character's transforms, so one-shot and
looping actions cannot compete.

## Full-body character (default)

`FullBodyCharacterNode` loads one complete transparent sprite and applies manifest-defined
position, normalized anchor, and scale. `FullBodyCharacterAnimator` keeps the approved image
intact and presents idle, happy, dragging, sleep, walk-in-place, and dance using only root-level
bobbing, small rotations, and squash-and-stretch. It does not claim independent limb, hair, eye,
or mouth animation. Missing full-body artwork selects the layered/procedural path instead.

## Layered character

`LayeredCharacterNode` provides a shared character root and distinct SpriteKit containers
for shadow, back hair, left/right legs, torso, left/right arms, head, face, left/right eyes,
mouth, and front hair. The built-in reference layout is 210 by 250 units. A dedicated
layout root scales those reference coordinates to the manifest render dimensions; AppKit
continues to store window sizes and positions in points.

Each visual container can hold either a transparent PNG sprite or its procedural fallback.
The manifest supplies each root's position and draw order plus the sprite's normalized pivot
and scale. Animation attachment anchors are applied as sprite pivots, so shoulders and hips can
rotate without character-specific coordinates in Swift. Small pose transforms are applied to
the containers rather than rebuilding art. This
supports independent head/body motion, alternating limbs, hair follow-through, blinking,
and expression changes without continuous physics.

## Manifest and artwork loading

`sleepy-coder.json` is the bundled default; `temporary-character.json` remains a backwards-
compatible procedural manifest. `CharacterManifest`
defines:

- stable identifier and display name;
- render width and height;
- an optional renderer mode (`layered` is the backward-compatible default);
- an optional complete PNG with position, normalized anchor, and scale;
- optional PNG references for each layer and eye/mouth expression variants;
- per-layer position, normalized anchor/pivot, draw order, scale, and optional animation anchor;
- timing and amplitude values for idle, blink, happy, sleep, walk, and dance.

`CharacterAssetLoader` resolves resources only inside the module bundle. Validation
rejects absolute paths, parent-directory traversal, non-PNG image references, empty
identifiers, non-positive dimensions, duplicate layers/orders, invalid anchors, and invalid
scales. Missing or unreadable layered assets use procedural counterparts. A missing full-body
image falls back to the layered node, whose absent pieces use those same procedural counterparts.
If the manifest itself is unavailable or invalid, the scene uses an in-code procedural fallback.

The `Characters` directory is copied rather than processed so namespaced asset paths survive
SwiftPM resource bundling. The packaging script copies SwiftPM resource bundles to
`CHIBI.app/Contents/Resources`, matching the generated `Bundle.module` lookup.

## Animation and behavior rules

The state machine remains the sole owner of exclusive poses:

- idle and happy retain M0 click behavior;
- sleep, walking, and dancing are selectable preview states;
- a new preview interrupts the previous preview;
- dragging a looping state restores that state on release;
- dragging a happy reaction returns to idle;
- preview requests are ignored while actively dragging.

Both animator implementations use keyed SpriteKit actions with ease-in/ease-out timing. Resetting
a pose removes actions from all animated containers and restores their baseline
transforms. Blink delays vary naturally within the configured minimum and variation.
There is no physics simulation or polling of external services.

The experimental layered mode supplies dedicated closed-eye and happy/sleep mouth assets. The
default full-body mode deliberately does not overlay them because their registration does not
match the approved master closely enough. Consequently the default sprite currently has no blink
or expression swap; reactions are communicated through whole-character motion.

## Artwork generation

`scripts/generate-sleepy-coder-full-sprite.py` cleans `base_character_transparent.png`, a
single-figure RGBA export. It keeps only the largest connected silhouette (clearing residue below
the shoes and along the canvas edge), remaps alpha so the faint outer halo becomes transparent
and the nearly opaque interior becomes fully opaque, and recolors only partially transparent
contour pixels from adjacent opaque ink. Fully opaque pixels stay byte-identical to the source.
It emits the runtime `full-body.png`, true-alpha and dark-background previews, and a
source/cleaned comparison without reconstructing or reshaping the character.

The retained experimental `scripts/generate-sleepy-coder-assets.py` extracts the flattened
`parts.jpeg` board using a
soft color-distance matte against a robust polynomial model of the sheet background. Explicit
geometry excludes the printed leg shadows, and a flood-selected mask removes the front-hair
face guide. Antialiased masks isolate the torso core and shoes, while small disconnected matte
specks are removed without recoloring the art. The script emits transparent PNGs, the manifest,
true-alpha and solid-contrast assembly previews, and a static animation-extremes review sheet.
It requires Pillow and NumPy only for development; generated resources have no runtime cost.

## Window, input, and performance

The borderless window is floating, joins all Spaces, and cannot become key or main. Its
frame is stored in AppKit screen points and clamped to a display's visible frame.
SpriteKit's `.aspectFit` mapping handles view scaling and Retina backing scale. Because
`SKView` paints letterbox bars opaque black even with transparency enabled, `CharacterScene`
expands the manifest render area to the view's exact aspect ratio
(`RenderDimensions.sceneSize(fitting:)`) on presentation and whenever `CharacterView` resizes.
Character coordinates and on-screen scale are unchanged; only transparent margin is added.

The approximate head/body silhouette controls mouse pass-through, preserving interaction
with applications under transparent pixels. No global event monitor is installed. The
SpriteKit view runs at 30 fps, culls non-visible nodes, and is paused while hidden. The
local hit-test timer is also suspended while hidden.

## Substitution seams

- `CharacterRendering` separates overlay input from the concrete SpriteKit scene.
- `CharacterAnimating` separates state presentation from full-body versus layered motion.
- `CharacterOverlayControlling` separates menu commands from the AppKit window controller.
- `AppSettings` centralizes persisted user choices.

The manifest and layer containers are data/implementation types rather than protocols.
Additional protocols should be added only when a real alternate implementation exists.
