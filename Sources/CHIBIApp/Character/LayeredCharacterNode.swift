import AppKit
import SpriteKit

enum CharacterLayerSource: Equatable {
  case bundledAsset(String)
  case proceduralFallback
}

@MainActor
final class LayeredCharacterNode: SKNode {
  private let layoutRoot = SKNode()
  let shadowRoot = SKNode()
  let hairBackRoot = SKNode()
  let leftLegRoot = SKNode()
  let rightLegRoot = SKNode()
  let torsoRoot = SKNode()
  let leftArmRoot = SKNode()
  let rightArmRoot = SKNode()
  let headRoot = SKNode()
  let faceRoot = SKNode()
  let leftEyeRoot = SKNode()
  let rightEyeRoot = SKNode()
  let mouthRoot = SKNode()
  let hairFrontRoot = SKNode()

  let manifest: CharacterManifest
  private let assetLoader: CharacterAssetLoader?
  private var sources: [CharacterManifest.Layer: CharacterLayerSource] = [:]
  private var openEyeSprites: [SKSpriteNode] = []
  private var closedEyeSprites: [SKSpriteNode] = []
  private var mouthSprites: [MouthExpression: SKSpriteNode] = [:]

  enum MouthExpression {
    case neutral
    case happy
    case sleeping
  }

  private var poseNodes: [SKNode] {
    [
      self, shadowRoot, hairBackRoot, leftLegRoot, rightLegRoot, torsoRoot, leftArmRoot,
      rightArmRoot, headRoot, faceRoot, leftEyeRoot, rightEyeRoot, mouthRoot, hairFrontRoot,
    ]
  }

  init(manifest: CharacterManifest, assetLoader: CharacterAssetLoader?) {
    self.manifest = manifest
    self.assetLoader = assetLoader
    super.init()
    name = "character-root"
    layoutRoot.name = "normalized-layout-root"
    addChild(layoutRoot)
    buildLayers()
  }

  required init?(coder aDecoder: NSCoder) {
    nil
  }

  func resetPose() {
    for node in poseNodes {
      node.removeAllActions()
      node.zRotation = 0
      node.xScale = 1
      node.yScale = 1
    }
    setBaselinePositions()
    setEyesClosed(false)
    setMouth(.neutral)
  }

  func setEyesClosed(_ closed: Bool) {
    if !closedEyeSprites.isEmpty {
      for sprite in openEyeSprites {
        sprite.isHidden = closed
      }
      for sprite in closedEyeSprites {
        sprite.isHidden = !closed
      }
      leftEyeRoot.yScale = 1
      rightEyeRoot.yScale = 1
      return
    }
    let scale: CGFloat = closed ? 0.08 : 1
    leftEyeRoot.yScale = scale
    rightEyeRoot.yScale = scale
  }

  func setMouth(_ expression: MouthExpression) {
    guard !mouthSprites.isEmpty else { return }
    let resolved = mouthSprites[expression] == nil ? MouthExpression.neutral : expression
    for (key, sprite) in mouthSprites {
      sprite.isHidden = key != resolved
    }
  }

  func source(for layer: CharacterManifest.Layer) -> CharacterLayerSource? {
    sources[layer]
  }

  var hasClosedEyeAssets: Bool {
    closedEyeSprites.count == 2
  }

  private func buildLayers() {
    for layout in manifest.resolvedLayers.sorted(by: { $0.drawOrder < $1.drawOrder }) {
      let root = root(for: layout.layer)
      root.zPosition = CGFloat(layout.drawOrder)
      layoutRoot.addChild(root)
    }
    setBaselinePositions()

    buildShadow()
    addLayer(.hairBack, path: manifest.assets.hairBack, to: hairBackRoot, fallback: buildHairBack)
    addLayer(.leftLeg, path: manifest.assets.leftLeg, to: leftLegRoot) {
      self.buildLeg(left: true)
    }
    addLayer(.rightLeg, path: manifest.assets.rightLeg, to: rightLegRoot) {
      self.buildLeg(left: false)
    }
    addLayer(.torso, path: manifest.assets.torso, to: torsoRoot, fallback: buildTorso)
    addLayer(.leftArm, path: manifest.assets.leftArm, to: leftArmRoot) {
      self.buildArm(left: true)
    }
    addLayer(.rightArm, path: manifest.assets.rightArm, to: rightArmRoot) {
      self.buildArm(left: false)
    }
    addLayer(.head, path: manifest.assets.head, to: headRoot, fallback: buildHead)
    addLayer(.face, path: manifest.assets.face, to: faceRoot) {}
    addEyeLayers()
    addMouthLayers()
    if manifest.assets.face == nil {
      buildCheeks()
    }
    addLayer(
      .hairFront, path: manifest.assets.hairFront, to: hairFrontRoot, fallback: buildHairFront)
  }

