import Foundation

/// Whole-sprite pose. Offsets are scene units applied to the character root. Rotation and scale
/// pivot at the character's feet so they stay planted.
struct FullBodyPose: Equatable, Sendable {
  var offsetX: Double = 0
  var offsetY: Double = 0
  var rotation: Double = 0
  var scaleX: Double = 1
  var scaleY: Double = 1

  static let rest = FullBodyPose()
}

/// Seamless warp of the single sprite, as fractions of the manifest rig's limits.
/// `headTilt` is positive counter-clockwise; `hairSway` is positive to the right.
struct FullBodyExpression: Equatable, Sendable {
  var headTilt: Double = 0
  var hairSway: Double = 0

  static let rest = FullBodyExpression()
}

enum MotionTiming: Equatable, Sendable {
  case linear
  case easeIn
  case easeOut
  case easeInEaseOut
}

struct MotionKeyframe<Pose: Equatable & Sendable>: Equatable, Sendable {
  var pose: Pose
  var duration: TimeInterval
  var timing: MotionTiming = .easeInEaseOut
}

/// Absolute keyframes: an optional one-shot intro followed by an optional repeating loop.
/// Absolute targets make interruption and repetition free of cumulative drift.
struct MotionTrack<Pose: Equatable & Sendable>: Equatable, Sendable {
  var intro: [MotionKeyframe<Pose>] = []
  var loop: [MotionKeyframe<Pose>] = []

  var isFinite: Bool { loop.isEmpty }
  var introDuration: TimeInterval { intro.reduce(0) { $0 + $1.duration } }
  var loopDuration: TimeInterval { loop.reduce(0) { $0 + $1.duration } }
  var allKeyframes: [MotionKeyframe<Pose>] { intro + loop }

  /// Eases from whatever pose is current into the first keyframe over at least `duration`.
  /// A loop without an intro is rotated so its first keyframe becomes the intro and the loop
  /// continues seamlessly from there.
  func blended(over duration: TimeInterval) -> MotionTrack {
    var track = self
    if let first = intro.first {
      track.intro[0].duration = max(first.duration, duration)
    } else if let first = loop.first {
      track.intro = [MotionKeyframe(pose: first.pose, duration: duration, timing: .easeInEaseOut)]
      track.loop = Array(loop.dropFirst()) + [first]
    }
    return track
  }
}

struct FullBodyMotion: Equatable, Sendable {
  var body: MotionTrack<FullBodyPose>
  var breath: MotionTrack<FullBodyPose>?
  var expression: MotionTrack<FullBodyExpression>?
  var emitsSleepBubbles = false

  /// One-shot motions report completion so the state machine can return to idle.
  var finishes: Bool { body.isFinite }

  func blended(over duration: TimeInterval) -> FullBodyMotion {
    var motion = self
    motion.body = body.blended(over: duration)
    motion.breath = breath?.blended(over: duration)
    motion.expression = expression?.blended(over: duration)
    return motion
  }
}

/// Character-independent choreography for the full-body renderer.
enum FullBodyChoreography {
  typealias Pose = FullBodyPose
  typealias Frame = MotionKeyframe<FullBodyPose>
  typealias ExpressionFrame = MotionKeyframe<FullBodyExpression>

  /// Music styles change only the two dance states: gentle is a slower, smaller sway, rhythmic
  /// is the standard sway, and energetic is a hop dance whose loop spans whole beats.
  static func motion(
    for state: CharacterState, style: MotionStyle,
    configuration: CharacterManifest.AnimationConfiguration
  ) -> FullBodyMotion {
    switch (state, style) {
    case (.dancing, .music(.gentle)):
      sway(beat: configuration.danceBeatDuration * 2, amplitude: 0.55, breathing: true)
    case (.hopDancing, .music):
      musicHopDance(configuration)
    default:
      motion(for: state, configuration: configuration)
    }
  }

  /// Playback rate that puts the dance's beat on the music's beat, folded by octaves into a
  /// comfortable 0.7–1.4× range so very slow or fast songs still look natural.
  static func tempoScale(
    forBeatDuration beatDuration: TimeInterval,
    configuration: CharacterManifest.AnimationConfiguration
  ) -> Double {
    guard beatDuration.isFinite, beatDuration > 0 else { return 1 }
    var scale = configuration.danceBeatDuration / beatDuration
    while scale < 0.7 { scale *= 2 }
    while scale > 1.4 { scale /= 2 }
    return scale
  }

