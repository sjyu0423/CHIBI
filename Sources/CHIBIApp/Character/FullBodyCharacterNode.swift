import SpriteKit

/// Hierarchy: root (translation) → body pivot at the feet (rotation, squash and stretch)
/// → breath pivot (breathing scale) → sprite root → sprite (optional seamless warp).
@MainActor
final class FullBodyCharacterNode: SKNode {
  let bodyPivot = SKNode()
  let breathPivot = SKNode()
  let spriteRoot = SKNode()
  let effectsRoot = SKNode()
  let sprite: SKSpriteNode
  let manifest: CharacterManifest
  let rig: CharacterManifest.FullBodyRig?
  /// The manifest image actually drawn: the selected variant, or the original as fallback.
  let imagePath: String
  let sampling: CharacterManifest.FullBodyDisplay.Sampling
  /// Top of the sprite relative to the feet, in scene units.
  let spriteHeight: CGFloat
  /// Pixel height of the texture currently drawn.
  private(set) var textureHeight: Int
  private let sourceImage: CGImage
  private let spriteSize: CGSize
  private let spriteAspect: Double

  init?(
    manifest: CharacterManifest,
    assetLoader: CharacterAssetLoader
  ) {
    guard
      let (path, image) = manifest.fullBodyImageCandidates.lazy.compactMap({ path in
        (try? assetLoader.image(named: path)).map { (path, $0) }
      }).first
    else {
      return nil
    }

    self.manifest = manifest
    imagePath = path
    sampling = manifest.resolvedFullBodyDisplay.sampling
    sourceImage = image
    textureHeight = image.height
    let layout =
      manifest.fullBodyLayout
      ?? .init(
        position: .init(x: 0, y: 0),
        anchorPoint: .init(x: 0.5, y: 0.5),
        scale: 1)
    spriteSize = CGSize(width: image.width, height: image.height)
    spriteHeight = spriteSize.height * layout.scale
    spriteAspect = spriteSize.width / max(spriteSize.height, 1)
    rig = manifest.fullBodyRig
    sprite = SKSpriteNode(texture: SKTexture(cgImage: image))
    super.init()
    name = "character-root"

    let feet = CGPoint(
      x: layout.position.x,
      y: layout.position.y - spriteHeight * layout.anchorPoint.y)
    bodyPivot.name = "full-body-pivot"
    bodyPivot.position = feet
    breathPivot.name = "full-body-breath"
    spriteRoot.name = "full-body-sprite-root"
    spriteRoot.position = CGPoint(x: 0, y: layout.position.y - feet.y)
    effectsRoot.name = "full-body-effects"
    addChild(bodyPivot)
    bodyPivot.addChild(breathPivot)
    breathPivot.addChild(spriteRoot)
    addChild(effectsRoot)

    sprite.name = path
    sprite.size = spriteSize
    sprite.anchorPoint = layout.anchorPoint.cgPoint
    sprite.setScale(layout.scale)
    spriteRoot.addChild(sprite)
  }

  required init?(coder aDecoder: NSCoder) {
    nil
  }

  /// Matches the texture to the sprite's on-screen pixel height when the manifest requests
  /// display resampling. The sprite's size in scene units never changes.
  func prepareTexture(pixelsPerSceneUnit: CGFloat) {
    guard sampling == .displayResampled, pixelsPerSceneUnit.isFinite, pixelsPerSceneUnit > 0
    else { return }
    let target = min(Int((spriteHeight * pixelsPerSceneUnit).rounded(.up)), sourceImage.height)
    guard target != textureHeight else { return }
    if target < sourceImage.height,
      let resampled = SpriteResampler.resample(sourceImage, toHeight: target)
    {
      sprite.texture = SKTexture(cgImage: resampled)
      textureHeight = target
    } else {
      sprite.texture = SKTexture(cgImage: sourceImage)
      textureHeight = sourceImage.height
    }
  }

  /// Head position relative to the root, for effects that should originate near the face.
  var headTop: CGPoint {
    CGPoint(x: bodyPivot.position.x, y: bodyPivot.position.y + spriteHeight * 0.88)
  }

  func warpGeometry(for expression: FullBodyExpression) -> SKWarpGeometryGrid? {
    guard let rig else { return nil }
    return SKWarpGeometryGrid(
      columns: FullBodyWarp.columns,
      rows: FullBodyWarp.rows,
      sourcePositions: FullBodyWarp.sourcePositions(),
      destinationPositions: FullBodyWarp.destinationPositions(
        rig: rig, expression: expression, aspect: spriteAspect))
  }

  func resetPose() {
    for node in [self, bodyPivot, breathPivot, spriteRoot, sprite, effectsRoot] as [SKNode] {
      node.removeAllActions()
    }
    effectsRoot.removeAllChildren()
    position = .zero
    zRotation = 0
    xScale = 1
    yScale = 1
    for node in [bodyPivot, breathPivot] {
      node.zRotation = 0
      node.xScale = 1
      node.yScale = 1
    }
    sprite.warpGeometry = nil
  }
}
