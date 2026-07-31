import SwiftUI
import OpenIslandCore

/// The living prismatic perimeter edge-light — Halo's whole state channel
/// (AB-341 · T22 · SPEC-halo §3a/§1a/§3c). A 1.5pt ring that hugs the *morphing*
/// silhouette (`OpenedIslandSurfaceShape`, closed pill → opened panel and back)
/// and (i) orbits for working, (ii) pulses for attention, (iii) blooms for
/// success, (iv) sits static for failure/idle — and never breaks during the
/// morph.
///
/// **Realization (the mockup's `conic-gradient` + `mask-composite: exclude`):**
/// fill the whole surface rect with the state's `AngularGradient`, then reveal
/// only the perimeter by masking with the **same** shape's 1.5pt stroke. Because
/// the mask uses the exact `OpenedIslandSurfaceShape` instance the open/close
/// transition drives (its `animatableData` corner radii), the ring and silhouette
/// interpolate in lockstep — one liquid black body, never a crossfade.
///
/// **Orbit vs morph independence (the key insight, §3a).** The working orbit is an
/// *independent* linear animation on the gradient's `angle` (a `@State` phase run
/// `withAnimation(.linear(6).repeatForever(autoreverses: false))`), never
/// `animatableData`. So the shape's radii interpolate on their spring while the
/// gradient angle rotates linearly — the two compose without conflict, and because
/// `Angle` is `Animatable`, SwiftUI interpolates the rotation on the render server
/// with **no per-frame body re-evaluation** (the orbit lives in the `HaloWorkingEdge`
/// leaf, so its parent — and `IslandPanelView` — never re-runs while it spins).
///
/// **Determinism + Reduce Motion.** The animated leaves are mounted **only** when
/// `animates` (not Reduce Motion *and* no frozen `\.haloEdgePhase`); otherwise the
/// static branch renders a settled frame off the pure model below, so (a) two
/// renders at a frozen phase are byte-equal and (b) under Reduce Motion no clock or
/// animation is ever acquired (§3c — the state stays legible as a static, still
/// *state-colored* ring; attention stays loudest at peak).
struct HaloEdgeLight: View {
    /// The single morphing shape the ring strokes — the exact instance the panel's
    /// open/close transition animates (never `V6ClosedPillShape`).
    let shape: OpenedIslandSurfaceShape
    /// The resolved ambient state + closed-vs-opened + surface size.
    let context: IslandSurfaceEdgeContext

    /// A frozen render phase for snapshots; `nil` = live clocks (production).
    @Environment(\.haloEdgePhase) private var frozenPhase
    /// Reduce Motion degrades the edge to a static state-colored hairline (§3c).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Increase Contrast brightens the idle hairline 0.08 → 0.24 (§3c / §5).
    @Environment(\.colorSchemeContrast) private var contrast

    /// Halo's colour axis is fixed, so the edge reads it directly (no `\.islandTokens`
    /// dependency needed) — the same values the pure model is unit-tested against.
    private var colors: IslandColorTokens { IslandColorTokens.halo }
    private var increaseContrast: Bool { contrast == .increased }

    /// The edge acquires a clock / animation only in the live case — never under
    /// Reduce Motion, never at a frozen phase. This single gate is what makes the
    /// §3c "never even acquires the clock" guarantee structural: the animated
    /// leaves are simply not in the tree otherwise.
    private var animates: Bool { !reduceMotion && frozenPhase == nil }

    /// G-36/M-20: the perimeter drops its own bloom while a hero is presented, so
    /// the card ring is the only glow in the frame.
    private var suppressesBloom: Bool {
        HaloEdgeLightModel.perimeterSuppressesBloom(for: context.state, isOpened: context.isOpened)
    }

    /// G-10: the opened working perimeter settles to the bare hairline, so the
    /// left gutter belongs to the row rails.
    private var settlesToHairline: Bool {
        HaloEdgeLightModel.perimeterSettlesToHairline(for: context.state, isOpened: context.isOpened)
    }