  static func motion(
    for state: CharacterState, configuration: CharacterManifest.AnimationConfiguration
  ) -> FullBodyMotion {
    switch state {
    case .idle: idle(configuration)
    case .reacting: happy(configuration)
    case .dragging: dragging()
    case .sleeping: sleeping(configuration)
    case .walking: walking(configuration)
    case .dancing: swayDance(configuration)
    case .hopDancing: hopDance(configuration)
    }
  }

  private static func idle(_ configuration: CharacterManifest.AnimationConfiguration)
    -> FullBodyMotion
  {
    let breath = configuration.idleCycleDuration
    let sway = breath * 2
    return FullBodyMotion(
      body: MotionTrack(loop: [
        Frame(pose: Pose(rotation: 0.011), duration: sway / 2),
        Frame(pose: Pose(rotation: -0.011), duration: sway / 2),
      ]),
      breath: MotionTrack(loop: [
        Frame(pose: Pose(scaleX: 0.997, scaleY: 1.011), duration: breath * 0.45),
        Frame(pose: .rest, duration: breath * 0.55),
      ]),
      expression: MotionTrack(
        intro: [ExpressionFrame(pose: .rest, duration: sway * 0.12)],
        loop: [
          ExpressionFrame(
            pose: FullBodyExpression(headTilt: -0.25, hairSway: -0.6), duration: sway / 2),
          ExpressionFrame(
            pose: FullBodyExpression(headTilt: 0.25, hairSway: 0.6), duration: sway / 2),
          ExpressionFrame(
            pose: FullBodyExpression(headTilt: -0.25, hairSway: -0.6), duration: sway / 2),
          ExpressionFrame(
            pose: FullBodyExpression(headTilt: 0.9, hairSway: 0.5), duration: sway / 2),
          ExpressionFrame(
            pose: FullBodyExpression(headTilt: 0.9, hairSway: -0.2), duration: sway / 2),
          ExpressionFrame(
            pose: FullBodyExpression(headTilt: 0.25, hairSway: 0.6), duration: sway / 2),
        ]))
  }

  private static func happy(_ configuration: CharacterManifest.AnimationConfiguration)
    -> FullBodyMotion
  {
    let hop = configuration.happyHopHeight
    return FullBodyMotion(
      body: MotionTrack(intro: [
        Frame(pose: Pose(scaleX: 1.04, scaleY: 0.945), duration: 0.1, timing: .easeOut),
        Frame(
          pose: Pose(offsetY: hop, rotation: -0.02, scaleX: 0.975, scaleY: 1.035), duration: 0.17,
          timing: .easeOut),
        Frame(
          pose: Pose(rotation: 0.012, scaleX: 0.985, scaleY: 1.02), duration: 0.15, timing: .easeIn),
        Frame(pose: Pose(scaleX: 1.05, scaleY: 0.94), duration: 0.07, timing: .easeOut),
        Frame(
          pose: Pose(offsetY: hop * 0.35, scaleX: 0.985, scaleY: 1.025), duration: 0.13,
          timing: .easeOut),
        Frame(pose: .rest, duration: 0.12, timing: .easeIn),
        Frame(pose: Pose(scaleX: 1.03, scaleY: 0.97), duration: 0.06, timing: .easeOut),
        Frame(pose: .rest, duration: 0.16),
      ]),
      expression: MotionTrack(intro: [
        ExpressionFrame(pose: .rest, duration: 0.1),
        ExpressionFrame(pose: FullBodyExpression(headTilt: 0.7, hairSway: -0.4), duration: 0.17),
        ExpressionFrame(pose: FullBodyExpression(headTilt: 0.5, hairSway: 0.8), duration: 0.22),
        ExpressionFrame(pose: FullBodyExpression(headTilt: 0.3, hairSway: -0.3), duration: 0.25),
        ExpressionFrame(pose: .rest, duration: 0.22),
      ]))
  }

