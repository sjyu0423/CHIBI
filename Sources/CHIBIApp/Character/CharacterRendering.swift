import SpriteKit

@MainActor
protocol CharacterRendering: AnyObject {
  var renderScene: SKScene { get }
  var supportsExpressiveMotion: Bool { get }
  var isExpressiveMotionEnabled: Bool { get }
  func reactToClick()
  func beginDragging()
  func endDragging()
  func setSleeping(_ sleeping: Bool)
  func previewAnimation(_ animation: CharacterAnimation)
  func containsCharacter(point: CGPoint) -> Bool
  func fitRenderArea(to viewSize: CGSize, backingScale: CGFloat)
  func setAnimationSpeed(_ speed: Double)
  func setExpressiveMotionEnabled(_ enabled: Bool)
}
