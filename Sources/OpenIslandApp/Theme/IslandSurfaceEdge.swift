import SwiftUI
import OpenIslandCore

/// The infrastructure the Halo theme's perimeter edge-light is built on
/// (AB-341 · SPEC-halo §3a/§4). Part 1 ships the *seam* — the resolved ambient
/// state, the surface-composition context, and the phase-freeze environment —
/// so the surface-level `IslandTheme.surfaceEdgeOverlay(shape:context:)` hook
/// has a stable payload. Part 2 (T22 · the `HaloEdgeLight` view) consumes it.
///
/// Everything here is shared, theme-agnostic vocabulary (not Halo-specific) so
/// the hook stays a truthful description any theme could map into its own
/// chrome — mirroring how `IslandClosedPillActivity` describes the closed
/// pill's spotlight for every theme rather than a Poured-shaped enum.

// MARK: - Resolved ambient edge state

/// The single ambient state the perimeter edge-light paints — the resolved
/// "one loud thing" across every surfaced session (SPEC-halo §0 · §4
/// "Attention is loudest").
///
/// Six states, not the raw `SessionPhase`: attention forks into **permission**
/// (amber, hottest — blooms) vs **question** (qgold, softer — pulses only), and
/// a completion forks by outcome into **success** (a brief green bloom that
/// dissolves to hairline) vs **failure** (a static dim red segment). An
/// interrupted or stale completion casts no light, so it resolves to **idle** —
/// the bare 8%-white hairline the edge wears 95% of the time.
enum IslandSurfaceEdgeState: Equatable, CaseIterable, Sendable {
    /// The bare 8%-white hairline — no gradient, no glow. The calmest frame.
    case idle
    /// A cyan→violet segment orbits the perimeter (running).
    case working
    /// Amber→magenta, pulses, and blooms outside the silhouette (the loudest —
    /// `waitingForApproval`).
    case permission
    /// A softer qgold edge with a gentler pulse and no bloom (`waitingForAnswer`).
    case question
    /// A brief green bloom that dissolves back to hairline (a fresh success).
    case success
    /// A static dim red segment that never pulses (a fresh failure).
    case failure

    /// The "one loud thing" priority (SPEC-halo §4): attention outranks working
    /// outranks the fresh-success window outranks failure outranks idle, and
    /// within attention permission (amber, hottest) outranks question (qgold,
    /// softer). `resolve` folds every session's candidate down to the loudest.
    var loudnessRank: Int {
        switch self {
        case .permission: return 5
        case .question:   return 4
        case .working:    return 3
        case .success:    return 2
        case .failure:    return 1
        case .idle:       return 0
        }
    }

    /// The loudest ambient state across `sessions` — the pure resolver the edge
    /// consumes (SPEC-halo §4). A completion only wears its verdict inside the
    /// settle window (`successWindow`, defaulting to the same
    /// `IslandClosedPillTiming.outcomeLabelWindow` the closed-pill label uses),
    /// after which it recedes to `idle` rather than pinning a permanent badge;
    /// an interrupted completion casts no light at all (§A6). A process that has
    /// receded (`islandPresence == .inactive`) is never loud.
    ///
    /// Pure and time-injectable (`now`) so it can be unit-tested against exact
    /// states without an overlay or the wall clock.
    static func resolve(
        sessions: [AgentSession],
        now: Date = .now,
        successWindow: TimeInterval = IslandClosedPillTiming.outcomeLabelWindow
    ) -> IslandSurfaceEdgeState {
        var loudest: IslandSurfaceEdgeState = .idle
        for session in sessions {
            let candidate = edgeState(for: session, now: now, successWindow: successWindow)
            if candidate.loudnessRank > loudest.loudnessRank {
                loudest = candidate
            }
        }
        return loudest
    }

