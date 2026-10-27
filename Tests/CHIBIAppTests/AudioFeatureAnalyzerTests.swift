import Foundation
import Testing

@testable import CHIBIApp

@Suite("Audio feature analyzer")
struct AudioFeatureAnalyzerTests {
  private func window(_ features: [AudioFeatures], from start: Double, to end: Double)
    -> [AudioFeatures]
  {
    features.filter { $0.time >= start && $0.time < end }
  }

  @Test func silenceIsInactiveWithNoOnsetsOrTempo() {
    let features = AudioFixtures.analyze(AudioFixtures.silence(seconds: 5))
    #expect(features.count == Int(5 * 48_000) / AudioFeatureAnalyzer.hopSize)
    #expect(features.allSatisfy { !$0.isActive && !$0.isOnset && $0.tempo == nil })
    #expect(features.allSatisfy { $0.beatStrength == nil && $0.intensity == 0 })
    #expect(features.last!.level < -100)
  }

  @Test func quietSustainedMusicIsActiveButLowIntensityAndHasNoTempo() {
    let features = AudioFixtures.analyze(AudioFixtures.pad(seconds: 8, amplitude: 0.03))
    let settled = window(features, from: 3, to: 8)
    #expect(settled.allSatisfy { $0.isActive })
    #expect(settled.allSatisfy { $0.intensity < 0.3 })
    #expect(features.filter(\.isOnset).count <= 1)
    #expect(features.allSatisfy { $0.tempo == nil && $0.beatStrength == nil })
  }

  @Test func barelyAudibleSoundStaysInactive() {
    let features = AudioFixtures.analyze(AudioFixtures.pad(seconds: 4, amplitude: 0.0005))
    #expect(features.allSatisfy { !$0.isActive && !$0.isOnset })
  }

  @Test func loudSteadyNoiseIsNotTreatedAsBeats() {
    let features = AudioFixtures.analyze(AudioFixtures.noise(seconds: 10, amplitude: 0.4))
    #expect(window(features, from: 1, to: 10).allSatisfy { $0.isActive })
    #expect(features.filter(\.isOnset).count <= 3)
    #expect(features.allSatisfy { $0.tempo == nil && $0.beatStrength == nil })
  }

  @Test(arguments: [96.0, 120.0, 128.0, 150.0])
  func rhythmicPulsesProduceStableTempoAndOneBeatPerPulse(bpm: Double) throws {
    let features = AudioFixtures.analyze(AudioFixtures.drumLoop(bpm: bpm, seconds: 14))
    let locked = try #require(features.first { $0.tempo != nil })
    #expect(locked.time < 6)
    let late = window(features, from: 8, to: 14)
    #expect(late.allSatisfy { $0.tempo != nil })
    let tempo = try #require(late.last?.tempo)
    #expect(abs(tempo.bpm / bpm - 1) < 0.03)

    let beats = late.filter { $0.beatStrength != nil }.map(\.time)
    let expected = 6 * bpm / 60
    #expect(Double(beats.count) >= expected - 2 && Double(beats.count) <= expected + 1)
    let gaps = zip(beats.dropFirst(), beats).map { $0 - $1 }
    #expect(gaps.allSatisfy { $0 > 0.8 * 60 / bpm })
    #expect(late.last!.intensity > 0.5)
  }

  @Test(arguments: [92.0, 118.0, 140.0, 174.0])
  func denseHumanizedGroovesHoldATempoUpToAnOctave(bpm: Double) throws {
    let features = AudioFixtures.analyze(AudioFixtures.bandLoop(bpm: bpm, seconds: 16))
    let locked = try #require(features.first { $0.tempo != nil })
    #expect(locked.time < 6)
    let late = window(features, from: 10, to: 16)
    #expect(late.allSatisfy { $0.tempo != nil })
    let tempo = try #require(late.last?.tempo)
    let ratio = tempo.bpm / bpm
    #expect([0.5, 1, 2].contains { abs(ratio / $0 - 1) < 0.04 })
    #expect(late.contains { $0.beatStrength != nil })
  }

  @Test(arguments: [UInt64(3), 11, 29, 47])
  func irregularTransientsRarelyProduceATempo(seed: UInt64) {
    let features = AudioFixtures.analyze(
      AudioFixtures.irregularTransients(seconds: 14, perSecond: 3, seed: seed))
    #expect(features.filter { $0.beatStrength != nil }.count <= 4)
    #expect(features.filter { $0.tempo != nil }.count < features.count / 5)
  }