    var body: some View {
        Group {
            switch context.state {
            case .idle, .failure:
                // Fully static in every mode — no clock, no animation parameters.
                staticEdge(state: context.state, angle: 0)

            case .working:
                if settlesToHairline {
                    // G-10 — the board's opened `.isle.panel` carries no state
                    // class, so its `::before` falls through to `background:
                    // var(--hair)`: a bare 8% hairline, edge OFF
                    // (`06-halo.html:130`, and every opened frame in §C/§E/§F/§H
                    // is a class-less `.isle panel`). The orbiting cyan→violet
                    // segment is a *closed-pill* signal; once open, the state
                    // light belongs to the content — and specifically, in §C, to
                    // the running row's own `.rail.run` cyan→violet, which the
                    // orbit was drowning as it swept the same 2pt of left gutter
                    // (measured: perimeter (119,125,249) against a rail of
                    // (119,139,250), one pixel apart). Painting the idle hairline
                    // rather than dimming the working ring is what keeps V0's
                    // hairline edge intact — a floored `white@.05` base would
                    // have left the silhouette with no edge at all.
                    staticEdge(state: .idle, angle: 0)
                } else if animates {
                    HaloWorkingEdge(shape: shape, colors: colors)
                } else {
                    // Reduce Motion → the full cyan→violet static ring (§3c "keep
                    // the steady working glow"); a frozen phase without RM → the
                    // orbiting segment held at the frozen angle (deterministic).
                    staticEdge(state: .working, angle: frozenPhase?.orbitAngle ?? 0)
                }

            case .permission:
                if animates {
                    HaloPermissionEdge(shape: shape, colors: colors, suppressesBloom: suppressesBloom)
                } else {
                    // Reduce Motion → peak opacity + bloom at peak radius (attention
                    // stays loudest statically, §3c); frozen phase → the frozen pulse.
                    staticEdge(state: .permission, angle: 0)
                }

            case .question:
                if animates {
                    HaloQuestionEdge(shape: shape, colors: colors, suppressesBloom: suppressesBloom)
                } else {
                    staticEdge(state: .question, angle: 0)
                }

            case .success:
                if animates {
                    HaloSuccessEdge(shape: shape, colors: colors)
                } else {
                    // Renders the settled frame (dissolved to hairline, no bloom).
                    staticEdge(state: .success, angle: 0)
                }
            }
        }
        // Glow-travel emphasis handoff (§3b step 4): when the surface is **open**
        // and the loud state is an attention one, the perimeter edge dims to a
        // luminous floor while the hero card grows its **own** amber ring — so the
        // light reads as *condensing* from the whole silhouette into the card
        // boundary rather than two separate lights. Both ends stay amber (nothing
        // goes dark mid-handoff), and the cross-fade is timed to the open spring by
        // animating on `isOpened`. Closed / non-attention states hold full opacity,
        // so this is a no-op everywhere except the open attention surface.
        .opacity(HaloEdgeLightModel.perimeterOpenHandoffOpacity(
            for: context.state, isOpened: context.isOpened
        ))
        .animation(IslandMotionTokens.halo.openAnimation.animation, value: context.isOpened)
    }

    /// The still frame the non-animated branches paint, straight off the pure model
    /// (Reduce Motion forces the peak/settled values inside each helper; a frozen
    /// phase feeds its held `pulse`). Success settles to `progress: 1`.
    private func staticEdge(state: IslandSurfaceEdgeState, angle: Double) -> some View {
        let pulse = frozenPhase?.pulse ?? 0
        return HaloEdgeRing(
            shape: shape,
            stops: HaloEdgeLightModel.stops(
                for: state, colors: colors,
                reduceMotion: reduceMotion, increaseContrast: increaseContrast
            ),
            angle: angle,
            edgeOpacity: HaloEdgeLightModel.edgeOpacity(
                for: state, pulse: pulse, successProgress: 1, reduceMotion: reduceMotion
            ),
            bloom: suppressesBloom ? nil : HaloEdgeLightModel.bloom(
                for: state, pulse: pulse, successProgress: 1,
                colors: colors, reduceMotion: reduceMotion
            )
        )
    }
}

