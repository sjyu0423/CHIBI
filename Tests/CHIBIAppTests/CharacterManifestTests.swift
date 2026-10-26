import AppKit
import Foundation
import Testing

@testable import CHIBIApp

struct CharacterManifestTests {
  @Test func bundledManifestLoadsAndValidates() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    #expect(manifest.identifier == "dev.chibi.sleepy-coder")
    #expect(manifest.displayName == "Sleepy Coder")
    #expect(manifest.renderDimensions.size.width == 640)
    #expect(manifest.resolvedRenderingMode == .fullBody)
    #expect(manifest.assets.fullBody == "Characters/sleepy-coder/full-body.png")
    #expect(manifest.fullBodyLayout?.anchorPoint == .init(x: 0.5, y: 0.5))
    #expect(manifest.animations.walkStepDuration == 0.3)
  }

  @Test func manifestsWithoutRenderingModeRemainLayered() throws {
    let manifest = try decodeManifest(assetPath: "head.png")
    #expect(manifest.resolvedRenderingMode == .layered)
  }

  @Test func fullBodyModeRequiresRegisteredAsset() throws {
    let json = """
      {
        "identifier": "dev.chibi.test",
        "displayName": "Test Character",
        "renderDimensions": { "width": 210, "height": 250 },
        "renderingMode": "fullBody",
        "assets": {},
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
    let manifest = try JSONDecoder().decode(CharacterManifest.self, from: Data(json.utf8))
    #expect(throws: CharacterManifestError.missingFullBodyAsset) {
      try manifest.validated()
    }
  }

  @Test func invalidFullBodyMetadataIsRejected() throws {
    let json = """
      {
        "identifier": "dev.chibi.test",
        "displayName": "Test Character",
        "renderDimensions": { "width": 210, "height": 250 },
        "renderingMode": "fullBody",
        "assets": { "fullBody": "character.png" },
        "fullBodyLayout": {
          "position": { "x": 0, "y": 0 },
          "anchorPoint": { "x": 1.2, "y": 0.5 },
          "scale": 1
        },
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
    let manifest = try JSONDecoder().decode(CharacterManifest.self, from: Data(json.utf8))
    #expect(throws: CharacterManifestError.invalidFullBodyLayout) {
      try manifest.validated()
    }
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

  @Test func layerMetadataControlsOrderingPlacementAndPivot() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    let ordered = manifest.resolvedLayers.sorted { $0.drawOrder < $1.drawOrder }
    #expect(ordered.first?.layer == .shadow)
    #expect(ordered.last?.layer == .hairFront)

    let leftArm = manifest.layout(for: .leftArm)
    #expect(leftArm.position == .init(x: -108, y: -24))
    #expect(leftArm.effectiveAnchorPoint == CGPoint(x: 0.5, y: 0.84))
    #expect(leftArm.drawOrder < manifest.layout(for: .torso).drawOrder)
  }

  @Test func invalidLayerMetadataIsRejected() throws {
    let manifest = try decodeManifest(
      assetPath: "head.png",
      layers: """
        [
          {
            "layer": "head",
            "position": { "x": 0, "y": 0 },
            "anchorPoint": { "x": 1.5, "y": 0.5 },
            "drawOrder": 1,
            "scale": 1
          }
        ]
        """)
    #expect(throws: CharacterManifestError.invalidLayerLayout(.head)) {
      try manifest.validated()
    }
  }

  @Test func allRegisteredAssetsExistAndHaveAlpha() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    let loader = CharacterAssetLoader.bundled
    for path in manifest.assets.allFiles {
      let data = try Data(contentsOf: loader.assetURL(named: path))
      let representation = NSBitmapImageRep(data: data)
      #expect(representation != nil, "Unreadable registered asset: \(path)")
      #expect(representation?.hasAlpha == true, "Asset lacks alpha: \(path)")
    }
  }

  @Test func bundledFullBodySpriteFitsRenderDimensions() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    let layout = try #require(manifest.fullBodyLayout)
    let path = try #require(manifest.assets.fullBody)
    let size = try CharacterAssetLoader.bundled.texture(named: path).size()
    let width = size.width * layout.scale
    let height = size.height * layout.scale
    let minX = layout.position.x - width * layout.anchorPoint.x
    let minY = layout.position.y - height * layout.anchorPoint.y
    let bounds = manifest.renderDimensions
    #expect(minX >= -bounds.width / 2 && minX + width <= bounds.width / 2)
    #expect(minY >= -bounds.height / 2 && minY + height <= bounds.height / 2)
  }

  @Test func sceneSizeMatchesEveryOverlayAspectWithoutShrinkingRenderArea() throws {
    let dimensions = try CharacterAssetLoader.loadBundledDefault().renderDimensions
    for characterSize in CharacterSize.allCases {
      let view = characterSize.dimensions
      let scene = dimensions.sceneSize(fitting: view)
      #expect(abs(scene.width / scene.height - view.width / view.height) < 1e-9)
      #expect(scene.width >= dimensions.width && scene.height >= dimensions.height)
      #expect(scene.width == dimensions.width || scene.height == dimensions.height)
    }
    #expect(dimensions.sceneSize(fitting: .zero) == dimensions.size)
    #expect(dimensions.sceneSize(fitting: dimensions.size) == dimensions.size)
  }

  @Test @MainActor func sceneFitsRenderAreaToViewWithoutChangingCharacterScale() throws {
    let scene = CharacterScene()
    let dimensions = try CharacterAssetLoader.loadBundledDefault().renderDimensions
    for characterSize in CharacterSize.allCases {
      let view = characterSize.dimensions
      scene.fitRenderArea(to: view)
      #expect(scene.size == dimensions.sceneSize(fitting: view))
      let letterboxedScale = min(view.width / dimensions.width, view.height / dimensions.height)
      let fittedScale = min(view.width / scene.size.width, view.height / scene.size.height)
      #expect(abs(fittedScale - letterboxedScale) < 1e-9)
    }
  }

  @Test @MainActor func missingImageUsesProceduralLayerFallback() throws {
    let manifest = try decodeManifest(assetPath: "Characters/missing/head.png")
    let character = LayeredCharacterNode(
      manifest: manifest, assetLoader: CharacterAssetLoader.bundled)
    #expect(character.source(for: .head) == .proceduralFallback)
    #expect(!character.headRoot.children.isEmpty)
  }

  @Test @MainActor func bundledFullBodySpriteLoadsAndMissingSpriteCanFallBack() throws {
    let bundled = try CharacterAssetLoader.loadBundledDefault()
    #expect(
      FullBodyCharacterNode(manifest: bundled, assetLoader: .bundled) != nil)

    let missingJSON = """
      {
        "identifier": "dev.chibi.test",
        "displayName": "Missing Full Body",
        "renderDimensions": { "width": 210, "height": 250 },
        "renderingMode": "fullBody",
        "assets": { "fullBody": "Characters/missing/full-body.png" },
        "fullBodyLayout": {
          "position": { "x": 0, "y": 0 },
          "anchorPoint": { "x": 0.5, "y": 0.5 },
          "scale": 1
        },
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
    let missing = try JSONDecoder().decode(
      CharacterManifest.self, from: Data(missingJSON.utf8)
    ).validated()
    #expect(FullBodyCharacterNode(manifest: missing, assetLoader: .bundled) == nil)
    let layeredFallback = LayeredCharacterNode(manifest: missing, assetLoader: .bundled)
    #expect(layeredFallback.source(for: .head) == .proceduralFallback)
  }

  private func decodeManifest(assetPath: String, layers: String? = nil) throws
    -> CharacterManifest
  {
    let layerProperty = layers.map { ", \"layers\": \($0)" } ?? ""
    let json = """
      {
        "identifier": "dev.chibi.test",
        "displayName": "Test Character",
        "renderDimensions": { "width": 210, "height": 250 },
        "assets": { "head": "\(assetPath)" }\(layerProperty),
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
