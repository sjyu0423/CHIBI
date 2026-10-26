import AppKit
import SpriteKit

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
    layoutRoot.xScale = manifest.renderDimensions.size.width / 210
    layoutRoot.yScale = manifest.renderDimensions.size.height / 250
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
  }

  func setEyesClosed(_ closed: Bool) {
    let scale: CGFloat = closed ? 0.08 : 1
    leftEyeRoot.yScale = scale
    rightEyeRoot.yScale = scale
  }

  private func buildLayers() {
    let layers = [
      shadowRoot, hairBackRoot, leftLegRoot, rightLegRoot, torsoRoot, leftArmRoot, rightArmRoot,
      headRoot, faceRoot, leftEyeRoot, rightEyeRoot, mouthRoot, hairFrontRoot,
    ]
    for (index, layer) in layers.enumerated() {
      layer.zPosition = CGFloat(index)
      layoutRoot.addChild(layer)
    }
    setBaselinePositions()

    buildShadow()
    addLayer(path: manifest.assets.hairBack, to: hairBackRoot, fallback: buildHairBack)
    addLayer(path: manifest.assets.leftLeg, to: leftLegRoot) { self.buildLeg(left: true) }
    addLayer(path: manifest.assets.rightLeg, to: rightLegRoot) { self.buildLeg(left: false) }
    addLayer(path: manifest.assets.torso, to: torsoRoot, fallback: buildTorso)
    addLayer(path: manifest.assets.leftArm, to: leftArmRoot) { self.buildArm(left: true) }
    addLayer(path: manifest.assets.rightArm, to: rightArmRoot) { self.buildArm(left: false) }
    addLayer(path: manifest.assets.head, to: headRoot, fallback: buildHead)
    addLayer(path: manifest.assets.face, to: faceRoot) {}
    addLayer(path: manifest.assets.leftEye, to: leftEyeRoot) { self.buildEye(left: true) }
    addLayer(path: manifest.assets.rightEye, to: rightEyeRoot) { self.buildEye(left: false) }
    addLayer(path: manifest.assets.mouth, to: mouthRoot, fallback: buildMouth)
    if manifest.assets.face == nil {
      buildCheeks()
    }
    addLayer(path: manifest.assets.hairFront, to: hairFrontRoot, fallback: buildHairFront)
  }

  private func addLayer(path: String?, to parent: SKNode, fallback: () -> Void) {
    if let path, let texture = try? assetLoader?.texture(named: path) {
      let sprite = SKSpriteNode(texture: texture)
      sprite.size = CGSize(
        width: sprite.size.width * 210 / manifest.renderDimensions.size.width,
        height: sprite.size.height * 250 / manifest.renderDimensions.size.height)
      sprite.name = path
      parent.addChild(sprite)
    } else {
      fallback()
    }
  }

  private func buildShadow() {
    let shadow = SKShapeNode(ellipseOf: CGSize(width: 106, height: 18))
    shadow.fillColor = NSColor.black.withAlphaComponent(0.14)
    shadow.strokeColor = .clear
    shadowRoot.addChild(shadow)
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
    shadowRoot.position = CGPoint(x: 0, y: -104)
    hairBackRoot.position = CGPoint(x: 0, y: 35)
    leftLegRoot.position = CGPoint(x: -22, y: -88)
    rightLegRoot.position = CGPoint(x: 22, y: -88)
    torsoRoot.position = CGPoint(x: 0, y: -55)
    leftArmRoot.position = CGPoint(x: -46, y: -55)
    rightArmRoot.position = CGPoint(x: 46, y: -55)
    headRoot.position = CGPoint(x: 0, y: 34)
    faceRoot.position = .zero
    leftEyeRoot.position = CGPoint(x: -31, y: 31)
    rightEyeRoot.position = CGPoint(x: 31, y: 31)
    mouthRoot.position = CGPoint(x: 0, y: 7)
    hairFrontRoot.position = CGPoint(x: 0, y: 74)
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