// MARK: - Animated state leaves

/// The working orbit — an independent linear angle sweep on the gradient (§3a).
/// Mounted only in the live case, so the `withAnimation` is never scheduled under
/// Reduce Motion / at a frozen phase. `Angle` is `Animatable`, so the rotation
/// runs on the render server: this leaf's body is evaluated once (start) and once
/// (end of a cycle), never per frame.
private struct HaloWorkingEdge: View {
    let shape: OpenedIslandSurfaceShape
    let colors: IslandColorTokens

    @State private var orbit: Double = 0

    var body: some View {
        HaloEdgeRing(
            shape: shape,
            stops: HaloEdgeLightModel.stops(for: .working, colors: colors, reduceMotion: false, increaseContrast: false),
            angle: orbit,
            edgeOpacity: 1,
            bloom: HaloEdgeLightModel.bloom(for: .working, pulse: 0, successProgress: 0, colors: colors, reduceMotion: false)
        )
        .onAppear {
            withAnimation(.linear(duration: HaloMotion.orbit).repeatForever(autoreverses: false)) {
                orbit = 360
            }
        }
    }
}

/// The permission pulse — amber→magenta edge opacity **and** bloom radius breathe
/// together off a `PulseClock` (its `sin`-based period ≈ 1.96s ≈ the SPEC's 1.9s
/// `edgepulse` — essentially free, §1c). The clock is owned here and ref-counted
/// via `onAppear`/`onDisappear`; the leaf is mounted only while permission is live,
/// so that lifecycle alone gates the timer (the `PouredPulsingStatusDot` pattern).
private struct HaloPermissionEdge: View {
    let shape: OpenedIslandSurfaceShape
    let colors: IslandColorTokens
    /// G-36/M-20: `true` once the hero is presented — the perimeter keeps its
    /// (dimmed) pulsing hairline but stops casting its own glow.
    var suppressesBloom: Bool = false

    @State private var clock = PulseClock()

    var body: some View {
        HaloEdgeRing(
            shape: shape,
            stops: HaloEdgeLightModel.stops(for: .permission, colors: colors, reduceMotion: false, increaseContrast: false),
            angle: 0,
            edgeOpacity: HaloEdgeLightModel.edgeOpacity(for: .permission, pulse: clock.phase, successProgress: 0, reduceMotion: false),
            bloom: suppressesBloom ? nil : HaloEdgeLightModel.bloom(for: .permission, pulse: clock.phase, successProgress: 0, colors: colors, reduceMotion: false)
        )
        .onAppear { clock.acquire() }
        .onDisappear { clock.release() }
    }
}

/// The question pulse — a gentler, dedicated 2.6s ease-in-out edge-opacity breathe
/// (§1c), on its own `@State` (render-server driven, no per-frame body eval). The
/// qgold bloom is *steady* (question pulses, it does not bloom — §4), so only the
/// edge opacity animates.
private struct HaloQuestionEdge: View {
    let shape: OpenedIslandSurfaceShape
    let colors: IslandColorTokens
    /// G-36/M-20 — see `HaloPermissionEdge.suppressesBloom`.
    var suppressesBloom: Bool = false

    @State private var pulse: Double = 0

    var body: some View {
        HaloEdgeRing(
            shape: shape,
            stops: HaloEdgeLightModel.stops(for: .question, colors: colors, reduceMotion: false, increaseContrast: false),
            angle: 0,
            edgeOpacity: HaloEdgeLightModel.edgeOpacity(for: .question, pulse: pulse, successProgress: 0, reduceMotion: false),
            bloom: suppressesBloom ? nil : HaloEdgeLightModel.bloom(for: .question, pulse: pulse, successProgress: 0, colors: colors, reduceMotion: false)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: HaloMotion.question).repeatForever(autoreverses: true)) {
                pulse = 1
            }
        }
    }
}