  private static func dragging() -> FullBodyMotion {
    FullBodyMotion(
      body: MotionTrack(
        intro: [
          Frame(
            pose: Pose(offsetY: 4, rotation: 0.02, scaleX: 0.985, scaleY: 1.035), duration: 0.16,
            timing: .easeOut)
        ],
        loop: [
          Frame(
            pose: Pose(offsetY: 4, rotation: -0.025, scaleX: 0.985, scaleY: 1.035), duration: 0.55),
          Frame(
            pose: Pose(offsetY: 4, rotation: 0.025, scaleX: 0.985, scaleY: 1.035), duration: 0.55),
        ]),
      expression: MotionTrack(loop: [
        ExpressionFrame(pose: FullBodyExpression(headTilt: 0.3, hairSway: 0.9), duration: 0.55),
        ExpressionFrame(pose: FullBodyExpression(headTilt: -0.3, hairSway: -0.9), duration: 0.55),
      ]))
  }

  private static func sleeping(_ configuration: CharacterManifest.AnimationConfiguration)
    -> FullBodyMotion
  {
    let breath = configuration.sleepSwayDuration
    return FullBodyMotion(
      body: MotionTrack(
        intro: [Frame(pose: Pose(rotation: -0.01), duration: 0.8)],
        loop: [
          Frame(pose: Pose(offsetY: -2, rotation: -0.02), duration: breath * 0.9),
          Frame(
            pose: Pose(offsetY: -3, rotation: -0.034, scaleY: 0.99), duration: breath * 0.6,
            timing: .easeIn),
          Frame(
            pose: Pose(offsetY: 1, rotation: -0.006, scaleX: 0.995, scaleY: 1.006), duration: 0.22,
            timing: .easeOut),
          Frame(pose: Pose(rotation: -0.01), duration: 0.5),
          Frame(pose: Pose(rotation: -0.01), duration: breath * 0.5),
        ]),
      breath: MotionTrack(loop: [
        Frame(pose: Pose(scaleX: 1.004, scaleY: 1.016), duration: breath * 0.45),
        Frame(pose: .rest, duration: breath * 0.55),
      ]),
      expression: MotionTrack(
        intro: [ExpressionFrame(pose: FullBodyExpression(headTilt: -0.3), duration: 0.8)],
        loop: [
          ExpressionFrame(
            pose: FullBodyExpression(headTilt: -0.5, hairSway: -0.2), duration: breath * 0.9),
          ExpressionFrame(
            pose: FullBodyExpression(headTilt: -1, hairSway: -0.4), duration: breath * 0.6,
            timing: .easeIn),
          ExpressionFrame(
            pose: FullBodyExpression(headTilt: -0.2, hairSway: 0.5), duration: 0.22,
            timing: .easeOut),
          ExpressionFrame(pose: FullBodyExpression(headTilt: -0.3), duration: 0.5),
          ExpressionFrame(pose: FullBodyExpression(headTilt: -0.3), duration: breath * 0.5),
        ]),
      emitsSleepBubbles: true)
  }

  private static func walking(_ configuration: CharacterManifest.AnimationConfiguration)
    -> FullBodyMotion
  {
    let half = configuration.walkStepDuration / 2
    return FullBodyMotion(
      body: MotionTrack(loop: [
        Frame(
          pose: Pose(offsetX: -2, offsetY: 5, rotation: 0.022, scaleX: 0.985, scaleY: 1.02),
          duration: half, timing: .easeOut),
        Frame(
          pose: Pose(offsetX: -1, rotation: 0.012, scaleX: 1.02, scaleY: 0.975), duration: half,
          timing: .easeIn),
        Frame(
          pose: Pose(offsetX: 2, offsetY: 5, rotation: -0.022, scaleX: 0.985, scaleY: 1.02),
          duration: half, timing: .easeOut),
        Frame(
          pose: Pose(offsetX: 1, rotation: -0.012, scaleX: 1.02, scaleY: 0.975), duration: half,
          timing: .easeIn),
      ]),
      expression: MotionTrack(loop: [
        ExpressionFrame(
          pose: FullBodyExpression(headTilt: -0.2, hairSway: 0.5), duration: half * 2),
        ExpressionFrame(
          pose: FullBodyExpression(headTilt: 0.2, hairSway: -0.5), duration: half * 2),
      ]))
  }

