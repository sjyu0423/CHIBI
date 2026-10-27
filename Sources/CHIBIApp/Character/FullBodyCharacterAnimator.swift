import AppKit
import SpriteKit

/// Presents `FullBodyChoreography` by transforming the approved complete sprite: rigid pose and
/// breathing always, plus an optional seamless warp (head tilt, hair sway) when the manifest
/// registers a rig. It never splits the artwork into separately moving parts.
@MainActor
final class FullBodyCharacterAnimator: CharacterAnimating {
  private enum ActionKey {
    static let translation = "character.full-body.translation"
    static let body = "character.full-body.body"
    static let breath = "character.full-body.breath"
    static let expression = "character.full-body.expression"
    static let completion = "character.full-body.completion"
    static let effects = "character.full-body.effects"
    static let accent = "character.full-body.accent"
  }

  private let character: FullBodyCharacterNode
  private let configuration: CharacterManifest.AnimationConfiguration
  private var currentState: CharacterState?
  private(set) var currentStyle: MotionStyle = .standard
  private var musicBeatDuration: TimeInterval?
  private var bubbleCount = 0
  var reactionDidFinish: (() -> Void)?

  var supportsExpressiveMotion: Bool { character.rig != nil }
  var isExpressiveMotionEnabled: Bool {
    didSet {
      guard oldValue != isExpressiveMotionEnabled, let currentState else { return }
      play(state: currentState, style: currentStyle, transition: .reset)
    }
  }

  init(
    character: FullBodyCharacterNode,
    configuration: CharacterManifest.AnimationConfiguration
  ) {
    self.character = character
    self.configuration = configuration
    isExpressiveMotionEnabled = character.rig != nil
  }

  func play(state: CharacterState, style: MotionStyle, transition: MotionTransition) {
    currentState = state
    currentStyle = style
    var motion = FullBodyChoreography.motion(for: state, style: style, configuration: configuration)
    switch transition {
    case .reset:
      character.resetPose()
    case .blend(let duration):
      character.stopPoseActions()
      motion = motion.blended(over: duration)
      if motion.breath == nil {
        character.breathPivot.run(easedScale(to: 1, duration: duration), withKey: ActionKey.breath)
      }
    }
    character.speed = speed

    character.run(
      action(for: motion.body) { pose, duration in
        [.move(to: CGPoint(x: pose.offsetX, y: pose.offsetY), duration: duration)]
      }, withKey: ActionKey.translation)
    character.bodyPivot.run(
      action(for: motion.body) { pose, duration in
        [
          .rotate(toAngle: pose.rotation, duration: duration, shortestUnitArc: false),
          .scaleX(to: pose.scaleX, y: pose.scaleY, duration: duration),
        ]
      }, withKey: ActionKey.body)
    if let breath = motion.breath {
      character.breathPivot.run(
        action(for: breath) { pose, duration in
          [.scaleX(to: pose.scaleX, y: pose.scaleY, duration: duration)]
        }, withKey: ActionKey.breath)
    }
    if isExpressiveMotionEnabled, let expression = motion.expression,
      let rest = character.warpGeometry(for: .rest)
    {
      if transition == .reset || character.sprite.warpGeometry == nil {
        character.sprite.warpGeometry = rest
      }
      character.sprite.run(
        action(for: expression) { [character] pose, duration in
          [
            character.warpGeometry(for: pose).flatMap { .warp(to: $0, duration: duration) }
              ?? .wait(forDuration: duration)
          ]
        }, withKey: ActionKey.expression)
    } else {
      character.sprite.warpGeometry = nil
    }
    if motion.emitsSleepBubbles {
      startSleepBubbles()
    }
    if motion.finishes {
      character.run(
        .sequence([
          .wait(forDuration: motion.body.introDuration),
          .run { [weak self] in self?.reactionDidFinish?() },
        ]), withKey: ActionKey.completion)
    }
  }

