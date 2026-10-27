import Foundation
import Testing

@testable import CHIBIApp

@Suite("Music dance controller")
struct MusicDanceControllerTests {
  static let hop = 0.02

  /// Steps the controller through `seconds` of identical features, returning every command with
  /// its time. `beatEvery` marks beats at that period.
  struct Run {
    var controller = MusicDanceController()
    var time = 0.0
    var log: [(time: Double, command: MusicDanceCommand)] = []

    mutating func feed(
      _ seconds: Double, active: Bool = true, intensity: Double = 0, pulse: Double = 0,
      bpm: Double? = nil, beatEvery: Double? = nil
    ) {
      let end = time + seconds
      var nextBeat = beatEvery.map { (time / $0).rounded(.up) * $0 } ?? .infinity
      while time < end - 1e-9 {
        time += MusicDanceControllerTests.hop
        var isBeat = false
        if let beatEvery, time >= nextBeat {
          isBeat = true
          nextBeat += beatEvery
        }
        let features = AudioFeatures(
          time: time, level: active ? -20 : -140, envelope: active ? -20 : -140,
          onsetStrength: isBeat ? 0.9 : 0, isOnset: isBeat, beatStrength: isBeat ? 0.9 : nil,
          tempo: bpm.map { TempoEstimate(bpm: $0, confidence: 0.7) }, pulse: pulse,
          isActive: active, intensity: intensity)
        for command in controller.update(features, now: time) {
          log.append((time, command))
        }
      }
    }

    var dances: [(time: Double, level: MusicDanceLevel)] {
      log.compactMap { entry in
        if case .dance(let level) = entry.command { (entry.time, level) } else { nil }
      }
    }

    var settles: [Double] {
      log.compactMap { $0.command == .settle ? $0.time : nil }
    }

    var accents: [Double] {
      log.compactMap { entry in
        if case .accent = entry.command { entry.time } else { nil }
      }
    }
  }

  @Test func silenceProducesNoCommands() {
    var run = Run()
    run.feed(5, active: false)
    #expect(run.log.isEmpty)
    #expect(!run.controller.isMusicPresent)
  }

  @Test func briefSoundsLikeNotificationsDoNotStartDancing() {
    var run = Run()
    run.feed(0.5, intensity: 0.5, pulse: 0.5)
    run.feed(2, active: false)
    run.feed(0.6, intensity: 0.5, pulse: 0.5)
    run.feed(2, active: false)
    #expect(run.log.isEmpty)
  }

  @Test func sustainedQuietMusicStartsAGentleSwayOnce() throws {
    var run = Run()
    run.feed(10, intensity: 0.2)
    let first = try #require(run.dances.first)
    #expect(run.dances.count == 1)
    #expect(first.level == .gentle)
    #expect(first.time >= 0.8 && first.time < 1.0)
  }

  @Test func energyLevelsMapToGentleRhythmicAndEnergetic() {
    var run = Run()
    run.feed(5, intensity: 0.5, pulse: 0.5)
    #expect(run.dances.last?.level == .rhythmic)
    run.feed(6, intensity: 0.8, pulse: 0.8, bpm: 120, beatEvery: 0.5)
    #expect(run.dances.last?.level == .energetic)
    run.feed(6, intensity: 0.15, pulse: 0.1)
    #expect(run.dances.last?.level == .gentle)
  }

  @Test func energeticNeedsAReliableTempoAndRhythmicNeedsPulseOrTempo() {
    var loudNoise = Run()
    loudNoise.feed(10, intensity: 0.9, pulse: 0)
    #expect(loudNoise.dances.map(\.level) == [.gentle])
    var pulsing = Run()
    pulsing.feed(10, intensity: 0.9, pulse: 0.6)
    #expect(pulsing.dances.map(\.level) == [.rhythmic])
  }

  @Test func hysteresisPreventsFlappingAroundAThreshold() {
    var run = Run()
    for index in 0..<40 {
      run.feed(0.5, intensity: index.isMultiple(of: 2) ? 0.43 : 0.35, pulse: 0.5)
    }
    #expect(run.dances.count <= 2)
  }

  @Test func levelChangesRespectDebounceAndMinimumDwell() throws {
    var run = Run()
    run.feed(1.5, intensity: 0.2)
    let start = try #require(run.dances.first?.time)
    run.feed(6, intensity: 0.5, pulse: 0.5)
    let change = try #require(run.dances.dropFirst().first)
    let tuning = run.controller.tuning
    #expect(change.level == .rhythmic)
    #expect(change.time - start >= tuning.minimumDwell - 1e-9)
    #expect(change.time - 1.5 >= tuning.changeDebounce - 1e-9)
    #expect(change.time - start < tuning.minimumDwell + 0.1)
  }

  @Test func levelChangesWaitForABeatWhenTempoIsKnown() throws {
    var run = Run()
    run.feed(5, intensity: 0.5, pulse: 0.5, bpm: 120, beatEvery: 0.5)
    run.feed(6, intensity: 0.8, pulse: 0.8, bpm: 120, beatEvery: 0.5)
    let energetic = try #require(run.dances.first { $0.level == .energetic })
    let remainder = energetic.time.truncatingRemainder(dividingBy: 0.5)
    #expect(min(remainder, 0.5 - remainder) < 0.03)
  }

