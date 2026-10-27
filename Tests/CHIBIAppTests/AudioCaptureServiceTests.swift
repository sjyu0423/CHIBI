import Foundation
import ScreenCaptureKit
import Testing

@testable import CHIBIApp

@MainActor
struct AudioCaptureServiceTests {
  private let chunk = AudioChunk(samples: [0.1, -0.1, 0.2], sampleRate: 48_000)

  @Test func startsOnlyWhenAskedAndDeliversSamples() async throws {
    let source = ScriptedAudioSource()
    let service = AudioCaptureService(source: source)
    #expect(service.status == .off)
    #expect(source.startCount == 0, "capture must never begin on its own")

    let received = LockedBox<[AudioChunk]>([])
    var statuses: [AudioCaptureStatus] = []
    service.onStatusChange = { statuses.append($0) }
    service.start { chunk in received.update { $0.append(chunk) } }
    #expect(service.status == .starting)
    await service.waitForPendingOperations()
    #expect(service.status == .listening)

    source.emit(chunk)
    #expect(received.current == [chunk])
    #expect(statuses == [.starting, .listening])

    service.start { _ in Issue.record("a second start must be ignored") }
    await service.waitForPendingOperations()
    #expect(source.startCount == 1)
  }

  @Test func permissionDenialIsReportedAndNothingIsDelivered() async {
    let source = ScriptedAudioSource()
    source.failure = .permissionDenied
    let service = AudioCaptureService(source: source)
    let received = LockedBox(0)
    service.start { _ in received.update { $0 += 1 } }
    await service.waitForPendingOperations()
    #expect(service.status == .permissionDenied)
    #expect(service.status.failure == .permissionDenied)
    #expect(!service.status.isActive)
    source.emit(chunk)
    #expect(received.current == 0)

    source.failure = nil
    service.start { _ in received.update { $0 += 1 } }
    await service.waitForPendingOperations()
    #expect(service.status == .listening, "a later attempt can succeed after permission is granted")
  }

  @Test func unavailableCaptureReportsTheReason() async {
    let source = ScriptedAudioSource()
    source.failure = .unavailable("No display")
    let service = AudioCaptureService(source: source)
    service.start { _ in }
    await service.waitForPendingOperations()
    #expect(service.status == .unavailable("No display"))
  }

  @Test func stopClosesDeliveryImmediatelyEvenForQueuedAudio() async {
    let source = ScriptedAudioSource()
    let service = AudioCaptureService(source: source)
    let received = LockedBox(0)
    service.start { _ in received.update { $0 += 1 } }
    await service.waitForPendingOperations()
    let staleHandler = source.currentSamplesHandler

    service.stop()
    #expect(service.status == .off)
    source.emit(chunk, using: staleHandler)
    #expect(received.current == 0, "audio queued before teardown must be dropped")
    await service.waitForPendingOperations()
    #expect(source.stopCount == 1)
    #expect(!source.isCapturing)
  }

  @Test func interruptionStopsCaptureAndReportsIt() async {
    let source = ScriptedAudioSource()
    let service = AudioCaptureService(source: source)
    let received = LockedBox(0)
    service.start { _ in received.update { $0 += 1 } }
    await service.waitForPendingOperations()
    let staleHandler = source.currentSamplesHandler

    source.interrupt(.interrupted("Stream ended"))
    #expect(await waitUntil { service.status == .interrupted("Stream ended") })
    await service.waitForPendingOperations()
    #expect(source.stopCount == 1)
    source.emit(chunk, using: staleHandler)
    #expect(received.current == 0)

    service.start { _ in received.update { $0 += 1 } }
    await service.waitForPendingOperations()
    #expect(service.status == .listening, "capture can be restarted after an interruption")
  }

  @Test func permissionRevokedDuringCaptureIsReportedAsDenied() async {
    let source = ScriptedAudioSource()
    let service = AudioCaptureService(source: source)
    service.start { _ in }
    await service.waitForPendingOperations()
    source.interrupt(.permissionDenied)
    #expect(await waitUntil { service.status == .permissionDenied })
  }

