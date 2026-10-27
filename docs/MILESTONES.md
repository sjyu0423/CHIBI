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

## M2B — Music-reactive dancing (implemented on `milestone-2b-music-reactive-dancing`; live review pending)

Branched from M2A (`be4716c`); M2A's pull request remains open and unmerged.

- Explicit, user-started system-audio capture through ScreenCaptureKit (audio only; a 2×2,
  1 fps video stream is required by the API and discarded). Never starts at launch, never uses
  the microphone, and never stores or uploads audio.
- Permission denial, unavailable streams, and interruptions are reported in the menu and in an
  alert with a link to Privacy & Security.
- Local Accelerate analysis: RMS level and envelope, activity with hysteresis, spectral-flux
  onsets with an adaptive median threshold, autocorrelation tempo reported only when stable,
  beats accepted only on the tempo grid, and a smoothed intensity.
- A pure `MusicDanceController` maps the analysis to gentle sway, rhythmic sway with beat
  accents, or a beat-aligned hop dance. It applies start delay, silence hold, hysteresis,
  minimum dwell, and beat-quantized level changes.
- Music is the lowest-priority input to `CharacterStateMachine`; dragging, clicks, sleep, and
  manual previews override it, and it resumes afterwards.
- Menu: Music Reactive › Start/Stop Listening, status line, Sensitivity (Low/Normal/High), and
  Auto Dance. Sensitivity and Auto Dance persist; listening does not.
- Synthetic-audio tests and a deterministic music-reactive preview clip.

Acceptance requires the manual music checklist in `docs/HANDOFF.md` with real playback.

## Later milestones (not started)

AI/LLM features, conversations, personality modes, costumes, networking, file access,
accessibility automation, global keystroke monitoring, and production distribution
signing/notarization remain outside the current milestone.
