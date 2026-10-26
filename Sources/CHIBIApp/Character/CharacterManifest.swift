import CoreGraphics
import Foundation

struct CharacterManifest: Codable, Equatable, Sendable {
  enum RenderingMode: String, Codable, Sendable {
    case layered
    case fullBody
  }

  enum Layer: String, Codable, CaseIterable, Sendable {
    case shadow
    case hairBack
    case leftLeg
    case rightLeg
    case torso
    case leftArm
    case rightArm
    case head
    case face
    case leftEye
    case rightEye
    case mouth
    case hairFront
  }

  struct Point: Codable, Equatable, Sendable {
    let x: Double
    let y: Double

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
  }

  struct LayerLayout: Codable, Equatable, Sendable {
    let layer: Layer
    let position: Point
    let anchorPoint: Point
    let drawOrder: Int
    let scale: Double
    let animationAnchorPoint: Point?

    var effectiveAnchorPoint: CGPoint {
      (animationAnchorPoint ?? anchorPoint).cgPoint
    }
  }

  struct RenderDimensions: Codable, Equatable, Sendable {
    let width: Double
    let height: Double

    var size: CGSize { CGSize(width: width, height: height) }

    /// Expands the render area to the view's aspect ratio so `.aspectFit` never letterboxes.
    /// SKView paints letterbox bars opaque black even when it allows transparency.
    func sceneSize(fitting viewSize: CGSize) -> CGSize {
      guard viewSize.width > 0, viewSize.height > 0 else { return size }
      let viewAspect = viewSize.width / viewSize.height
      if viewAspect < width / height {
        return CGSize(width: width, height: width / viewAspect)
      }
      return CGSize(width: height * viewAspect, height: height)
    }
  }

  struct AssetReferences: Codable, Equatable, Sendable {
    var fullBody: String?
    var hairBack: String?
    var leftLeg: String?
    var rightLeg: String?
    var torso: String?
    var leftArm: String?
    var rightArm: String?
    var head: String?
    var face: String?
    var leftEye: String?
    var rightEye: String?
    var leftEyeClosed: String?
    var rightEyeClosed: String?
    var mouth: String?
    var mouthHappy: String?
    var mouthSleep: String?
    var hairFront: String?

    var allFiles: [String] {
      [
        fullBody, hairBack, leftLeg, rightLeg, torso, leftArm, rightArm, head, face, leftEye,
        rightEye,
        leftEyeClosed, rightEyeClosed, mouth, mouthHappy, mouthSleep, hairFront,
      ]
      .compactMap { $0 }
    }
  }

  struct FullBodyLayout: Codable, Equatable, Sendable {
    let position: Point
    let anchorPoint: Point
    let scale: Double
  }

  struct AnimationConfiguration: Codable, Equatable, Sendable {
    let idleBobHeight: Double
    let idleCycleDuration: Double
    let blinkMinimumDelay: Double
    let blinkDelayVariation: Double
    let happyHopHeight: Double
    let walkStepDuration: Double
    let danceBeatDuration: Double
    let sleepSwayDuration: Double

    static let standard = AnimationConfiguration(
      idleBobHeight: 3.5,
      idleCycleDuration: 2.4,
      blinkMinimumDelay: 2.0,
      blinkDelayVariation: 2.4,
      happyHopHeight: 18,
      walkStepDuration: 0.28,
      danceBeatDuration: 0.42,
      sleepSwayDuration: 2.8
    )
  }

  let identifier: String
  let displayName: String
  let renderDimensions: RenderDimensions
  var renderingMode: RenderingMode?
  let assets: AssetReferences
  var fullBodyLayout: FullBodyLayout?
  var layers: [LayerLayout]?
  let animations: AnimationConfiguration

  var resolvedRenderingMode: RenderingMode {
    renderingMode ?? .layered
  }

  var resolvedLayers: [LayerLayout] {
    layers ?? Self.proceduralLayerLayouts
  }

