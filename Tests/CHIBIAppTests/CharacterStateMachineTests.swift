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

  @Test func musicDrivesDanceLevelsFromIdleAndSettlesBack() {
    var machine = CharacterStateMachine()
    #expect(machine.handle(.musicDanceRequested(.gentle)) == .dancing)
    #expect(machine.musicLevel == .gentle)
    #expect(machine.handle(.musicDanceRequested(.rhythmic)) == .dancing)
    #expect(machine.musicLevel == .rhythmic)
    #expect(machine.handle(.musicDanceRequested(.energetic)) == .hopDancing)
    #expect(machine.handle(.musicStopped) == .idle)
    #expect(machine.musicLevel == nil && machine.musicTarget == nil)
  }

  @Test func draggingOverridesMusicAndResumesTheLatestLevel() {
    var machine = CharacterStateMachine()
    machine.handle(.musicDanceRequested(.rhythmic))
    #expect(machine.handle(.dragBegan) == .dragging)
    #expect(machine.musicLevel == nil)
    #expect(machine.handle(.musicDanceRequested(.energetic)) == .dragging)
    #expect(machine.handle(.dragEnded) == .hopDancing)
    #expect(machine.musicLevel == .energetic)
  }

  @Test func musicStoppingDuringADragEndsInIdle() {
    var machine = CharacterStateMachine()
    machine.handle(.musicDanceRequested(.energetic))
    machine.handle(.dragBegan)
    #expect(machine.handle(.musicStopped) == .dragging)
    #expect(machine.handle(.dragEnded) == .idle)
    #expect(machine.musicLevel == nil)
  }

  @Test func manualLoopingPreviewsOverrideMusicUntilIdlePreview() {
    var machine = CharacterStateMachine()
    machine.handle(.musicDanceRequested(.energetic))
    #expect(machine.handle(.previewRequested(.walk)) == .walking)
    #expect(machine.musicLevel == nil && machine.isManualPreview)
    #expect(machine.handle(.musicDanceRequested(.rhythmic)) == .walking)
    machine.handle(.dragBegan)
    #expect(machine.handle(.dragEnded) == .walking)
    #expect(machine.handle(.musicStopped) == .walking)
    machine.handle(.musicDanceRequested(.gentle))
    #expect(machine.handle(.previewRequested(.idle)) == .dancing)
    #expect(machine.musicLevel == .gentle && !machine.isManualPreview)
  }

  @Test func manualDancePreviewIsNotMistakenForMusic() {
    var machine = CharacterStateMachine()
    machine.handle(.previewRequested(.dance))
    #expect(machine.handle(.musicDanceRequested(.energetic)) == .dancing)
    #expect(machine.musicLevel == nil)
    #expect(machine.handle(.clicked) == .dancing)
  }

  @Test func clickingAMusicDancePlaysTheReactionThenResumes() {
    var machine = CharacterStateMachine()
    machine.handle(.musicDanceRequested(.rhythmic))
    #expect(machine.handle(.clicked) == .reacting)
    #expect(machine.musicLevel == nil)
    #expect(machine.handle(.musicDanceRequested(.gentle)) == .reacting)
    #expect(machine.handle(.reactionFinished) == .dancing)
    #expect(machine.musicLevel == .gentle)
  }

  @Test func sleepingIgnoresMusicUntilWoken() {
    var machine = CharacterStateMachine()
    machine.handle(.musicDanceRequested(.rhythmic))
    #expect(machine.handle(.sleepRequested) == .sleeping)
    #expect(machine.handle(.musicDanceRequested(.energetic)) == .sleeping)
    #expect(machine.handle(.wakeRequested) == .hopDancing)
    machine.handle(.sleepRequested)
    machine.handle(.musicStopped)
    #expect(machine.handle(.wakeRequested) == .idle)
  }

  @Test func happyPreviewDuringMusicReturnsToTheMusicDance() {
    var machine = CharacterStateMachine()
    machine.handle(.musicDanceRequested(.gentle))
    #expect(machine.handle(.previewRequested(.happy)) == .reacting)
    #expect(machine.handle(.reactionFinished) == .dancing)
    #expect(machine.musicLevel == .gentle)
  }
}
