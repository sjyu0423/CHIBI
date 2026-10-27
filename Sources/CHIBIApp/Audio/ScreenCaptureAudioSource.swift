import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Screen & System Audio Recording permission checks, injectable so tests never prompt.
struct ScreenCaptureAccess: Sendable {
  var isGranted: @Sendable () -> Bool
  /// Shows the system prompt (first time) or adds CHIBI to the Settings list; returns the result.
  var request: @Sendable () -> Bool

  static let system = ScreenCaptureAccess(
    isGranted: { CGPreflightScreenCaptureAccess() },
    request: { CGRequestScreenCaptureAccess() })
}

/// System audio through ScreenCaptureKit. Audio of every app is captured locally (CHIBI's own
/// output excluded), downmixed to mono, and handed to the analyzer; nothing is stored. A stream
/// always carries video, so it is limited to one discarded 2×2 frame per second.
final class ScreenCaptureAudioSource: NSObject, SystemAudioSource, @unchecked Sendable {
  private let access: ScreenCaptureAccess
  private let queue = DispatchQueue(label: "dev.chibi.system-audio", qos: .userInitiated)
  private let lock = NSLock()
  private var stream: SCStream?
  private var samplesHandler: (@Sendable (AudioChunk) -> Void)?
  private var interruptionHandler: (@Sendable (AudioCaptureError) -> Void)?

  init(access: ScreenCaptureAccess = .system) {
    self.access = access
  }

  func start(
    samples: @escaping @Sendable (AudioChunk) -> Void,
    interrupted: @escaping @Sendable (AudioCaptureError) -> Void
  ) async throws(AudioCaptureError) {
    guard access.isGranted() || access.request() else {
      throw .permissionDenied
    }
    let content: SCShareableContent
    do {
      content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
    } catch {
      throw Self.captureError(for: error)
    }
    guard let display = content.displays.first else {
      throw .unavailable("No display is available for system audio capture.")
    }
    let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
    let stream = SCStream(filter: filter, configuration: Self.configuration(), delegate: self)
    do {
      try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
      try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    } catch {
      throw .unavailable(error.localizedDescription)
    }
    lock.withLock {
      self.stream = stream
      samplesHandler = samples
      interruptionHandler = interrupted
    }
    do {
      try await stream.startCapture()
    } catch {
      _ = detach()
      throw Self.captureError(for: error)
    }
  }

  func stop() async {
    guard let stream = detach() else { return }
    try? await stream.stopCapture()
  }

  static func configuration() -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration()
    configuration.capturesAudio = true
    configuration.excludesCurrentProcessAudio = true
    configuration.sampleRate = 48_000
    configuration.channelCount = 2
    configuration.width = 2
    configuration.height = 2
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    configuration.showsCursor = false
    return configuration
  }

  static func captureError(for error: Error) -> AudioCaptureError {
    let nsError = error as NSError
    if nsError.domain == SCStreamErrorDomain,
      nsError.code == SCStreamError.Code.userDeclined.rawValue
    {
      return .permissionDenied
    }
    return .unavailable(nsError.localizedDescription)
  }

  private func detach() -> SCStream? {
    lock.withLock {
      let current = stream
      stream = nil
      samplesHandler = nil
      interruptionHandler = nil
      return current
    }
  }
}

extension ScreenCaptureAudioSource: SCStreamOutput, SCStreamDelegate {
  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .audio, sampleBuffer.isValid,
      let handler = lock.withLock({ samplesHandler }),
      let chunk = AudioSampleBufferConverter.chunk(from: sampleBuffer)
    else { return }
    handler(chunk)
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    guard let handler = lock.withLock({ interruptionHandler }) else { return }
    _ = detach()
    let failure = Self.captureError(for: error)
    handler(failure == .permissionDenied ? failure : .interrupted(error.localizedDescription))
  }
}

/// Converts ScreenCaptureKit's Float32 PCM sample buffers to mono chunks.
enum AudioSampleBufferConverter {
  static func chunk(from sampleBuffer: CMSampleBuffer) -> AudioChunk? {
    guard
      let format = sampleBuffer.formatDescription?.audioStreamBasicDescription,
      format.mFormatID == kAudioFormatLinearPCM,
      format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
      format.mBitsPerChannel == 32
    else { return nil }
    let channels = Int(format.mChannelsPerFrame)
    let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
    return try? sampleBuffer.withAudioBufferList { list, _ in
      let buffers = list.map { buffer in
        UnsafeBufferPointer(
          start: buffer.mData?.assumingMemoryBound(to: Float.self),
          count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
      }
      let mono =
        interleaved
        ? AudioDownmix.mono(
          interleaved: buffers.first ?? UnsafeBufferPointer(start: nil, count: 0),
          channels: channels)
        : AudioDownmix.mono(planar: buffers)
      return AudioChunk(samples: mono, sampleRate: format.mSampleRate)
    }
  }
}
