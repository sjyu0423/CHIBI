import Foundation

enum CharacterState: String, Equatable, Sendable {
  case idle
  case reacting
  case dragging
  case sleeping
  case walking
  case dancing
  case hopDancing
}

enum CharacterAnimation: String, CaseIterable, Equatable, Sendable {
  case idle
  case happy
  case sleep
  case walk
  case dance
  case hopDance

  var title: String {
    switch self {
    case .idle: "Idle"
    case .happy: "Happy"
    case .sleep: "Sleep"
    case .walk: "Walk in Place"
    case .dance: "Sway Dance"
    case .hopDance: "Hop Dance"
    }
  }
}

enum CharacterEvent: Equatable, Sendable {
  case clicked
  case reactionFinished
  case dragBegan
  case dragEnded
  case sleepRequested
  case wakeRequested
  case previewRequested(CharacterAnimation)
  case musicDanceRequested(MusicDanceLevel)
  case musicStopped
}

/// Single authority for exclusive poses. Music is lowest priority: it drives the pose only from
/// idle or an existing music dance. Its latest request is remembered while a reaction, drag,
/// sleep, or manual looping preview has control, and resumes when the character is idle again.
struct CharacterStateMachine: Sendable {
  private(set) var state: CharacterState = .idle
  /// The music level being presented, or nil when the current pose is not music-driven.
  private(set) var musicLevel: MusicDanceLevel?
  /// The most recent music request, kept while something else has control.
  private(set) var musicTarget: MusicDanceLevel?
  /// A looping preview chosen from the menu, which music must not override.
  private(set) var isManualPreview = false
  private var stateBeforeDragging: CharacterState = .idle
  private var musicLevelBeforeDragging: MusicDanceLevel?

  @discardableResult
  mutating func handle(_ event: CharacterEvent) -> CharacterState {
    switch (state, event) {
    case (.idle, .clicked):
      state = .reacting
    case (.dancing, .clicked), (.hopDancing, .clicked):
      guard musicLevel != nil else { break }
      musicLevel = nil
      state = .reacting
    case (.reacting, .reactionFinished):
      state = .idle
      resumeMusicIfIdle()
    case (.idle, .dragBegan), (.reacting, .dragBegan), (.sleeping, .dragBegan),
      (.walking, .dragBegan), (.dancing, .dragBegan), (.hopDancing, .dragBegan):
      stateBeforeDragging = state == .reacting ? .idle : state
      musicLevelBeforeDragging = musicLevel
      musicLevel = nil
      state = .dragging
    case (.dragging, .dragEnded):
      state = stateBeforeDragging
      if musicLevelBeforeDragging != nil {
        musicLevelBeforeDragging = nil
        state = .idle
      }
      resumeMusicIfIdle()
    case (.idle, .sleepRequested), (.reacting, .sleepRequested), (.walking, .sleepRequested),
      (.dancing, .sleepRequested), (.hopDancing, .sleepRequested):
      state = .sleeping
      musicLevel = nil
      isManualPreview = false
    case (.sleeping, .wakeRequested):
      state = .idle
      resumeMusicIfIdle()
    case (.dragging, .previewRequested):
      break
    case (_, .previewRequested(let animation)):
      state = animation.state
      musicLevel = nil
      isManualPreview = animation.isManualLoop
      resumeMusicIfIdle()
    case (_, .musicDanceRequested(let level)):
      musicTarget = level
      if musicLevel != nil {
        musicLevel = level
        state = level.state
      } else {
        resumeMusicIfIdle()
      }
    case (_, .musicStopped):
      musicTarget = nil
      if musicLevelBeforeDragging != nil {
        musicLevelBeforeDragging = nil
        stateBeforeDragging = .idle
      }
      if musicLevel != nil {
        musicLevel = nil
        state = .idle
      }
    default:
      break
    }
    return state
  }

  private mutating func resumeMusicIfIdle() {
    guard state == .idle, !isManualPreview, let musicTarget else { return }
    musicLevel = musicTarget
    state = musicTarget.state
  }
}

extension MusicDanceLevel {
  fileprivate var state: CharacterState {
    self == .energetic ? .hopDancing : .dancing
  }
}

extension CharacterAnimation {
  fileprivate var state: CharacterState {
    switch self {
    case .idle: .idle
    case .happy: .reacting
    case .sleep: .sleeping
    case .walk: .walking
    case .dance: .dancing
    case .hopDance: .hopDancing
    }
  }

  fileprivate var isManualLoop: Bool {
    self == .walk || self == .dance || self == .hopDance
  }
}
