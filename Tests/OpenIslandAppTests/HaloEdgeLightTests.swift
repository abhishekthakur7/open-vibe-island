import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-341 (T22 · Halo perimeter edge-light engine, Part 2): the `HaloEdgeLight`
/// view + its pure, view-free `HaloEdgeLightModel`. These pin the load-bearing
/// stop tables (exact colours + degree positions per state, SPEC-halo §1a), the
/// bloom specs, the `.55↔1` / dissolve opacity curves, and — critically — the
/// Reduce-Motion statics (§3c): every animated value collapses to a
/// **phase-independent** peak/settled frame under Reduce Motion, so the view has
/// no reason to acquire a clock (the `AnnualSessionRowFormat` proof pattern).
///
/// The colours are compared with `==` against the same token / `HaloEdge`
/// expressions the model builds them from, so equality is exact (not approximate).
@MainActor
struct HaloEdgeLightTests {

    private let colors = IslandColorTokens.halo

    private func stops(_ state: IslandSurfaceEdgeState, reduceMotion: Bool = false, increaseContrast: Bool = false) -> [HaloEdgeStop] {
        HaloEdgeLightModel.stops(for: state, colors: colors, reduceMotion: reduceMotion, increaseContrast: increaseContrast)
    }

    // MARK: - Stop tables (SPEC §1a — exact colours + degrees)

    @Test
    func idleIsAFlatEightPercentWhiteHairline() {
        let s = stops(.idle)
        #expect(s == [HaloEdgeStop(Color.white.opacity(0.08), 0), HaloEdgeStop(Color.white.opacity(0.08), 360)])
        // The hairline reads the pinned token, not a literal.
        #expect(colors.hairlineOpacity == 0.08)
    }

    /// Increase Contrast brightens the idle hairline 0.08 → 0.24 (the token the
    /// edge consumes). Only idle changes with contrast — the coloured states already
    /// clear contrast on pure black.
    @Test
    func idleHairlineBrightensUnderIncreaseContrast() {
        let s = stops(.idle, increaseContrast: true)
        #expect(s == [HaloEdgeStop(Color.white.opacity(0.24), 0), HaloEdgeStop(Color.white.opacity(0.24), 360)])
        #expect(colors.hairlineOpacityIncreasedContrast == 0.24)
        // A coloured state is unchanged by Increase Contrast.
        #expect(stops(.working, increaseContrast: true) == stops(.working, increaseContrast: false))
    }