/// The success dissolve — a **one-shot** on state entry: the green→cyan→green edge
/// and its bloom fade from full to a hairline over 3s ease-out, then settle (§1c).
/// A single non-repeating `withAnimation` drives `progress` 0 → 1.
private struct HaloSuccessEdge: View {
    let shape: OpenedIslandSurfaceShape
    let colors: IslandColorTokens

    @State private var progress: Double = 0

    var body: some View {
        HaloEdgeRing(
            shape: shape,
            stops: HaloEdgeLightModel.stops(for: .success, colors: colors, reduceMotion: false, increaseContrast: false),
            angle: 0,
            edgeOpacity: HaloEdgeLightModel.edgeOpacity(for: .success, pulse: 0, successProgress: progress, reduceMotion: false),
            bloom: HaloEdgeLightModel.bloom(for: .success, pulse: 0, successProgress: progress, colors: colors, reduceMotion: false)
        )
        .onAppear {
            withAnimation(.easeOut(duration: HaloMotion.success)) {
                progress = 1
            }
        }
    }
}

// MARK: - The masked ring

/// The shared leaf that paints one frame of the edge: the state's `AngularGradient`
/// masked to the 1.5pt perimeter stroke, over a same-shape coloured bloom. Every
/// animated value (`angle`, `edgeOpacity`, `bloom`) arrives as a plain parameter
/// from an animating `@State` above, so this view carries no clock of its own.
///
/// The bloom is the **same** shape's stroke blurred away into a pure glow — no
/// crisp lit ring of its own — so the only visible ring is the masked angular
/// gradient. It bleeds *unclipped* past the silhouette (the overlay is composited
/// outside every `.clipShape` — the point of Halo's grown shadow-inset window
/// tokens).
struct HaloEdgeRing<S: Shape>: View {
    let shape: S
    let stops: [HaloEdgeStop]
    let angle: Double
    let edgeOpacity: Double
    let bloom: HaloBloomSpec?

    var body: some View {
        let gradient = Gradient(stops: stops.map { Gradient.Stop(color: $0.color, location: $0.location) })
        ZStack {
            if let bloom {
                shape
                    .stroke(lineWidth: HaloMetrics.edge)
                    .foregroundStyle(bloom.color)
                    .blur(radius: bloom.radius)
            }
            AngularGradient(gradient: gradient, center: .center, angle: .degrees(angle))
                .mask(shape.stroke(lineWidth: HaloMetrics.edge))
                .opacity(edgeOpacity)
        }
    }
}

// MARK: - Pure model (unit-tested; view-free)

/// One angular-gradient stop expressed in the SPEC's own terms — a colour at a
/// position in **degrees** (0…360), measured from the gradient's `from`. `location`
/// converts to SwiftUI's 0…1 `Gradient` space (`degrees / 360`).
struct HaloEdgeStop: Equatable {
    var color: Color
    var degrees: Double
    var location: Double { degrees / 360 }

    init(_ color: Color, _ degrees: Double) {
        self.color = color
        self.degrees = degrees
    }
}

/// A bloom shadow spec — a colour (carrying its own alpha) and a SwiftUI blur
/// radius. `nil` means the state casts no bloom (idle / failure).
struct HaloBloomSpec: Equatable {
    var color: Color
    var radius: CGFloat
}

/// The pure, view-free edge-light model (AB-341 · SPEC §1a/§3c). Every stop table,
/// opacity, and bloom is a deterministic function of `(state, pulse, progress,
/// reduceMotion, increaseContrast)` — no clocks, no environment — so
/// `HaloEdgeLightTests` can pin exact colours/degrees and prove the Reduce-Motion
/// statics without rendering. The view (`HaloEdgeLight`) is a thin animator over
/// this; the format mirrors `AnnualSessionRowFormat` / `FlightDeckApprovalFormat`.
enum HaloEdgeLightModel {

