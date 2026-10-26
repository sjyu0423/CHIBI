import AppKit

@main
@MainActor
final class CHIBIApplication: NSObject, NSApplicationDelegate {
  private var overlayController: CharacterOverlayWindowController?
  private var menuBarController: MenuBarController?

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
    overlayController = overlay
    menuBarController = MenuBarController(settings: settings, overlay: overlay)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}
