import AppKit
import SpriteKit

@MainActor
final class CharacterView: SKView {
  weak var dragDelegate: CharacterViewDragDelegate?
  private(set) var isDraggingCharacter = false
  private var mouseDownLocation: CGPoint?
  private var windowOriginAtMouseDown: CGPoint?
  private var didDrag = false

  override var acceptsFirstResponder: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let renderer = scene as? CharacterRendering else { return nil }
    let scenePoint = convert(point, to: renderer.renderScene)
    return renderer.containsCharacter(point: scenePoint) ? self : nil
  }

  override func mouseDown(with event: NSEvent) {
    mouseDownLocation = NSEvent.mouseLocation
    windowOriginAtMouseDown = window?.frame.origin
    didDrag = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start = mouseDownLocation, let windowStart = windowOriginAtMouseDown else { return }
    let current = NSEvent.mouseLocation
    let delta = CGPoint(x: current.x - start.x, y: current.y - start.y)
    if !didDrag, hypot(delta.x, delta.y) > 3 {
      didDrag = true
      isDraggingCharacter = true
      (scene as? CharacterRendering)?.beginDragging()
    }
    guard didDrag else { return }
    window?.setFrameOrigin(CGPoint(x: windowStart.x + delta.x, y: windowStart.y + delta.y))
  }

  override func mouseUp(with event: NSEvent) {
    if didDrag {
      (scene as? CharacterRendering)?.endDragging()
      if let position = window?.frame.origin {
        dragDelegate?.characterView(self, didMoveTo: position)
      }
    } else {
      (scene as? CharacterRendering)?.reactToClick()
    }
    mouseDownLocation = nil
    windowOriginAtMouseDown = nil
    didDrag = false
    isDraggingCharacter = false
  }

  func containsCharacter(screenPoint: CGPoint) -> Bool {
    guard let window, let renderer = scene as? CharacterRendering else { return false }
    let windowPoint = window.convertPoint(fromScreen: screenPoint)
    let viewPoint = convert(windowPoint, from: nil)
    let scenePoint = convert(viewPoint, to: renderer.renderScene)
    return renderer.containsCharacter(point: scenePoint)
  }
}

@MainActor
protocol CharacterViewDragDelegate: AnyObject {
  func characterView(_ view: CharacterView, didMoveTo position: CGPoint)
}
