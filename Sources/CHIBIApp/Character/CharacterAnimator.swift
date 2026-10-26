import SpriteKit

@MainActor
protocol CharacterAnimating: AnyObject {
  var reactionDidFinish: (() -> Void)? { get set }
  func play(state: CharacterState)
}

@MainActor
final class CharacterAnimator: CharacterAnimating {
  private enum ActionKey {
    static let primary = "character.primary"
    static let blink = "character.blink"
  }

  private let character: LayeredCharacterNode
  private let configuration: CharacterManifest.AnimationConfiguration
  var reactionDidFinish: (() -> Void)?

  init(
    character: LayeredCharacterNode,
    configuration: CharacterManifest.AnimationConfiguration
  ) {
    self.character = character
    self.configuration = configuration
  }

  func play(state: CharacterState) {
    character.resetPose()
    switch state {
    case .idle:
      playIdle()
    case .reacting:
      playHappyReaction()
    case .dragging:
      playDragging()
    case .sleeping:
      playSleep()
    case .walking:
      playWalking()
    case .dancing:
      playDance()
    }
  }

  private func playIdle() {
    let halfCycle = configuration.idleCycleDuration / 2
    character.run(
      .repeatForever(
        .sequence([
          eased(.moveBy(x: 0, y: configuration.idleBobHeight, duration: halfCycle)),
          eased(.moveBy(x: 0, y: -configuration.idleBobHeight, duration: halfCycle)),
        ])),
      withKey: ActionKey.primary)

    character.torsoRoot.run(
      .repeatForever(
        .sequence([
          eased(.scaleY(to: 1.025, duration: halfCycle)),
          eased(.scaleY(to: 1, duration: halfCycle)),
        ])),
      withKey: ActionKey.primary)
    character.headRoot.run(secondaryBounce(height: 1.5, duration: configuration.idleCycleDuration))
    character.hairFrontRoot.run(
      secondaryBounce(height: 1.1, duration: configuration.idleCycleDuration * 0.82))
    startBlinking()
  }

  private func playHappyReaction() {
    character.setMouth(.happy)
    let hop = eased(
      .group([
        .moveBy(x: 0, y: configuration.happyHopHeight, duration: 0.14),
        .scaleX(to: 1.07, duration: 0.14),
        .scaleY(to: 0.94, duration: 0.14),
      ]))
    let land = eased(
      .group([
        .moveBy(x: 0, y: -configuration.happyHopHeight, duration: 0.22),
        .scale(to: 1, duration: 0.22),
      ]))
    character.leftArmRoot.run(waveAction(direction: -1))
    character.rightArmRoot.run(waveAction(direction: 1))
    character.headRoot.run(
      .sequence([
        eased(.rotate(toAngle: -0.06, duration: 0.14)),
        eased(.rotate(toAngle: 0, duration: 0.22)),
      ]))
    character.mouthRoot.run(
      .sequence([
        eased(.scaleX(to: 1.3, duration: 0.12)),
        eased(.scaleX(to: 1, duration: 0.24)),
      ]))
    character.run(
      .sequence([
        hop, land,
        .run { [weak self] in self?.reactionDidFinish?() },
      ]),
      withKey: ActionKey.primary)
  }

  private func playDragging() {
    character.run(eased(.scale(to: 1.045, duration: 0.1)), withKey: ActionKey.primary)
    character.headRoot.run(eased(.moveBy(x: 0, y: 2, duration: 0.1)))
    startBlinking()
  }

  private func playSleep() {
    character.setEyesClosed(true)
    character.setMouth(.sleeping)
    let half = configuration.sleepSwayDuration / 2
    character.run(
      .repeatForever(
        .sequence([
          eased(.rotate(toAngle: -0.035, duration: half)),
          eased(.rotate(toAngle: 0.025, duration: half)),
        ])),
      withKey: ActionKey.primary)
    character.headRoot.run(
      .repeatForever(
        .sequence([
          eased(.moveBy(x: 0, y: -2, duration: half)),
          eased(.moveBy(x: 0, y: 2, duration: half)),
        ])))
    character.hairFrontRoot.run(
      secondaryBounce(height: 0.8, duration: configuration.sleepSwayDuration))
  }

