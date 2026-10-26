import AppKit
import Foundation
import SpriteKit

struct CharacterAssetLoader {
  private let bundle: Bundle

  init(bundle: Bundle) {
    self.bundle = bundle
  }

  static func loadBundledDefault() throws -> CharacterManifest {
    try CharacterAssetLoader(bundle: .module).loadManifest(named: "temporary-character")
  }

  func loadManifest(named name: String) throws -> CharacterManifest {
    guard let url = bundle.url(forResource: name, withExtension: "json") else {
      throw CharacterManifestError.missingBundledManifest(name)
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(CharacterManifest.self, from: data).validated()
  }

  func texture(named path: String) throws -> SKTexture {
    let file = path as NSString
    let subdirectory = file.deletingLastPathComponent
    let resource = (file.lastPathComponent as NSString).deletingPathExtension
    let directory = subdirectory == "." ? nil : subdirectory
    guard
      let url = bundle.url(
        forResource: resource, withExtension: file.pathExtension, subdirectory: directory),
      let image = NSImage(contentsOf: url)
    else {
      throw CharacterManifestError.unreadableAsset(path)
    }
    return SKTexture(image: image)
  }
}
