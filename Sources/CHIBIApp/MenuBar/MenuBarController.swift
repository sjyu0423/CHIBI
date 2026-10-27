import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
  private static let privacySettingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

  private let statusItem: NSStatusItem
  private let settings: AppSettings
  private weak var overlay: CharacterOverlayControlling?
  private let music: MusicReactiveCoordinator
  private let visibilityItem = NSMenuItem()
  private var sizeItems: [CharacterSize: NSMenuItem] = [:]
  private let slowMotionItem = NSMenuItem()
  private let expressiveMotionItem = NSMenuItem()
  private let musicStatusItem = NSMenuItem()
  private let musicListenItem = NSMenuItem()
  private let musicSettingsItem = NSMenuItem()
  private let autoDanceItem = NSMenuItem()
  private var sensitivityItems: [MusicSensitivity: NSMenuItem] = [:]
  private var isSlowMotion = false

  init(settings: AppSettings, overlay: CharacterOverlayControlling, music: MusicReactiveCoordinator)
  {
    self.settings = settings
    self.overlay = overlay
    self.music = music
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    statusItem.button?.title = "🌸"
    statusItem.button?.toolTip = "CHIBI controls"
    statusItem.menu = buildMenu()
    music.onStatusChange = { [weak self] status in self?.musicStatusChanged(status) }
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

  @objc private func toggleSlowMotion() {
    isSlowMotion.toggle()
    overlay?.setAnimationSpeed(isSlowMotion ? 0.25 : 1)
    refreshMenuState()
  }

  @objc private func toggleExpressiveMotion() {
    guard let overlay else { return }
    overlay.setExpressiveMotionEnabled(!overlay.isExpressiveMotionEnabled)
    refreshMenuState()
  }

  @objc private func toggleListening() {
    if music.status.isListening {
      music.stop()
    } else {
      music.start()
    }
    refreshMenuState()
  }

  @objc private func chooseSensitivity(_ sender: NSMenuItem) {
    guard
      let sensitivity = MusicSensitivity(rawValue: sender.representedObject as? String ?? "")
    else { return }
    settings.musicSensitivity = sensitivity
    music.sensitivity = sensitivity
    refreshMenuState()
  }

  @objc private func toggleAutoDance() {
    settings.isAutoDanceEnabled.toggle()
    music.isAutoDanceEnabled = settings.isAutoDanceEnabled
    refreshMenuState()
  }

  @objc private func openPrivacySettings() {
    NSWorkspace.shared.open(Self.privacySettingsURL)
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

    let musicRoot = NSMenuItem(title: "Music Reactive", action: nil, keyEquivalent: "")
    musicRoot.submenu = buildMusicMenu()
    menu.addItem(musicRoot)

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

    let developerMenu = NSMenu(title: "Developer")
    developerMenu.autoenablesItems = false
    slowMotionItem.title = "Slow Motion (¼×)"
    slowMotionItem.target = self
    slowMotionItem.action = #selector(toggleSlowMotion)
    developerMenu.addItem(slowMotionItem)
    expressiveMotionItem.title = "Head Tilt & Hair Motion (Experimental)"
    expressiveMotionItem.target = self
    expressiveMotionItem.action = #selector(toggleExpressiveMotion)
    developerMenu.addItem(expressiveMotionItem)
    let developerRoot = NSMenuItem(title: "Developer", action: nil, keyEquivalent: "")
    developerRoot.submenu = developerMenu
    menu.addItem(developerRoot)

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

  private func buildMusicMenu() -> NSMenu {
    let menu = NSMenu(title: "Music Reactive")
    menu.autoenablesItems = false
    musicStatusItem.isEnabled = false
    menu.addItem(musicStatusItem)
    musicListenItem.target = self
    musicListenItem.action = #selector(toggleListening)
    menu.addItem(musicListenItem)
    musicSettingsItem.title = "Open Privacy Settings…"
    musicSettingsItem.target = self
    musicSettingsItem.action = #selector(openPrivacySettings)
    menu.addItem(musicSettingsItem)
    menu.addItem(.separator())

    let sensitivityMenu = NSMenu(title: "Sensitivity")
    for sensitivity in MusicSensitivity.allCases {
      let item = NSMenuItem(
        title: sensitivity.title, action: #selector(chooseSensitivity(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = sensitivity.rawValue
      sensitivityMenu.addItem(item)
      sensitivityItems[sensitivity] = item
    }
    let sensitivityRoot = NSMenuItem(title: "Sensitivity", action: nil, keyEquivalent: "")
    sensitivityRoot.submenu = sensitivityMenu
    menu.addItem(sensitivityRoot)

    autoDanceItem.title = "Auto Dance"
    autoDanceItem.target = self
    autoDanceItem.action = #selector(toggleAutoDance)
    menu.addItem(autoDanceItem)
    return menu
  }

  private func refreshMenuState() {
    visibilityItem.title = settings.isCharacterVisible ? "Hide Character" : "Show Character"
    for (size, item) in sizeItems {
      item.state = settings.characterSize == size ? .on : .off
    }
    slowMotionItem.state = isSlowMotion ? .on : .off
    expressiveMotionItem.isEnabled = overlay?.supportsExpressiveMotion ?? false
    expressiveMotionItem.state = overlay?.isExpressiveMotionEnabled == true ? .on : .off

    let status = music.status
    musicStatusItem.title = status.summary
    musicListenItem.title = status.isListening ? "Stop Listening" : "Start Listening"
    musicSettingsItem.isHidden = status.capture != .permissionDenied
    for (sensitivity, item) in sensitivityItems {
      item.state = settings.musicSensitivity == sensitivity ? .on : .off
    }
    autoDanceItem.state = settings.isAutoDanceEnabled ? .on : .off
  }

  private func musicStatusChanged(_ status: MusicReactiveStatus) {
    refreshMenuState()
    guard let failure = status.capture.failure else { return }
    DispatchQueue.main.async { [weak self] in
      self?.presentAlert(for: failure)
    }
  }

  private func presentAlert(for failure: AudioCaptureError) {
    let alert = NSAlert()
    switch failure {
    case .permissionDenied:
      alert.messageText = "CHIBI needs permission to hear system audio"
      alert.informativeText = """
        macOS includes system audio in Screen & System Audio Recording. Allow CHIBI in \
        System Settings › Privacy & Security, then quit and reopen CHIBI.

        CHIBI only measures loudness and rhythm on this Mac. It discards video frames and never \
        records, saves, or uploads audio.
        """
      alert.addButton(withTitle: "Open System Settings")
      alert.addButton(withTitle: "Not Now")
    case .unavailable(let reason):
      alert.messageText = "System audio is unavailable"
      alert.informativeText = reason
      alert.addButton(withTitle: "OK")
    case .interrupted(let reason):
      alert.messageText = "Music listening stopped"
      alert.informativeText = "\(reason)\n\nChoose Start Listening to try again."
      alert.addButton(withTitle: "OK")
    }
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn, failure == .permissionDenied {
      openPrivacySettings()
    }
  }
}
