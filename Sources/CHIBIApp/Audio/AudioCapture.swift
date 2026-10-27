import Foundation

/// Mono PCM from a system-audio source. Audio stays in memory only long enough to analyze.
struct AudioChunk: Sendable, Equatable {
  var samples: [Float]
  var sampleRate: Double
}

enum AudioCaptureError: Error, Equatable, Sendable {
  case permissionDenied
  case unavailable(String)
  case interrupted(String)
}

enum AudioCaptureStatus: Equatable, Sendable {
  case off
  case starting
  case listening
  case permissionDenied
  case unavailable(String)
  case interrupted(String)

  var isActive: Bool { self == .starting || self == .listening }

  var failure: AudioCaptureError? {
    switch self {
    case .permissionDenied: .permissionDenied
    case .unavailable(let reason): .unavailable(reason)
    case .interrupted(let reason): .interrupted(reason)
    case .off, .starting, .listening: nil
    }
  }
}

/// Substitution seam between ScreenCaptureKit and scripted test sources.
protocol SystemAudioSource: AnyObject, Sendable {
  /// Starts capture. Handlers may be called on any thread until `stop()` returns.
  func start(
    samples: @escaping @Sendable (AudioChunk) -> Void,
    interrupted: @escaping @Sendable (AudioCaptureError) -> Void
  ) async throws(AudioCaptureError)
  func stop() async
}

/// Thread-safe switch that stops delivery the moment capture is stopped, even for audio that a
/// source has already queued.
final class AudioDeliveryGate: @unchecked Sendable {
  private let lock = NSLock()
  private var open = true

  var isOpen: Bool { lock.withLock { open } }

  func close() {
    lock.withLock { open = false }
  }
}

/// Lets off-main callbacks find a main-actor owner without keeping it alive. Only dereference
/// `object` on the owner's actor.
final class WeakReference<Object: AnyObject>: @unchecked Sendable {
  weak var object: Object?

  init(_ object: Object) {
    self.object = object
  }
}

/// Owns explicit, user-controlled start/stop of system-audio capture. Source operations run
/// strictly in order, so rapid start/stop cannot leave a stale stream running.
@MainActor
final class AudioCaptureService {
  private let source: SystemAudioSource
  private var gate: AudioDeliveryGate?
  private var generation = 0
  private var lastOperation: Task<Void, Never>?

  var onStatusChange: ((AudioCaptureStatus) -> Void)?
  private(set) var status: AudioCaptureStatus = .off {
    didSet {
      if status != oldValue { onStatusChange?(status) }
    }
  }

  init(source: SystemAudioSource) {
    self.source = source
  }

  /// `sink` runs on the source's delivery thread and must not touch main-actor state.
  func start(sink: @escaping @Sendable (AudioChunk) -> Void) {
    guard !status.isActive else { return }
    generation += 1
    let generation = generation
    let gate = AudioDeliveryGate()
    self.gate = gate
    status = .starting
    let owner = WeakReference(self)
    let interrupted: @Sendable (AudioCaptureError) -> Void = { error in
      Task { @MainActor in owner.object?.handleInterruption(error, generation: generation) }
    }
    enqueue { [weak self, source] in
      do throws(AudioCaptureError) {
        try await source.start(
          samples: { chunk in
            if gate.isOpen { sink(chunk) }
          },
          interrupted: interrupted)
      } catch {
        await self?.finishStart(generation: generation, failure: error)
        return
      }
      await self?.finishStart(generation: generation, failure: nil)
    }
  }

  /// Stops delivery immediately; the source is torn down asynchronously.
  func stop() {
    guard status != .off else { return }
    generation += 1
    gate?.close()
    gate = nil
    status = .off
    enqueue { [source] in await source.stop() }
  }

  /// Waits for queued source operations; used by tests and orderly shutdown.
  func waitForPendingOperations() async {
    await lastOperation?.value
  }

  /// A superseded start needs no cleanup here: whatever bumped the generation also queued a stop
  /// that runs after this start completes.
  private func finishStart(generation: Int, failure: AudioCaptureError?) {
    guard generation == self.generation else { return }
    if let failure {
      gate?.close()
      gate = nil
      status = Self.status(for: failure)
    } else {
      status = .listening
    }
  }

  private func handleInterruption(_ error: AudioCaptureError, generation: Int) {
    guard generation == self.generation, status.isActive else { return }
    self.generation += 1
    gate?.close()
    gate = nil
    status = Self.status(for: error)
    enqueue { [source] in await source.stop() }
  }

  private func enqueue(_ operation: @escaping @Sendable () async -> Void) {
    let previous = lastOperation
    lastOperation = Task {
      await previous?.value
      await operation()
    }
  }

  private static func status(for error: AudioCaptureError) -> AudioCaptureStatus {
    switch error {
    case .permissionDenied: .permissionDenied
    case .unavailable(let reason): .unavailable(reason)
    case .interrupted(let reason): .interrupted(reason)
    }
  }
}