    /// One session's candidate edge state, before the "one loud thing" fold.
    static func edgeState(
        for session: AgentSession,
        now: Date = .now,
        successWindow: TimeInterval = IslandClosedPillTiming.outcomeLabelWindow
    ) -> IslandSurfaceEdgeState {
        // A dead process never keeps a loud edge — it recedes to the hairline.
        if session.islandPresence(at: now) == .inactive { return .idle }

        switch session.phase {
        case .waitingForApproval:
            return .permission
        case .waitingForAnswer:
            return .question
        case .running:
            return .working
        case .completed:
            // Only inside the settle window does a completion wear its verdict;
            // afterwards it is just another quiet session (§A5 "a moment, not a
            // permanent badge").
            let age = now.timeIntervalSince(session.updatedAt)
            guard age >= 0, age < successWindow else { return .idle }
            switch session.outcome {
            case .success:
                return .success
            case .failed:
                return .failure
            case .interrupted:
                // Interrupted casts no glow (§A6) — it is a quiet outcome, not
                // an attention state, so the edge stays off.
                return .idle
            }
        }
    }
}

// MARK: - Surface-composition context

/// The payload the surface-level edge hook receives alongside the morphing
/// shape (AB-341 · SPEC-halo §3a). It carries the resolved ambient `state`,
/// whether the surface is presenting **closed** vs **opened**, and the surface
/// `size` the overlay draws into — everything the edge-light needs that the
/// shape alone does not encode.
///
/// The morphing `OpenedIslandSurfaceShape` travels as a separate hook parameter
/// (not on the context) because it *is* the mask the ring strokes, and it must
/// be the exact same instance the morph animates so the ring and silhouette
/// interpolate in lockstep. The context is the surrounding state; the shape is
/// the geometry.
struct IslandSurfaceEdgeContext: Equatable {
    /// The resolved "one loud thing" the edge paints.
    var state: IslandSurfaceEdgeState
    /// `true` when the surface is presenting the opened panel; `false` for the
    /// closed pill. The morph feeds the shape's interpolating radii regardless;
    /// this lets a theme size blooms or pick a stop table per presentation.
    var isOpened: Bool
    /// The surface frame the overlay is placed into (the same width/height the
    /// clipped fill uses). Blooms are drawn *unclipped* on top of this frame so
    /// they can bleed past the silhouette.
    var size: CGSize

    init(state: IslandSurfaceEdgeState, isOpened: Bool, size: CGSize) {
        self.state = state
        self.isOpened = isOpened
        self.size = size
    }
}

// MARK: - Phase-freeze environment (snapshots / previews)

/// A frozen render phase for the animated edge-light (AB-341 · SPEC-halo §6.3).
///
/// The edge orbits, pulses and blooms off live clocks, which makes its render
/// non-reproducible in a snapshot. Injecting a `HaloEdgePhase` through
/// `\.haloEdgePhase` overrides those clocks with a fixed `orbitAngle` and
/// `pulse`, so the snapshot harness renders a settled, deterministic frame.
/// `nil` in the environment means "use the live clocks" (production).
struct HaloEdgePhase: Equatable {
    /// The gradient's orbit angle, in degrees, held constant instead of driven
    /// by the 6s linear repeat.
    var orbitAngle: Double
    /// The pulse phase (0…1) held constant instead of driven by the pulse clock.
    var pulse: Double

    init(orbitAngle: Double, pulse: Double) {
        self.orbitAngle = orbitAngle
        self.pulse = pulse
    }

    /// The canonical settled frame the snapshot harness renders at — orbit
    /// angle 0, pulse 0 (SPEC-halo §6.3).
    static let frozen = HaloEdgePhase(orbitAngle: 0, pulse: 0)
}

private struct HaloEdgePhaseKey: EnvironmentKey {
    #if HALO_PARITY_TESTING
    // Gate 0A parity may install a manual diagnostic phase before the real
    // production composition is presented. Normal and Release launches leave
    // this nil and therefore retain the production monotonic clocks.
    static var defaultValue: HaloEdgePhase? {
        HaloParityEventClock.installedManualPhase
    }
    #else
    static let defaultValue: HaloEdgePhase? = nil
    #endif
}

extension EnvironmentValues {
    /// A fixed render phase for the Halo edge-light, or `nil` for live clocks.
    ///
    /// Production leaves this `nil` so the edge orbits/pulses/blooms off its own
    /// clocks. Snapshot tests inject `.frozen` (orbit 0 / pulse 0) so the edge
    /// renders deterministically — two renders at the same frozen phase produce
    /// identical output. Defaults to `nil` so a view read without an explicit
    /// injection runs live, exactly as production.
    var haloEdgePhase: HaloEdgePhase? {
        get { self[HaloEdgePhaseKey.self] }
        set { self[HaloEdgePhaseKey.self] = newValue }
    }
}