  private func addLayer(
    _ layer: CharacterManifest.Layer, path: String?, to parent: SKNode, fallback: () -> Void
  ) {
    if let path, let texture = try? assetLoader?.texture(named: path) {
      let sprite = spriteNode(texture: texture, path: path, layer: layer)
      parent.addChild(sprite)
      sources[layer] = .bundledAsset(path)
    } else {
      fallback()
      sources[layer] = .proceduralFallback
    }
  }

  private func addEyeLayers() {
    addEye(
      .leftEye, openPath: manifest.assets.leftEye, closedPath: manifest.assets.leftEyeClosed,
      to: leftEyeRoot, left: true)
    addEye(
      .rightEye, openPath: manifest.assets.rightEye, closedPath: manifest.assets.rightEyeClosed,
      to: rightEyeRoot, left: false)
  }

  private func addEye(
    _ layer: CharacterManifest.Layer, openPath: String?, closedPath: String?, to root: SKNode,
    left: Bool
  ) {
    guard let openPath, let openTexture = try? assetLoader?.texture(named: openPath) else {
      buildEye(left: left)
      sources[layer] = .proceduralFallback
      return
    }
    let open = spriteNode(texture: openTexture, path: openPath, layer: layer)
    root.addChild(open)
    openEyeSprites.append(open)
    sources[layer] = .bundledAsset(openPath)
    if let closedPath, let texture = try? assetLoader?.texture(named: closedPath) {
      let closed = spriteNode(texture: texture, path: closedPath, layer: layer)
      closed.isHidden = true
      root.addChild(closed)
      closedEyeSprites.append(closed)
    }
  }

  private func addMouthLayers() {
    guard
      let path = manifest.assets.mouth,
      let texture = try? assetLoader?.texture(named: path)
    else {
      buildMouth()
      sources[.mouth] = .proceduralFallback
      return
    }
    let neutral = spriteNode(texture: texture, path: path, layer: .mouth)
    mouthRoot.addChild(neutral)
    mouthSprites[.neutral] = neutral
    sources[.mouth] = .bundledAsset(path)
    addMouthVariant(.happy, path: manifest.assets.mouthHappy)
    addMouthVariant(.sleeping, path: manifest.assets.mouthSleep)
  }

  private func addMouthVariant(_ expression: MouthExpression, path: String?) {
    guard let path, let texture = try? assetLoader?.texture(named: path) else { return }
    let sprite = spriteNode(texture: texture, path: path, layer: .mouth)
    sprite.isHidden = true
    mouthRoot.addChild(sprite)
    mouthSprites[expression] = sprite
  }

  private func spriteNode(
    texture: SKTexture, path: String, layer: CharacterManifest.Layer
  ) -> SKSpriteNode {
    let layout = manifest.layout(for: layer)
    let sprite = SKSpriteNode(texture: texture)
    sprite.name = path
    sprite.anchorPoint = layout.effectiveAnchorPoint
    sprite.setScale(layout.scale)
    return sprite
  }

  private func root(for layer: CharacterManifest.Layer) -> SKNode {
    switch layer {
    case .shadow: shadowRoot
    case .hairBack: hairBackRoot
    case .leftLeg: leftLegRoot
    case .rightLeg: rightLegRoot
    case .torso: torsoRoot
    case .leftArm: leftArmRoot
    case .rightArm: rightArmRoot
    case .head: headRoot
    case .face: faceRoot
    case .leftEye: leftEyeRoot
    case .rightEye: rightEyeRoot
    case .mouth: mouthRoot
    case .hairFront: hairFrontRoot
    }
  }

  private func buildShadow() {
    let shadow = SKShapeNode(ellipseOf: CGSize(width: 106, height: 18))
    shadow.fillColor = NSColor.black.withAlphaComponent(0.14)
    shadow.strokeColor = .clear
    shadowRoot.addChild(shadow)
    sources[.shadow] = .proceduralFallback
  }

  private func buildHairBack() {
    let hair = SKShapeNode(ellipseOf: CGSize(width: 150, height: 150))
    hair.fillColor = Palette.hair
    hair.strokeColor = Palette.outline
    hair.lineWidth = 4
    hairBackRoot.addChild(hair)
  }

  private func buildLeg(left: Bool) {
    let leg = roundedNode(
      size: CGSize(width: 24, height: 48), radius: 11, fill: Palette.leggings, lineWidth: 3)
    let root = left ? leftLegRoot : rightLegRoot
    root.addChild(leg)

    let shoe = roundedNode(
      size: CGSize(width: 31, height: 17), radius: 8, fill: Palette.shoe, lineWidth: 2)
    shoe.position = CGPoint(x: left ? -3 : 3, y: -20)
    root.addChild(shoe)
  }

