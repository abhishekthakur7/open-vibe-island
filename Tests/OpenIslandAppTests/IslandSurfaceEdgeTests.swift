import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-341 (T22 · Halo edge infrastructure, Part 1): the surface-level edge-light
/// seam — the `IslandTheme.surfaceEdgeOverlay(shape:context:)` hook (default nil
/// so every shipped surface stays byte-identical), the pure "one loud thing"
/// ambient-state resolver, and the `\.haloEdgePhase` freeze environment.
///
/// Part 2 (the `HaloEdgeLight` view) is the only consumer that returns a non-nil
/// overlay; these tests pin the infrastructure it builds on.
///
/// `@MainActor` because `IslandTheme` / `ThemeRegistry` are main-actor.
@MainActor
struct IslandSurfaceEdgeTests {

    private static let now = Date(timeIntervalSince1970: 1_800_000)

    // MARK: - Fixtures

    private func session(
        phase: SessionPhase,
        outcome: SessionOutcome = .success,
        ageSeconds: TimeInterval = 0
    ) -> AgentSession {
        AgentSession(
            id: UUID().uuidString,
            title: "Claude · demo",
            tool: .claudeCode,
            phase: phase,
            outcome: outcome,
            summary: "demo",
            updatedAt: Self.now.addingTimeInterval(-ageSeconds)
        )
    }

    // MARK: - Hook default nil (byte-identical surfaces)

