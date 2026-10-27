import AppKit
import SpriteKit
import Testing

@testable import CHIBIApp

struct FullBodyAnimationTests {
  private static let allStates: [CharacterState] = [
    .idle, .reacting, .dragging, .sleeping, .walking, .dancing, .hopDancing,
  ]

  @Test func everyStateHasValidKeyframes() throws {
    let configuration = try CharacterAssetLoader.loadBundledDefault().animations
    for state in Self.allStates {
      let motion = FullBodyChoreography.motion(for: state, configuration: configuration)
      #expect(!motion.body.allKeyframes.isEmpty, "\(state) has no body motion")
      let durations =
        motion.body.allKeyframes.map(\.duration)
        + (motion.breath?.allKeyframes.map(\.duration) ?? [])
        + (motion.expression?.allKeyframes.map(\.duration) ?? [])
      #expect(durations.allSatisfy { $0.isFinite && $0 > 0 }, "\(state) has invalid durations")
    }
  }

  @Test func onlyTheHappyReactionFinishesAndItEndsAtRest() throws {
    let configuration = try CharacterAssetLoader.loadBundledDefault().animations
    for state in Self.allStates {
      let motion = FullBodyChoreography.motion(for: state, configuration: configuration)
      #expect(motion.finishes == (state == .reacting), "\(state) completion mismatch")
    }
    let happy = FullBodyChoreography.motion(for: .reacting, configuration: configuration)
    #expect(happy.body.intro.last?.pose == .rest)
    #expect(happy.expression?.intro.last?.pose == .rest)
    #expect(happy.body.introDuration < 1.5)
  }

