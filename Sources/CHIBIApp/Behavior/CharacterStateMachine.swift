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
}

struct CharacterStateMachine: Sendable {
  private(set) var state: CharacterState = .idle
  private var stateBeforeDragging: CharacterState = .idle

  @discardableResult
  mutating func handle(_ event: CharacterEvent) -> CharacterState {
    switch (state, event) {
    case (.idle, .clicked):
      state = .reacting
    case (.reacting, .reactionFinished):
      state = .idle
    case (.idle, .dragBegan), (.reacting, .dragBegan), (.sleeping, .dragBegan),
      (.walking, .dragBegan), (.dancing, .dragBegan), (.hopDancing, .dragBegan):
      stateBeforeDragging = state == .reacting ? .idle : state
      state = .dragging
    case (.dragging, .dragEnded):
      state = stateBeforeDragging
    case (.idle, .sleepRequested), (.reacting, .sleepRequested), (.walking, .sleepRequested),
      (.dancing, .sleepRequested), (.hopDancing, .sleepRequested):
      state = .sleeping
    case (.sleeping, .wakeRequested):
      state = .idle
    case (.dragging, .previewRequested):
      break
    case (_, .previewRequested(let animation)):
      state = animation.state
    default:
      break
    }
    return state
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
}
