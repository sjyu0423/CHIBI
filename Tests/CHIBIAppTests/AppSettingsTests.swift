import Foundation
import Testing

@testable import CHIBIApp

@MainActor
struct AppSettingsTests {
  @Test func defaultsAndValuesPersist() throws {
    let suiteName = "CHIBIAppTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    #expect(settings.isCharacterVisible)
    #expect(settings.characterSize == .medium)
    #expect(settings.savedPosition == nil)

    settings.isCharacterVisible = false
    settings.characterSize = .large
    settings.savedPosition = CGPoint(x: 42.5, y: 81.25)

    let reloaded = AppSettings(defaults: defaults)
    #expect(!reloaded.isCharacterVisible)
    #expect(reloaded.characterSize == .large)
    #expect(reloaded.savedPosition == CGPoint(x: 42.5, y: 81.25))
  }

  @Test func musicPreferencesDefaultToNormalAutoDanceAndPersist() throws {
    let suiteName = "CHIBIAppTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    #expect(settings.musicSensitivity == .normal)
    #expect(settings.isAutoDanceEnabled)
    settings.musicSensitivity = .high
    settings.isAutoDanceEnabled = false

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.musicSensitivity == .high)
    #expect(!reloaded.isAutoDanceEnabled)
    defaults.set("deafening", forKey: "musicSensitivity")
    #expect(reloaded.musicSensitivity == .normal)
    #expect(
      defaults.dictionaryRepresentation().keys.allSatisfy { !$0.lowercased().contains("listen") })
  }

  @Test func sensitivityShiftsLoudnessThresholdsMonotonically() {
    #expect(MusicSensitivity.low.loudnessOffsetDB > MusicSensitivity.normal.loudnessOffsetDB)
    #expect(MusicSensitivity.normal.loudnessOffsetDB == 0)
    #expect(MusicSensitivity.high.loudnessOffsetDB < MusicSensitivity.normal.loudnessOffsetDB)
  }

  @Test func positionCanBeCleared() throws {
    let suiteName = "CHIBIAppTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    settings.savedPosition = CGPoint(x: 1, y: 2)
    settings.savedPosition = nil
    #expect(settings.savedPosition == nil)
  }
}
