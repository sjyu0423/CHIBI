import Foundation
import simd

/// Seamless deformation of the single full-body sprite. Vertices are row-major from the bottom-left
/// in normalized sprite coordinates, matching `SKWarpGeometryGrid`.
enum FullBodyWarp {
  static let columns = 8
  static let rows = 16
  static var vertexCount: Int { (columns + 1) * (rows + 1) }

  static func sourcePositions() -> [SIMD2<Float>] {
    (0...rows).flatMap { row in
      (0...columns).map { column in
        SIMD2(Float(column) / Float(columns), Float(row) / Float(rows))
      }
    }
  }

  /// `aspect` is the sprite's width divided by its height, so rotation stays rigid in pixels.
  static func destinationPositions(
    rig: CharacterManifest.FullBodyRig, expression: FullBodyExpression, aspect: Double
  ) -> [SIMD2<Float>] {
    let angle = expression.headTilt * rig.maxHeadTilt
    let sway = expression.hairSway * rig.maxHairSway
    let tipFade = 0.05
    return sourcePositions().map { vertex in
      var x = Double(vertex.x)
      var y = Double(vertex.y)

      let hairWeight =
        y < rig.hairTipY
        ? smoothstep((y - (rig.hairTipY - tipFade)) / tipFade)
        : 1 - smoothstep((y - rig.hairTipY) / (rig.hairRootY - rig.hairTipY))
      let sideWeight = smoothstep((abs(x - 0.5) * 2 - 0.45) / 0.55)
      x += sway * hairWeight * sideWeight

      let tiltWeight = smoothstep((y - (rig.neck.y - rig.headBlendHeight)) / rig.headBlendHeight)
      let theta = angle * tiltWeight
      if theta != 0 {
        let dx = (x - rig.neck.x) * aspect
        let dy = y - rig.neck.y
        x = rig.neck.x + (dx * cos(theta) - dy * sin(theta)) / aspect
        y = rig.neck.y + dx * sin(theta) + dy * cos(theta)
      }
      return SIMD2(Float(x), Float(y))
    }
  }

  private static func smoothstep(_ value: Double) -> Double {
    let t = min(max(value, 0), 1)
    return t * t * (3 - 2 * t)
  }
}