  private static func swayDance(_ configuration: CharacterManifest.AnimationConfiguration)
    -> FullBodyMotion
  {
    sway(beat: configuration.danceBeatDuration, amplitude: 1, breathing: false)
  }

  /// One side per beat, landing with a small dip. `amplitude` 1 is the standard sway dance.
  private static func sway(beat: TimeInterval, amplitude a: Double, breathing: Bool)
    -> FullBodyMotion
  {
    func reach(_ side: Double) -> Pose {
      Pose(
        offsetX: 7 * a * side, offsetY: 3 * a, rotation: -0.05 * a * side, scaleX: 1 - 0.01 * a,
        scaleY: 1 + 0.015 * a)
    }
    func dip(_ side: Double) -> Pose {
      Pose(
        offsetX: 7 * a * side, rotation: -0.045 * a * side, scaleX: 1 + 0.02 * a,
        scaleY: 1 - 0.025 * a)
    }
    func lean(_ side: Double, tilt: Double, hair: Double) -> FullBodyExpression {
      FullBodyExpression(headTilt: tilt * a * side, hairSway: hair * a * -side)
    }
    return FullBodyMotion(
      body: MotionTrack(loop: [
        Frame(pose: reach(-1), duration: beat * 0.7),
        Frame(pose: dip(-1), duration: beat * 0.3, timing: .easeIn),
        Frame(pose: reach(1), duration: beat * 0.7),
        Frame(pose: dip(1), duration: beat * 0.3, timing: .easeIn),
      ]),
      breath: breathing
        ? MotionTrack(loop: [
          Frame(pose: Pose(scaleX: 0.997, scaleY: 1.01), duration: beat),
          Frame(pose: .rest, duration: beat),
        ]) : nil,
      expression: MotionTrack(loop: [
        ExpressionFrame(pose: lean(-1, tilt: 0.7, hair: 0.4), duration: beat * 0.7),
        ExpressionFrame(pose: lean(-1, tilt: 0.6, hair: 0.9), duration: beat * 0.3),
        ExpressionFrame(pose: lean(1, tilt: 0.7, hair: 0.4), duration: beat * 0.7),
        ExpressionFrame(pose: lean(1, tilt: 0.6, hair: 0.9), duration: beat * 0.3),
      ]))
  }

  /// Three side hops and a centered jump, one beat each, so the four-beat loop stays on the beat
  /// when its playback rate follows the music.
  private static func musicHopDance(_ configuration: CharacterManifest.AnimationConfiguration)
    -> FullBodyMotion
  {
    let beat = configuration.danceBeatDuration
    let hop = configuration.happyHopHeight * 0.6
    let crouch = Pose(scaleX: 1.04, scaleY: 0.955)
    func sideHop(_ side: Double) -> [Frame] {
      [
        Frame(
          pose: Pose(offsetY: hop, rotation: -0.045 * side, scaleX: 0.98, scaleY: 1.03),
          duration: beat * 0.4, timing: .easeOut),
        Frame(
          pose: Pose(offsetX: 10 * side, rotation: -0.02 * side, scaleX: 1.04, scaleY: 0.955),
          duration: beat * 0.35, timing: .easeIn),
        Frame(pose: Pose(offsetX: 10 * side, scaleX: 1.02, scaleY: 0.98), duration: beat * 0.25),
      ]
    }
    let jump = [
      Frame(
        pose: Pose(offsetY: hop * 1.25, scaleX: 0.96, scaleY: 1.05), duration: beat * 0.45,
        timing: .easeOut),
      Frame(pose: crouch, duration: beat * 0.35, timing: .easeIn),
      Frame(pose: Pose(scaleX: 1.02, scaleY: 0.98), duration: beat * 0.2),
    ]
    return FullBodyMotion(
      body: MotionTrack(
        intro: [Frame(pose: crouch, duration: beat * 0.3, timing: .easeOut)],
        loop: sideHop(1) + sideHop(-1) + sideHop(1) + jump),
      expression: MotionTrack(
        intro: [ExpressionFrame(pose: .rest, duration: beat * 0.3)],
        loop: hopExpression(beat: beat) + [
          ExpressionFrame(
            pose: FullBodyExpression(headTilt: 0.6, hairSway: -0.8), duration: beat * 0.4),
          ExpressionFrame(
            pose: FullBodyExpression(headTilt: 0.2, hairSway: 1), duration: beat * 0.6),
          ExpressionFrame(pose: FullBodyExpression(hairSway: -0.6), duration: beat * 0.45),
          ExpressionFrame(pose: FullBodyExpression(hairSway: 0.4), duration: beat * 0.35),
          ExpressionFrame(pose: .rest, duration: beat * 0.2),
        ]))
  }

