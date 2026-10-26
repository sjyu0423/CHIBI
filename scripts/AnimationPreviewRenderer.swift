// Developer tool: renders deterministic animation frames from the real CHIBI character code.
// Built and run by scripts/render-animation-previews.sh; not part of the app target.
import AppKit
import Metal
import SpriteKit

extension Bundle {
  static var module: Bundle {
    guard
      let path = ProcessInfo.processInfo.environment["CHIBI_RESOURCE_BUNDLE"],
      let bundle = Bundle(path: path)
    else {
      fatalError("Set CHIBI_RESOURCE_BUNDLE to the built CHIBI_CHIBIApp.bundle")
    }
    return bundle
  }
}

@MainActor
struct OffscreenRenderer {
  let device: MTLDevice
  let queue: MTLCommandQueue
  let renderer: SKRenderer
  let texture: MTLTexture
  let width: Int
  let height: Int

  init(scene: SKScene, width: Int, height: Int) {
    device = MTLCreateSystemDefaultDevice()!
    queue = device.makeCommandQueue()!
    renderer = SKRenderer(device: device)
    renderer.scene = scene
    scene.isPaused = false
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.usage = [.renderTarget, .shaderRead]
    descriptor.storageMode = .shared
    texture = device.makeTexture(descriptor: descriptor)!
    self.width = width
    self.height = height
  }

  /// SKRenderer does not advance actions for timestamps near zero, so offset by a fixed base.
  static let timeBase: TimeInterval = 10_000

  func render(atTime time: TimeInterval, to url: URL) {
    renderer.update(atTime: Self.timeBase + time)
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    pass.colorAttachments[0].storeAction = .store
    let commands = queue.makeCommandBuffer()!
    renderer.render(
      withViewport: CGRect(x: 0, y: 0, width: width, height: height), commandBuffer: commands,
      renderPassDescriptor: pass)
    commands.commit()
    commands.waitUntilCompleted()

    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    texture.getBytes(
      &bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(
        rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! data.write(to: url)
  }
}

struct Clip {
  let name: String
  let duration: TimeInterval
  let expressive: Bool
  let start: @MainActor (CharacterScene) -> Void
}

@main
struct AnimationPreviewRenderer {
  static let framesPerSecond = 24.0
  static let overlay = CGSize(width: 210, height: 250)
  static let pixelScale = 2

  @MainActor static func main() {
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    if CommandLine.arguments.dropFirst(2).first == "display" {
      renderDisplayComparison(into: output)
      return
    }
    let clips: [Clip] = [
      Clip(name: "idle", duration: 6.4, expressive: true) { _ in },
      Clip(name: "idle-rigid", duration: 6.4, expressive: false) { _ in },
      Clip(name: "happy", duration: 1.6, expressive: true) { $0.reactToClick() },
      Clip(name: "sleep", duration: 8.5, expressive: true) { $0.previewAnimation(.sleep) },
      Clip(name: "walk", duration: 2.4, expressive: true) { $0.previewAnimation(.walk) },
      Clip(name: "sway-dance", duration: 3.52, expressive: true) { $0.previewAnimation(.dance) },
      Clip(name: "hop-dance", duration: 3.7, expressive: true) { $0.previewAnimation(.hopDance) },
      Clip(name: "dragging", duration: 2.2, expressive: true) { $0.beginDragging() },
    ]
    for clip in clips {
      renderClip(clip, into: output.appendingPathComponent("clips/\(clip.name)"))
    }
    renderWarpStills(into: output.appendingPathComponent("stills"))
  }

  @MainActor static func renderClip(_ clip: Clip, into directory: URL) {
    try? FileManager.default.removeItem(at: directory)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let scene = CharacterScene()
    scene.fitRenderArea(to: overlay, backingScale: CGFloat(pixelScale))
    scene.setExpressiveMotionEnabled(clip.expressive)
    let renderer = OffscreenRenderer(
      scene: scene, width: Int(overlay.width) * pixelScale, height: Int(overlay.height) * pixelScale)
    renderer.renderer.update(atTime: OffscreenRenderer.timeBase)
    clip.start(scene)
    let frames = Int((clip.duration * framesPerSecond).rounded())
    for frame in 0..<frames {
      let time = 1 / framesPerSecond + Double(frame) / framesPerSecond
      renderer.render(
        atTime: time, to: directory.appendingPathComponent(String(format: "%04d.png", frame)))
    }
    print("\(clip.name): \(frames) frames")
  }

  /// The resting character at each overlay preset, 1× and Retina 2×, for every display option.
  @MainActor static func renderDisplayComparison(into directory: URL) {
    try? FileManager.default.removeItem(at: directory)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let bundled = try! CharacterAssetLoader.loadBundledDefault()
    let variants = bundled.fullBodyDisplay?.variants
    let options: [(String, CharacterManifest.FullBodyDisplay)] = [
      ("original-direct", .standard),
      ("original-resampled", .init(sampling: .displayResampled, variant: "original", variants: nil)),
    ]
      + (variants ?? [:]).keys.sorted().map {
        ("\($0)-resampled", .init(sampling: .displayResampled, variant: $0, variants: variants))
      }
    for characterSize in CharacterSize.allCases {
      for backingScale in [1, 2] {
        for (name, display) in options {
          var manifest = bundled
          manifest.fullBodyDisplay = display
          let scene = CharacterScene(manifest: manifest, assetLoader: .bundled)
          let overlay = characterSize.dimensions
          scene.fitRenderArea(to: overlay, backingScale: CGFloat(backingScale))
          scene.setExpressiveMotionEnabled(false)
          let renderer = OffscreenRenderer(
            scene: scene, width: Int(overlay.width) * backingScale,
            height: Int(overlay.height) * backingScale)
          renderer.renderer.update(atTime: OffscreenRenderer.timeBase)
          renderer.render(
            atTime: 1 / framesPerSecond,
            to: directory.appendingPathComponent(
              "\(characterSize.rawValue)@\(backingScale)x-\(name).png"))
        }
      }
    }
    print("display: \(CharacterSize.allCases.count * 2 * options.count) stills")
  }

  /// Full-resolution warp extremes, for checking seams and distortion against the approved art.
  @MainActor static func renderWarpStills(into directory: URL) {
    try? FileManager.default.removeItem(at: directory)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let manifest = try! CharacterAssetLoader.loadBundledDefault()
    guard let node = FullBodyCharacterNode(manifest: manifest, assetLoader: .bundled) else {
      fatalError("Full-body sprite unavailable")
    }
    let texture = node.sprite.texture!.size()
    let scene = SKScene(size: CGSize(width: texture.width + 80, height: texture.height + 80))
    scene.backgroundColor = .clear
    scene.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    node.sprite.removeFromParent()
    node.sprite.setScale(1)
    node.sprite.position = .zero
    scene.addChild(node.sprite)
    let renderer = OffscreenRenderer(
      scene: scene, width: Int(scene.size.width), height: Int(scene.size.height))
    let stills: [(String, FullBodyExpression)] = [
      ("rest", .rest),
      ("tilt-left", FullBodyExpression(headTilt: 1)),
      ("tilt-right", FullBodyExpression(headTilt: -1)),
      ("hair-left", FullBodyExpression(hairSway: -1)),
      ("hair-right", FullBodyExpression(hairSway: 1)),
    ]
    for (index, (name, expression)) in stills.enumerated() {
      node.sprite.warpGeometry = node.warpGeometry(for: expression)
      renderer.render(
        atTime: Double(index), to: directory.appendingPathComponent("\(name).png"))
    }
    print("stills: \(stills.count)")
  }
}