  private func buildTorso() {
    let hoodie = roundedNode(
      size: CGSize(width: 78, height: 78), radius: 28, fill: Palette.hoodie, lineWidth: 4)
    torsoRoot.addChild(hoodie)

    let pocket = roundedNode(
      size: CGSize(width: 42, height: 18), radius: 9, fill: Palette.hoodieShadow, lineWidth: 2)
    pocket.position = CGPoint(x: 0, y: -15)
    torsoRoot.addChild(pocket)

    for x in [-10.0, 10.0] {
      let string = SKShapeNode(rectOf: CGSize(width: 2.5, height: 20), cornerRadius: 1.25)
      string.fillColor = Palette.hoodieShadow
      string.strokeColor = .clear
      string.position = CGPoint(x: x, y: 20)
      torsoRoot.addChild(string)
    }
  }

  private func buildArm(left: Bool) {
    let arm = roundedNode(
      size: CGSize(width: 27, height: 65), radius: 13, fill: Palette.hoodie, lineWidth: 3)
    arm.zRotation = left ? -0.15 : 0.15
    (left ? leftArmRoot : rightArmRoot).addChild(arm)
  }

  private func buildHead() {
    let head = SKShapeNode(ellipseOf: CGSize(width: 146, height: 132))
    head.fillColor = Palette.skin
    head.strokeColor = Palette.outline
    head.lineWidth = 4
    headRoot.addChild(head)
  }

  private func buildEye(left: Bool) {
    let eye = SKShapeNode(ellipseOf: CGSize(width: 17, height: 24))
    eye.fillColor = Palette.eye
    eye.strokeColor = .clear
    let highlight = SKShapeNode(circleOfRadius: 3.2)
    highlight.fillColor = .white
    highlight.strokeColor = .clear
    highlight.position = CGPoint(x: -3, y: 6)
    let root = left ? leftEyeRoot : rightEyeRoot
    root.addChild(eye)
    root.addChild(highlight)
  }

  private func buildMouth() {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -10, y: 0))
    path.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 0, y: -10))
    let mouth = SKShapeNode(path: path)
    mouth.strokeColor = Palette.mouth
    mouth.lineWidth = 3
    mouth.lineCap = .round
    mouthRoot.addChild(mouth)
  }

  private func buildCheeks() {
    for x in [-53.0, 53.0] {
      let cheek = SKShapeNode(ellipseOf: CGSize(width: 23, height: 10))
      cheek.fillColor = Palette.cheek
      cheek.strokeColor = .clear
      cheek.position = CGPoint(x: x, y: 9)
      faceRoot.addChild(cheek)
    }
  }

  private func buildHairFront() {
    let cap = SKShapeNode(ellipseOf: CGSize(width: 148, height: 75))
    cap.fillColor = Palette.hair
    cap.strokeColor = .clear
    cap.position = CGPoint(x: 0, y: 4)
    hairFrontRoot.addChild(cap)

    for x in [-52.0, -26.0, 0.0, 26.0, 52.0] {
      let bang = SKShapeNode(ellipseOf: CGSize(width: 35, height: 62))
      bang.fillColor = Palette.hair
      bang.strokeColor = .clear
      bang.position = CGPoint(x: x, y: -14 - abs(x) * 0.08)
      bang.zRotation = x * -0.002
      hairFrontRoot.addChild(bang)
    }
  }

  private func roundedNode(
    size: CGSize, radius: CGFloat, fill: NSColor, lineWidth: CGFloat
  ) -> SKShapeNode {
    let node = SKShapeNode(rectOf: size, cornerRadius: radius)
    node.fillColor = fill
    node.strokeColor = Palette.outline
    node.lineWidth = lineWidth
    return node
  }

  private func setBaselinePositions() {
    position = .zero
    for layer in CharacterManifest.Layer.allCases {
      let layout = manifest.layout(for: layer)
      let node = root(for: layer)
      node.position = layout.position.cgPoint
      node.zPosition = CGFloat(layout.drawOrder)
    }
  }
}

private enum Palette {
  static let outline = NSColor(calibratedRed: 0.24, green: 0.16, blue: 0.27, alpha: 1)
  static let skin = NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.77, alpha: 1)
  static let hair = NSColor(calibratedRed: 0.31, green: 0.20, blue: 0.40, alpha: 1)
  static let hoodie = NSColor(calibratedRed: 0.49, green: 0.73, blue: 0.96, alpha: 1)
  static let hoodieShadow = NSColor(calibratedRed: 0.28, green: 0.53, blue: 0.78, alpha: 1)
  static let leggings = NSColor(calibratedRed: 0.22, green: 0.25, blue: 0.36, alpha: 1)
  static let shoe = NSColor(calibratedRed: 0.95, green: 0.96, blue: 1, alpha: 1)
  static let eye = NSColor(calibratedRed: 0.15, green: 0.10, blue: 0.22, alpha: 1)
  static let mouth = NSColor(calibratedRed: 0.48, green: 0.18, blue: 0.28, alpha: 1)
  static let cheek = NSColor(calibratedRed: 1, green: 0.42, blue: 0.52, alpha: 0.32)
}
