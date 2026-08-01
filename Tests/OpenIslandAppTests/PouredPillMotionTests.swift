import SwiftUI
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// AB-330 stage 1: pins the Poured 2.0 closed pill's motion constants, its
/// ambient-state resolution, and the two-tone label split so any drift in the
/// six-state vocabulary (`SPEC-poured-island` §1c / §4A) fails the build. Stage 2
/// extends this suite alongside the right-slot variants + snapshot regression.
struct PouredPillMotionTests {

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

}

/// Stage 2 regression: the Poured 2.0 closed pill keeps the shipped
/// `V6ClosedPill.*OuterWidth` math **byte-identical** for every (label,
/// rightSlot) combination — the morph frame (and every theme's pill silhouette)
/// depends on it, and the new right-slot variants (amber badge, `?` badge, task
/// chip, usage dial) must render *inside* the slot this already reserves, never
/// widen it.
///
/// The goldens below were computed from the CURRENT formula (stage 1 left the
/// statics untouched), so they pin today's output as the contract. If the width
/// math drifts, this fails — regardless of what the right-slot views draw.
@MainActor
struct PouredClosedPillWidthRegressionTests {

    /// Pinned at a fixed height (38 — the notch closed height); the formula is
    /// height-parametric, so one height is enough to pin its shape.
    private static let height: CGFloat = 38
    private static let tolerance: CGFloat = 0.001

    private func external(_ label: String?, _ rightSlot: IslandRightSlotContent?) -> CGFloat {
        V6ClosedPill.externalOuterWidth(
            label: label, rightSlot: rightSlot, minWidth: 70, height: Self.height
        )
    }

    private func macbook(_ label: String?, notch: CGFloat) -> CGFloat {
        V6ClosedPill.macbookOuterWidth(
            label: label, physicalNotchWidth: notch, height: Self.height
        )
    }

    /// External / top-bar fluid layout — width DOES fold in the right slot, so
    /// each right-slot kind is pinned. The four count-shaped kinds (`.count`,
    /// `.attentionCount`, `.taskCounter`, `.usage`) share the badge width math,
    /// so the Poured variants never move the frame.
    @Test
    func externalOuterWidthGoldensAreUnchanged() {
        #expect(abs(external(nil, nil) - 70) < Self.tolerance)
        #expect(abs(external("Editing AppModel.swift", nil) - 238.6) < Self.tolerance)
        #expect(abs(external("Approve swift build?", .attentionCount(count: 1, kind: .permission)) - 244.4) < Self.tolerance)
        #expect(abs(external("3 working", .count(3)) - 164.1) < Self.tolerance)
        #expect(abs(external(nil, .attentionCount(count: 12, kind: .question)) - 89.6) < Self.tolerance)
        #expect(abs(external("Refactoring", .taskCounter(completed: 2, total: 5, subagents: 0)) - 178.7) < Self.tolerance)
        #expect(abs(external(nil, .usage(percent: 92, windowLabel: "5h", providerTitle: "Claude")) - 89.6) < Self.tolerance)
        #expect(abs(external(nil, .agents([
            .session(color: .blue, state: .running),
            .session(color: .green, state: .idle),
            .session(color: .red, state: .waiting),
        ])) - 96) < Self.tolerance)
        #expect(abs(external("Done · the-automator", nil) - 224) < Self.tolerance)
    }

    /// MacBook / notch layout — outer width does NOT fold in the right slot
    /// (the wings straddle the physical notch), so it depends only on the label
    /// and the notch width. Pinned so the notch-lane math stays put.
    ///
    /// **Halo parity V2 · G-20 (owner-sanctioned, 2026-07-31).** The long-label
    /// golden moved 454 → 540. The notch lane's cap is no longer the fixed 84pt
    /// constant — which truncated every narrated label the redesign asks the
    /// pill to speak — but `V6ClosedPill.notchLaneLabelWidth(physicalNotchWidth:
    /// height:)`, the lane the hardware actually admits before the closed pill
    /// would outgrow the opened panel. At a 180pt cutout and a 38pt pill that is
    /// 127pt, so a 22-character label now lands the pill exactly on
    /// `macbookMaxOuterWidth`. The other two goldens are untouched: a pill with
    /// no label never consults the lane, and `hi` is far under the old 84 floor
    /// — i.e. every short-label pill in every theme is byte-identical.
    @Test
    func macbookOuterWidthGoldensAreUnchanged() {
        #expect(abs(macbook(nil, notch: 180) - 274) < Self.tolerance)
        #expect(abs(macbook("Editing AppModel.swift", notch: 180) - 540) < Self.tolerance)
        #expect(abs(macbook("hi", notch: 200) - 340.4) < Self.tolerance)
    }
}