  private static func hopDance(_ configuration: CharacterManifest.AnimationConfiguration)
    -> FullBodyMotion
  {
    let beat = configuration.danceBeatDuration * 0.8
    let hop = configuration.happyHopHeight * 0.6
    let crouch = Pose(scaleX: 1.04, scaleY: 0.955)
    func landing(_ side: Double) -> Pose {
      Pose(offsetX: 10 * side, rotation: -0.02 * side, scaleX: 1.04, scaleY: 0.955)
    }
    func apex(toward side: Double, height: Double) -> Pose {
      Pose(offsetY: height, rotation: -0.045 * side, scaleX: 0.98, scaleY: 1.03)
    }
    return FullBodyMotion(
      body: MotionTrack(
        intro: [Frame(pose: crouch, duration: beat * 0.3, timing: .easeOut)],
        loop: [
          Frame(pose: apex(toward: 1, height: hop), duration: beat * 0.4, timing: .easeOut),
          Frame(pose: landing(1), duration: beat * 0.35, timing: .easeIn),
          Frame(pose: Pose(offsetX: 10, scaleX: 1.02, scaleY: 0.98), duration: beat * 0.25),
          Frame(pose: apex(toward: -1, height: hop), duration: beat * 0.4, timing: .easeOut),
          Frame(pose: landing(-1), duration: beat * 0.35, timing: .easeIn),
          Frame(pose: Pose(offsetX: -10, scaleX: 1.02, scaleY: 0.98), duration: beat * 0.25),
          Frame(pose: apex(toward: 1, height: hop), duration: beat * 0.4, timing: .easeOut),
          Frame(pose: landing(1), duration: beat * 0.35, timing: .easeIn),
          Frame(pose: Pose(offsetX: 10, scaleX: 1.02, scaleY: 0.98), duration: beat * 0.25),
          Frame(pose: apex(toward: -1, height: hop), duration: beat * 0.4, timing: .easeOut),
          Frame(pose: landing(-1), duration: beat * 0.35, timing: .easeIn),
          Frame(pose: Pose(offsetX: -10, scaleX: 1.06, scaleY: 0.92), duration: beat * 0.25),
          Frame(
            pose: Pose(offsetY: hop * 1.35, scaleX: 0.96, scaleY: 1.05), duration: beat * 0.5,
            timing: .easeOut),
          Frame(pose: crouch, duration: beat * 0.45, timing: .easeIn),
          Frame(pose: Pose(scaleX: 1.02, scaleY: 0.98), duration: beat * 0.3),
        ]),
      expression: MotionTrack(
        intro: [ExpressionFrame(pose: .rest, duration: beat * 0.3)],
        loop: Array(repeating: hopExpression(beat: beat), count: 2).flatMap { $0 } + [
          ExpressionFrame(pose: FullBodyExpression(hairSway: -0.6), duration: beat * 0.5),
          ExpressionFrame(pose: FullBodyExpression(hairSway: 0.4), duration: beat * 0.45),
          ExpressionFrame(pose: .rest, duration: beat * 0.3),
        ]))
  }

  private static func hopExpression(beat: TimeInterval) -> [ExpressionFrame] {
    [
      ExpressionFrame(
        pose: FullBodyExpression(headTilt: 0.6, hairSway: -0.8), duration: beat * 0.4),
      ExpressionFrame(pose: FullBodyExpression(headTilt: 0.2, hairSway: 1), duration: beat * 0.6),
      ExpressionFrame(
        pose: FullBodyExpression(headTilt: -0.6, hairSway: 0.8), duration: beat * 0.4),
      ExpressionFrame(pose: FullBodyExpression(headTilt: -0.2, hairSway: -1), duration: beat * 0.6),
    ]
  }
}
