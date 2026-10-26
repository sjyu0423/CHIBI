import AppKit
import SpriteKit
import Testing

@testable import CHIBIApp

struct FullBodyDisplayTests {
  private static let original = "Characters/sleepy-coder/full-body.png"
  private static let soft = "Characters/sleepy-coder/full-body-soft.png"

  @Test func bundledManifestSelectsResampledSoftVariantWithOriginalFallback() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    let display = manifest.resolvedFullBodyDisplay
    #expect(display.sampling == .displayResampled)
    #expect(display.variant == "soft")
    #expect(manifest.fullBodyImageCandidates == [Self.soft, Self.original])
    #expect(manifest.allAssetFiles.contains(Self.soft))
  }

  @Test func manifestsWithoutDisplaySettingsDrawTheOriginalDirectly() throws {
    let manifest = try decodeManifest(display: nil)
    #expect(manifest.resolvedFullBodyDisplay == .standard)
    #expect(manifest.fullBodyImageCandidates == [Self.original])

    let reverted = try decodeManifest(
      display: """
        { "sampling": "displayResampled", "variant": "original",
          "variants": { "soft": "\(Self.soft)" } }
        """)
    #expect(reverted.fullBodyImageCandidates == [Self.original])
  }

  @Test func invalidDisplaySettingsAreRejected() throws {
    let unknownVariant = try decodeManifest(
      display: #"{ "sampling": "direct", "variant": "missing" }"#)
    #expect(throws: CharacterManifestError.invalidFullBodyDisplay) {
      try unknownVariant.validated()
    }
    let shadowsOriginal = try decodeManifest(
      display: """
        { "sampling": "direct", "variant": "original",
          "variants": { "original": "\(Self.soft)" } }
        """)
    #expect(throws: CharacterManifestError.invalidFullBodyDisplay) {
      try shadowsOriginal.validated()
    }
    let unsafe = try decodeManifest(
      display: #"{ "sampling": "direct", "variant": "a", "variants": { "a": "../a.png" } }"#)
    #expect(throws: CharacterManifestError.unsafeAssetPath("../a.png")) {
      try unsafe.validated()
    }
    let jpeg = try decodeManifest(
      display: #"{ "sampling": "direct", "variant": "a", "variants": { "a": "a.jpeg" } }"#)
    #expect(throws: CharacterManifestError.unsupportedAssetFormat("a.jpeg")) {
      try jpeg.validated()
    }
  }

  @Test @MainActor func missingVariantFallsBackToTheOriginalImage() throws {
    let manifest = try decodeManifest(
      display: """
        { "sampling": "displayResampled", "variant": "gone",
          "variants": { "gone": "Characters/missing/full-body-soft.png" } }
        """
    ).validated()
    let node = try #require(FullBodyCharacterNode(manifest: manifest, assetLoader: .bundled))
    #expect(node.imagePath == Self.original)
  }

  @Test func softVariantOnlyChangesHairAndKeepsDimensionsAndAlpha() throws {
    let original = try rgba(Self.original)
    let soft = try rgba(Self.soft)
    #expect(original.width == soft.width && original.height == soft.height)
    var alphaMatches = true
    var protectedMatches = true
    var changedPixels = 0
    let eyeBoxes = [(200, 538, 376, 684), (528, 533, 706, 684)]
    let hairLimit = Int(Double(original.height) * 0.555)
    for y in 0..<original.height {
      for x in 0..<original.width {
        let index = (y * original.width + x) * 4
        if original.bytes[index + 3] != soft.bytes[index + 3] { alphaMatches = false }
        let same = (0..<3).allSatisfy { original.bytes[index + $0] == soft.bytes[index + $0] }
        if !same { changedPixels += 1 }
        let isProtected =
          y >= hairLimit
          || eyeBoxes.contains { x >= $0.0 && x < $0.2 && y >= $0.1 && y < $0.3 }
        if isProtected, !same { protectedMatches = false }
      }
    }
    #expect(alphaMatches, "soft variant changed alpha")
    #expect(protectedMatches, "soft variant changed eyes or pixels below the hair")
    let changedFraction = Double(changedPixels) / Double(original.width * original.height)
    #expect(changedFraction > 0.02 && changedFraction < 0.15)
  }

  @Test func resamplerProducesValidPremultipliedPixelsAtTheRequestedHeight() throws {
    let source = try CharacterAssetLoader.bundled.image(named: Self.original)
    let image = try #require(SpriteResampler.resample(source, toHeight: 430))
    #expect(image.height == 430)
    #expect(image.width == Int((Double(source.width) * 430 / Double(source.height)).rounded()))
    let pixels = try #require(premultipliedBytes(image))
    var colorAboveAlpha = 0
    var opaque = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let alpha = pixels[index + 3]
      if pixels[index] > alpha || pixels[index + 1] > alpha || pixels[index + 2] > alpha {
        colorAboveAlpha += 1
      }
      if alpha == 255 { opaque += 1 }
    }
    #expect(colorAboveAlpha == 0)
    #expect(opaque > image.width * image.height / 3)
    let rowBytes = image.width * 4
    let edgeAlpha = stride(from: 3, to: rowBytes, by: 4).flatMap {
      [pixels[$0], pixels[pixels.count - rowBytes + $0]]
    }
    #expect((edgeAlpha.max() ?? 0) <= 16, "artwork must not reach the texture edge")
  }

  @Test @MainActor func resampledTextureMatchesOnScreenPixelsForEveryPreset() throws {
    let scene = CharacterScene()
    let node = try #require(scene.childNode(withName: "character-root") as? FullBodyCharacterNode)
    let spriteSize = node.sprite.size
    let frame = node.sprite.frame
    let source = try CharacterAssetLoader.bundled.image(named: node.imagePath)
    for characterSize in CharacterSize.allCases {
      for backingScale in [1.0, 2.0] {
        let view = characterSize.dimensions
        scene.fitRenderArea(to: view, backingScale: backingScale)
        let onScreen = node.spriteHeight * view.height / scene.size.height * backingScale
        #expect(node.textureHeight == Int(onScreen.rounded(.up)))
        #expect(node.textureHeight < source.height / 2)
        #expect(node.sprite.texture?.size().height == CGFloat(node.textureHeight))
        #expect(node.sprite.size == spriteSize)
        #expect(node.sprite.frame == frame)
      }
    }
  }

  @Test @MainActor func directSamplingKeepsTheFullResolutionTexture() throws {
    var manifest = try CharacterAssetLoader.loadBundledDefault()
    manifest.fullBodyDisplay = .standard
    let scene = CharacterScene(manifest: manifest, assetLoader: .bundled)
    let node = try #require(scene.childNode(withName: "character-root") as? FullBodyCharacterNode)
    scene.fitRenderArea(to: CharacterSize.small.dimensions, backingScale: 1)
    #expect(node.imagePath == Self.original)
    #expect(node.textureHeight == 1599)
  }

  @Test @MainActor func overlayViewResamplesForItsWindowBackingScale() throws {
    let size = CharacterSize.medium.dimensions
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
      backing: .buffered, defer: false)
    let view = CharacterView(frame: CGRect(origin: .zero, size: size))
    window.contentView = view
    let scene = CharacterScene()
    view.presentScene(scene)
    let node = try #require(scene.childNode(withName: "character-root") as? FullBodyCharacterNode)
    let expected =
      node.spriteHeight * size.height / scene.size.height * window.backingScaleFactor
    #expect(node.textureHeight == Int(expected.rounded(.up)))

    view.setFrameSize(CharacterSize.large.dimensions)
    let large =
      node.spriteHeight * CharacterSize.large.dimensions.height / scene.size.height
      * window.backingScaleFactor
    #expect(node.textureHeight == Int(large.rounded(.up)))
  }

  private func rgba(_ path: String) throws -> (width: Int, height: Int, bytes: [UInt8]) {
    let url = try CharacterAssetLoader.bundled.assetURL(named: path)
    let representation = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
    #expect(representation.samplesPerPixel == 4 && representation.bitsPerSample == 8)
    #expect(!representation.bitmapFormat.contains(.alphaFirst))
    let width = representation.pixelsWide
    let height = representation.pixelsHigh
    let data = try #require(representation.bitmapData)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<(width * 4) {
        bytes[y * width * 4 + x] = data[y * representation.bytesPerRow + x]
      }
    }
    return (width, height, bytes)
  }

  private func premultipliedBytes(_ image: CGImage) -> [UInt8]? {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: image.width * 4,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return true
    }
    return drawn ? bytes : nil
  }

  private func decodeManifest(display: String?) throws -> CharacterManifest {
    let displayProperty = display.map { ", \"fullBodyDisplay\": \($0)" } ?? ""
    let json = """
      {
        "identifier": "dev.chibi.test",
        "displayName": "Display Test",
        "renderDimensions": { "width": 640, "height": 760 },
        "renderingMode": "fullBody",
        "assets": { "fullBody": "\(Self.original)" },
        "fullBodyLayout": {
          "position": { "x": 0, "y": -24 },
          "anchorPoint": { "x": 0.5, "y": 0.5 },
          "scale": 0.41
        }\(displayProperty),
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
