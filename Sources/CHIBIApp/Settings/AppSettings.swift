import AppKit
import Foundation

enum CharacterSize: String, CaseIterable, Sendable {
  case small
  case medium
  case large

  var dimensions: CGSize {
    switch self {
    case .small: CGSize(width: 150, height: 180)
    case .medium: CGSize(width: 210, height: 250)
    case .large: CGSize(width: 285, height: 340)
    }
  }

  var title: String { rawValue.capitalized }
}

@MainActor
final class AppSettings {
  private enum Key {
    static let isCharacterVisible = "isCharacterVisible"
    static let characterSize = "characterSize"
    static let positionX = "positionX"
    static let positionY = "positionY"
    static let hasSavedPosition = "hasSavedPosition"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [
      Key.isCharacterVisible: true,
      Key.characterSize: CharacterSize.medium.rawValue,
    ])
  }

  var isCharacterVisible: Bool {
    get { defaults.bool(forKey: Key.isCharacterVisible) }
    set { defaults.set(newValue, forKey: Key.isCharacterVisible) }
  }

  var characterSize: CharacterSize {
    get { CharacterSize(rawValue: defaults.string(forKey: Key.characterSize) ?? "") ?? .medium }
    set { defaults.set(newValue.rawValue, forKey: Key.characterSize) }
  }

  var savedPosition: CGPoint? {
    get {
      guard defaults.bool(forKey: Key.hasSavedPosition) else { return nil }
      return CGPoint(
        x: defaults.double(forKey: Key.positionX),
        y: defaults.double(forKey: Key.positionY)
      )
    }
    set {
      guard let newValue else {
        defaults.set(false, forKey: Key.hasSavedPosition)
        defaults.removeObject(forKey: Key.positionX)
        defaults.removeObject(forKey: Key.positionY)
        return
      }
      defaults.set(Double(newValue.x), forKey: Key.positionX)
      defaults.set(Double(newValue.y), forKey: Key.positionY)
      defaults.set(true, forKey: Key.hasSavedPosition)
    }
  }
}
