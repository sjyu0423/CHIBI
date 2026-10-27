import AppKit
import SpriteKit

private final class PassiveOverlayWindow: NSWindow {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

@MainActor
protocol CharacterOverlayControlling: AnyObject {
  func setCharacterVisible(_ visible: Bool)
  func setCharacterSize(_ size: CharacterSize)
  func resetPosition()
  func previewAnimation(_ animation: CharacterAnimation)
  var supportsExpressiveMotion: Bool { get }
  var isExpressiveMotionEnabled: Bool { get }
  func setExpressiveMotionEnabled(_ enabled: Bool)
  func setAnimationSpeed(_ speed: Double)
  func applyMusic(_ command: MusicDanceCommand)
}

@MainActor
final class CharacterOverlayWindowController: NSWindowController, CharacterOverlayControlling,
  CharacterViewDragDelegate
{
  private let settings: AppSettings
  private let characterView: CharacterView
  private var hitTestTimer: Timer?

  init(settings: AppSettings) {
    self.settings = settings
    characterView = CharacterView(
      frame: CGRect(origin: .zero, size: settings.characterSize.dimensions))

    let window = PassiveOverlayWindow(
      contentRect: CGRect(origin: .zero, size: settings.characterSize.dimensions),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    super.init(window: window)

    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.hidesOnDeactivate = false
    window.isMovable = false
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    window.contentView = characterView

    characterView.allowsTransparency = true
    characterView.ignoresSiblingOrder = true
    characterView.preferredFramesPerSecond = 30
    characterView.shouldCullNonVisibleNodes = true
    characterView.dragDelegate = self
    characterView.presentScene(CharacterScene())

    let timer = Timer(
      timeInterval: 1.0 / 30.0, target: self, selector: #selector(updateMousePassthrough),
      userInfo: nil, repeats: true)
    RunLoop.main.add(timer, forMode: .common)
    hitTestTimer = timer
    restorePositionOrUseDefault()
    setCharacterVisible(settings.isCharacterVisible)
  }

  required init?(coder: NSCoder) {
    nil
  }

  func setCharacterVisible(_ visible: Bool) {
    characterView.isPaused = !visible
    if visible {
      hitTestTimer?.fireDate = .distantPast
      window?.orderFrontRegardless()
    } else {
      hitTestTimer?.fireDate = .distantFuture
      window?.ignoresMouseEvents = true
      window?.orderOut(nil)
    }
  }

  func setCharacterSize(_ size: CharacterSize) {
    guard let window else { return }
    let oldFrame = window.frame
    let newSize = size.dimensions
    let origin = CGPoint(x: oldFrame.midX - newSize.width / 2, y: oldFrame.minY)
    window.setFrame(CGRect(origin: origin, size: newSize), display: true)
    persistClampedPosition()
  }

  func resetPosition() {
    settings.savedPosition = nil
    let origin = defaultOrigin(for: window?.frame.size ?? settings.characterSize.dimensions)
    window?.setFrameOrigin(origin)
    settings.savedPosition = origin
  }

  func previewAnimation(_ animation: CharacterAnimation) {
    renderer?.previewAnimation(animation)
  }

  var supportsExpressiveMotion: Bool { renderer?.supportsExpressiveMotion ?? false }
  var isExpressiveMotionEnabled: Bool { renderer?.isExpressiveMotionEnabled ?? false }

  func setExpressiveMotionEnabled(_ enabled: Bool) {
    renderer?.setExpressiveMotionEnabled(enabled)
  }

  func setAnimationSpeed(_ speed: Double) {
    renderer?.setAnimationSpeed(speed)
  }

  func applyMusic(_ command: MusicDanceCommand) {
    renderer?.applyMusic(command)
  }

  private var renderer: CharacterRendering? {
    characterView.scene as? CharacterRendering
  }

  func characterView(_ view: CharacterView, didMoveTo position: CGPoint) {
    persistClampedPosition()
  }

  @objc private func updateMousePassthrough() {
    guard let window, window.isVisible else { return }
    if characterView.isDraggingCharacter {
      window.ignoresMouseEvents = false
    } else {
      window.ignoresMouseEvents = !characterView.containsCharacter(
        screenPoint: NSEvent.mouseLocation)
    }
  }

  private func restorePositionOrUseDefault() {
    guard let window else { return }
    let desired = settings.savedPosition ?? defaultOrigin(for: window.frame.size)
    window.setFrameOrigin(clamped(origin: desired, size: window.frame.size))
  }

  private func persistClampedPosition() {
    guard let window else { return }
    let origin = clamped(origin: window.frame.origin, size: window.frame.size)
    window.setFrameOrigin(origin)
    settings.savedPosition = origin
  }

  private func defaultOrigin(for size: CGSize) -> CGPoint {
    let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    return CGPoint(x: visible.maxX - size.width - 32, y: visible.minY + 32)
  }

  private func clamped(origin: CGPoint, size: CGSize) -> CGPoint {
    let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return origin }
    return CGPoint(
      x: min(max(origin.x, visible.minX), visible.maxX - size.width),
      y: min(max(origin.y, visible.minY), visible.maxY - size.height)
    )
  }
}
