import Foundation
import Testing

@testable import CHIBIApp

struct CharacterManifestTests {
  @Test func bundledManifestLoadsAndValidates() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    #expect(manifest.identifier == "dev.chibi.temporary-layered")
    #expect(manifest.displayName == "Temporary Layered Chibi")
    #expect(manifest.renderDimensions.size.width == 210)
    #expect(manifest.animations.walkStepDuration == 0.28)
  }

  @Test func transparentPNGReferencesAreAccepted() throws {
    let manifest = try decodeManifest(assetPath: "Characters/Hero/head.png")
    #expect(try manifest.validated().assets.head == "Characters/Hero/head.png")
  }

  @Test func unsafeAssetPathsAreRejected() throws {
    let manifest = try decodeManifest(assetPath: "../private/head.png")
    #expect(throws: CharacterManifestError.unsafeAssetPath("../private/head.png")) {
      try manifest.validated()
    }
  }

  @Test func nonPNGAssetsAreRejected() throws {
    let manifest = try decodeManifest(assetPath: "head.jpg")
    #expect(throws: CharacterManifestError.unsupportedAssetFormat("head.jpg")) {
      try manifest.validated()
    }
  }

  private func decodeManifest(assetPath: String) throws -> CharacterManifest {
    let json = """
      {
        "identifier": "dev.chibi.test",
        "displayName": "Test Character",
        "renderDimensions": { "width": 210, "height": 250 },
        "assets": { "head": "\(assetPath)" },
        "animations": {
          "idleBobHeight": 3.5,
          "idleCycleDuration": 2.4,
          "blinkMinimumDelay": 2.0,
          "blinkDelayVariation": 2.4,
          "happyHopHeight": 18.0,
          "walkStepDuration": 0.28,
          "danceBeatDuration": 0.42,
          "sleepSwayDuration": 2.8
        }
      }
      """
    return try JSONDecoder().decode(CharacterManifest.self, from: Data(json.utf8))
  }
}