  private func playWalking() {
    let step = configuration.walkStepDuration
    character.leftLegRoot.run(alternatingStep(height: 5, duration: step))
    character.rightLegRoot.run(delayed(alternatingStep(height: 5, duration: step), by: step))
    character.leftArmRoot.run(alternatingHorizontal(distance: 3, duration: step))
    character.rightArmRoot.run(
      delayed(alternatingHorizontal(distance: -3, duration: step), by: step))
    character.torsoRoot.run(
      .repeatForever(
        .sequence([
          eased(.moveBy(x: 0, y: 2, duration: step / 2)),
          eased(.moveBy(x: 0, y: -2, duration: step / 2)),
        ])))
    character.headRoot.run(secondaryBounce(height: 1.5, duration: step * 2))
    character.hairFrontRoot.run(secondaryBounce(height: 2, duration: step * 1.7))
    startBlinking()
  }

  private func playDance() {
    let beat = configuration.danceBeatDuration
    character.run(
      .repeatForever(
        .sequence([
          eased(
            .group([.moveBy(x: -7, y: 4, duration: beat), .rotate(toAngle: 0.045, duration: beat)])),
          eased(
            .group([.moveBy(x: 14, y: 0, duration: beat), .rotate(toAngle: -0.045, duration: beat)])
          ),
          eased(
            .group([.moveBy(x: -7, y: -4, duration: beat), .rotate(toAngle: 0, duration: beat)])),
        ])),
      withKey: ActionKey.primary)
    character.leftArmRoot.run(danceArm(direction: -1, duration: beat))
    character.rightArmRoot.run(danceArm(direction: 1, duration: beat))
    character.headRoot.run(
      .repeatForever(
        .sequence([
          eased(.rotate(toAngle: -0.055, duration: beat)),
          eased(.rotate(toAngle: 0.055, duration: beat)),
        ])))
    character.hairFrontRoot.run(secondaryBounce(height: 2.5, duration: beat * 1.8))
    startBlinking()
  }

  private func startBlinking() {
    let wait = SKAction.wait(
      forDuration: configuration.blinkMinimumDelay + configuration.blinkDelayVariation / 2,
      withRange: configuration.blinkDelayVariation)
    let blink = SKAction.repeatForever(
      .sequence([
        wait,
        .run { [weak self] in
          guard let self else { return }
          if self.character.hasClosedEyeAssets {
            self.character.run(
              .sequence([
                .run { [weak self] in self?.character.setEyesClosed(true) },
                .wait(forDuration: 0.075),
                .run { [weak self] in self?.character.setEyesClosed(false) },
              ]))
          } else {
            self.character.leftEyeRoot.run(self.blinkAction())
            self.character.rightEyeRoot.run(self.blinkAction())
          }
        },
      ]))
    character.run(blink, withKey: ActionKey.blink)
  }

  private func blinkAction() -> SKAction {
    .sequence([
      eased(.scaleY(to: 0.08, duration: 0.065)),
      eased(.scaleY(to: 1, duration: 0.095)),
    ])
  }

  private func secondaryBounce(height: CGFloat, duration: TimeInterval) -> SKAction {
    .repeatForever(
      .sequence([
        eased(.moveBy(x: 0, y: height, duration: duration / 2)),
        eased(.moveBy(x: 0, y: -height, duration: duration / 2)),
      ]))
  }

  private func waveAction(direction: CGFloat) -> SKAction {
    .sequence([
      eased(.moveBy(x: 5 * direction, y: 8, duration: 0.12)),
      eased(.moveBy(x: -5 * direction, y: -8, duration: 0.24)),
    ])
  }

  private func alternatingStep(height: CGFloat, duration: TimeInterval) -> SKAction {
    .repeatForever(
      .sequence([
        eased(.moveBy(x: 0, y: height, duration: duration / 2)),
        eased(.moveBy(x: 0, y: -height, duration: duration / 2)),
        .wait(forDuration: duration),
      ]))
  }

  private func alternatingHorizontal(distance: CGFloat, duration: TimeInterval) -> SKAction {
    .repeatForever(
      .sequence([
        eased(.moveBy(x: distance, y: 0, duration: duration)),
        eased(.moveBy(x: -distance, y: 0, duration: duration)),
      ]))
  }

  private func danceArm(direction: CGFloat, duration: TimeInterval) -> SKAction {
    .repeatForever(
      .sequence([
        eased(.moveBy(x: 5 * direction, y: 12, duration: duration)),
        eased(.moveBy(x: -10 * direction, y: -4, duration: duration)),
        eased(.moveBy(x: 5 * direction, y: -8, duration: duration)),
      ]))
  }

  private func delayed(_ action: SKAction, by delay: TimeInterval) -> SKAction {
    .sequence([.wait(forDuration: delay), action])
  }

  private func eased(_ action: SKAction) -> SKAction {
    action.timingMode = .easeInEaseOut
    return action
  }
}
