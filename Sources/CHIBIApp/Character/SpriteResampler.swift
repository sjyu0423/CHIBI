import Accelerate
import CoreGraphics

/// High-quality downsampling for artwork drawn far below its native size. SpriteKit samples
/// textures bilinearly and ignores mipmaps for non-power-of-two textures, so thin lines and
/// highlights alias when a texture is minified by more than about 2×.
enum SpriteResampler {
  /// Lanczos-resamples premultiplied RGBA to `height` pixels, keeping the aspect ratio.
  static func resample(_ image: CGImage, toHeight height: Int) -> CGImage? {
    guard height > 0, image.height > 0 else { return nil }
    let width = max(1, Int((Double(image.width) * Double(height) / Double(image.height)).rounded()))
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let format = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)),
      var source = try? vImage_Buffer(cgImage: image, format: format)
    else {
      return nil
    }
    defer { source.free() }
    guard var destination = try? vImage_Buffer(width: width, height: height, bitsPerPixel: 32)
    else {
      return nil
    }
    defer { destination.free() }
    let error = vImageScale_ARGB8888(
      &source, &destination, nil, vImage_Flags(kvImageHighQualityResampling))
    guard error == kvImageNoError else { return nil }
    clampToAlpha(destination)
    return try? destination.createCGImage(format: format)
  }

  /// Lanczos overshoot can push a premultiplied color above its alpha near silhouette edges,
  /// which would draw as a bright fringe.
  private static func clampToAlpha(_ buffer: vImage_Buffer) {
    guard let base = buffer.data?.assumingMemoryBound(to: UInt8.self) else { return }
    for row in 0..<Int(buffer.height) {
      let pixels = base + row * buffer.rowBytes
      for column in 0..<Int(buffer.width) {
        let pixel = pixels + column * 4
        let alpha = pixel[3]
        pixel[0] = min(pixel[0], alpha)
        pixel[1] = min(pixel[1], alpha)
        pixel[2] = min(pixel[2], alpha)
      }
    }
  }
}