    // MARK: Opacity ranges (SPEC §1a)

    /// The `edgepulse` keyframe both attention states ride (`.55 ↔ 1`), differing
    /// only in period/curve (permission 1.9s, question 2.6s).
    static let pulseOpacityMin: Double = 0.55
    static let pulseOpacityMax: Double = 1.0
    /// The success `okedge` dissolve (`1 → .12`) — full to a hairline over 3s.
    static let successOpacityStart: Double = 1.0
    static let successOpacityEnd: Double = 0.12

    /// The perimeter edge's opacity floor once the surface opens on an **attention**
    /// state (the glow-travel handoff, §3b step 4). The whole silhouette edge dims
    /// to this luminous floor as the hero card grows its own amber ring, so the
    /// light reads as *condensing* into the card. Only permission / question dim;
    /// every other state (and the closed pill) holds full `1.0`.
    ///
    /// G-36/M-20: 0.55 left both rings loud, so the §E filmstrip's third frame —
    /// "the perimeter goes dark, the card ring becomes the only light" — never
    /// happened. The floor now sits at the same near-dark luminance the success
    /// dissolve settles to (`successOpacityEnd = 0.12`): still amber, still
    /// present as a hairline, but unmistakably the quiet end of the handoff.
    static let perimeterOpenHandoffFloor: Double = 0.15

    /// The perimeter-edge opacity for the glow-travel handoff (§3b step 4): the
    /// `perimeterOpenHandoffFloor` when the surface is **open** on an attention
    /// state, else fully opaque. Pure so the linear open→condense relationship is
    /// pinned without rendering; the view animates the transition on the open
    /// spring by keying it to `isOpened`.
    static func perimeterOpenHandoffOpacity(
        for state: IslandSurfaceEdgeState,
        isOpened: Bool
    ) -> Double {
        guard isOpened else { return 1.0 }
        switch state {
        case .permission, .question:
            return perimeterOpenHandoffFloor
        case .idle, .working, .success, .failure:
            return 1.0
        }
    }

    /// Whether the perimeter suppresses its **own bloom** for this frame
    /// (G-36/M-20). Dimming the ring alone is not enough: the permission bloom is
    /// a 42pt coloured shadow that keeps washing the whole silhouette even at a
    /// 0.15 floor, so the panel still reads as two competing lights. While a hero
    /// is presented (open + attention) the silhouette therefore keeps only its
    /// dimmed hairline and casts no glow at all — the hero card's own
    /// `0 0 48px -8px` amber glow is the one loud thing. Same predicate as
    /// `perimeterOpenHandoffOpacity`, kept separate so both ends stay pinnable.
    /// Whether the perimeter drops this state's own light for the board's **bare
    /// hairline** this frame (G-10).
    ///
    /// Every opened frame in the mockup is a class-less `<div class="isle panel">`
    /// — §C's list, §E's permission heroes, §F's question, §H's completion — so
    /// `.isle::before` falls through to its `background:var(--hair)` default:
    /// "idle: bare 8% hairline, edge OFF" (`06-halo.html:130`). The loud state
    /// perimeters (`.isle.work` / `.perm` / `.ques` / `.ok` / `.fail`) appear only
    /// on the **closed pill** and on the mid-morph `.travel` stages. Opened, Halo's
    /// state light belongs to the content.
    ///
    /// Scoped to `.working` because that is the state G-10 is about: its orbiting
    /// cyan→violet segment sweeps the very 2pt of left gutter that §C's
    /// `.rail.run` occupies, in the very same hue, so the rail stopped reading
    /// once every ~6s. The attention states already hand their light to the hero
    /// through `perimeterOpenHandoffOpacity` + `perimeterSuppressesBloom` (a
    /// dimmed amber hairline, deliberately still amber — G-36/M-20), and
    /// `.success` / `.failure` draw no rail to collide with, so both are left
    /// exactly as judged.
    static func perimeterSettlesToHairline(
        for state: IslandSurfaceEdgeState,
        isOpened: Bool
    ) -> Bool {
        guard isOpened else { return false }
        switch state {
        case .working:
            return true
        case .idle, .permission, .question, .success, .failure:
            return false
        }
    }

