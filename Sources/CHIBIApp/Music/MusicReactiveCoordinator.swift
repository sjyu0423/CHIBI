import Foundation

/// What the menu shows about music reaction.
struct MusicReactiveStatus: Equatable, Sendable {
  var capture: AudioCaptureStatus = .off
  var isMusicPresent = false
  var tempoBPM: Int?
  var level: MusicDanceLevel?

  var isListening: Bool { capture.isActive }

  var summary: String {
    switch capture {
    case .off: "Not listening"
    case .starting: "Starting…"
    case .listening:
      if !isMusicPresent {
        "Listening — waiting for music"
      } else if let tempoBPM {
        "Hearing music (~\(tempoBPM) BPM)"
      } else {
        "Hearing music"
      }
    case .permissionDenied: "Needs Screen & System Audio Recording permission"
    case .unavailable(let reason): "Unavailable: \(reason)"
    case .interrupted(let reason): "Stopped: \(reason)"
    }
  }
}

/// Connects system-audio capture, analysis, and the dance controller to the character. Capture
/// starts only when `start()` is called; when capture ends for any reason the controller resets
/// and the character settles back to idle.
///
/// The controller runs on the audio timeline (analyzed seconds), so its timing follows the music
/// rather than main-thread delivery jitter. The wall clock is used only to notice a stalled
/// stream, extrapolating audio time across the gap.
@MainActor
final class MusicReactiveCoordinator {
  typealias Clock = @MainActor () -> TimeInterval

  private let capture: AudioCaptureService
  private let apply: (MusicDanceCommand) -> Void
  private let now: Clock
  private let tickInterval: TimeInterval
  private var controller = MusicDanceController()
  private var pipeline: AudioAnalysisPipeline?
  private var session = 0
  private var timer: Timer?
  private var audioTime: TimeInterval = 0
  private var audioTimeReceivedAt: TimeInterval = 0

  var onStatusChange: ((MusicReactiveStatus) -> Void)?
  private(set) var status = MusicReactiveStatus() {
    didSet {
      if status != oldValue { onStatusChange?(status) }
    }
  }

  var sensitivity: MusicSensitivity {
    didSet { pipeline?.configuration = analysisConfiguration }
  }

  var isAutoDanceEnabled: Bool {
    get { controller.isAutoDanceEnabled }
    set {
      send(controller.setAutoDanceEnabled(newValue))
      refreshStatus()
    }
  }

  init(
    source: SystemAudioSource, sensitivity: MusicSensitivity = .normal,
    isAutoDanceEnabled: Bool = true, tickInterval: TimeInterval = 0.1,
    now: @escaping Clock = { ProcessInfo.processInfo.systemUptime },
    apply: @escaping (MusicDanceCommand) -> Void
  ) {
    capture = AudioCaptureService(source: source)
    self.sensitivity = sensitivity
    self.tickInterval = tickInterval
    self.now = now
    self.apply = apply
    _ = controller.setAutoDanceEnabled(isAutoDanceEnabled)
    capture.onStatusChange = { [weak self] status in self?.captureStatusChanged(status) }
  }

  func start() {
    guard !capture.status.isActive else { return }
    session += 1
    let session = session
    let owner = WeakReference(self)
    let pipeline = AudioAnalysisPipeline(configuration: analysisConfiguration) { features in
      Task { @MainActor in owner.object?.receive(features, session: session) }
    }
    self.pipeline = pipeline
    audioTime = 0
    audioTimeReceivedAt = now()
    capture.start { chunk in pipeline.consume(chunk) }
    startTimer()
  }

  func stop() {
    capture.stop()
  }

  /// Waits for queued capture start/stop work; used by tests and orderly shutdown.
  func waitForPendingOperations() async {
    await capture.waitForPendingOperations()
  }

  /// Advances gap handling without waiting for the timer; used by tests.
  func tick() {
    guard capture.status.isActive else { return }
    send(controller.tick(now: audioTime + max(0, now() - audioTimeReceivedAt)))
    refreshStatus()
  }

  private func receive(_ features: [AudioFeatures], session: Int) {
    guard session == self.session, capture.status.isActive else { return }
    for feature in features {
      audioTime = feature.time
      send(controller.update(feature, now: feature.time))
    }
    audioTimeReceivedAt = now()
    refreshStatus()
  }

  private func captureStatusChanged(_ status: AudioCaptureStatus) {
    if !status.isActive {
      session += 1
      audioTime = 0
      pipeline = nil
      timer?.invalidate()
      timer = nil
      send(controller.reset())
    }
    refreshStatus()
  }

  private func startTimer() {
    timer?.invalidate()
    let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func send(_ commands: [MusicDanceCommand]) {
    for command in commands {
      apply(command)
    }
  }

  private func refreshStatus() {
    status = MusicReactiveStatus(
      capture: capture.status, isMusicPresent: controller.isMusicPresent,
      tempoBPM: controller.tempoBPM.map { Int($0.rounded()) }, level: controller.level)
  }

  private var analysisConfiguration: AudioAnalysisConfiguration {
    AudioAnalysisConfiguration(loudnessOffsetDB: sensitivity.loudnessOffsetDB)
  }
}
