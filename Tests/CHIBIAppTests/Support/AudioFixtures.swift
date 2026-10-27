import Foundation

@testable import CHIBIApp

/// Deterministic synthetic audio for analyzer tests. Nothing here is recorded material.
enum AudioFixtures {
  static let sampleRate = 48_000.0

  struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
      state = seed
    }

    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var value = state
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      return value ^ (value >> 31)
    }
  }

  static func silence(seconds: Double) -> [Float] {
    [Float](repeating: 0, count: frames(seconds))
  }

  /// Sustained chord with no attacks after the first note.
  static func pad(seconds: Double, amplitude: Float) -> [Float] {
    let count = frames(seconds)
    let fade = frames(0.05)
    return (0..<count).map { index in
      let time = Double(index) / sampleRate
      let tone =
        sin(2 * .pi * 220 * time) + sin(2 * .pi * 277.2 * time) + sin(2 * .pi * 329.6 * time)
      let ramp = Float(min(1, Double(min(index, count - index)) / Double(fade)))
      return amplitude * ramp * Float(tone / 3)
    }
  }

  static func noise(seconds: Double, amplitude: Float, seed: UInt64 = 1) -> [Float] {
    var generator = SeededGenerator(seed: seed)
    return (0..<frames(seconds)).map { _ in amplitude * Float.random(in: -1...1, using: &generator)
    }
  }

  /// Kick on every beat, optional hi-hats between beats, over a quiet pad.
  static func drumLoop(
    bpm: Double, seconds: Double, amplitude: Float = 0.5, hats: Bool = true, seed: UInt64 = 2
  ) -> [Float] {
    var samples = pad(seconds: seconds, amplitude: amplitude * 0.15)
    let period = 60 / bpm
    var generator = SeededGenerator(seed: seed)
    var beat = 0.0
    while beat < seconds {
      addKick(to: &samples, at: beat, amplitude: amplitude)
      if hats {
        addBurst(
          to: &samples, at: beat + period / 2, duration: 0.03, amplitude: amplitude * 0.2,
          highPass: true, generator: &generator)
      }
      beat += period
    }
    return samples
  }

  /// A denser, humanized groove: kicks on 1 and 3 plus a syncopated kick, snares on 2 and 4,
  /// eighth-note hats, a moving bass line, and a noise bed, with up to ±10 ms timing jitter.
  static func bandLoop(bpm: Double, seconds: Double, amplitude: Float = 0.4, seed: UInt64 = 4)
    -> [Float]
  {
    var generator = SeededGenerator(seed: seed)
    var samples = noise(seconds: seconds, amplitude: amplitude * 0.04, seed: seed + 100)
    let chord = pad(seconds: seconds, amplitude: amplitude * 0.2)
    for index in samples.indices { samples[index] += chord[index] }
    let period = 60 / bpm
    let bassNotes = [55.0, 55.0, 65.4, 49.0]
    var beat = 0
    while Double(beat) * period < seconds {
      func jitter() -> Double { Double.random(in: -0.01...0.01, using: &generator) }
      let time = Double(beat) * period
      switch beat % 4 {
      case 0, 2:
        addKick(to: &samples, at: time + jitter(), amplitude: amplitude)
      default:
        addBurst(
          to: &samples, at: time + jitter(), duration: 0.12, amplitude: amplitude * 0.6,
          generator: &generator)
      }
      if beat % 8 == 6 {
        addKick(to: &samples, at: time + period * 0.5 + jitter(), amplitude: amplitude * 0.7)
      }
      for eighth in 0..<2 {
        addBurst(
          to: &samples, at: time + Double(eighth) * period / 2 + jitter(), duration: 0.03,
          amplitude: amplitude * 0.15, highPass: true, generator: &generator)
      }
      addTone(
        to: &samples, at: time, duration: period * 0.9,
        frequency: bassNotes[(beat / 4) % bassNotes.count], amplitude: amplitude * 0.25)
      beat += 1
    }
    return samples
  }

  /// Clicks at random intervals with random strengths: loud, but with no steady pulse.
  static func irregularTransients(
    seconds: Double, perSecond rate: Double, amplitude: Float = 0.5, seed: UInt64 = 3
  ) -> [Float] {
    var samples = pad(seconds: seconds, amplitude: amplitude * 0.15)
    var generator = SeededGenerator(seed: seed)
    var time = 0.1
    while time < seconds {
      let strength = Float.random(in: 0.4...1, using: &generator)
      if Bool.random(using: &generator) {
        addKick(to: &samples, at: time, amplitude: amplitude * strength)
      } else {
        addBurst(
          to: &samples, at: time, duration: 0.05, amplitude: amplitude * strength,
          generator: &generator)
      }
      let uniform = Double.random(in: 0.0001...1, using: &generator)
      time += max(0.1, -log(uniform) / rate)
    }
    return samples
  }

  static func chunks(_ samples: [Float], size: Int = 960) -> [AudioChunk] {
    stride(from: 0, to: samples.count, by: size).map { start in
      AudioChunk(
        samples: Array(samples[start..<min(samples.count, start + size)]), sampleRate: sampleRate)
    }
  }

  static func analyze(
    _ samples: [Float], chunkSize: Int = 960,
    configuration: AudioAnalysisConfiguration = .init()
  ) -> [AudioFeatures] {
    let analyzer = AudioFeatureAnalyzer(sampleRate: sampleRate, configuration: configuration)
    return chunks(samples, size: chunkSize).flatMap { analyzer.process($0) }
  }

  private static func frames(_ seconds: Double) -> Int {
    Int(max(0, seconds) * sampleRate)
  }

  private static func addKick(to samples: inout [Float], at time: Double, amplitude: Float) {
    let start = frames(time)
    var phase = 0.0
    for offset in 0..<frames(0.18) where start + offset < samples.count {
      let elapsed = Double(offset) / sampleRate
      phase += 2 * .pi * (50 + 90 * exp(-elapsed * 30)) / sampleRate
      samples[start + offset] += amplitude * Float(exp(-elapsed * 18) * sin(phase))
    }
  }

  private static func addTone(
    to samples: inout [Float], at time: Double, duration: Double, frequency: Double,
    amplitude: Float
  ) {
    let start = frames(time)
    let length = frames(duration)
    let edge = Double(frames(0.01))
    for offset in 0..<length where start + offset < samples.count {
      let ramp = min(1, Double(min(offset, length - offset)) / edge)
      let phase = 2 * .pi * frequency * Double(offset) / sampleRate
      samples[start + offset] += amplitude * Float(ramp * sin(phase))
    }
  }

  private static func addBurst(
    to samples: inout [Float], at time: Double, duration: Double, amplitude: Float,
    highPass: Bool = false, generator: inout SeededGenerator
  ) {
    let start = frames(time)
    let length = frames(duration)
    var previous: Float = 0
    for offset in 0..<length where start + offset < samples.count {
      let decay = Float(exp(-Double(offset) / Double(length) * 4))
      let white = Float.random(in: -1...1, using: &generator)
      let value = highPass ? (white - previous) / 2 : white
      previous = white
      samples[start + offset] += amplitude * decay * value
    }
  }
}