  func validated() throws -> CharacterManifest {
    guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CharacterManifestError.missingIdentifier
    }
    guard renderDimensions.width > 0, renderDimensions.height > 0 else {
      throw CharacterManifestError.invalidRenderDimensions
    }
    for file in assets.allFiles {
      let path = file as NSString
      guard !path.isAbsolutePath, !path.pathComponents.contains("..") else {
        throw CharacterManifestError.unsafeAssetPath(file)
      }
      guard path.pathExtension.lowercased() == "png" else {
        throw CharacterManifestError.unsupportedAssetFormat(file)
      }
    }
    if resolvedRenderingMode == .fullBody, assets.fullBody == nil {
      throw CharacterManifestError.missingFullBodyAsset
    }
    if let layout = fullBodyLayout {
      guard
        layout.position.x.isFinite, layout.position.y.isFinite,
        layout.anchorPoint.x.isFinite, layout.anchorPoint.y.isFinite,
        (0...1).contains(layout.anchorPoint.x), (0...1).contains(layout.anchorPoint.y),
        layout.scale.isFinite, layout.scale > 0
      else {
        throw CharacterManifestError.invalidFullBodyLayout
      }
    }
    if let layers {
      guard Set(layers.map(\.layer)).count == layers.count else {
        throw CharacterManifestError.duplicateLayer
      }
      guard Set(layers.map(\.drawOrder)).count == layers.count else {
        throw CharacterManifestError.duplicateDrawOrder
      }
      for layout in layers {
        guard
          layout.position.x.isFinite, layout.position.y.isFinite,
          layout.anchorPoint.x.isFinite, layout.anchorPoint.y.isFinite,
          (0...1).contains(layout.anchorPoint.x), (0...1).contains(layout.anchorPoint.y),
          layout.scale.isFinite, layout.scale > 0
        else {
          throw CharacterManifestError.invalidLayerLayout(layout.layer)
        }
        if let anchor = layout.animationAnchorPoint {
          guard
            anchor.x.isFinite, anchor.y.isFinite,
            (0...1).contains(anchor.x), (0...1).contains(anchor.y)
          else {
            throw CharacterManifestError.invalidLayerLayout(layout.layer)
          }
        }
      }
    }
    return self
  }

  func layout(for layer: Layer) -> LayerLayout {
    if let configured = layers?.first(where: { $0.layer == layer }) {
      return configured
    }
    let fallback = Self.proceduralLayerLayouts.first(where: { $0.layer == layer })!
    guard layers == nil else { return fallback }
    return LayerLayout(
      layer: fallback.layer,
      position: Point(
        x: fallback.position.x * renderDimensions.width / 210,
        y: fallback.position.y * renderDimensions.height / 250
      ),
      anchorPoint: fallback.anchorPoint,
      drawOrder: fallback.drawOrder,
      scale: fallback.scale,
      animationAnchorPoint: fallback.animationAnchorPoint
    )
  }

  static let proceduralLayerLayouts: [LayerLayout] = [
    layout(.shadow, 0, -104, -10),
    layout(.hairBack, 0, 35, 0),
    layout(.leftLeg, -22, -88, 10),
    layout(.rightLeg, 22, -88, 11),
    layout(.torso, 0, -55, 20),
    layout(.leftArm, -46, -55, 30),
    layout(.rightArm, 46, -55, 31),
    layout(.head, 0, 34, 40),
    layout(.face, 0, 0, 50),
    layout(.leftEye, -31, 31, 60),
    layout(.rightEye, 31, 31, 61),
    layout(.mouth, 0, 7, 70),
    layout(.hairFront, 0, 74, 80),
  ]

  private static func layout(
    _ layer: Layer, _ x: Double, _ y: Double, _ drawOrder: Int
  ) -> LayerLayout {
    LayerLayout(
      layer: layer,
      position: Point(x: x, y: y),
      anchorPoint: Point(x: 0.5, y: 0.5),
      drawOrder: drawOrder,
      scale: 1,
      animationAnchorPoint: nil
    )
  }
}

enum CharacterManifestError: Error, Equatable {
  case missingIdentifier
  case invalidRenderDimensions
  case missingBundledManifest(String)
  case unsafeAssetPath(String)
  case unsupportedAssetFormat(String)
  case unreadableAsset(String)
  case missingFullBodyAsset
  case invalidFullBodyLayout
  case duplicateLayer
  case duplicateDrawOrder
  case invalidLayerLayout(CharacterManifest.Layer)
}