    static func perimeterSuppressesBloom(
        for state: IslandSurfaceEdgeState,
        isOpened: Bool
    ) -> Bool {
        guard isOpened else { return false }
        switch state {
        case .permission, .question:
            return true
        case .idle, .working, .success, .failure:
            return false
        }
    }

    // MARK: Bloom opacity ranges (SPEC §1a bloom column)

    static let workingBloomOpacity: Double = 0.45          // steady
    static let questionBloomOpacity: Double = 0.40          // steady
    static let permissionBloomOpacityMin: Double = 0.50     // pulse trough
    static let permissionBloomOpacityMax: Double = 0.85     // pulse crest
    static let successBloomOpacityStart: Double = 0.70      // dissolves to 0

    // MARK: Stop tables

    /// The per-state `AngularGradient` stops (SPEC §1a — the load-bearing table).
    /// Degrees are the mockup's conic positions verbatim. `reduceMotion` swaps the
    /// working table from the orbiting *segment* to the full static cyan→violet
    /// ring (§3c); `increaseContrast` brightens only the idle hairline (0.08→0.24).
    static func stops(
        for state: IslandSurfaceEdgeState,
        colors: IslandColorTokens,
        reduceMotion: Bool,
        increaseContrast: Bool
    ) -> [HaloEdgeStop] {
        let hair = HaloEdge.hair2                        // white@.05 off-band wash
        let cyan = colors.statusRunning                  // #33DCFF
        let violet = HaloEdge.violet                     // #7C5CFF
        let amber = colors.statusWaitingForApproval      // #FFB14D
        let magenta = HaloEdge.magenta                   // #FF5EA8
        let qgold = colors.statusWaitingForAnswer        // #FFCF7A
        let green = colors.statusCompleted               // #5FE39A
        let red = colors.statusFailed                    // #E0596C

        switch state {
        case .idle:
            // Flat white hairline; Increase Contrast consumes the pinned IC token.
            let op = increaseContrast ? colors.hairlineOpacityIncreasedContrast : colors.hairlineOpacity
            let ink = Color.white.opacity(op)
            return [HaloEdgeStop(ink, 0), HaloEdgeStop(ink, 360)]

        case .working:
            if reduceMotion {
                // §3c: static cyan→violet full ring (no orbit).
                return [HaloEdgeStop(cyan, 0), HaloEdgeStop(violet, 180), HaloEdgeStop(cyan, 360)]
            }
            // Orbiting segment: mostly white@.05, a cyan→violet arc that rotates.
            return [
                HaloEdgeStop(hair, 0), HaloEdgeStop(hair, 176),
                HaloEdgeStop(cyan, 232), HaloEdgeStop(violet, 300),
                HaloEdgeStop(hair, 348), HaloEdgeStop(hair, 360),
            ]

        case .permission:
            let amberWash = amber.opacity(0.04)
            return [
                HaloEdgeStop(amberWash, 0), HaloEdgeStop(amber, 40),
                HaloEdgeStop(magenta, 84), HaloEdgeStop(amber, 128),
                HaloEdgeStop(amberWash, 190), HaloEdgeStop(amberWash, 360),
            ]

        case .question:
            let qgoldWash = qgold.opacity(0.04)
            return [
                HaloEdgeStop(qgoldWash, 0), HaloEdgeStop(qgold, 46),
                HaloEdgeStop(qgold, 122), HaloEdgeStop(qgoldWash, 190),
                HaloEdgeStop(qgoldWash, 360),
            ]

        case .success:
            return [HaloEdgeStop(green, 0), HaloEdgeStop(cyan, 180), HaloEdgeStop(green, 360)]

        case .failure:
            // §1a: a static dim-red segment 60–120°, white@.05 elsewhere.
            return [
                HaloEdgeStop(hair, 0), HaloEdgeStop(hair, 20),
                HaloEdgeStop(red, 60), HaloEdgeStop(red, 120),
                HaloEdgeStop(hair, 160), HaloEdgeStop(hair, 360),
            ]
        }
    }

