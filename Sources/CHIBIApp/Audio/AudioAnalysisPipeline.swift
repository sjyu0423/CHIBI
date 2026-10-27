import Foundation

/// Runs analysis on the capture thread as chunks arrive and forwards only the resulting
/// features. Audio samples are discarded once analyzed.
final class AudioAnalysisPipeline: @unchecked Sendable {
  private let lock = NSLock()
  private let analyzer: AudioFeatureAnalyzer
  private let deliver: @Sendable ([AudioFeatures]) -> Void

  init(
    configuration: AudioAnalysisConfiguration = .init(),
    deliver: @escaping @Sendable ([AudioFeatures]) -> Void
  ) {
    analyzer = AudioFeatureAnalyzer(configuration: configuration)
    self.deliver = deliver
  }

  var configuration: AudioAnalysisConfiguration {
    get { lock.withLock { analyzer.configuration } }
    set { lock.withLock { analyzer.configuration = newValue } }
  }

  func consume(_ chunk: AudioChunk) {
    let features = lock.withLock { analyzer.process(chunk) }
    if !features.isEmpty { deliver(features) }
  }

  func reset() {
    lock.withLock { analyzer.reset() }
  }
}
