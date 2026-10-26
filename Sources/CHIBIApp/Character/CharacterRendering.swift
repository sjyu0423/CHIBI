import SpriteKit

@MainActor
protocol CharacterRendering: AnyObject {
  var renderScene: SKScene { get }
  func reactToClick()
  func beginDragging()
  func endDragging()
  func setSleeping(_ sleeping: Bool)
  func previewAnimation(_ animation: CharacterAnimation)
  func containsCharacter(point: CGPoint) -> Bool
  func fitRenderArea(to viewSize: CGSize)
}
