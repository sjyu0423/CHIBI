import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let settings: AppSettings
  private weak var overlay: CharacterOverlayControlling?
  private let visibilityItem = NSMenuItem()
  private var sizeItems: [CharacterSize: NSMenuItem] = [:]

  init(settings: AppSettings, overlay: CharacterOverlayControlling) {
    self.settings = settings
    self.overlay = overlay
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    statusItem.button?.title = "🌸"
    statusItem.button?.toolTip = "CHIBI controls"
    statusItem.menu = buildMenu()
    refreshMenuState()
  }

  func menuWillOpen(_ menu: NSMenu) {
    refreshMenuState()
  }

  @objc private func toggleVisibility() {
    settings.isCharacterVisible.toggle()
    overlay?.setCharacterVisible(settings.isCharacterVisible)
    refreshMenuState()
  }

  @objc private func chooseSize(_ sender: NSMenuItem) {
    guard let size = CharacterSize(rawValue: sender.representedObject as? String ?? "") else {
      return
    }
    settings.characterSize = size
    overlay?.setCharacterSize(size)
    refreshMenuState()
  }

  @objc private func resetPosition() {
    overlay?.resetPosition()
  }

  @objc private func previewAnimation(_ sender: NSMenuItem) {
    guard let animation = CharacterAnimation(rawValue: sender.representedObject as? String ?? "")
    else {
      return
    }
    overlay?.previewAnimation(animation)
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func buildMenu() -> NSMenu {
    let menu = NSMenu()
    menu.delegate = self

    visibilityItem.target = self
    visibilityItem.action = #selector(toggleVisibility)
    menu.addItem(visibilityItem)

    let sizeMenu = NSMenu(title: "Character Size")
    for size in CharacterSize.allCases {
      let item = NSMenuItem(title: size.title, action: #selector(chooseSize(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = size.rawValue
      sizeMenu.addItem(item)
      sizeItems[size] = item
    }
    let sizeRoot = NSMenuItem(title: "Character Size", action: nil, keyEquivalent: "")
    sizeRoot.submenu = sizeMenu
    menu.addItem(sizeRoot)

    let animationMenu = NSMenu(title: "Animation Preview")
    for animation in CharacterAnimation.allCases {
      let item = NSMenuItem(
        title: animation.title, action: #selector(previewAnimation(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = animation.rawValue
      animationMenu.addItem(item)
    }
    let animationRoot = NSMenuItem(title: "Animation Preview", action: nil, keyEquivalent: "")
    animationRoot.submenu = animationMenu
    menu.addItem(animationRoot)

    let reset = NSMenuItem(
      title: "Reset Position", action: #selector(resetPosition), keyEquivalent: "r")
    reset.target = self
    menu.addItem(reset)
    menu.addItem(.separator())

    let quit = NSMenuItem(title: "Quit CHIBI", action: #selector(quit), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
    return menu
  }

  private func refreshMenuState() {
    visibilityItem.title = settings.isCharacterVisible ? "Hide Character" : "Show Character"
    for (size, item) in sizeItems {
      item.state = settings.characterSize == size ? .on : .off
    }
  }
}
