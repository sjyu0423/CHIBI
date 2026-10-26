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
