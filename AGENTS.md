# CHIBI Agent Guide

## Structure

- `Sources/CHIBIApp/App`: application lifecycle only.
- `Sources/CHIBIApp/Overlay`: AppKit window, hit testing, and drag coordination.
- `Sources/CHIBIApp/Character`: manifests, asset loading, full-body/layered SpriteKit rendering,
  and animation presentation.
- `Sources/CHIBIApp/Resources`: bundled character manifests and licensed/generated PNG layers.
- `assets/source`: original character sheets; `assets/previews`: generated assembly reviews.
- `Sources/CHIBIApp/Behavior`: UI-independent character state machine.
- `Sources/CHIBIApp/Settings`: persisted preferences and size definitions.
- `Sources/CHIBIApp/MenuBar`: status-item commands and animation preview controls.
- `Tests/CHIBIAppTests`: state, manifest, resource, and persistence tests.
- `Support` and `scripts`: app bundle metadata and packaging.

## Commands

```sh
swift build
swift test
swift-format lint -r Sources Tests Package.swift
chmod +x scripts/build-app.sh && scripts/build-app.sh
open .build/CHIBI.app
```

Use Xcode/Command Line Tools whose compiler and SDK builds match. No third-party packages
are required.

## Architectural rules

- Keep lifecycle, AppKit overlay behavior, SpriteKit rendering, behavior state, persistence,
  and menu UI separate.
- Drive exclusive poses through `CharacterStateMachine`; do not start competing actions
  directly from window/menu code.
- Reset keyed animation actions and baseline transforms before presenting a new pose.
- Keep screen positions in AppKit points. Let `SKView` perform backing-scale conversion;
  do not manually multiply by Retina scale.
- Select full-body versus layered rendering through the manifest. Full-body artwork uses
  manifest-defined position, normalized anchor, and scale; layered PNGs additionally use
  manifest-defined pivots and draw order.
- Resolve character artwork through `CharacterAssetLoader`; a missing full-body image falls back
  to the layered/procedural path, and missing layers retain procedural counterparts.
- Treat generated character PNGs and their manifest as reproducible outputs of the matching
  script under `scripts`; do not hand-adjust generated layers without updating the script.
- Add protocols only at real substitution seams. `CharacterRendering` and
  `CharacterOverlayControlling` are the current seams.
- Preserve click-through behavior outside the character silhouette and never make the
  overlay key or main.
- Persist user choices through `AppSettings`, not scattered `UserDefaults` calls.

## Coding standards

- Swift 6, main-actor isolation for AppKit/SpriteKit objects, value types for pure state.
- Prefer small files and explicit names. Keep logic testable without launching AppKit.
- Add tests for every state transition, manifest rule, and persisted setting change.
- Use only original or properly licensed assets. Procedural character art is temporary.
- Update `docs/HANDOFF.md` after each work session. Do not commit or push unless asked.

## Milestone boundary

M1B integrates the Sleepy Coder artwork and metadata-driven registration. It does not include
music/audio capture, synchronization, costumes, networking, AI/LLM features, file access,
accessibility automation, or global keystroke monitoring. Consult `docs/MILESTONES.md` before
expanding scope.

## Continuing in Codex or Cursor

Start with `git status`, read this file and `docs/HANDOFF.md`, then run the verification
commands. Work on `milestone-1b-character-integration` for M1B. Preserve source artwork and
unrelated working-tree changes. Record files touched, exact commands/results, known issues,
and one concrete next step in the handoff. Do not commit or push without approval.