    @Test
    func workingOrbitStopsMatchTheSpec() {
        let hair = HaloEdge.hair2
        #expect(stops(.working) == [
            HaloEdgeStop(hair, 0), HaloEdgeStop(hair, 176),
            HaloEdgeStop(colors.statusRunning, 232), HaloEdgeStop(HaloEdge.violet, 300),
            HaloEdgeStop(hair, 348), HaloEdgeStop(hair, 360),
        ])
    }

    /// §3c: under Reduce Motion the working segment becomes a full cyan→violet
    /// ring (no white filler, no orbit), so the running state stays legible frozen.
    @Test
    func workingReduceMotionIsTheFullCyanVioletRing() {
        #expect(stops(.working, reduceMotion: true) == [
            HaloEdgeStop(colors.statusRunning, 0),
            HaloEdgeStop(HaloEdge.violet, 180),
            HaloEdgeStop(colors.statusRunning, 360),
        ])
        // It genuinely differs from the orbiting table.
        #expect(stops(.working, reduceMotion: true) != stops(.working, reduceMotion: false))
    }

    @Test
    func permissionStopsMatchTheSpecAmberMagentaBand() {
        let amber = colors.statusWaitingForApproval
        #expect(stops(.permission) == [
            HaloEdgeStop(amber.opacity(0.04), 0), HaloEdgeStop(amber, 40),
            HaloEdgeStop(HaloEdge.magenta, 84), HaloEdgeStop(amber, 128),
            HaloEdgeStop(amber.opacity(0.04), 190), HaloEdgeStop(amber.opacity(0.04), 360),
        ])
    }

    @Test
    func questionStopsMatchTheSpecQGoldBand() {
        let qgold = colors.statusWaitingForAnswer
        #expect(stops(.question) == [
            HaloEdgeStop(qgold.opacity(0.04), 0), HaloEdgeStop(qgold, 46),
            HaloEdgeStop(qgold, 122), HaloEdgeStop(qgold.opacity(0.04), 190),
            HaloEdgeStop(qgold.opacity(0.04), 360),
        ])
    }

    @Test
    func successStopsAreGreenCyanGreen() {
        #expect(stops(.success) == [
            HaloEdgeStop(colors.statusCompleted, 0),
            HaloEdgeStop(colors.statusRunning, 180),
            HaloEdgeStop(colors.statusCompleted, 360),
        ])
    }

    @Test
    func failureStopsAreAStaticRedSegment() {
        let hair = HaloEdge.hair2
        #expect(stops(.failure) == [
            HaloEdgeStop(hair, 0), HaloEdgeStop(hair, 20),
            HaloEdgeStop(colors.statusFailed, 60), HaloEdgeStop(colors.statusFailed, 120),
            HaloEdgeStop(hair, 160), HaloEdgeStop(hair, 360),
        ])
        // Reduce Motion changes nothing — failure is already static in every mode.
        #expect(stops(.failure, reduceMotion: true) == stops(.failure, reduceMotion: false))
    }

    /// The degree → location conversion is `degrees / 360`, and every table is
    /// non-decreasing across 0…1 (a valid `Gradient`).
    @Test
    func stopLocationsAreNormalizedAndMonotonic() {
        #expect(HaloEdgeStop(colors.statusRunning, 232).location == 232.0 / 360.0)
        for state in IslandSurfaceEdgeState.allCases {
            let locs = stops(state).map(\.location)
            #expect(locs.first == 0)
            #expect(locs.last == 1)
            #expect(zip(locs, locs.dropFirst()).allSatisfy { $0 <= $1 }, "\(state) stops must be monotonic")
        }
    }

    // MARK: - Animation presence (failure/idle produce no animation parameters)

    @Test
    func onlyIdleAndFailureAreInert() {
        #expect(HaloEdgeLightModel.animates(.idle) == false)
        #expect(HaloEdgeLightModel.animates(.failure) == false)
        for state in [IslandSurfaceEdgeState.working, .permission, .question, .success] {
            #expect(HaloEdgeLightModel.animates(state))
        }
    }

    /// Idle and failure carry **no** animation parameters at all: opacity is a
    /// constant 1.0 regardless of pulse, and they cast no bloom.
    @Test
    func idleAndFailureHaveNoAnimationParameters() {
        for state in [IslandSurfaceEdgeState.idle, .failure] {
            #expect(HaloEdgeLightModel.edgeOpacity(for: state, pulse: 0, successProgress: 0, reduceMotion: false) == 1.0)
            #expect(HaloEdgeLightModel.edgeOpacity(for: state, pulse: 1, successProgress: 1, reduceMotion: false) == 1.0)
            #expect(HaloEdgeLightModel.bloom(for: state, pulse: 0, successProgress: 0, colors: colors, reduceMotion: false) == nil)
            #expect(HaloEdgeLightModel.bloom(for: state, pulse: 1, successProgress: 1, colors: colors, reduceMotion: false) == nil)
        }
    }

    // MARK: - Edge opacity curves (SPEC §1a)

    @Test
    func attentionOpacityRidesTheFiftyFiveToOnePulse() {
        for state in [IslandSurfaceEdgeState.permission, .question] {
            #expect(HaloEdgeLightModel.edgeOpacity(for: state, pulse: 0, successProgress: 0, reduceMotion: false) == 0.55)
            #expect(HaloEdgeLightModel.edgeOpacity(for: state, pulse: 1, successProgress: 0, reduceMotion: false) == 1.0)
            // Monotonic across the pulse.
            let mid = HaloEdgeLightModel.edgeOpacity(for: state, pulse: 0.5, successProgress: 0, reduceMotion: false)
            #expect(mid > 0.55 && mid < 1.0)
        }
    }

    /// §3c: under Reduce Motion the attention edge holds its **peak** opacity,
    /// phase-independently — so the view never reads a clock (attention loudest static).
    @Test
    func attentionHoldsPeakOpacityUnderReduceMotion() {
        for state in [IslandSurfaceEdgeState.permission, .question] {
            #expect(HaloEdgeLightModel.edgeOpacity(for: state, pulse: 0, successProgress: 0, reduceMotion: true) == 1.0)
            #expect(HaloEdgeLightModel.edgeOpacity(for: state, pulse: 0.5, successProgress: 0, reduceMotion: true) == 1.0)
            #expect(HaloEdgeLightModel.edgeOpacity(for: state, pulse: 1, successProgress: 0, reduceMotion: true) == 1.0)
        }
    }

    @Test
    func successOpacityDissolvesOneToPointOneTwo() {
        #expect(HaloEdgeLightModel.edgeOpacity(for: .success, pulse: 0, successProgress: 0, reduceMotion: false) == 1.0)
        #expect(HaloEdgeLightModel.edgeOpacity(for: .success, pulse: 0, successProgress: 1, reduceMotion: false) == 0.12)
        // Reduce Motion renders the settled (dissolved) frame, phase-independently.
        #expect(HaloEdgeLightModel.edgeOpacity(for: .success, pulse: 0, successProgress: 0, reduceMotion: true) == 0.12)
    }

    // MARK: - Bloom specs (SPEC §1a bloom column)

    @Test
    func workingBloomIsSteadyBlue() {
        let b = HaloEdgeLightModel.bloom(for: .working, pulse: 0, successProgress: 0, colors: colors, reduceMotion: false)
        #expect(b == HaloBloomSpec(color: HaloEdge.workingBloom.opacity(0.45), radius: HaloMetrics.workingBloomRadius))
        // Steady — Reduce Motion keeps the working glow (§3c).
        #expect(HaloEdgeLightModel.bloom(for: .working, pulse: 0, successProgress: 0, colors: colors, reduceMotion: true) == b)
    }

    @Test
    func questionBloomIsSteadyQGold() {
        let b = HaloEdgeLightModel.bloom(for: .question, pulse: 1, successProgress: 0, colors: colors, reduceMotion: false)
        #expect(b == HaloBloomSpec(color: HaloEdge.questionBloom.opacity(0.40), radius: HaloMetrics.questionBloomRadius))
    }

    @Test
    func permissionBloomBreathesRadiusAndOpacity() {
        let trough = HaloEdgeLightModel.bloom(for: .permission, pulse: 0, successProgress: 0, colors: colors, reduceMotion: false)
        let crest = HaloEdgeLightModel.bloom(for: .permission, pulse: 1, successProgress: 0, colors: colors, reduceMotion: false)
        #expect(trough == HaloBloomSpec(color: HaloEdge.permissionBloom.opacity(0.50), radius: HaloMetrics.permissionBloomRadiusMin))
        #expect(crest == HaloBloomSpec(color: HaloEdge.permissionBloom.opacity(0.85), radius: HaloMetrics.permissionBloomRadiusMax))
        // §3c: Reduce Motion holds the bloom at its PEAK radius/opacity.
        #expect(HaloEdgeLightModel.bloom(for: .permission, pulse: 0, successProgress: 0, colors: colors, reduceMotion: true) == crest)
    }

    @Test
    func successBloomDissolvesToNothing() {
        let peak = HaloEdgeLightModel.bloom(for: .success, pulse: 0, successProgress: 0, colors: colors, reduceMotion: false)
        #expect(peak == HaloBloomSpec(color: HaloEdge.successBloom.opacity(0.70), radius: HaloMetrics.successBloomRadiusMax))
        // Fully settled → no bloom (green dot + check only).
        #expect(HaloEdgeLightModel.bloom(for: .success, pulse: 0, successProgress: 1, colors: colors, reduceMotion: false) == nil)
        // §3c: Reduce Motion renders the settled frame — no bloom animation.
        #expect(HaloEdgeLightModel.bloom(for: .success, pulse: 0, successProgress: 0, colors: colors, reduceMotion: true) == nil)
    }

    // MARK: - Determinism (SPEC §6.3 — frozen phase renders reproducibly)

    /// The **view state** the frozen phase resolves to — the tuple
    /// `(stops, edgeOpacity, bloom)` — is a pure function of the frozen inputs, so
    /// two evaluations at the same frozen phase are equal and carry **no** wall-clock
    /// or clock dependency. This is the reproducibility the harness relies on; the
    /// pixel bitmap is deliberately *not* asserted (the bloom's Gaussian `.shadow`
    /// blur is GPU-nondeterministic — the same reason the shipped `ThemeSnapshotting`
    /// harness gates golden pixels on an environment fingerprint).
    ///
    /// The frozen frame mirrors `HaloEdgeLight.staticEdge`: `pulse = frozen.pulse`,
    /// `successProgress = 1` (settled), Reduce Motion on (as §6.3 pins).
    @Test
    func frozenPhaseResolvesADeterministicViewState() {
        struct Frame: Equatable {
            var stops: [HaloEdgeStop]
            var opacity: Double
            var bloom: HaloBloomSpec?
        }
        let frozen = HaloEdgePhase.frozen
        func frame(_ state: IslandSurfaceEdgeState) -> Frame {
            Frame(
                stops: HaloEdgeLightModel.stops(for: state, colors: colors, reduceMotion: true, increaseContrast: false),
                opacity: HaloEdgeLightModel.edgeOpacity(for: state, pulse: frozen.pulse, successProgress: 1, reduceMotion: true),
                bloom: HaloEdgeLightModel.bloom(for: state, pulse: frozen.pulse, successProgress: 1, colors: colors, reduceMotion: true)
            )
        }
        for state in IslandSurfaceEdgeState.allCases {
            #expect(frame(state) == frame(state), "\(state) view state is non-deterministic at a frozen phase")
        }
        // Attention holds its peak, success is settled (dissolved, no bloom).
        #expect(frame(.permission).opacity == 1.0)
        #expect(frame(.permission).bloom?.radius == HaloMetrics.permissionBloomRadiusMax)
        #expect(frame(.success).opacity == 0.12)
        #expect(frame(.success).bloom == nil)
    }

    /// The view builds a non-empty bitmap in **both** presentation geometries — the
    /// closed-pill silhouette (`topCornerRadius 0`, `bottomCornerRadius height/2`)
    /// and the opened panel (radii 20/20) — on **both** profiles (notch + top-bar),
    /// around the concave notch fillet, for every state. This exercises the whole
    /// masked-gradient + bloom path so a crash / build regression fails loudly. The
    /// pixel-level AA-at-the-fillet, bloom-bleed, and morph-continuity sign-off is a
    /// dev-app judged-by-eye item (SPEC §6.4) — unreachable headless.
    @Test
    func edgeRendersNonEmptyInEveryGeometryAndState() {
        func renderIsNonEmpty(profile: OpenedIslandSurfaceShape.TopProfile, opened: Bool, state: IslandSurfaceEdgeState) -> Bool {
            let height: CGFloat = opened ? 220 : 38
            let width: CGFloat = opened ? 520 : 214
            let shape = OpenedIslandSurfaceShape(
                topProfile: profile,
                topCornerRadius: opened ? 20 : 0,
                bottomCornerRadius: opened ? 20 : height / 2,
                filletRadius: 0
            )
            let view = HaloEdgeLight(
                shape: shape,
                context: IslandSurfaceEdgeContext(state: state, isOpened: opened, size: CGSize(width: width, height: height))
            )
            .frame(width: width, height: height)
            .environment(\.haloEdgePhase, .frozen)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage else { return false }
            return image.size.width > 0 && image.size.height > 0
        }

        for profile in [OpenedIslandSurfaceShape.TopProfile.notch, .topBar] {
            for opened in [true, false] {
                for state in IslandSurfaceEdgeState.allCases {
                    #expect(renderIsNonEmpty(profile: profile, opened: opened, state: state),
                            "\(profile) opened=\(opened) state=\(state) rendered nothing")
                }
            }
        }
    }
}