  @Test func stopWhileStartingTearsDownTheLateStream() async {
    let source = ScriptedAudioSource()
    source.startDelay = .milliseconds(40)
    let service = AudioCaptureService(source: source)
    let received = LockedBox(0)
    service.start { _ in received.update { $0 += 1 } }
    service.stop()
    #expect(service.status == .off)
    await service.waitForPendingOperations()
    #expect(service.status == .off)
    #expect(!source.isCapturing)
    #expect(source.events == ["start", "started", "stop"])
    source.emit(chunk)
    #expect(received.current == 0)
  }

  @Test func rapidPauseResumeLeavesOnlyTheLatestStreamDelivering() async {
    let source = ScriptedAudioSource()
    source.startDelay = .milliseconds(10)
    let service = AudioCaptureService(source: source)
    let received = LockedBox<[Int]>([])
    for attempt in 1...3 {
      service.start { _ in received.update { $0.append(attempt) } }
      if attempt < 3 { service.stop() }
    }
    await service.waitForPendingOperations()
    #expect(service.status == .listening)
    #expect(source.startCount == 3)
    #expect(
      source.events == ["start", "started", "stop", "start", "started", "stop", "start", "started"])
    source.emit(chunk)
    #expect(received.current == [3])
    service.stop()
    await service.waitForPendingOperations()
    #expect(!source.isCapturing)
  }

  @Test func screenCaptureSourceReportsDeniedPermissionWithoutCapturing() async {
    let requests = LockedBox(0)
    let source = ScreenCaptureAudioSource(
      access: ScreenCaptureAccess(
        isGranted: { false },
        request: {
          requests.update { $0 += 1 }
          return false
        }))
    var thrown: AudioCaptureError?
    do {
      try await source.start(samples: { _ in }, interrupted: { _ in })
    } catch {
      thrown = error
    }
    #expect(thrown == .permissionDenied)
    #expect(requests.current == 1, "the system prompt is requested once per explicit start")
    await source.stop()
  }

  @Test func screenCaptureConfigurationCapturesAudioWithMinimalVideo() {
    let configuration = ScreenCaptureAudioSource.configuration()
    #expect(configuration.capturesAudio)
    #expect(configuration.excludesCurrentProcessAudio)
    #expect(configuration.sampleRate == 48_000)
    #expect(configuration.width == 2 && configuration.height == 2)
    #expect(configuration.minimumFrameInterval.seconds >= 1)
    #expect(!configuration.showsCursor)
  }

  @Test func screenCaptureErrorsMapToCaptureStatus() {
    let declined = NSError(
      domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
    #expect(ScreenCaptureAudioSource.captureError(for: declined) == .permissionDenied)
    let other = NSError(
      domain: NSCocoaErrorDomain, code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Display disconnected"])
    #expect(
      ScreenCaptureAudioSource.captureError(for: other) == .unavailable("Display disconnected"))
  }

  @Test func downmixAveragesPlanarAndInterleavedChannels() {
    let left: [Float] = [1, 0, -1, 0.5]
    let right: [Float] = [0, 1, -1, -0.5]
    let planar = left.withUnsafeBufferPointer { l in
      right.withUnsafeBufferPointer { r in AudioDownmix.mono(planar: [l, r]) }
    }
    #expect(planar == [0.5, 0.5, -1, 0])
    let interleaved: [Float] = [1, 0, 0, 1, -1, -1, 0.5, -0.5]
    let mixed = interleaved.withUnsafeBufferPointer {
      AudioDownmix.mono(interleaved: $0, channels: 2)
    }
    #expect(mixed == [0.5, 0.5, -1, 0])
    let mono = left.withUnsafeBufferPointer { AudioDownmix.mono(interleaved: $0, channels: 1) }
    #expect(mono == left)
  }
}
