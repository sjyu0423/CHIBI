# Milestones

## M0 — Native macOS foundation (accepted)

- Transparent, floating, non-activating character overlay
- Original procedural chibi placeholder
- Idle motion, blinking, click reaction, and dragging
- Idle/reacting/dragging/sleeping state machine
- Menu-bar visibility, size, position reset, and quit controls
- Local persistence, logic tests, packaging, and documentation

## M1A — Character system and animation foundation (complete)

- Shared-root layered character with separate hair, head, face, eyes, torso, arms, and legs
- Validated bundled character manifest and optional transparent PNG layer loading
- Procedural per-layer fallback when production artwork is absent
- Reusable idle, randomized blink, happy, sleep, walk-in-place, and dance animations
- Clean animation interruption/restoration through the state machine
- Menu-bar animation preview
- Hidden-state rendering and hit-test timer suspension
- Resource-aware application packaging and unit coverage

The procedural character remains the fallback implementation.

## M1B — Real character integration (renderer recovery implemented; animation GUI review pending)

- Sleepy Coder defaults to a faithful one-piece cutout of the approved master illustration.
- The manifest selects `fullBody` or the retained experimental `layered` renderer.
- Full-body animation uses whole-sprite bob, rotation, and squash-and-stretch only.
- Reproducible soft-matte extraction produces transparent head, hair, body, limb, eye, and mouth
  layers for the optional experimental renderer.
- Character manifests control layer registration, pivots, ordering, and scale.
- Closed-eye and mouth variants participate in the existing animation/state system.
- Generated true-alpha, solid-contrast, and animation-extreme previews support asset review.
- Resource registration, alpha, metadata, placement, and fallback behavior have unit coverage.

The neutral full-body overlay has been visually smoke-tested. Acceptance still requires the
menu-driven animation and input checklist at all three overlay sizes.

## M2A — Full-body animation foundation (implemented on `milestone-2a-animation`; GUI review pending)

Baseline: tag `v0.1-character-baseline` (`fde39ea`) on `main`.

- Pure, tested keyframe choreography (`FullBodyChoreography`) for idle breathing/sway, happy
  bounce, sleepy dozing, walk in place, gentle sway dance, energetic hop dance, and dragging.
- Feet-anchored body pivot, separate breathing pivot, and keyed per-channel actions that reset
  before every state.
- Experimental head tilt and hair secondary motion through a manifest-registered
  `SKWarpGeometryGrid` rig (accepted; toggleable from the Developer menu).
- Blink using the existing registered eye overlays was evaluated and rejected; it needs
  artist-made closed-eye art matching the approved sprite.
- Developer menu (slow motion, expressive-motion toggle) and an offscreen SpriteKit preview
  renderer that produces GIFs, filmstrips, and warp review sheets.

Acceptance requires the manual review checklist in `docs/HANDOFF.md`. M2A must not be merged
into `main` until approved.

## Later milestones (not started)

Music synchronization may be explored only after M2A is accepted and its privacy,
permission, and performance design is approved. Do not add audio capture as part of M1A.

Costumes, networking, AI/LLM features, file access, accessibility automation, global
keystroke monitoring, and production distribution signing/notarization remain outside the
current milestone.
