import Accelerate

/// Averages multichannel Float32 PCM to mono.
enum AudioDownmix {
  static func mono(planar channels: [UnsafeBufferPointer<Float>]) -> [Float] {
    guard let first = channels.first else { return [] }
    let frames = channels.map(\.count).min() ?? 0
    var mono = Array(first.prefix(frames))
    for channel in channels.dropFirst() {
      vDSP.add(mono, UnsafeBufferPointer(rebasing: channel.prefix(frames)), result: &mono)
    }
    if channels.count > 1 {
      vDSP.multiply(1 / Float(channels.count), mono, result: &mono)
    }
    return mono
  }

  static func mono(interleaved samples: UnsafeBufferPointer<Float>, channels: Int) -> [Float] {
    guard channels > 0, let base = samples.baseAddress else { return [] }
    let frames = samples.count / channels
    var mono = [Float](repeating: 0, count: frames)
    guard frames > 0 else { return mono }
    mono.withUnsafeMutableBufferPointer { output in
      guard let sum = output.baseAddress else { return }
      for channel in 0..<channels {
        vDSP_vadd(
          base + channel, vDSP_Stride(channels), sum, 1, sum, 1, vDSP_Length(frames))
      }
    }
    if channels > 1 {
      vDSP.multiply(1 / Float(channels), mono, result: &mono)
    }
    return mono
  }
}
