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

  @Test func everyPoseKeepsTheSpriteInsideTheRenderArea() throws {
    let manifest = try CharacterAssetLoader.loadBundledDefault()
    let layout = try #require(manifest.fullBodyLayout)
    let path = try #require(manifest.assets.fullBody)
    let texture = try CharacterAssetLoader.bundled.texture(named: path).size()
    let width = texture.width * layout.scale
    let height = texture.height * layout.scale
    let feetY = layout.position.y - height * layout.anchorPoint.y
    let bounds = manifest.renderDimensions
    for state in Self.allStates {
      let motion = FullBodyChoreography.motion(for: state, configuration: manifest.animations)
      let breathY = motion.breath?.allKeyframes.map(\.pose.scaleY).max() ?? 1
      let breathX = motion.breath?.allKeyframes.map(\.pose.scaleX).max() ?? 1
      for pose in motion.body.allKeyframes.map(\.pose) {
        let tallest = height * pose.scaleY * breathY
        let top = feetY + pose.offsetY + tallest * cos(pose.rotation)
        let halfWidth =
          width / 2 * pose.scaleX * breathX + tallest * abs(sin(pose.rotation)) + abs(pose.offsetX)
        #expect(top <= bounds.height / 2, "\(state) clips the top: \(top)")
        #expect(feetY + pose.offsetY >= -bounds.height / 2, "\(state) clips the bottom")
        #expect(halfWidth <= bounds.width / 2, "\(state) clips the sides: \(halfWidth)")
      }
    }
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