  @Test func onsetsAreNeverCloserThanTheRefractoryPeriod() {
    let features = AudioFixtures.analyze(AudioFixtures.drumLoop(bpm: 170, seconds: 8))
    let onsets = features.filter(\.isOnset).map(\.time)
    #expect(onsets.count > 10)
    let gaps = zip(onsets.dropFirst(), onsets).map { $0 - $1 }
    #expect(gaps.allSatisfy { $0 >= AudioFeatureAnalyzer.refractoryPeriod - 0.001 })
  }

  @Test func irregularTransientsProduceOnsetsButAlmostNoBeats() {
    let features = AudioFixtures.analyze(
      AudioFixtures.irregularTransients(seconds: 14, perSecond: 2.5))
    #expect(features.filter(\.isOnset).count > 15)
    #expect(features.filter { $0.beatStrength != nil }.count <= 3)
    #expect(features.filter { $0.tempo != nil }.count < features.count / 10)
  }

  @Test func pauseDropsActivityAndTempoAndResumeReacquiresThem() throws {
    let samples =
      AudioFixtures.drumLoop(bpm: 120, seconds: 8) + AudioFixtures.silence(seconds: 4)
      + AudioFixtures.drumLoop(bpm: 120, seconds: 8)
    let features = AudioFixtures.analyze(samples)
    #expect(window(features, from: 6, to: 8).allSatisfy { $0.tempo != nil })
    #expect(window(features, from: 9, to: 12).allSatisfy { !$0.isActive && $0.tempo == nil })
    #expect(window(features, from: 9, to: 12).allSatisfy { $0.beatStrength == nil })
    let decayed = try #require(features.first { $0.time > 8 && $0.intensity < 0.1 })
    #expect(decayed.time < 12)
    #expect(window(features, from: 18, to: 20).allSatisfy { $0.tempo != nil && $0.isActive })
  }

  @Test func resultsDoNotDependOnChunkSize() {
    let samples = AudioFixtures.drumLoop(bpm: 120, seconds: 6)
    let reference = AudioFixtures.analyze(samples, chunkSize: 960)
    #expect(AudioFixtures.analyze(samples, chunkSize: 4096) == reference)
    #expect(AudioFixtures.analyze(samples, chunkSize: 333) == reference)
  }

  @Test func sensitivityOffsetShiftsTheActivityGate() {
    let quiet = AudioFixtures.pad(seconds: 3, amplitude: 0.0025)
    let sensitive = AudioFixtures.analyze(
      quiet, configuration: AudioAnalysisConfiguration(loudnessOffsetDB: -8))
    let normal = AudioFixtures.analyze(quiet)
    let insensitive = AudioFixtures.analyze(
      quiet, configuration: AudioAnalysisConfiguration(loudnessOffsetDB: 8))
    #expect(sensitive.last!.isActive)
    #expect(!normal.last!.isActive)
    #expect(!insensitive.last!.isActive)
    let loud = AudioFixtures.pad(seconds: 3, amplitude: 0.05)
    let louder = AudioFixtures.analyze(
      loud, configuration: AudioAnalysisConfiguration(loudnessOffsetDB: -8))
    let quieter = AudioFixtures.analyze(
      loud, configuration: AudioAnalysisConfiguration(loudnessOffsetDB: 8))
    #expect(louder.last!.intensity > quieter.last!.intensity)
  }

  @Test func sampleRateChangeRestartsAnalysisWithoutCrashing() {
    let analyzer = AudioFeatureAnalyzer(sampleRate: 48_000)
    _ = analyzer.process(
      AudioChunk(samples: AudioFixtures.noise(seconds: 1, amplitude: 0.3), sampleRate: 48_000))
    let features = analyzer.process(
      AudioChunk(samples: [Float](repeating: 0, count: 44_100), sampleRate: 44_100))
    #expect(analyzer.sampleRate == 44_100)
    #expect(features.count == 44_100 / AudioFeatureAnalyzer.hopSize)
    #expect(features.allSatisfy { !$0.isActive })
  }

  @Test func pipelineDeliversOnlyFeatures() {
    let received = LockedBox<[AudioFeatures]>([])
    let pipeline = AudioAnalysisPipeline { features in
      received.update { $0.append(contentsOf: features) }
    }
    for chunk in AudioFixtures.chunks(AudioFixtures.drumLoop(bpm: 120, seconds: 2)) {
      pipeline.consume(chunk)
    }
    #expect(received.current.count == Int(2 * 48_000) / AudioFeatureAnalyzer.hopSize)
    pipeline.reset()
    pipeline.configuration = AudioAnalysisConfiguration(loudnessOffsetDB: 4)
    #expect(pipeline.configuration.loudnessOffsetDB == 4)
  }
}
