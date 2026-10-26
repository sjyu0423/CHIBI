import SpriteKit

@MainActor
final class CharacterScene: SKScene, CharacterRendering {
  var renderScene: SKScene { self }

  private var stateMachine = CharacterStateMachine()
  private let character: LayeredCharacterNode
  private let animator: CharacterAnimator

  override init() {
    let loader = CharacterAssetLoader(bundle: .module)
    let manifest = (try? loader.loadManifest(named: "temporary-character")) ?? .proceduralFallback
    let character = LayeredCharacterNode(manifest: manifest, assetLoader: loader)
    self.character = character
    animator = CharacterAnimator(character: character, configuration: manifest.animations)

    super.init(size: manifest.renderDimensions.size)
    scaleMode = .aspectFit
    backgroundColor = .clear
    anchorPoint = CGPoint(x: 0.5, y: 0.5)
    addChild(character)

    animator.reactionDidFinish = { [weak self] in
      guard let self, self.stateMachine.state == .reacting else { return }
      self.stateMachine.handle(.reactionFinished)
      self.animator.play(state: .idle)
    }
    animator.play(state: .idle)
  }

  required init?(coder aDecoder: NSCoder) {
    nil
  }

  func containsCharacter(point: CGPoint) -> Bool {
    let local = character.convert(point, from: self)
    let dimensions = character.manifest.renderDimensions.size
    let headOffset = CGPoint(x: local.x, y: local.y - dimensions.height * 0.136)
    let isInsideHead =
      pow(headOffset.x / (dimensions.width * 0.367), 2)
      + pow(headOffset.y / (dimensions.height * 0.28), 2) <= 1
    let isInsideBody = CGRect(
      x: dimensions.width * -0.276,
      y: dimensions.height * -0.464,
      width: dimensions.width * 0.552,
      height: dimensions.height * 0.424
    ).contains(local)
    return isInsideHead || isInsideBody
  }

  func reactToClick() {
    guard stateMachine.handle(.clicked) == .reacting else { return }
    animator.play(state: .reacting)
  }

  func beginDragging() {
    stateMachine.handle(.dragBegan)
    animator.play(state: .dragging)
  }

  func endDragging() {
    stateMachine.handle(.dragEnded)
    animator.play(state: stateMachine.state)
  }

  func setSleeping(_ sleeping: Bool) {
    stateMachine.handle(sleeping ? .sleepRequested : .wakeRequested)
    animator.play(state: stateMachine.state)
  }

  func previewAnimation(_ animation: CharacterAnimation) {
    stateMachine.handle(.previewRequested(animation))
    animator.play(state: stateMachine.state)
  }
}

extension CharacterManifest {
  fileprivate static let proceduralFallback = CharacterManifest(
    identifier: "dev.chibi.procedural-fallback",
    displayName: "Procedural Fallback",
    renderDimensions: RenderDimensions(width: 210, height: 250),
    assets: AssetReferences(),
    animations: .standard
  )
}
