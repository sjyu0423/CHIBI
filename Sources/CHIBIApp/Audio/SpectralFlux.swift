import Accelerate

/// Onset-detection function: the mean rise in log-compressed magnitude per frequency bin between
/// overlapping Hann-windowed frames. Log compression makes it largely independent of playback
/// volume, and only rising bins count, so sustained tones and steady noise produce a low, flat
/// signal. The compression has a soft floor about 60 dB below full scale so sounds emerging from
/// digital silence do not dwarf everything else.
final class SpectralFlux {
  struct Value: Equatable, Sendable {
    /// Mean positive change per bin, 30 Hz–10 kHz, in decades of compressed magnitude.
    var broadband: Float
    /// Mean positive change per bin, 30–200 Hz (kick drums and bass notes).
    var bass: Float
  }

  let frameSize: Int
  private static let compression: Float = 1000
  private let log2n: vDSP_Length
  private let setup: FFTSetup
  private let window: [Float]
  private let normalization: Float
  private let broadbandBins: Range<Int>
  private let bassBins: Range<Int>
  private var windowed: [Float]
  private var real: [Float]
  private var imaginary: [Float]
  private var power: [Float]
  private var compressed: [Float]
  private var previous: [Float]
  private var hasPrevious = false

  init(frameSize: Int, sampleRate: Double) {
    precondition(frameSize >= 256 && frameSize.nonzeroBitCount == 1)
    self.frameSize = frameSize
    log2n = vDSP_Length(frameSize.trailingZeroBitCount)
    setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    window = vDSP.window(
      ofType: Float.self, usingSequence: .hanningDenormalized, count: frameSize,
      isHalfWindow: false)
    let half = frameSize / 2
    // vDSP's real FFT doubles amplitudes and a Hann window halves them, so a full-scale sine
    // peaks at frameSize / 2; normalize that to 1.
    normalization = 1 / Float(half)
    let binWidth = sampleRate / Double(frameSize)
    func bin(_ hertz: Double) -> Int { min(half - 1, max(1, Int((hertz / binWidth).rounded()))) }
    broadbandBins = bin(30)..<max(bin(30) + 1, bin(10_000))
    bassBins = bin(30)..<max(bin(30) + 1, bin(200))
    windowed = [Float](repeating: 0, count: frameSize)
    real = [Float](repeating: 0, count: half)
    imaginary = [Float](repeating: 0, count: half)
    power = [Float](repeating: 0, count: half)
    compressed = [Float](repeating: 0, count: half)
    previous = compressed
  }

  deinit {
    vDSP_destroy_fftsetup(setup)
  }

  func reset() {
    hasPrevious = false
  }

  func process(_ frame: [Float]) -> Value {
    precondition(frame.count == frameSize)
    let half = frameSize / 2
    vDSP.multiply(frame, window, result: &windowed)
    real.withUnsafeMutableBufferPointer { real in
      imaginary.withUnsafeMutableBufferPointer { imaginary in
        power.withUnsafeMutableBufferPointer { power in
          var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
          windowed.withUnsafeBytes { bytes in
            vDSP_ctoz(
              bytes.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1,
              vDSP_Length(half))
          }
          vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
          vDSP_zvmags(&split, 1, power.baseAddress!, 1, vDSP_Length(half))
        }
      }
    }
    vForce.sqrt(power, result: &compressed)
    vDSP.multiply(normalization * Self.compression, compressed, result: &compressed)
    vDSP.add(1, compressed, result: &compressed)
    vForce.log10(compressed, result: &compressed)

    defer {
      swap(&previous, &compressed)
      hasPrevious = true
    }
    guard hasPrevious else { return Value(broadband: 0, bass: 0) }
    return Value(broadband: meanRise(over: broadbandBins), bass: meanRise(over: bassBins))
  }

  private func meanRise(over bins: Range<Int>) -> Float {
    var total: Float = 0
    for bin in bins {
      total += max(0, compressed[bin] - previous[bin])
    }
    return total / Float(bins.count)
  }
}