    // MARK: Motion (Reduce Motion → phase-independent statics)

    /// Whether the state drives *any* animation. Idle and failure are inert in
    /// every mode — the "failure/idle produce no animation parameters" contract.
    static func animates(_ state: IslandSurfaceEdgeState) -> Bool {
        switch state {
        case .idle, .failure: return false
        case .working, .permission, .question, .success: return true
        }
    }

    /// The edge-line opacity for a frame. Attention rides the `.55 ↔ 1` pulse;
    /// success dissolves `1 → .12` by `successProgress`; working/idle/failure are
    /// fully opaque (their look lives in the stop opacities). Under Reduce Motion
    /// attention holds its **peak** and success renders **settled** — both
    /// phase-independent, so the view never reads a clock (§3c).
    static func edgeOpacity(
        for state: IslandSurfaceEdgeState,
        pulse: Double,
        successProgress: Double,
        reduceMotion: Bool
    ) -> Double {
        switch state {
        case .idle, .working, .failure:
            return 1.0
        case .permission, .question:
            if reduceMotion { return pulseOpacityMax }   // peak — loudest static
            return lerp(pulseOpacityMin, pulseOpacityMax, clamp01(pulse))
        case .success:
            let p = reduceMotion ? 1.0 : clamp01(successProgress)
            return lerp(successOpacityStart, successOpacityEnd, p)
        }
    }

    /// The bloom shadow for a frame, or `nil` for a state that never glows (idle /
    /// failure — "failure never glows", §1a). Working / question are steady;
    /// permission's radius+opacity breathe on the pulse (peak under RM); success's
    /// bloom dissolves `r40→0` by `successProgress` (settled → no bloom under RM).
    static func bloom(
        for state: IslandSurfaceEdgeState,
        pulse: Double,
        successProgress: Double,
        colors: IslandColorTokens,
        reduceMotion: Bool
    ) -> HaloBloomSpec? {
        switch state {
        case .idle, .failure:
            return nil

        case .working:
            return HaloBloomSpec(
                color: HaloEdge.workingBloom.opacity(workingBloomOpacity),
                radius: HaloMetrics.workingBloomRadius
            )

        case .question:
            return HaloBloomSpec(
                color: HaloEdge.questionBloom.opacity(questionBloomOpacity),
                radius: HaloMetrics.questionBloomRadius
            )

        case .permission:
            let p = reduceMotion ? 1.0 : clamp01(pulse)
            let radius = lerp(HaloMetrics.permissionBloomRadiusMin, HaloMetrics.permissionBloomRadiusMax, p)
            let opacity = lerp(permissionBloomOpacityMin, permissionBloomOpacityMax, p)
            return HaloBloomSpec(color: HaloEdge.permissionBloom.opacity(opacity), radius: radius)

        case .success:
            let p = reduceMotion ? 1.0 : clamp01(successProgress)
            let opacity = lerp(successBloomOpacityStart, 0, p)
            if opacity <= 0.001 { return nil }           // settled → no bloom
            let radius = lerp(HaloMetrics.successBloomRadiusMax, 0, p)
            return HaloBloomSpec(color: HaloEdge.successBloom.opacity(opacity), radius: radius)
        }
    }

    // MARK: Helpers

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }

    private static func clamp01(_ x: Double) -> Double {
        min(1, max(0, x))
    }
}
