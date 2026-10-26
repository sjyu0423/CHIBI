import CoreGraphics
import Foundation

struct CharacterManifest: Codable, Equatable, Sendable {
  struct RenderDimensions: Codable, Equatable, Sendable {
    let width: Double
    let height: Double

    var size: CGSize { CGSize(width: width, height: height) }
  }

  struct AssetReferences: Codable, Equatable, Sendable {
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
    var mouth: String?
    var hairFront: String?

    var allFiles: [String] {
      [
        hairBack, leftLeg, rightLeg, torso, leftArm, rightArm, head, face, leftEye, rightEye,
        mouth, hairFront,
      ]
      .compactMap { $0 }
    }
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
  let assets: AssetReferences
  let animations: AnimationConfiguration

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
    return self
  }
}

enum CharacterManifestError: Error, Equatable {
  case missingIdentifier
  case invalidRenderDimensions
  case missingBundledManifest(String)
  case unsafeAssetPath(String)
  case unsupportedAssetFormat(String)
  case unreadableAsset(String)
}
