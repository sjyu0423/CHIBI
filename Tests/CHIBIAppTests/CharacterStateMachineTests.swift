import Testing

@testable import CHIBIApp

struct CharacterStateMachineTests {
  @Test func clickReactionCompletesBackToIdle() {
    var machine = CharacterStateMachine()
    #expect(machine.handle(.clicked) == .reacting)
    #expect(machine.handle(.reactionFinished) == .idle)
  }

  @Test func conflictingClickDoesNotInterruptReaction() {
    var machine = CharacterStateMachine()
    machine.handle(.clicked)
    #expect(machine.handle(.clicked) == .reacting)
  }

  @Test func draggingInterruptsReactionAndReturnsToIdle() {
    var machine = CharacterStateMachine()
    machine.handle(.clicked)
    #expect(machine.handle(.dragBegan) == .dragging)
    #expect(machine.handle(.dragEnded) == .idle)
  }

  @Test func draggingSleepingCharacterReturnsToSleep() {
    var machine = CharacterStateMachine()
    machine.handle(.sleepRequested)
    #expect(machine.handle(.dragBegan) == .dragging)
    #expect(machine.handle(.dragEnded) == .sleeping)
  }

  @Test func invalidTransitionsAreIgnored() {
    var machine = CharacterStateMachine()
    #expect(machine.handle(.reactionFinished) == .idle)
    machine.handle(.sleepRequested)
    #expect(machine.handle(.clicked) == .sleeping)
  }

  @Test func previewAnimationsCanReplaceEachOther() {
    var machine = CharacterStateMachine()
    #expect(machine.handle(.previewRequested(.walk)) == .walking)
    #expect(machine.handle(.previewRequested(.dance)) == .dancing)
    #expect(machine.handle(.previewRequested(.sleep)) == .sleeping)
    #expect(machine.handle(.previewRequested(.happy)) == .reacting)
    #expect(machine.handle(.reactionFinished) == .idle)
  }

  @Test func draggingRestoresLoopingPreview() {
    var machine = CharacterStateMachine()
    machine.handle(.previewRequested(.dance))
    #expect(machine.handle(.dragBegan) == .dragging)
    #expect(machine.handle(.dragEnded) == .dancing)
  }

  @Test func hopDancePreviewCanBeDraggedSleptAndReplaced() {
    var machine = CharacterStateMachine()
    #expect(machine.handle(.previewRequested(.hopDance)) == .hopDancing)
    #expect(machine.handle(.dragBegan) == .dragging)
    #expect(machine.handle(.previewRequested(.dance)) == .dragging)
    #expect(machine.handle(.dragEnded) == .hopDancing)
    #expect(machine.handle(.clicked) == .hopDancing)
    #expect(machine.handle(.sleepRequested) == .sleeping)
    #expect(machine.handle(.previewRequested(.hopDance)) == .hopDancing)
    #expect(machine.handle(.previewRequested(.idle)) == .idle)
  }

  @Test func everyPreviewAnimationMapsToADistinctState() {
    var states: Set<String> = []
    for animation in CharacterAnimation.allCases {
      var machine = CharacterStateMachine()
      states.insert(machine.handle(.previewRequested(animation)).rawValue)
    }
    #expect(states.count == CharacterAnimation.allCases.count)
  }

  @Test func draggingInterruptsHappyPreviewToIdle() {
    var machine = CharacterStateMachine()
    machine.handle(.previewRequested(.happy))
    #expect(machine.handle(.dragBegan) == .dragging)
    #expect(machine.handle(.dragEnded) == .idle)
  }
}
