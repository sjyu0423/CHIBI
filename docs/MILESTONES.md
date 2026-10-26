# Milestones

## M0 — Native macOS foundation (accepted)

- Transparent, floating, non-activating character overlay
- Original procedural chibi placeholder
- Idle motion, blinking, click reaction, and dragging
- Idle/reacting/dragging/sleeping state machine
- Menu-bar visibility, size, position reset, and quit controls
- Local persistence, logic tests, packaging, and documentation

## M1A — Character system and animation foundation (implemented; manual review pending)

- Shared-root layered character with separate hair, head, face, eyes, torso, arms, and legs
- Validated bundled character manifest and optional transparent PNG layer loading
- Procedural per-layer fallback when production artwork is absent
- Reusable idle, randomized blink, happy, sleep, walk-in-place, and dance animations
- Clean animation interruption/restoration through the state machine
- Menu-bar animation preview
- Hidden-state rendering and hit-test timer suspension
- Resource-aware application packaging and unit coverage

M1A intentionally contains temporary procedural visuals. Completion acceptance requires the
manual GUI checklist in `README.md` and review of replacement artwork when it becomes
available.

## M1B and later (not started)

M1B may explore music synchronization only after M1A is accepted and its privacy,
permission, and performance design is approved. Do not add audio capture as part of M1A.

Costumes, networking, AI/LLM features, file access, accessibility automation, global
keystroke monitoring, and production distribution signing/notarization remain outside the
current milestone.
