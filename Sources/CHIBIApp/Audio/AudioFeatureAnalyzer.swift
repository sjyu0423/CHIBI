import Accelerate
import Foundation

/// Per-hop audio description (~21 ms at 48 kHz). Contains no audio, only measurements.
struct AudioFeatures: Equatable, Sendable {
  /// Seconds of audio analyzed since the analyzer started.
  var time: TimeInterval
  /// RMS level of the hop, dBFS.
  var level: Double
  /// Level smoothed with a fast attack and slow release, dBFS.
  var envelope: Double
  /// Strength of the onset detected at this hop relative to recent strong onsets, 0–1.
  var onsetStrength: Double
  var isOnset: Bool
  /// Strength of a beat accepted on the tempo grid at this hop.
  var beatStrength: Double?
  /// Present only once tempo estimates have agreed for a while.
  var tempo: TempoEstimate?
  /// Recent onset activity, 0–1 (about four strong onsets per second is 1).
  var pulse: Double
  var isActive: Bool
  /// Smoothed overall drive combining loudness, onset activity, and rhythmic regularity, 0–1.
  var intensity: Double
}

struct AudioAnalysisConfiguration: Equatable, Sendable {
  /// Shifts every loudness threshold; negative values react to quieter audio.
  var loudnessOffsetDB: Double = 0
}

/// Lightweight, deterministic analysis of mono audio: RMS energy, a smoothed envelope, spectral
/// flux onsets with an adaptive threshold, autocorrelation tempo, beats on the tempo grid, and
/// activity with hysteresis. Not thread-safe; `AudioAnalysisPipeline` serializes access.
///
/// Onsets are reported one hop (~21 ms) after they occur because peak picking needs the next
/// value; beats inherit that delay.
final class AudioFeatureAnalyzer {
  static let hopSize = 1024
  static let frameSize = 2048
  static let activeThresholdDB = -55.0
  static let inactiveThresholdDB = -62.0
  static let quietLoudnessDB = -46.0
  static let loudLoudnessDB = -12.0
  static let refractoryPeriod: TimeInterval = 0.09
  static let activityWindow: TimeInterval = 0.5
  static let thresholdWindow: TimeInterval = 1.5
  static let tempoResetDelay: TimeInterval = 1
  /// Time constants for onset activity and overall intensity.
  static let pulseSmoothing: TimeInterval = 1.5
  static let intensitySmoothing: TimeInterval = 0.6
  private static let minimumOnsetRise: Float = 0.02
  private static let minimumOnsetStrength = 0.12

  var configuration: AudioAnalysisConfiguration
  private(set) var sampleRate: Double
  private var flux: SpectralFlux
  private var tempo: TempoTracker
  private var grid = BeatGrid()
  private var frame = [Float](repeating: 0, count: frameSize)
  private var pending: [Float] = []
  private var hops = 0
  private var envelope: Float = 0
  private var recentPower: [Float] = []
  private var onsetHistory: [Float] = []
  private var recentPeak: Float = 0
  private var lastOnsetTime = -Double.infinity
  private var isActive = false
  private var inactiveDuration: TimeInterval = 0
  private var drive = 0.0
  private var intensity = 0.0

  init(sampleRate: Double = 48_000, configuration: AudioAnalysisConfiguration = .init()) {
    self.sampleRate = sampleRate
    self.configuration = configuration
    flux = SpectralFlux(frameSize: Self.frameSize, sampleRate: sampleRate)
    tempo = TempoTracker(frameRate: sampleRate / Double(Self.hopSize))
  }

  var hopDuration: TimeInterval { Double(Self.hopSize) / sampleRate }

  func process(_ chunk: AudioChunk) -> [AudioFeatures] {
    if chunk.sampleRate != sampleRate, chunk.sampleRate > 0 {
      reset(sampleRate: chunk.sampleRate)
    }
    pending.append(contentsOf: chunk.samples)
    var features: [AudioFeatures] = []
    var start = 0
    while pending.count - start >= Self.hopSize {
      features.append(analyzeHop(pending[start..<(start + Self.hopSize)]))
      start += Self.hopSize
    }
    pending.removeFirst(start)
    return features
  }

  func reset(sampleRate: Double? = nil) {
    let time = Double(hops) * hopDuration
    if let sampleRate {
      self.sampleRate = sampleRate
      flux = SpectralFlux(frameSize: Self.frameSize, sampleRate: sampleRate)
      tempo = TempoTracker(frameRate: sampleRate / Double(Self.hopSize))
      hops = Int((time / hopDuration).rounded())
    } else {
      flux.reset()
      tempo.reset()
    }
    grid.reset()
    frame = [Float](repeating: 0, count: Self.frameSize)
    pending.removeAll()
    envelope = 0
    recentPower.removeAll()
    onsetHistory.removeAll()
    recentPeak = 0
    lastOnsetTime = -.infinity
    isActive = false
    inactiveDuration = 0
    drive = 0
    intensity = 0
  }

