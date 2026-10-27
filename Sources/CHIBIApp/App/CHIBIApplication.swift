import AppKit

@main
@MainActor
final class CHIBIApplication: NSObject, NSApplicationDelegate {
  private var overlayController: CharacterOverlayWindowController?
  private var menuBarController: MenuBarController?
  private var musicCoordinator: MusicReactiveCoordinator?

  static func main() {
    let app = NSApplication.shared
    let delegate = CHIBIApplication()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let settings = AppSettings()
    let overlay = CharacterOverlayWindowController(settings: settings)
    let music = MusicReactiveCoordinator(
      source: ScreenCaptureAudioSource(), sensitivity: settings.musicSensitivity,
      isAutoDanceEnabled: settings.isAutoDanceEnabled
    ) { [weak overlay] command in
      overlay?.applyMusic(command)
    }
    overlayController = overlay
    musicCoordinator = music
    menuBarController = MenuBarController(settings: settings, overlay: overlay, music: music)
  }

  func applicationWillTerminate(_ notification: Notification) {
    musicCoordinator?.stop()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}
