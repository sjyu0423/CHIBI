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
`CharacterStateMachine`, then asks `CharacterAnimator` to present the resulting
exclusive state. A new state first resets every animated container, so one-shot and
looping actions cannot compete.

## Layered character

`LayeredCharacterNode` provides a shared character root and distinct SpriteKit containers
for shadow, back hair, left/right legs, torso, left/right arms, head, face, left/right eyes,
mouth, and front hair. The built-in reference layout is 210 by 250 units. A dedicated
layout root scales those reference coordinates to the manifest render dimensions; AppKit
continues to store window sizes and positions in points.

Each visual container can hold either a transparent PNG sprite or its procedural fallback.
Small pose transforms are applied to the containers rather than rebuilding art. This
supports independent head/body motion, alternating limbs, hair follow-through, blinking,
and expression changes without continuous physics.

## Manifest and artwork loading

`temporary-character.json` is processed as a SwiftPM resource. `CharacterManifest`
defines:

- stable identifier and display name;
- render width and height;
- optional PNG reference for each layer;
- timing and amplitude values for idle, blink, happy, sleep, walk, and dance.

`CharacterAssetLoader` resolves resources only inside the module bundle. Validation
rejects absolute paths, parent-directory traversal, non-PNG image references, empty
identifiers, and non-positive dimensions. Missing or unreadable layer assets use the
procedural counterpart. If the manifest itself is unavailable or invalid, the scene uses
an in-code procedural fallback manifest.

The packaging script copies SwiftPM resource bundles to
`CHIBI.app/Contents/Resources`, matching the generated `Bundle.module` lookup.

## Animation and behavior rules

The state machine remains the sole owner of exclusive poses:

- idle and happy retain M0 click behavior;
- sleep, walking, and dancing are selectable preview states;
- a new preview interrupts the previous preview;
- dragging a looping state restores that state on release;
- dragging a happy reaction returns to idle;
- preview requests are ignored while actively dragging.

`CharacterAnimator` uses keyed SpriteKit actions with ease-in/ease-out timing. Resetting
a pose removes actions from all animated containers and restores their baseline
transforms. Blink delays vary naturally within the configured minimum and variation.
There is no physics simulation or polling of external services.

## Window, input, and performance

The borderless window is floating, joins all Spaces, and cannot become key or main. Its
frame is stored in AppKit screen points and clamped to a display's visible frame.
SpriteKit's `.aspectFit` mapping handles view scaling and Retina backing scale.

The approximate head/body silhouette controls mouse pass-through, preserving interaction
with applications under transparent pixels. No global event monitor is installed. The
SpriteKit view runs at 30 fps, culls non-visible nodes, and is paused while hidden. The
local hit-test timer is also suspended while hidden.

## Substitution seams

- `CharacterRendering` separates overlay input from the concrete SpriteKit scene.
- `CharacterOverlayControlling` separates menu commands from the AppKit window controller.
- `AppSettings` centralizes persisted user choices.

The manifest and layer containers are data/implementation types rather than protocols.
Additional protocols should be added only when a real alternate implementation exists.
