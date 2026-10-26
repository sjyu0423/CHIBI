import SpriteKit

@MainActor
final class FullBodyCharacterNode: SKNode {
  let spriteRoot = SKNode()
  let manifest: CharacterManifest

  init?(
    manifest: CharacterManifest,
    assetLoader: CharacterAssetLoader
  ) {
    guard
      let path = manifest.assets.fullBody,
      let texture = try? assetLoader.texture(named: path)
    else {
      return nil
    }

    self.manifest = manifest
    super.init()
    name = "character-root"
    spriteRoot.name = "full-body-sprite-root"
    addChild(spriteRoot)

    let layout =
      manifest.fullBodyLayout
      ?? .init(
        position: .init(x: 0, y: 0),
        anchorPoint: .init(x: 0.5, y: 0.5),
        scale: 1)
    spriteRoot.position = layout.position.cgPoint

    let sprite = SKSpriteNode(texture: texture)
    sprite.name = path
    sprite.anchorPoint = layout.anchorPoint.cgPoint
    sprite.setScale(layout.scale)
    spriteRoot.addChild(sprite)
  }

  required init?(coder aDecoder: NSCoder) {
    nil
  }

  func resetPose() {
    removeAllActions()
    spriteRoot.removeAllActions()
    position = .zero
    zRotation = 0
    xScale = 1
    yScale = 1
    spriteRoot.zRotation = 0
    spriteRoot.xScale = 1
    spriteRoot.yScale = 1
  }
}