  /// Squashes briefly at the feet and rebounds. Runs on its own pivot so it layers over the
  /// dance without interrupting it, and keeps the same real duration at any tempo.
  func accentBeat(strength: Double) {
    guard currentStyle.isMusic else { return }
    let amount = 0.02 + 0.035 * max(0, min(1, strength))
    let rate = max(Double(character.speed), 0.1)
    let squash = SKAction.group([
      .scaleX(to: 1 + amount * 0.6, duration: 0.07 * rate),
      .scaleY(to: 1 - amount, duration: 0.07 * rate),
    ])
    squash.timingMode = .easeOut
    character.accentPivot.run(
      .sequence([squash, easedScale(to: 1, duration: 0.2 * rate)]), withKey: ActionKey.accent)
  }

  func setMusicTempo(beatDuration: TimeInterval?) {
    musicBeatDuration = beatDuration
    character.speed = speed
  }

  private var speed: CGFloat {
    guard currentStyle.isMusic, let musicBeatDuration else { return 1 }
    return FullBodyChoreography.tempoScale(
      forBeatDuration: musicBeatDuration, configuration: configuration)
  }

  private func easedScale(to scale: CGFloat, duration: TimeInterval) -> SKAction {
    let action = SKAction.scale(to: scale, duration: duration)
    action.timingMode = .easeInEaseOut
    return action
  }

  private func action<Pose>(
    for track: MotionTrack<Pose>, _ make: (Pose, TimeInterval) -> [SKAction]
  ) -> SKAction {
    func steps(_ frames: [MotionKeyframe<Pose>]) -> SKAction {
      .sequence(frames.map { .group(timed(make($0.pose, $0.duration), $0.timing)) })
    }
    var parts: [SKAction] = []
    if !track.intro.isEmpty {
      parts.append(steps(track.intro))
    }
    if !track.loop.isEmpty {
      parts.append(.repeatForever(steps(track.loop)))
    }
    return .sequence(parts)
  }

  /// SpriteKit applies a timing mode only to the action it is set on, so set it on each leaf.
  private func timed(_ actions: [SKAction], _ timing: MotionTiming) -> [SKAction] {
    let mode: SKActionTimingMode =
      switch timing {
      case .linear: .linear
      case .easeIn: .easeIn
      case .easeOut: .easeOut
      case .easeInEaseOut: .easeInEaseOut
      }
    for action in actions {
      action.timingMode = mode
    }
    return actions
  }

  private func startSleepBubbles() {
    bubbleCount = 0
    character.effectsRoot.run(
      .repeatForever(
        .sequence([
          .wait(forDuration: 0.9),
          .run { [weak self] in self?.spawnSleepBubble() },
          .wait(forDuration: 1.1),
        ])), withKey: ActionKey.effects)
  }

  private func spawnSleepBubble() {
    let sizes: [CGFloat] = [32, 40, 48]
    let label = SKLabelNode(text: "z")
    label.fontName = "AvenirNext-Heavy"
    label.fontSize = sizes[bubbleCount % sizes.count]
    label.fontColor = NSColor(calibratedRed: 0.38, green: 0.47, blue: 0.9, alpha: 1)
    label.verticalAlignmentMode = .center
    bubbleCount += 1

    let head = character.headTop
    label.position = CGPoint(x: head.x + 170, y: head.y + 5)
    label.alpha = 0
    label.setScale(0.6)
    label.zRotation = 0.15
    character.effectsRoot.addChild(label)

    let lifetime: TimeInterval = 2.6
    let rise = SKAction.moveBy(x: 28, y: 80, duration: lifetime)
    rise.timingMode = .easeOut
    label.run(
      .sequence([
        .group([
          rise,
          .scale(to: 1.1, duration: lifetime),
          .rotate(toAngle: -0.1, duration: lifetime),
          .sequence([
            .fadeAlpha(to: 0.9, duration: 0.45),
            .wait(forDuration: lifetime - 1.25),
            .fadeOut(withDuration: 0.8),
          ]),
        ]),
        .removeFromParent(),
      ]))
  }
}
