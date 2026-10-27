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

/// How loud audio must be before the character treats it as music and how hard it dances.
enum MusicSensitivity: String, CaseIterable, Sendable {
  case low
  case normal
  case high

  var title: String { rawValue.capitalized }

  /// Offset applied to every loudness threshold in the analyzer.
  var loudnessOffsetDB: Double {
    switch self {
    case .low: 8
    case .normal: 0
    case .high: -8
    }
  }
}

/// Listening itself is never persisted: music reaction always starts off at launch.
@MainActor
final class AppSettings {
  private enum Key {
    static let isCharacterVisible = "isCharacterVisible"
    static let characterSize = "characterSize"
    static let positionX = "positionX"
    static let positionY = "positionY"
    static let hasSavedPosition = "hasSavedPosition"
    static let musicSensitivity = "musicSensitivity"
    static let isAutoDanceEnabled = "isAutoDanceEnabled"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [
      Key.isCharacterVisible: true,
      Key.characterSize: CharacterSize.medium.rawValue,
      Key.musicSensitivity: MusicSensitivity.normal.rawValue,
      Key.isAutoDanceEnabled: true,
    ])
  }

  var musicSensitivity: MusicSensitivity {
    get {
      MusicSensitivity(rawValue: defaults.string(forKey: Key.musicSensitivity) ?? "") ?? .normal
    }
    set { defaults.set(newValue.rawValue, forKey: Key.musicSensitivity) }
  }

  var isAutoDanceEnabled: Bool {
    get { defaults.bool(forKey: Key.isAutoDanceEnabled) }
    set { defaults.set(newValue, forKey: Key.isAutoDanceEnabled) }
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
