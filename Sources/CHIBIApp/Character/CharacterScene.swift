import SpriteKit

@MainActor
final class CharacterScene: SKScene, CharacterRendering {
  var renderScene: SKScene { self }

  private var stateMachine = CharacterStateMachine()
  private let character: SKNode
  private let manifest: CharacterManifest
  private let animator: any CharacterAnimating

  override convenience init() {
    self.init(
      manifest: (try? CharacterAssetLoader.loadBundledDefault()) ?? .proceduralFallback,
      assetLoader: .bundled)
  }

  init(manifest: CharacterManifest, assetLoader loader: CharacterAssetLoader) {
    let character: SKNode
    let animator: any CharacterAnimating
    if manifest.resolvedRenderingMode == .fullBody,
      let fullBody = FullBodyCharacterNode(manifest: manifest, assetLoader: loader)
    {
      character = fullBody
      animator = FullBodyCharacterAnimator(
        character: fullBody, configuration: manifest.animations)
    } else {
      let layered = LayeredCharacterNode(manifest: manifest, assetLoader: loader)
      character = layered
      animator = CharacterAnimator(character: layered, configuration: manifest.animations)
    }
    self.character = character
    self.manifest = manifest
    self.animator = animator

    super.init(size: manifest.renderDimensions.size)
    scaleMode = .aspectFit
    backgroundColor = .clear
    anchorPoint = CGPoint(x: 0.5, y: 0.5)
    addChild(character)

    animator.reactionDidFinish = { [weak self] in
      guard let self, self.stateMachine.state == .reacting else { return }
      self.stateMachine.handle(.reactionFinished)
      self.present()
    }
    present()
  }

  static let musicBlendDuration: TimeInterval = 0.35
  static let musicSettleDuration: TimeInterval = 0.7

  required init?(coder aDecoder: NSCoder) {
    nil
  }

  override func didMove(to view: SKView) {
    fitRenderArea(to: view.bounds.size, backingScale: view.window?.backingScaleFactor ?? 1)
  }

  /// `backingScale` only selects the full-body texture resolution; layout stays in points.
  func fitRenderArea(to viewSize: CGSize, backingScale: CGFloat) {
    let fitted = manifest.renderDimensions.sceneSize(fitting: viewSize)
    if size != fitted {
      size = fitted
    }
    guard viewSize.height > 0, let fullBody = character as? FullBodyCharacterNode else { return }
    fullBody.prepareTexture(pixelsPerSceneUnit: viewSize.height / fitted.height * backingScale)
  }

  var state: CharacterState { stateMachine.state }
  var musicLevel: MusicDanceLevel? { stateMachine.musicLevel }
  var supportsExpressiveMotion: Bool { animator.supportsExpressiveMotion }
  var isExpressiveMotionEnabled: Bool { animator.isExpressiveMotionEnabled }

  /// Developer playback rate; 1 is normal speed.
  func setAnimationSpeed(_ speed: Double) {
    self.speed = max(0.05, min(speed, 4))
  }

  func setExpressiveMotionEnabled(_ enabled: Bool) {
    animator.isExpressiveMotionEnabled = enabled && animator.supportsExpressiveMotion
  }

  func containsCharacter(point: CGPoint) -> Bool {
    let local = character.convert(point, from: self)
    let dimensions = manifest.renderDimensions.size
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
    present()
  }

  func beginDragging() {
    stateMachine.handle(.dragBegan)
    present()
  }

  func endDragging() {
    stateMachine.handle(.dragEnded)
    present()
  }

  func setSleeping(_ sleeping: Bool) {
    stateMachine.handle(sleeping ? .sleepRequested : .wakeRequested)
    present()
  }

  func previewAnimation(_ animation: CharacterAnimation) {
    stateMachine.handle(.previewRequested(animation))
    present()
  }

  /// Music commands only replay the animation when the pose or music level actually changes;
  /// accents and tempo changes layer onto the running dance.
  func applyMusic(_ command: MusicDanceCommand) {
    switch command {
    case .dance(let level):
      updatePresentation(after: .musicDanceRequested(level), blend: Self.musicBlendDuration)
    case .settle:
      updatePresentation(after: .musicStopped, blend: Self.musicSettleDuration)
    case .accent(let strength):
      guard stateMachine.musicLevel != nil else { return }
      animator.accentBeat(strength: strength)
    case .tempo(let beatDuration):
      animator.setMusicTempo(beatDuration: beatDuration)
    }
  }

  private func updatePresentation(after event: CharacterEvent, blend: TimeInterval) {
    let before = (stateMachine.state, stateMachine.musicLevel)
    stateMachine.handle(event)
    guard before != (stateMachine.state, stateMachine.musicLevel) else { return }
    present(.blend(blend))
  }

  private func present(_ transition: MotionTransition = .reset) {
    let style = stateMachine.musicLevel.map(MotionStyle.music) ?? .standard
    animator.play(state: stateMachine.state, style: style, transition: transition)
  }
}

extension CharacterManifest {
  fileprivate static let proceduralFallback = CharacterManifest(
    identifier: "dev.chibi.procedural-fallback",
    displayName: "Procedural Fallback",
    renderDimensions: RenderDimensions(width: 210, height: 250),
    renderingMode: .layered,
    assets: AssetReferences(),
    fullBodyLayout: nil,
    layers: nil,
    animations: .standard
  )
}
