import Accelerate
import Foundation

struct TempoEstimate: Equatable, Sendable {
  var bpm: Double
  /// Normalized autocorrelation at the beat period, 0–1.
  var confidence: Double

  var beatDuration: TimeInterval { 60 / bpm }
}

/// Estimates tempo from the autocorrelation of a few seconds of detected onsets (an impulse
/// train weighted by onset strength), and reports it only after estimates have agreed for a
/// while. Sub-threshold ripple never reaches it, and irregular onsets rarely keep a stable
/// periodic peak, so neither becomes a reliable tempo.
struct TempoTracker {
  static let minimumBPM = 70.0
  static let maximumBPM = 180.0
  static let historyDuration: TimeInterval = 6
  static let minimumHistory: TimeInterval = 2.5
  static let minimumOnsets = 5
  static let estimateInterval: TimeInterval = 0.25
  static let acquisitionConfidence = 0.3
  static let retentionConfidence = 0.2
  static let agreementDuration: TimeInterval = 1.5
  static let agreementTolerance = 0.04
  static let weakDuration: TimeInterval = 3
  private static let smoothing: [Float] = [0.1, 0.2, 0.4, 0.2, 0.1]

  let frameRate: Double
  private(set) var reliable: TempoEstimate?
  private var history: [Float] = []
  private var framesSinceEstimate = 0
  private var candidateBPM: Double?
  private var agreeingEstimates = 0
  private var weakEstimates = 0

  init(frameRate: Double) {
    self.frameRate = frameRate
  }

  mutating func reset() {
    reliable = nil
    history.removeAll(keepingCapacity: true)
    framesSinceEstimate = 0
    candidateBPM = nil
    agreeingEstimates = 0
    weakEstimates = 0
  }

  /// Appends one analysis hop: the onset strength if an onset was detected there, otherwise 0.
  /// Strength is compressed so a few accented hits do not drown out the steady pulse.
  mutating func append(onsetStrength: Float) {
    history.append(onsetStrength > 0 ? 0.5 + 0.5 * min(1, onsetStrength) : 0)
    let capacity = Int(Self.historyDuration * frameRate)
    if history.count > capacity {
      history.removeFirst(history.count - capacity)
    }
    framesSinceEstimate += 1
    guard framesSinceEstimate >= Int(Self.estimateInterval * frameRate) else { return }
    framesSinceEstimate = 0
    update(with: estimate())
  }

  /// Best periodicity in the current history, without the agreement requirement.
  func estimate() -> TempoEstimate? {
    guard Double(history.count) >= Self.minimumHistory * frameRate,
      history.lazy.filter({ $0 > 0 }).count >= Self.minimumOnsets
    else { return nil }
    let padded = [0, 0] + history + [0, 0]
    let smoothed = vDSP.convolve(padded, withKernel: Self.smoothing)
    let centered = vDSP.add(-vDSP.mean(smoothed), smoothed)
    let energy = vDSP.dot(centered, centered)
    guard energy > 1e-6 else { return nil }
    let count = centered.count
    func correlation(_ lag: Int) -> Double {
      guard lag > 0, lag < count - 1 else { return 0 }
      let product = centered.withUnsafeBufferPointer { values in
        vDSP.dot(
          UnsafeBufferPointer(rebasing: values[0..<(count - lag)]),
          UnsafeBufferPointer(rebasing: values[lag..<count]))
      }
      return Double(product / energy) * Double(count) / Double(count - lag)
    }
    let shortestLag = max(2, Int((60 * frameRate / Self.maximumBPM).rounded(.down)))
    let longestLag = Int((60 * frameRate / Self.minimumBPM).rounded(.up))
    var best: (lag: Int, score: Double)?
    for lag in shortestLag...longestLag {
      let bpm = 60 * frameRate / Double(lag)
      let prior = exp(-0.5 * pow(log2(bpm / 120), 2))
      let score = (correlation(lag) + 0.5 * correlation(2 * lag)) * prior
      if score > (best?.score ?? 0) { best = (lag, score) }
    }
    guard let best else { return nil }
    let previous = correlation(best.lag - 1)
    let peak = correlation(best.lag)
    let next = correlation(best.lag + 1)
    let curvature = previous - 2 * peak + next
    let offset = curvature < 0 ? max(-0.5, min(0.5, 0.5 * (previous - next) / curvature)) : 0
    return TempoEstimate(
      bpm: 60 * frameRate / (Double(best.lag) + offset), confidence: max(0, min(1, peak)))
  }

  /// Keeps a reliable tempo while agreeing estimates stay moderately confident; replaces it only
  /// when a different tempo has itself agreed for `agreementDuration`, and drops it after
  /// `weakDuration` without support.
  private mutating func update(with estimate: TempoEstimate?) {
    if let estimate, let current = reliable, estimate.confidence >= Self.retentionConfidence,
      abs(estimate.bpm / current.bpm - 1) <= Self.agreementTolerance
    {
      weakEstimates = 0
      let bpm = current.bpm * 0.8 + estimate.bpm * 0.2
      reliable = TempoEstimate(bpm: bpm, confidence: estimate.confidence)
      candidateBPM = bpm
      agreeingEstimates += 1
      return
    }
    if reliable == nil {
      weakEstimates = 0
    } else {
      weakEstimates += 1
      if Double(weakEstimates) * Self.estimateInterval >= Self.weakDuration {
        reliable = nil
      }
    }
    guard let estimate, estimate.confidence >= Self.acquisitionConfidence else {
      candidateBPM = nil
      agreeingEstimates = 0
      return
    }
    if let candidate = candidateBPM, abs(estimate.bpm / candidate - 1) <= Self.agreementTolerance {
      agreeingEstimates += 1
      candidateBPM = candidate * 0.8 + estimate.bpm * 0.2
    } else {
      candidateBPM = estimate.bpm
      agreeingEstimates = 1
    }
    let agreedFor = Double(agreeingEstimates - 1) * Self.estimateInterval
    if agreedFor >= Self.agreementDuration, let candidate = candidateBPM {
      reliable = TempoEstimate(bpm: candidate, confidence: estimate.confidence)
      weakEstimates = 0
    }
  }
}

/// Accepts onsets as beats only when they land on the reliable tempo grid, re-anchoring the
/// grid to each accepted onset. Off-grid sounds (fills, hi-hats between beats, notifications)
/// are not beats, and accepted beats are always at least most of a period apart.
struct BeatGrid {
  static let tolerance = 0.15
  static let anchorStrength = 0.45

  private(set) var lastBeat: TimeInterval?

  mutating func reset() {
    lastBeat = nil
  }

  mutating func isBeat(onsetAt time: TimeInterval, strength: Double, period: TimeInterval?)
    -> Bool
  {
    guard let period else {
      lastBeat = nil
      return false
    }
    guard let lastBeat, time - lastBeat < 4 * period else {
      guard strength >= Self.anchorStrength else { return false }
      self.lastBeat = time
      return true
    }
    let phase = (time - lastBeat) / period
    let nearest = phase.rounded()
    guard nearest >= 1, abs(phase - nearest) <= Self.tolerance else { return false }
    self.lastBeat = time
    return true
  }
}