  private func analyzeHop(_ hop: ArraySlice<Float>) -> AudioFeatures {
    hops += 1
    let time = Double(hops) * hopDuration
    let dt = hopDuration
    frame.removeFirst(Self.hopSize)
    frame.append(contentsOf: hop)

    let rms = vDSP.rootMeanSquare(hop)
    let attack = Float(exp(-dt / 0.03))
    let release = Float(exp(-dt / 0.35))
    let coefficient = rms > envelope ? attack : release
    envelope = coefficient * envelope + (1 - coefficient) * rms
    let level = Self.decibels(rms)
    let envelopeDB = Self.decibels(envelope)
    updateActivity(power: rms * rms, dt: dt)

    let spectral = flux.process(frame)
    let onsetValue = spectral.broadband + spectral.bass
    let (isOnset, strength) = pickOnset(current: onsetValue, at: time)
    tempo.append(onsetStrength: isOnset ? Float(strength) : 0)
    push(onsetValue, into: &onsetHistory, window: Self.thresholdWindow)

    let reliableTempo = isActive ? tempo.reliable : nil
    var beatStrength: Double?
    if isOnset,
      grid.isBeat(onsetAt: time - dt, strength: strength, period: reliableTempo?.beatDuration)
    {
      beatStrength = strength
    }

    let impulse = isOnset ? strength / dt : 0
    drive += (impulse - drive) * (1 - exp(-dt / Self.pulseSmoothing))
    let pulse = min(1, drive / 4)
    let offset = configuration.loudnessOffsetDB
    let loudness = Self.clamp(
      (envelopeDB - (Self.quietLoudnessDB + offset))
        / (Self.loudLoudnessDB - Self.quietLoudnessDB))
    let rhythm = reliableTempo.map { Self.clamp(($0.confidence - 0.2) / 0.4) } ?? 0
    let target = isActive ? 0.45 * loudness + 0.35 * pulse + 0.2 * rhythm : 0
    intensity += (target - intensity) * (1 - exp(-dt / Self.intensitySmoothing))

    return AudioFeatures(
      time: time, level: level, envelope: envelopeDB, onsetStrength: isOnset ? strength : 0,
      isOnset: isOnset, beatStrength: beatStrength, tempo: reliableTempo, pulse: pulse,
      isActive: isActive, intensity: intensity)
  }

  /// Gates on mean power over a short window so pauses register within about half a second while
  /// gaps between notes do not.
  private func updateActivity(power: Float, dt: TimeInterval) {
    push(power, into: &recentPower, window: Self.activityWindow)
    let windowDB = 10 * log10(Double(max(vDSP.mean(recentPower), 1e-14)))
    let offset = configuration.loudnessOffsetDB
    if isActive {
      if windowDB < Self.inactiveThresholdDB + offset { isActive = false }
    } else if windowDB > Self.activeThresholdDB + offset {
      isActive = true
    }
    inactiveDuration = isActive ? 0 : inactiveDuration + dt
    if inactiveDuration >= Self.tempoResetDelay, tempo.reliable != nil || grid.lastBeat != nil {
      tempo.reset()
      grid.reset()
    }
  }

  /// Peak-picks the previous hop's onset value: it must be a local maximum and clear an adaptive
  /// threshold built from the median and median absolute deviation of the last 1.5 s, which
  /// tracks steady noise and dense mixes without being dragged up by the onsets themselves.
  private func pickOnset(current: Float, at time: TimeInterval) -> (Bool, Double) {
    recentPeak *= Float(exp(-hopDuration / 4))
    guard onsetHistory.count >= 10 else { return (false, 0) }
    let candidate = onsetHistory[onsetHistory.count - 1]
    let before = onsetHistory[onsetHistory.count - 2]
    let reference = onsetHistory.dropLast().sorted()
    let median = reference[reference.count / 2]
    let deviations = reference.map { abs($0 - median) }.sorted()
    let deviation = deviations[deviations.count / 2]
    let threshold = median + max(6 * deviation, 0.5 * median + Self.minimumOnsetRise)
    let onsetTime = time - hopDuration
    guard isActive, candidate > before, candidate >= current, candidate > threshold,
      onsetTime - lastOnsetTime >= Self.refractoryPeriod
    else { return (false, 0) }
    recentPeak = max(recentPeak, candidate)
    let strength = Double(candidate / recentPeak)
    guard strength >= Self.minimumOnsetStrength else { return (false, 0) }
    lastOnsetTime = onsetTime
    return (true, strength)
  }

  private func push(_ value: Float, into values: inout [Float], window: TimeInterval) {
    values.append(value)
    let capacity = max(1, Int(window / hopDuration))
    if values.count > capacity {
      values.removeFirst(values.count - capacity)
    }
  }

  private static func decibels(_ amplitude: Float) -> Double {
    20 * log10(Double(max(amplitude, 1e-7)))
  }

  private static func clamp(_ value: Double) -> Double {
    max(0, min(1, value))
  }
}