    /// Every registered theme returns `nil` from the surface edge hook, so the
    /// morph / Reduce-Motion surfaces render byte-identically — the AC's "no
    /// shipped theme changes" pin. A premature Part-2 override that leaks into a
    /// shipped theme (or a registration of Halo before it is complete) trips this.
    @Test
    func everyRegisteredThemeReturnsNilEdgeOverlay() {
        let shape = OpenedIslandSurfaceShape(
            topProfile: .notch,
            topCornerRadius: 0,
            bottomCornerRadius: 12,
            filletRadius: 0
        )
        // Exercise several states/presentations — the default must be nil for all.
        for state in IslandSurfaceEdgeState.allCases {
            for isOpened in [true, false] {
                let context = IslandSurfaceEdgeContext(
                    state: state,
                    isOpened: isOpened,
                    size: CGSize(width: 540, height: 260)
                )
                for theme in ThemeRegistry.all {
                    #expect(
                        theme.surfaceEdgeOverlay(shape: shape, context: context) == nil,
                        "\(theme.id) must trace no edge overlay in Part 1 (state: \(state), opened: \(isOpened))"
                    )
                }
                // Halo is unregistered in Part 1 and does not override the hook
                // yet, so it takes the same nil default (Part 2 flips this).
                #expect(HaloTheme().surfaceEdgeOverlay(shape: shape, context: context) == nil)
            }
        }
    }

    // MARK: - Ambient-state resolver ("one loud thing")

    /// The resolver picks exactly one loudest state per the SPEC-halo §4 ladder:
    /// attention > working > success-window > failure > idle, with permission
    /// (amber, hottest) outranking question (qgold, softer) inside attention.
    @Test
    func resolverPicksTheSingleLoudestStateInPriorityOrder() {
        typealias E = IslandSurfaceEdgeState
        let now = Self.now

        // Empty island → the bare hairline.
        #expect(E.resolve(sessions: [], now: now) == .idle)

        // Attention beats working, and permission beats question.
        #expect(E.resolve(sessions: [session(phase: .running), session(phase: .waitingForApproval)], now: now) == .permission)
        #expect(E.resolve(sessions: [session(phase: .running), session(phase: .waitingForAnswer)], now: now) == .question)
        #expect(E.resolve(sessions: [session(phase: .waitingForAnswer), session(phase: .waitingForApproval)], now: now) == .permission)

        // Working beats a fresh success.
        #expect(E.resolve(sessions: [
            session(phase: .completed, outcome: .success, ageSeconds: 1),
            session(phase: .running),
        ], now: now) == .working)

        // A fresh success beats a fresh failure (success-window > failure).
        #expect(E.resolve(sessions: [
            session(phase: .completed, outcome: .failed, ageSeconds: 1),
            session(phase: .completed, outcome: .success, ageSeconds: 1),
        ], now: now) == .success)

        // Failure beats only idle — it is the quietest loud thing.
        #expect(E.resolve(sessions: [session(phase: .completed, outcome: .failed, ageSeconds: 1)], now: now) == .failure)

        // The whole ladder together resolves to the single loudest (permission).
        #expect(E.resolve(sessions: [
            session(phase: .completed, outcome: .failed, ageSeconds: 1),
            session(phase: .completed, outcome: .success, ageSeconds: 1),
            session(phase: .running),
            session(phase: .waitingForAnswer),
            session(phase: .waitingForApproval),
        ], now: now) == .permission)
    }

    /// The loudness ranks encode the exact SPEC-halo §4 priority order, so the
    /// fold is total and unambiguous.
    @Test
    func loudnessRanksEncodeTheAttentionLadder() {
        #expect(IslandSurfaceEdgeState.permission.loudnessRank > IslandSurfaceEdgeState.question.loudnessRank)
        #expect(IslandSurfaceEdgeState.question.loudnessRank > IslandSurfaceEdgeState.working.loudnessRank)
        #expect(IslandSurfaceEdgeState.working.loudnessRank > IslandSurfaceEdgeState.success.loudnessRank)
        #expect(IslandSurfaceEdgeState.success.loudnessRank > IslandSurfaceEdgeState.failure.loudnessRank)
        #expect(IslandSurfaceEdgeState.failure.loudnessRank > IslandSurfaceEdgeState.idle.loudnessRank)
        // All six ranks are distinct — no two states ever tie.
        let ranks = IslandSurfaceEdgeState.allCases.map(\.loudnessRank)
        #expect(Set(ranks).count == IslandSurfaceEdgeState.allCases.count)
    }

    /// Per-session mapping: phase → state, attention forks permission/question,
    /// and a completion wears its verdict only inside the settle window — after
    /// which it recedes to idle, and an interrupted completion casts no light.
    @Test
    func perSessionEdgeStateMapsPhaseOutcomeAndFreshness() {
        typealias E = IslandSurfaceEdgeState
        let now = Self.now

        #expect(E.edgeState(for: session(phase: .running), now: now) == .working)
        #expect(E.edgeState(for: session(phase: .waitingForApproval), now: now) == .permission)
        #expect(E.edgeState(for: session(phase: .waitingForAnswer), now: now) == .question)

        // Fresh completions wear their verdict…
        #expect(E.edgeState(for: session(phase: .completed, outcome: .success, ageSeconds: 1), now: now) == .success)
        #expect(E.edgeState(for: session(phase: .completed, outcome: .failed, ageSeconds: 1), now: now) == .failure)
        // …interrupted casts no glow even while fresh (§A6).
        #expect(E.edgeState(for: session(phase: .completed, outcome: .interrupted, ageSeconds: 1), now: now) == .idle)

        // A stale completion (past the settle window) recedes to the hairline —
        // no permanent green/red badge (§A5 "a moment, not a permanent badge").
        let staleAge = IslandClosedPillTiming.outcomeLabelWindow + 5
        #expect(E.edgeState(for: session(phase: .completed, outcome: .success, ageSeconds: staleAge), now: now) == .idle)
        #expect(E.edgeState(for: session(phase: .completed, outcome: .failed, ageSeconds: staleAge), now: now) == .idle)
    }

    /// A completed process old enough that its presence reads `.inactive` never
    /// keeps a loud edge — it resolves to idle regardless of stored outcome.
    @Test
    func inactiveProcessRecedesToIdle() {
        // 30 min past the last update → `islandPresence == .inactive`.
        let deadAge: TimeInterval = 30 * 60
        #expect(
            IslandSurfaceEdgeState.edgeState(
                for: session(phase: .completed, outcome: .failed, ageSeconds: deadAge),
                now: Self.now
            ) == .idle
        )
    }

    // MARK: - Context payload

    @Test
    func contextCarriesStateOpenedAndGeometry() {
        let context = IslandSurfaceEdgeContext(
            state: .permission,
            isOpened: false,
            size: CGSize(width: 214, height: 38)
        )
        #expect(context.state == .permission)
        #expect(context.isOpened == false)
        #expect(context.size == CGSize(width: 214, height: 38))
        // Value semantics — two equal payloads compare equal (drives SwiftUI diffing).
        #expect(context == IslandSurfaceEdgeContext(state: .permission, isOpened: false, size: CGSize(width: 214, height: 38)))
        #expect(context != IslandSurfaceEdgeContext(state: .question, isOpened: false, size: CGSize(width: 214, height: 38)))
    }

    // MARK: - Phase-freeze environment

    /// `\.haloEdgePhase` defaults to nil (live clocks) and round-trips a frozen
    /// phase through the environment, so the snapshot harness can pin the orbit,
    /// pulse and bloom at a settled angle 0 / pulse 0 — two reads at the same
    /// frozen phase are equal, i.e. deterministic (SPEC-halo §6.3).
    @Test
    func haloEdgePhaseDefaultsLiveAndFreezesDeterministically() {
        var env = EnvironmentValues()
        // Production: nil → the edge runs off its live clocks.
        #expect(env.haloEdgePhase == nil)

        // Freeze at the canonical settled frame.
        env.haloEdgePhase = .frozen
        #expect(env.haloEdgePhase == HaloEdgePhase(orbitAngle: 0, pulse: 0))
        #expect(env.haloEdgePhase?.orbitAngle == 0)
        #expect(env.haloEdgePhase?.pulse == 0)
        // Two reads at the same frozen phase are equal — the determinism the
        // harness relies on for reproducible edge-light snapshots.
        #expect(env.haloEdgePhase == env.haloEdgePhase)

        // A distinct phase is distinguishable (the freeze actually carries state).
        env.haloEdgePhase = HaloEdgePhase(orbitAngle: 180, pulse: 0.5)
        #expect(env.haloEdgePhase != .frozen)
        #expect(env.haloEdgePhase?.orbitAngle == 180)
        #expect(env.haloEdgePhase?.pulse == 0.5)
    }
}
