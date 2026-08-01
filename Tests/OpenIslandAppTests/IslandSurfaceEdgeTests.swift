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

    /// Every shipped theme **except Halo** returns `nil` from the surface edge
    /// hook, so the morph / Reduce-Motion surfaces render byte-identically — the
    /// AC's "no other theme changes" pin. Halo (now registered — T26/AB-345) is the
    /// sole overrider: its whole identity is the living edge, so it traces the
    /// `HaloEdgeLight` ring for every state. A stray override that leaks into any
    /// other theme trips the loop.
    @Test
    func onlyHaloTracesAnEdgeOverlayEveryOtherThemeStaysNil() {
        let shape = OpenedIslandSurfaceShape(
            topProfile: .notch,
            topCornerRadius: 0,
            bottomCornerRadius: 12,
            filletRadius: 0
        )
        // Exercise several states/presentations — the default must be nil for all
        // shipped themes, and non-nil for Halo, across every state/presentation.
        for state in IslandSurfaceEdgeState.allCases {
            for isOpened in [true, false] {
                let context = IslandSurfaceEdgeContext(
                    state: state,
                    isOpened: isOpened,
                    size: CGSize(width: 540, height: 260)
                )
                for theme in ThemeRegistry.all where theme.id != "halo" {
                    #expect(
                        theme.surfaceEdgeOverlay(shape: shape, context: context) == nil,
                        "\(theme.id) must trace no edge overlay (state: \(state), opened: \(isOpened))"
                    )
                }
                // Halo overrides the hook in Part 2 — the one theme whose whole
                // identity is the living edge — so it returns the ring for every state.
                #expect(
                    HaloTheme().surfaceEdgeOverlay(shape: shape, context: context) != nil,
                    "Halo must trace the edge-light (state: \(state), opened: \(isOpened))"
                )
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

}
