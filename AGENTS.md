# CHIBI Agent Guide

## Structure

- `Sources/CHIBIApp/App`: application lifecycle only.
- `Sources/CHIBIApp/Overlay`: AppKit window, hit testing, and drag coordination.
- `Sources/CHIBIApp/Character`: manifests, asset loading, layered SpriteKit rendering,
  and animation presentation.
- `Sources/CHIBIApp/Resources`: bundled character manifests and licensed PNG layers.
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
- Keep character parts under the shared normalized layout root. PNG layer artwork must use
  the documented layer registration points and transparent backgrounds.
- Resolve character artwork through `CharacterAssetLoader`; missing layers must retain a
  procedural fallback.
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

M1A includes the replaceable layered renderer, PNG/manifest pipeline, idle/blink/happy/
sleep/walk/dance presentation, preview controls, tests, and documentation. It does not
include music/audio capture, synchronization, costumes, networking, AI/LLM features, file
access, accessibility automation, or global keystroke monitoring. Consult
`docs/MILESTONES.md` before expanding scope.

## Continuing in Codex or Cursor

Start with `git status`, read this file and `docs/HANDOFF.md`, then run the verification
commands. Work on `milestone-1a-character-system` until M1A is accepted. The repository
currently has no commits, so preserve the untracked M0/M1A working tree. Record files
touched, exact commands/results, known issues, and one concrete next step in the handoff.
Do not commit or push without approval.