  @Test func accentsFollowBeatsOnlyWhileDancingRhythmicallyWithCooldown() {
    var gentle = Run()
    gentle.feed(6, intensity: 0.2, bpm: 120, beatEvery: 0.5)
    #expect(gentle.accents.isEmpty)

    var rhythmic = Run()
    rhythmic.feed(6, intensity: 0.5, pulse: 0.5, bpm: 120, beatEvery: 0.5)
    #expect(rhythmic.accents.count >= 8)
    var fast = Run()
    fast.feed(6, intensity: 0.5, pulse: 0.5, bpm: 120, beatEvery: 0.1)
    let gaps = zip(fast.accents.dropFirst(), fast.accents).map { $0 - $1 }
    #expect(gaps.allSatisfy { $0 >= fast.controller.tuning.accentCooldown - 1e-9 })
  }

  @Test func shortPausesHoldTheDanceAndLongSilenceSettlesOnce() throws {
    var run = Run()
    run.feed(4, intensity: 0.5, pulse: 0.5)
    run.feed(1, active: false)
    run.feed(2, intensity: 0.5, pulse: 0.5)
    #expect(run.settles.isEmpty)
    let silenceStart = run.time
    run.feed(4, active: false)
    let settle = try #require(run.settles.first)
    #expect(run.settles.count == 1)
    #expect(abs(settle - silenceStart - 1.5) < 0.05)
    #expect(run.controller.level == nil)
  }

  @Test func rapidPauseResumeNeverRestartsTheDance() {
    var run = Run()
    run.feed(3, intensity: 0.5, pulse: 0.5)
    for _ in 0..<10 {
      run.feed(0.4, active: false)
      run.feed(0.6, intensity: 0.5, pulse: 0.5)
    }
    #expect(run.settles.isEmpty)
    #expect(run.dances.count == 1)
  }

  @Test func stalledFeatureStreamCountsAsSilence() throws {
    var run = Run()
    run.feed(3, intensity: 0.5, pulse: 0.5)
    var time = run.time
    var settled = false
    while time < run.time + 4, !settled {
      time += 0.1
      settled = run.controller.tick(now: time).contains(.settle)
    }
    #expect(settled)
    #expect(time - run.time > 1.5)
  }

  @Test func autoDanceOffSettlesAndSuppressesDancing() {
    var run = Run()
    run.feed(3, intensity: 0.5, pulse: 0.5)
    #expect(run.controller.setAutoDanceEnabled(false) == [.settle])
    run.feed(3, intensity: 0.5, pulse: 0.5)
    #expect(run.dances.count == 1)
    #expect(run.controller.isMusicPresent)
    #expect(run.controller.setAutoDanceEnabled(true).isEmpty)
    run.feed(0.1, intensity: 0.5, pulse: 0.5)
    #expect(run.dances.count == 2)
  }

  @Test func tempoIsReportedOnlyWhenItChangesMeaningfully() {
    var run = Run()
    run.feed(2, intensity: 0.5, pulse: 0.5, bpm: 120)
    run.feed(2, intensity: 0.5, pulse: 0.5, bpm: 121.5)
    run.feed(2, intensity: 0.5, pulse: 0.5, bpm: 128)
    run.feed(2, intensity: 0.5, pulse: 0.5)
    let tempos = run.log.compactMap { entry -> TimeInterval?? in
      if case .tempo(let beat) = entry.command { beat } else { nil }
    }
    #expect(tempos.count == 3)
    #expect(tempos.last! == nil)
  }

  @Test func resetSettlesAndClearsTempo() {
    var run = Run()
    run.feed(3, intensity: 0.5, pulse: 0.5, bpm: 120)
    #expect(run.controller.reset() == [.settle, .tempo(beatDuration: nil)])
    #expect(run.controller.level == nil && !run.controller.isMusicPresent)
    #expect(run.controller.reset().isEmpty)
  }

  @Test func analyzedDrumLoopDancesEnergeticallyAndSettlesAfterItStops() throws {
    let samples =
      AudioFixtures.drumLoop(bpm: 120, seconds: 14) + AudioFixtures.silence(seconds: 4)
    var controller = MusicDanceController()
    var dances: [(Double, MusicDanceLevel)] = []
    var settles: [Double] = []
    var accents = 0
    for features in AudioFixtures.analyze(samples) {
      for command in controller.update(features, now: features.time) {
        switch command {
        case .dance(let level): dances.append((features.time, level))
        case .settle: settles.append(features.time)
        case .accent: accents += 1
        case .tempo: break
        }
      }
    }
    let first = try #require(dances.first)
    #expect(first.0 < 1.5)
    #expect(dances.last?.1 == .energetic)
    #expect(dances.count <= 3)
    #expect(accents >= 8)
    let settle = try #require(settles.first)
    #expect(settles.count == 1 && settle > 14 && settle < 16.5)
  }

  @Test func analyzedIrregularTransientsNeverReachEnergetic() {
    var controller = MusicDanceController()
    var levels: Set<MusicDanceLevel> = []
    let samples = AudioFixtures.irregularTransients(seconds: 14, perSecond: 3)
    for features in AudioFixtures.analyze(samples) {
      for case .dance(let level) in controller.update(features, now: features.time) {
        levels.insert(level)
      }
    }
    #expect(!levels.contains(.energetic))
  }
}
