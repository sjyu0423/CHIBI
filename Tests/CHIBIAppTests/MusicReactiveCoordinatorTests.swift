import Foundation
import Testing

@testable import CHIBIApp

@MainActor
@Suite("Music reactive coordinator")
struct MusicReactiveCoordinatorTests {
  private final class Recorder {
    var commands: [MusicDanceCommand] = []
    var statuses: [MusicReactiveStatus] = []

    var dances: [MusicDanceLevel] {
      commands.compactMap { if case .dance(let level) = $0 { level } else { nil } }
    }
    var settleCount: Int { commands.filter { $0 == .settle }.count }
  }

  private func makeCoordinator(
    source: ScriptedAudioSource, sensitivity: MusicSensitivity = .normal,
    autoDance: Bool = true
  ) -> (MusicReactiveCoordinator, Recorder) {
    let recorder = Recorder()
    let coordinator = MusicReactiveCoordinator(
      source: source, sensitivity: sensitivity, isAutoDanceEnabled: autoDance,
      tickInterval: 3600, now: { 0 }, apply: { recorder.commands.append($0) })
    coordinator.onStatusChange = { recorder.statuses.append($0) }
    return (coordinator, recorder)
  }

  private func emit(_ samples: [Float], to source: ScriptedAudioSource) {
    for chunk in AudioFixtures.chunks(samples) {
      source.emit(chunk)
    }
  }

  @Test func doesNothingUntilStartedAndDancesToRhythmicAudio() async {
    let source = ScriptedAudioSource()
    let (coordinator, recorder) = makeCoordinator(source: source)
    #expect(coordinator.status.capture == .off && source.startCount == 0)

    coordinator.start()
    await coordinator.waitForPendingOperations()
    #expect(coordinator.status.capture == .listening)
    #expect(coordinator.status.summary == "Listening — waiting for music")

    emit(AudioFixtures.drumLoop(bpm: 120, seconds: 12), to: source)
    #expect(await waitUntil { recorder.dances.last == .energetic })
    #expect(coordinator.status.isMusicPresent)
    #expect(coordinator.status.tempoBPM.map { abs($0 - 120) <= 3 } == true)
    #expect(coordinator.status.summary.hasPrefix("Hearing music (~"))
    #expect(recorder.commands.contains { if case .accent = $0 { true } else { false } })
    #expect(recorder.dances.count <= 3)

    coordinator.stop()
    #expect(coordinator.status.capture == .off && !coordinator.status.isMusicPresent)
    #expect(recorder.settleCount == 1)
    #expect(recorder.commands.last == .tempo(beatDuration: nil))
    await coordinator.waitForPendingOperations()
    #expect(source.stopCount == 1)
  }

  @Test func silenceEndsTheDanceWhileStillListening() async {
    let source = ScriptedAudioSource()
    let (coordinator, recorder) = makeCoordinator(source: source)
    coordinator.start()
    await coordinator.waitForPendingOperations()
    emit(AudioFixtures.drumLoop(bpm: 120, seconds: 6), to: source)
    emit(AudioFixtures.silence(seconds: 4), to: source)
    #expect(await waitUntil { recorder.settleCount == 1 })
    #expect(coordinator.status.capture == .listening && !coordinator.status.isMusicPresent)
    coordinator.stop()
  }

  @Test func audioArrivingAfterStopIsIgnored() async {
    let source = ScriptedAudioSource()
    let (coordinator, recorder) = makeCoordinator(source: source)
    coordinator.start()
    await coordinator.waitForPendingOperations()
    let lateHandler = source.currentSamplesHandler
    coordinator.stop()
    for chunk in AudioFixtures.chunks(AudioFixtures.drumLoop(bpm: 120, seconds: 4)) {
      source.emit(chunk, using: lateHandler)
    }
    try? await Task.sleep(for: .milliseconds(100))
    #expect(recorder.commands.isEmpty)
  }

  @Test func permissionDenialReportsAndNeverDances() async {
    let source = ScriptedAudioSource()
    source.failure = .permissionDenied
    let (coordinator, recorder) = makeCoordinator(source: source)
    coordinator.start()
    await coordinator.waitForPendingOperations()
    #expect(coordinator.status.capture == .permissionDenied)
    #expect(coordinator.status.summary.contains("permission"))
    #expect(!coordinator.status.isListening)
    #expect(recorder.commands.isEmpty)
    #expect(recorder.statuses.map(\.capture) == [.starting, .permissionDenied])

    source.failure = nil
    coordinator.start()
    await coordinator.waitForPendingOperations()
    #expect(coordinator.status.capture == .listening)
    coordinator.stop()
  }

  @Test func interruptionWhileDancingSettlesAndReportsTheReason() async {
    let source = ScriptedAudioSource()
    let (coordinator, recorder) = makeCoordinator(source: source)
    coordinator.start()
    await coordinator.waitForPendingOperations()
    emit(AudioFixtures.drumLoop(bpm: 120, seconds: 4), to: source)
    #expect(await waitUntil { !recorder.dances.isEmpty })
    source.interrupt(.interrupted("Display disconnected"))
    #expect(await waitUntil { coordinator.status.capture == .interrupted("Display disconnected") })
    #expect(recorder.settleCount == 1)
    #expect(coordinator.status.summary == "Stopped: Display disconnected")
  }

  @Test func autoDanceOffListensWithoutDancing() async {
    let source = ScriptedAudioSource()
    let (coordinator, recorder) = makeCoordinator(source: source, autoDance: false)
    coordinator.start()
    await coordinator.waitForPendingOperations()
    emit(AudioFixtures.drumLoop(bpm: 120, seconds: 6), to: source)
    #expect(await waitUntil { coordinator.status.isMusicPresent })
    #expect(recorder.dances.isEmpty)

    coordinator.isAutoDanceEnabled = true
    emit(AudioFixtures.drumLoop(bpm: 120, seconds: 1), to: source)
    #expect(await waitUntil { !recorder.dances.isEmpty })
    coordinator.isAutoDanceEnabled = false
    #expect(recorder.commands.last == .settle)
    coordinator.stop()
  }

  @Test func sensitivityDecidesWhetherQuietAudioCountsAsMusic() async {
    let quiet = AudioFixtures.pad(seconds: 4, amplitude: 0.0025)
    for (sensitivity, expectsMusic) in [(MusicSensitivity.high, true), (.normal, false)] {
      let source = ScriptedAudioSource()
      let (coordinator, recorder) = makeCoordinator(source: source, sensitivity: sensitivity)
      coordinator.start()
      await coordinator.waitForPendingOperations()
      emit(quiet, to: source)
      try? await Task.sleep(for: .milliseconds(150))
      #expect(coordinator.status.isMusicPresent == expectsMusic, "\(sensitivity)")
      #expect(recorder.dances.isEmpty == !expectsMusic)
      coordinator.stop()
    }
  }

  @Test func stalledStreamSettlesThroughTheTick() async {
    let source = ScriptedAudioSource()
    var wall = 0.0
    var commands: [MusicDanceCommand] = []
    let coordinator = MusicReactiveCoordinator(
      source: source, tickInterval: 3600, now: { wall }, apply: { commands.append($0) })
    coordinator.start()
    await coordinator.waitForPendingOperations()
    emit(AudioFixtures.drumLoop(bpm: 120, seconds: 3), to: source)
    #expect(await waitUntil { commands.contains { if case .dance = $0 { true } else { false } } })
    for _ in 0..<40 {
      wall += 0.1
      coordinator.tick()
    }
    #expect(commands.contains(.settle))
    #expect(coordinator.status.capture == .listening)
    coordinator.stop()
  }
}
