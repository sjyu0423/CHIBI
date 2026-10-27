import Foundation

@testable import CHIBIApp

/// Scriptable `SystemAudioSource` for deterministic capture tests.
final class ScriptedAudioSource: SystemAudioSource, @unchecked Sendable {
  private let lock = NSLock()
  private var samplesHandler: (@Sendable (AudioChunk) -> Void)?
  private var interruptionHandler: (@Sendable (AudioCaptureError) -> Void)?
  private var _startCount = 0
  private var _stopCount = 0
  private var _events: [String] = []

  var failure: AudioCaptureError?
  var startDelay: Duration?

  var startCount: Int { lock.withLock { _startCount } }
  var stopCount: Int { lock.withLock { _stopCount } }
  var events: [String] { lock.withLock { _events } }
  var isCapturing: Bool { lock.withLock { samplesHandler != nil } }

  func start(
    samples: @escaping @Sendable (AudioChunk) -> Void,
    interrupted: @escaping @Sendable (AudioCaptureError) -> Void
  ) async throws(AudioCaptureError) {
    lock.withLock {
      _startCount += 1
      _events.append("start")
    }
    if let startDelay {
      try? await Task.sleep(for: startDelay)
    }
    if let failure {
      lock.withLock { _events.append("failed") }
      throw failure
    }
    lock.withLock {
      samplesHandler = samples
      interruptionHandler = interrupted
      _events.append("started")
    }
  }

  func stop() async {
    lock.withLock {
      _stopCount += 1
      samplesHandler = nil
      interruptionHandler = nil
      _events.append("stop")
    }
  }

  /// Delivers audio through the handler captured at start, as a real stream's queue would even
  /// after the service has asked it to stop.
  func emit(_ chunk: AudioChunk, using handler: (@Sendable (AudioChunk) -> Void)? = nil) {
    (handler ?? lock.withLock { samplesHandler })?(chunk)
  }

  var currentSamplesHandler: (@Sendable (AudioChunk) -> Void)? {
    lock.withLock { samplesHandler }
  }

  func interrupt(_ error: AudioCaptureError) {
    lock.withLock { interruptionHandler }?(error)
  }
}

/// Thread-safe collector for values delivered off the main actor.
final class LockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) {
    self.value = value
  }

  func update(_ change: (inout Value) -> Void) {
    lock.withLock { change(&value) }
  }

  var current: Value { lock.withLock { value } }
}

@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
  let deadline = ContinuousClock.now + timeout
  while !condition() {
    if ContinuousClock.now > deadline { return false }
    try? await Task.sleep(for: .milliseconds(5))
  }
  return true
}
