import SwiftUI
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// AB-330 stage 1: pins the Poured 2.0 closed pill's motion constants, its
/// ambient-state resolution, and the two-tone label split so any drift in the
/// six-state vocabulary (`SPEC-poured-island` §1c / §4A) fails the build. Stage 2
/// extends this suite alongside the right-slot variants + snapshot regression.
struct PouredPillMotionTests {

    // MARK: - Motion constants (mockup §A keyframes)

    @Test
    func workingLumenConstantsMatchSpec() {
        #expect(PouredPillMotion.Working.period == 3.0)
        #expect(PouredPillMotion.Working.glowRadius == 22)
        #expect(PouredPillMotion.Working.glowOpacity == 0.16)
    }

    @Test
    func manyWorkingAgentsGridConstantsMatchSpec() {
        #expect(PouredPillMotion.AgentsGrid.runningGlowRadius == 6)
        #expect(PouredPillMotion.AgentsGrid.runningGlowOpacity == 0.6)
        #expect(PouredPillMotion.AgentsGrid.idleCellOpacity == 0.5)
    }

    @Test
    func permissionAttnpulseConstantsMatchSpec() {
        #expect(PouredPillMotion.Permission.period == 1.9)
        #expect(PouredPillMotion.Permission.radiusMin == 18)
        #expect(PouredPillMotion.Permission.radiusMax == 34)
        #expect(PouredPillMotion.Permission.spreadMax == 4)
        #expect(PouredPillMotion.Permission.opacityMin == 0.28)
        #expect(PouredPillMotion.Permission.opacityMax == 0.55)
        #expect(PouredPillMotion.Permission.ringWidth == 3)
        #expect(PouredPillMotion.Permission.ringOpacity == 0.22)
    }

    @Test
    func questionGlowConstantsMatchSpec() {
        #expect(PouredPillMotion.Question.glowRadius == 26)
        #expect(PouredPillMotion.Question.glowOpacity == 0.34)
        #expect(PouredPillMotion.Question.glyphBreathePeriod == 2.6)
    }

    @Test
    func settleConstantsMatchSpec() {
        #expect(PouredPillMotion.Settle.duration == 2.6)
        #expect(PouredPillMotion.Settle.greenKeyTime == 0.22)
        #expect(PouredPillMotion.Settle.flashRadius == 30)
        #expect(PouredPillMotion.Settle.flashSpread == 3)
        #expect(PouredPillMotion.Settle.flashOpacity == 0.4)
        #expect(PouredPillMotion.Settle.greenRadius == 22)
        #expect(PouredPillMotion.Settle.greenSpread == 2)
        #expect(PouredPillMotion.Settle.greenOpacity == 0.4)
    }

    // MARK: - Ambient-state resolution

    private func activity(
        _ phase: SessionPhase,
        outcome: SessionOutcome = .success,
        fresh: Bool = true
    ) -> IslandClosedPillActivity {
        IslandClosedPillActivity(phase: phase, outcome: outcome, isOutcomeFresh: fresh)
    }

    private var agentsGrid: IslandRightSlotContent {
        .agents([.session(color: .blue, state: .running), .session(color: .green, state: .idle)])
    }

    @Test
    func resolveFallsBackToModeWhenNoActivity() {
        #expect(PouredPillAmbientState.resolve(activity: nil, mode: .idle, rightSlot: nil) == .idle)
        #expect(PouredPillAmbientState.resolve(activity: nil, mode: .running, rightSlot: nil)
                == .working(manyWorking: false))
        #expect(PouredPillAmbientState.resolve(activity: nil, mode: .running, rightSlot: agentsGrid)
                == .working(manyWorking: true))
        // `.waiting` without a spotlight can't be split — takes the calmer gold
        // question frame, never the loud amber it can't substantiate.
        #expect(PouredPillAmbientState.resolve(activity: nil, mode: .waiting, rightSlot: nil) == .question)
    }

    @Test
    func resolvePermissionAndQuestionFromPhase() {
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.waitingForApproval), mode: .waiting, rightSlot: nil) == .permission)
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.waitingForAnswer), mode: .waiting, rightSlot: nil) == .question)
    }

    @Test
    func resolveWorkingTracksAgentsGrid() {
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.running), mode: .running, rightSlot: .count(1))
            == .working(manyWorking: false))
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.running), mode: .running, rightSlot: agentsGrid)
            == .working(manyWorking: true))
    }

    @Test
    func resolveCompletedGatesOnFreshness() {
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.completed, outcome: .success, fresh: true), mode: .idle, rightSlot: nil)
            == .completed(.success))
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.completed, outcome: .interrupted, fresh: true), mode: .idle, rightSlot: nil)
            == .completed(.interrupted))
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.completed, outcome: .failed, fresh: true), mode: .idle, rightSlot: nil)
            == .completed(.failed))
        // Past the settle window a completion is just another quiet session.
        #expect(PouredPillAmbientState.resolve(
            activity: activity(.completed, outcome: .success, fresh: false), mode: .idle, rightSlot: nil)
            == .idle)
    }

    @Test
    func castsGlowOnlyForLiveAndSuccessStates() {
        #expect(PouredPillAmbientState.idle.castsGlow == false)
        #expect(PouredPillAmbientState.working(manyWorking: false).castsGlow == true)
        #expect(PouredPillAmbientState.permission.castsGlow == true)
        #expect(PouredPillAmbientState.question.castsGlow == true)
        #expect(PouredPillAmbientState.completed(.success).castsGlow == true)
        // A6 interrupted / failed rest with no glow.
        #expect(PouredPillAmbientState.completed(.interrupted).castsGlow == false)
        #expect(PouredPillAmbientState.completed(.failed).castsGlow == false)
    }

    // MARK: - Two-tone narrated label split

    @Test
    func completedLabelSplitsPrefixDimWorkspacePrimary() {
        let segments = PouredPillLabelTone.segments(
            for: "Done · the-automator", ambient: .completed(.success))
        #expect(segments == [
            .init(text: "Done ·", isDim: true),
            .init(text: " the-automator", isDim: false),
        ])
    }

    @Test
    func workingVerbLabelSplitsVerbDimObjectPrimary() {
        let segments = PouredPillLabelTone.segments(
            for: "Editing AppModel.swift", ambient: .working(manyWorking: false))
        #expect(segments == [
            .init(text: "Editing", isDim: true),
            .init(text: " AppModel.swift", isDim: false),
        ])
    }

    @Test
    func manyWorkingLabelMakesCountStrongPrimaryWordDim() {
        let segments = PouredPillLabelTone.segments(
            for: "3 working", ambient: .working(manyWorking: true))
        #expect(segments == [
            .init(text: "3", isDim: false, isStrong: true),
            .init(text: " working", isDim: true),
        ])
    }

    @Test
    func attentionAndIdleLabelsStayWhollyPrimary() {
        #expect(PouredPillLabelTone.segments(for: "Approve swift build?", ambient: .permission)
                == [.init(text: "Approve swift build?", isDim: false)])
        #expect(PouredPillLabelTone.segments(for: "Answer needed", ambient: .question)
                == [.init(text: "Answer needed", isDim: false)])
        #expect(PouredPillLabelTone.segments(for: "", ambient: .idle).isEmpty)
    }
}
