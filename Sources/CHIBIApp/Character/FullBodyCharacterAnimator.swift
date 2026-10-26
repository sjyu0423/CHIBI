import SpriteKit

/// Presents motion by transforming the approved complete sprite as one unit.
/// It intentionally does not imply independent limb, hair, or facial animation.
@MainActor
final class FullBodyCharacterAnimator: CharacterAnimating {
  private enum ActionKey {
    static let primary = "character.full-body.primary"
    static let secondary = "character.full-body.secondary"
  }

  private let character: FullBodyCharacterNode
  private let configuration: CharacterManifest.AnimationConfiguration
  var reactionDidFinish: (() -> Void)?

  init(
    character: FullBodyCharacterNode,
    configuration: CharacterManifest.AnimationConfiguration
  ) {
    self.character = character
    self.configuration = configuration
  }

  func play(state: CharacterState) {
    character.resetPose()
    switch state {
    case .idle: playIdle()
    case .reacting: playHappyReaction()
    case .dragging: playDragging()
    case .sleeping: playSleep()
    case .walking: playWalkingInPlace()
    case .dancing: playDance()
    }
  }

  private func playIdle() {
    let half = configuration.idleCycleDuration / 2
    character.run(
      repeating([
        eased(.moveBy(x: 0, y: configuration.idleBobHeight, duration: half)),
        eased(.moveBy(x: 0, y: -configuration.idleBobHeight, duration: half)),
      ]), withKey: ActionKey.primary)
    character.spriteRoot.run(
      repeating([
        eased(.scaleX(to: 0.995, y: 1.008, duration: half)),
        eased(.scaleX(to: 1, y: 1, duration: half)),
      ]), withKey: ActionKey.secondary)
  }

  private func playHappyReaction() {
    let rise = eased(
      .group([
        .moveBy(x: 0, y: configuration.happyHopHeight, duration: 0.14),
        .scaleX(to: 0.95, y: 1.06, duration: 0.14),
        .rotate(toAngle: -0.025, duration: 0.14),
      ]))
    let land = eased(
      .group([
        .moveBy(x: 0, y: -configuration.happyHopHeight, duration: 0.2),
        .scaleX(to: 1.04, y: 0.96, duration: 0.2),
        .rotate(toAngle: 0.018, duration: 0.2),
      ]))
    let settle = eased(
      .group([
        .scaleX(to: 1, y: 1, duration: 0.16),
        .rotate(toAngle: 0, duration: 0.16),
      ]))
    character.run(
      .sequence([
        rise, land, settle,
        .run { [weak self] in self?.reactionDidFinish?() },
      ]), withKey: ActionKey.primary)
  }

  private func playDragging() {
    character.run(
      eased(.group([.scale(to: 1.035, duration: 0.1), .moveBy(x: 0, y: 3, duration: 0.1)])),
      withKey: ActionKey.primary)
  }

  private func playSleep() {
    let half = configuration.sleepSwayDuration / 2
    character.run(
      repeating([
        eased(
          .group([
            .rotate(toAngle: -0.022, duration: half),
            .scaleX(to: 1.006, y: 0.994, duration: half),
          ])),
        eased(
          .group([
            .rotate(toAngle: 0.018, duration: half),
            .scaleX(to: 1, y: 1, duration: half),
          ])),
      ]), withKey: ActionKey.primary)
  }

  private func playWalkingInPlace() {
    let halfStep = configuration.walkStepDuration / 2
    character.run(
      repeating([
        eased(
          .group([
            .moveBy(x: -2.5, y: 4, duration: halfStep),
            .rotate(toAngle: 0.018, duration: halfStep),
            .scaleX(to: 0.99, y: 1.015, duration: halfStep),
          ])),
        eased(
          .group([
            .moveBy(x: 5, y: -4, duration: halfStep),
            .rotate(toAngle: -0.018, duration: halfStep),
            .scaleX(to: 1.01, y: 0.985, duration: halfStep),
          ])),
        eased(
          .group([
            .moveBy(x: -2.5, y: 0, duration: halfStep),
            .rotate(toAngle: 0, duration: halfStep),
            .scaleX(to: 1, y: 1, duration: halfStep),
          ])),
      ]), withKey: ActionKey.primary)
  }

  private func playDance() {
    let beat = configuration.danceBeatDuration
    character.run(
      repeating([
        eased(
          .group([
            .moveBy(x: -8, y: 5, duration: beat),
            .rotate(toAngle: 0.045, duration: beat),
            .scaleX(to: 0.98, y: 1.025, duration: beat),
          ])),
        eased(
          .group([
            .moveBy(x: 16, y: -1, duration: beat),
            .rotate(toAngle: -0.045, duration: beat),
            .scaleX(to: 1.025, y: 0.98, duration: beat),
          ])),
        eased(
          .group([
            .moveBy(x: -8, y: -4, duration: beat),
            .rotate(toAngle: 0, duration: beat),
            .scaleX(to: 1, y: 1, duration: beat),
          ])),
      ]), withKey: ActionKey.primary)
  }

  private func repeating(_ actions: [SKAction]) -> SKAction {
    .repeatForever(.sequence(actions))
  }

  private func eased(_ action: SKAction) -> SKAction {
    action.timingMode = .easeInEaseOut
    return action
  }
}
