import Foundation

/// How strongly the character dances to music. These describe the audio's drive, not its genre.
enum MusicDanceLevel: Int, CaseIterable, Comparable, Sendable {
  case gentle
  case rhythmic
  case energetic

  static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum MusicDanceCommand: Equatable, Sendable {
  case dance(MusicDanceLevel)
  /// Music has stopped (or auto dance was turned off): ease back to idle.
  case settle
  /// A beat landed while dancing; strength 0–1.
  case accent(strength: Double)
  /// Reliable beat period for tempo-following motion, or nil to return to the default tempo.
  case tempo(beatDuration: TimeInterval?)
}

/// Turns per-hop audio features into infrequent dance commands. Pure value logic: callers supply
/// the clock, so every timing rule is testable without audio or SpriteKit.
///
/// It waits for sustained activity before dancing (a notification sound is not music), holds
/// through short pauses, uses separate enter and exit thresholds per level, keeps each level for
/// a minimum time, and changes level on a beat when a tempo is known. Commands are emitted only
/// on changes, so the animation never restarts per analysis frame.
struct MusicDanceController {
  struct Tuning: Equatable, Sendable {
    var startDelay: TimeInterval = 0.8
    var silenceHold: TimeInterval = 1.5
    /// Without features for this long, the signal counts as silent.
    var signalTimeout: TimeInterval = 0.6
    var minimumDwell: TimeInterval = 2.5
    var changeDebounce: TimeInterval = 0.6
    var beatAlignmentWindow: TimeInterval = 0.75
    var accentCooldown: TimeInterval = 0.22
    var rhythmicEnter = 0.4
    var rhythmicExit = 0.32
    var energeticEnter = 0.66
    var energeticExit = 0.56
    var rhythmicPulse = 0.25
    var tempoChangeTolerance = 0.03
  }

  let tuning: Tuning
  private(set) var level: MusicDanceLevel?
  private(set) var isMusicPresent = false
  private(set) var isAutoDanceEnabled = true
  private(set) var tempoBPM: Double?
  private var activeSince: TimeInterval?
  private var inactiveSince: TimeInterval?
  private var lastUpdate: TimeInterval?
  private var levelSince: TimeInterval = 0
  private var candidate: (level: MusicDanceLevel, since: TimeInterval)?
  private var pending: (level: MusicDanceLevel, deadline: TimeInterval)?
  private var lastAccent = -Double.infinity

  init(tuning: Tuning = Tuning()) {
    self.tuning = tuning
  }

  mutating func update(_ features: AudioFeatures, now: TimeInterval) -> [MusicDanceCommand] {
    lastUpdate = now
    var commands: [MusicDanceCommand] = []
    updatePresence(isActive: features.isActive, now: now)
    updateTempo(features.tempo?.bpm, into: &commands)

    let target: MusicDanceLevel? =
      if !isMusicPresent || !isAutoDanceEnabled {
        nil
      } else if features.isActive {
        desiredLevel(for: features)
      } else {
        // A pause holds the current level until music resumes or the silence hold expires.
        level ?? pending?.level ?? .gentle
      }
    apply(target: target, features: features, now: now, into: &commands)

    if let beat = features.beatStrength, let level, level >= .rhythmic,
      now - lastAccent >= tuning.accentCooldown, !commands.contains(where: \.isDance)
    {
      lastAccent = now
      commands.append(.accent(strength: max(0.2, min(1, beat))))
    }
    return commands
  }

  /// Call periodically; treats a stalled feature stream as silence.
  mutating func tick(now: TimeInterval) -> [MusicDanceCommand] {
    guard let lastUpdate, now - lastUpdate >= tuning.signalTimeout else { return [] }
    let silent = AudioFeatures(
      time: now, level: -140, envelope: -140, onsetStrength: 0, isOnset: false,
      beatStrength: nil, tempo: nil, pulse: 0, isActive: false, intensity: 0)
    return update(silent, now: now)
  }

  /// Capture ended: forget everything and settle if dancing.
  mutating func reset() -> [MusicDanceCommand] {
    var commands: [MusicDanceCommand] = []
    if level != nil { commands.append(.settle) }
    if tempoBPM != nil { commands.append(.tempo(beatDuration: nil)) }
    let autoDance = isAutoDanceEnabled
    self = MusicDanceController(tuning: tuning)
    isAutoDanceEnabled = autoDance
    return commands
  }

  mutating func setAutoDanceEnabled(_ enabled: Bool) -> [MusicDanceCommand] {
    guard enabled != isAutoDanceEnabled else { return [] }
    isAutoDanceEnabled = enabled
    guard !enabled else { return [] }
    pending = nil
    candidate = nil
    guard level != nil else { return [] }
    level = nil
    return [.settle]
  }

  private mutating func updatePresence(isActive: Bool, now: TimeInterval) {
    if isActive {
      inactiveSince = nil
      let since = activeSince ?? now
      activeSince = since
      if !isMusicPresent, now - since >= tuning.startDelay { isMusicPresent = true }
    } else {
      activeSince = nil
      let since = inactiveSince ?? now
      inactiveSince = since
      if isMusicPresent, now - since >= tuning.silenceHold { isMusicPresent = false }
    }
  }

  private mutating func updateTempo(_ bpm: Double?, into commands: inout [MusicDanceCommand]) {
    let changed: Bool =
      switch (tempoBPM, bpm) {
      case (nil, nil): false
      case (let old?, let new?): abs(new / old - 1) > tuning.tempoChangeTolerance
      default: true
      }
    guard changed else { return }
    tempoBPM = bpm
    commands.append(.tempo(beatDuration: bpm.map { 60 / $0 }))
  }

  private func desiredLevel(for features: AudioFeatures) -> MusicDanceLevel {
    let intensity = features.intensity
    let hasTempo = features.tempo != nil
    let canRhythm = hasTempo || features.pulse >= tuning.rhythmicPulse
    let current = pending?.level ?? level ?? .gentle
    let energetic =
      hasTempo
      && intensity >= (current == .energetic ? tuning.energeticExit : tuning.energeticEnter)
    if energetic { return .energetic }
    let rhythmic =
      canRhythm
      && intensity >= (current >= .rhythmic ? tuning.rhythmicExit : tuning.rhythmicEnter)
    return rhythmic ? .rhythmic : .gentle
  }

  private mutating func apply(
    target: MusicDanceLevel?, features: AudioFeatures, now: TimeInterval,
    into commands: inout [MusicDanceCommand]
  ) {
    guard let target else {
      pending = nil
      candidate = nil
      if level != nil {
        level = nil
        commands.append(.settle)
      }
      return
    }
    let alignment = features.tempo == nil ? 0 : tuning.beatAlignmentWindow
    if level == nil {
      if pending == nil { pending = (target, now + alignment) }
      pending?.level = target
    } else if target != level {
      if candidate?.level != target { candidate = (target, now) }
      if let candidate, now - candidate.since >= tuning.changeDebounce,
        now - levelSince >= tuning.minimumDwell, pending?.level != target
      {
        pending = (target, now + alignment)
      }
    } else {
      candidate = nil
      pending = nil
    }
    if let pending, features.beatStrength != nil || now >= pending.deadline {
      self.pending = nil
      candidate = nil
      level = pending.level
      levelSince = now
      commands.append(.dance(pending.level))
    }
  }
}

extension MusicDanceCommand {
  fileprivate var isDance: Bool {
    if case .dance = self { true } else { false }
  }
}
