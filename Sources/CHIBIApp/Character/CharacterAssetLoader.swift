import AppKit
import Foundation
import ImageIO
import SpriteKit

struct CharacterAssetLoader {
  private let bundle: Bundle

  static var bundled: CharacterAssetLoader {
    CharacterAssetLoader(bundle: .module)
  }

  init(bundle: Bundle) {
    self.bundle = bundle
  }

  static func loadBundledDefault() throws -> CharacterManifest {
    try bundled.loadManifest(named: "sleepy-coder")
  }

  func loadManifest(named name: String) throws -> CharacterManifest {
    guard let url = bundle.url(forResource: name, withExtension: "json") else {
      throw CharacterManifestError.missingBundledManifest(name)
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(CharacterManifest.self, from: data).validated()
  }

  func texture(named path: String) throws -> SKTexture {
    let url = try assetURL(named: path)
    guard let image = NSImage(contentsOf: url) else {
      throw CharacterManifestError.unreadableAsset(path)
    }
    return SKTexture(image: image)
  }

  func image(named path: String) throws -> CGImage {
    let url = try assetURL(named: path)
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw CharacterManifestError.unreadableAsset(path)
    }
    return image
  }

  func assetURL(named path: String) throws -> URL {
    let file = path as NSString
    let subdirectory = file.deletingLastPathComponent
    let resource = (file.lastPathComponent as NSString).deletingPathExtension
    let directory = subdirectory == "." ? nil : subdirectory
    guard
      let url = bundle.url(
        forResource: resource, withExtension: file.pathExtension, subdirectory: directory)
    else {
      throw CharacterManifestError.unreadableAsset(path)
    }
    return url
  }
}