  @Test func expressionLoopsStaySynchronizedWithBodyLoops() throws {
    let configuration = try CharacterAssetLoader.loadBundledDefault().animations
    for state in Self.allStates {
      let motion = FullBodyChoreography.motion(for: state, configuration: configuration)
      guard let expression = motion.expression, !expression.isFinite, !motion.body.isFinite
      else { continue }
      #expect(
        abs(expression.introDuration - motion.body.introDuration) < 0.35 * motion.body.loopDuration)
      let ratio = expression.loopDuration / motion.body.loopDuration
      #expect(abs(ratio - ratio.rounded()) < 1e-9, "\(state) expression drifts from body")
    }
  }

  private static let musicMotions: [(CharacterState, MotionStyle)] = MusicDanceLevel.allCases
    .map { level in (level == .energetic ? .hopDancing : .dancing, .music(level)) }

  @Test func everyPoseKeepsTheSpriteInsideTheRenderArea() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    let layout = try #require(manifest.fullBodyLayout)
    let path = try #require(manifest.assets.fullBody)
    let texture = try CharacterAssetLoader.bundled.texture(named: path).size()
    let width = texture.width * layout.scale
    let height = texture.height * layout.scale
    let feetY = layout.position.y - height * layout.anchorPoint.y
    let bounds = manifest.renderDimensions
    let standard = Self.allStates.map { ($0, MotionStyle.standard) }
    for (state, style) in standard + Self.musicMotions {
      let motion = FullBodyChoreography.motion(
        for: state, style: style, configuration: manifest.animations)
      let breathY = motion.breath?.allKeyframes.map(\.pose.scaleY).max() ?? 1
      // Beat accents squash at most 5.5% and widen at most 3.3%.
      let accentX = style.isMusic ? 1.033 : 1
      let breathX = (motion.breath?.allKeyframes.map(\.pose.scaleX).max() ?? 1) * accentX
      for pose in motion.body.allKeyframes.map(\.pose) {
        let tallest = height * pose.scaleY * breathY
        let top = feetY + pose.offsetY + tallest * cos(pose.rotation)
        let halfWidth =
          width / 2 * pose.scaleX * breathX + tallest * abs(sin(pose.rotation)) + abs(pose.offsetX)
        #expect(top <= bounds.height / 2, "\(state) \(style) clips the top: \(top)")
        #expect(feetY + pose.offsetY >= -bounds.height / 2, "\(state) \(style) clips the bottom")
        #expect(halfWidth <= bounds.width / 2, "\(state) \(style) clips the sides: \(halfWidth)")
      }
    }
  }

  @Test func musicChoreographyLoopsSpanWholeBeatsAndStaySynchronized() throws {
    let configuration = try CharacterAssetLoader.loadBundledDefault().animations
    let beat = configuration.danceBeatDuration
    for (state, style) in Self.musicMotions {
      let motion = FullBodyChoreography.motion(
        for: state, style: style, configuration: configuration)
      #expect(!motion.finishes)
      let beats = motion.body.loopDuration / beat
      #expect(abs(beats - beats.rounded()) < 1e-9, "\(style) loop is \(beats) beats")
      let expression = try #require(motion.expression)
      #expect(abs(expression.loopDuration - motion.body.loopDuration) < 1e-9)
      #expect(abs(expression.introDuration - motion.body.introDuration) < 1e-9)
      let durations = motion.body.allKeyframes.map(\.duration)
      #expect(durations.allSatisfy { $0.isFinite && $0 > 0 })
    }
    let gentle = FullBodyChoreography.motion(
      for: .dancing, style: .music(.gentle), configuration: configuration)
    let rhythmic = FullBodyChoreography.motion(
      for: .dancing, style: .music(.rhythmic), configuration: configuration)
    #expect(rhythmic == FullBodyChoreography.motion(for: .dancing, configuration: configuration))
    let gentleReach = gentle.body.loop.map { abs($0.pose.offsetX) }.max()!
    let rhythmicReach = rhythmic.body.loop.map { abs($0.pose.offsetX) }.max()!
    #expect(gentleReach < rhythmicReach * 0.6)
    #expect(gentle.body.loopDuration == rhythmic.body.loopDuration * 2)
  }

  @Test func tempoScaleFollowsTheBeatAndFoldsIntoAComfortableRange() throws {
    let configuration = try CharacterAssetLoader.loadBundledDefault().animations
    let base = configuration.danceBeatDuration
    #expect(
      abs(FullBodyChoreography.tempoScale(forBeatDuration: base, configuration: configuration) - 1)
        < 1e-9)
    let at120 = FullBodyChoreography.tempoScale(forBeatDuration: 0.5, configuration: configuration)
    #expect(abs(at120 - base / 0.5) < 1e-9)
    for bpm in stride(from: 40.0, through: 240, by: 7) {
      let scale = FullBodyChoreography.tempoScale(
        forBeatDuration: 60 / bpm, configuration: configuration)
      #expect(scale >= 0.7 && scale <= 1.4, "\(bpm) BPM -> \(scale)")
      let ratio = log2(scale * (60 / bpm) / base)
      #expect(abs(ratio - ratio.rounded()) < 1e-9, "\(bpm) BPM is not octave-folded")
    }
    #expect(FullBodyChoreography.tempoScale(forBeatDuration: 0, configuration: configuration) == 1)
  }

  @Test func blendedTracksEaseIntoTheFirstKeyframeWithoutChangingTheLoop() {
    let a = FullBodyPose(rotation: 0.1)
    let b = FullBodyPose(rotation: -0.1)
    let loop = MotionTrack(loop: [
      MotionKeyframe(pose: a, duration: 0.5), MotionKeyframe(pose: b, duration: 0.3),
    ])
    let blended = loop.blended(over: 0.2)
    #expect(blended.intro == [MotionKeyframe(pose: a, duration: 0.2)])
    #expect(blended.loop.map(\.pose) == [b, a])
    #expect(blended.loopDuration == loop.loopDuration)

    let withIntro = MotionTrack(
      intro: [MotionKeyframe(pose: a, duration: 0.1)], loop: [MotionKeyframe(pose: b, duration: 1)])
    #expect(withIntro.blended(over: 0.4).intro[0].duration == 0.4)
    #expect(withIntro.blended(over: 0.05).intro[0].duration == 0.1)
    #expect(withIntro.blended(over: 0.4).loop == withIntro.loop)
  }

  @Test @MainActor func blendKeepsTheCurrentPoseWhileResetRestoresBaseline() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    let node = try #require(FullBodyCharacterNode(manifest: manifest, assetLoader: .bundled))
    let animator = FullBodyCharacterAnimator(character: node, configuration: manifest.animations)
    animator.play(state: .idle)
    node.bodyPivot.zRotation = 0.03
    node.position = CGPoint(x: 4, y: 2)
    node.breathPivot.yScale = 1.01

    animator.play(state: .dancing, style: .music(.gentle), transition: .blend(0.35))
    #expect(abs(node.bodyPivot.zRotation - 0.03) < 1e-6 && node.position == CGPoint(x: 4, y: 2))
    #expect(node.bodyPivot.hasActions() && node.breathPivot.hasActions())
    #expect(node.sprite.warpGeometry != nil)

    animator.play(state: .hopDancing, style: .music(.energetic), transition: .blend(0.35))
    #expect(node.breathPivot.action(forKey: "character.full-body.breath") != nil)

    animator.play(state: .idle)
    #expect(node.bodyPivot.zRotation == 0 && node.position == .zero)
    #expect(node.breathPivot.yScale == 1)
  }

  @Test @MainActor func accentsAndTempoApplyOnlyToMusicStyles() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    let node = try #require(FullBodyCharacterNode(manifest: manifest, assetLoader: .bundled))
    let animator = FullBodyCharacterAnimator(character: node, configuration: manifest.animations)
    animator.setMusicTempo(beatDuration: 0.5)
    animator.play(state: .dancing)
    #expect(node.speed == 1)
    animator.accentBeat(strength: 1)
    #expect(!node.accentPivot.hasActions())

    animator.play(state: .dancing, style: .music(.rhythmic), transition: .blend(0.35))
    #expect(abs(node.speed - manifest.animations.danceBeatDuration / 0.5) < 1e-6)
    animator.accentBeat(strength: 1)
    #expect(node.accentPivot.hasActions())
    animator.setMusicTempo(beatDuration: nil)
    #expect(node.speed == 1)

    animator.play(state: .dragging)
    #expect(node.speed == 1 && !node.accentPivot.hasActions())
    #expect(node.accentPivot.xScale == 1 && node.accentPivot.yScale == 1)
  }

  @Test @MainActor func sceneReplaysOnlyWhenTheMusicPresentationChanges() throws {
    let scene = CharacterScene()
    let pivot = try #require(scene.childNode(withName: "//full-body-pivot"))
    let accent = try #require(scene.childNode(withName: "//full-body-accent"))
    scene.applyMusic(.dance(.gentle))
    #expect(scene.state == .dancing && scene.musicLevel == .gentle)
    let body = try #require(pivot.action(forKey: "character.full-body.body"))
    scene.applyMusic(.dance(.gentle))
    scene.applyMusic(.tempo(beatDuration: 0.5))
    #expect(pivot.action(forKey: "character.full-body.body") === body)
    scene.applyMusic(.accent(strength: 0.8))
    #expect(accent.hasActions())

    scene.applyMusic(.dance(.energetic))
    #expect(scene.state == .hopDancing)
    #expect(pivot.action(forKey: "character.full-body.body") !== body)

    scene.beginDragging()
    scene.applyMusic(.accent(strength: 1))
    scene.applyMusic(.dance(.rhythmic))
    #expect(scene.state == .dragging && scene.musicLevel == nil)
    scene.endDragging()
    #expect(scene.state == .dancing && scene.musicLevel == .rhythmic)

    scene.previewAnimation(.walk)
    scene.applyMusic(.dance(.energetic))
    #expect(scene.state == .walking)
    scene.previewAnimation(.idle)
    #expect(scene.state == .hopDancing && scene.musicLevel == .energetic)

    scene.applyMusic(.settle)
    #expect(scene.state == .idle && scene.musicLevel == nil)
  }

  @Test func bundledRigIsRegisteredAndInvalidRigsAreRejected() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    #expect(manifest.fullBodyRig?.isValid == true)

    var broken = manifest
    broken.fullBodyRig = CharacterManifest.FullBodyRig(
      neck: .init(x: 0.5, y: 0.46), headBlendHeight: 0.07, maxHeadTilt: 0.5, hairTipY: 0.46,
      hairRootY: 0.72, maxHairSway: 0.014)
    #expect(throws: CharacterManifestError.invalidFullBodyRig) { try broken.validated() }
    broken.fullBodyRig = CharacterManifest.FullBodyRig(
      neck: .init(x: 0.5, y: 0.46), headBlendHeight: 0.07, maxHeadTilt: 0.03, hairTipY: 0.8,
      hairRootY: 0.72, maxHairSway: 0.014)
    #expect(throws: CharacterManifestError.invalidFullBodyRig) { try broken.validated() }
  }

  @Test func restWarpIsIdentityAndBodyBelowTheNeckNeverMoves() throws {
    let rig = try #require(CharacterAssetLoader.loadBundledDefault().fullBodyRig)
    let source = FullBodyWarp.sourcePositions()
    #expect(source.count == FullBodyWarp.vertexCount)
    #expect(FullBodyWarp.destinationPositions(rig: rig, expression: .rest, aspect: 0.6) == source)

    let extreme = FullBodyWarp.destinationPositions(
      rig: rig, expression: FullBodyExpression(headTilt: 1, hairSway: 1), aspect: 0.6)
    let fixedBelow = min(rig.neck.y - rig.headBlendHeight, rig.hairTipY - 0.05)
    for (from, to) in zip(source, extreme) where Double(from.y) <= fixedBelow {
      #expect(from == to, "Vertex below the neck moved: \(from) -> \(to)")
    }
    for (from, to) in zip(source, extreme) {
      #expect(abs(to.x - from.x) < 0.06 && abs(to.y - from.y) < 0.06)
    }
  }

  @Test func positiveHeadTiltRotatesTheHeadCounterClockwise() throws {
    let rig = try #require(CharacterAssetLoader.loadBundledDefault().fullBodyRig)
    let source = FullBodyWarp.sourcePositions()
    let tilted = FullBodyWarp.destinationPositions(
      rig: rig, expression: FullBodyExpression(headTilt: 1), aspect: 0.6)
    let top = try #require(
      source.indices.first { source[$0].y == 1 && abs(source[$0].x - 0.5) < 1e-6 })
    #expect(tilted[top].x < source[top].x)
  }

  @Test @MainActor func feetPivotKeepsTheSpriteAtItsLayoutPosition() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    let layout = try #require(manifest.fullBodyLayout)
    let node = try #require(FullBodyCharacterNode(manifest: manifest, assetLoader: .bundled))
    let center = node.convert(node.sprite.position, from: node.spriteRoot)
    #expect(abs(center.x - layout.position.x) < 1e-3)
    #expect(abs(center.y - layout.position.y) < 1e-3)
    #expect(abs(node.bodyPivot.position.y - (layout.position.y - node.spriteHeight / 2)) < 1e-3)
  }

  @Test @MainActor func playingAStateReplacesActionsAndExpressiveToggleControlsWarp() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    let node = try #require(FullBodyCharacterNode(manifest: manifest, assetLoader: .bundled))
    let animator = FullBodyCharacterAnimator(character: node, configuration: manifest.animations)
    #expect(animator.supportsExpressiveMotion && animator.isExpressiveMotionEnabled)

    animator.play(state: .sleeping)
    #expect(node.action(forKey: "character.full-body.translation") != nil)
    #expect(node.bodyPivot.hasActions() && node.breathPivot.hasActions())
    #expect(node.effectsRoot.hasActions())
    #expect(node.sprite.warpGeometry != nil)

    animator.play(state: .walking)
    #expect(!node.breathPivot.hasActions())
    #expect(!node.effectsRoot.hasActions() && node.effectsRoot.children.isEmpty)

    animator.isExpressiveMotionEnabled = false
    #expect(node.sprite.warpGeometry == nil && !node.sprite.hasActions())
    #expect(node.bodyPivot.hasActions())

    node.resetPose()
    #expect(!node.hasActions() && !node.bodyPivot.hasActions())
    #expect(node.bodyPivot.zRotation == 0 && node.bodyPivot.xScale == 1 && node.position == .zero)
  }

  @Test @MainActor func sceneDeveloperControlsClampSpeedAndRespectRigSupport() {
    let scene = CharacterScene()
    scene.setAnimationSpeed(0.25)
    #expect(scene.speed == 0.25)
    scene.setAnimationSpeed(100)
    #expect(scene.speed == 4)
    #expect(scene.supportsExpressiveMotion)
    scene.setExpressiveMotionEnabled(false)
    #expect(!scene.isExpressiveMotionEnabled)
    scene.previewAnimation(.hopDance)
    #expect(scene.state == .hopDancing)
  }
}
