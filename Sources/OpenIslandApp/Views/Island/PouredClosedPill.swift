import SwiftUI
import OpenIslandCore

/// Poured Island's closed-pill slot (AB-300 · AB-330).
///
/// The closed state is the "black stem" the panel pours out of, so the pill
/// keeps a dark `surfaceInk` body — hierarchy is carried by light, not chrome —
/// lit by a specular top edge for the glass hint. Layout (glyph, centre label,
/// notch-lane label, right slot) and the fluid-width math are shared verbatim
/// with `V6ClosedPill` so the pill's outer dimensions — and therefore the
/// closed↔opened morph frame in `IslandPanelView` — stay identical across
/// themes; only the fill treatment and the agents-grid tiles differ.
///
/// AB-330 gives it the six ambient states of `SPEC-poured-island` §4A / mockup
/// §A. The frame stays byte-identical (the `V6ClosedPill.*OuterWidth` statics
/// are untouched); the state is expressed entirely inside the reserved slots:
///
/// - **A1 idle** — still 3-bar glyph at `paper@0.5`; no glow, no breathing.
/// - **A2 working** (and **A2′ many**) — the body breathes the cool `lumen`
///   glow; the glyph waves; the label is the narrated activity, verb dimmed and
///   object primary (two-tone). A2′ additionally lights the agents grid.
/// - **A3 permission** — the loudest state: an amber `attnpulse` bleeds outside
///   the silhouette; the left indicator is the approval dot with its warm ring.
/// - **A4 question** — a static gold halo + gold-tinted breathing glyph, kept
///   distinct from A3 by hue *and* shape (never colour alone).
/// - **A5 just completed** — a one-shot cool-white→green `settle`, then quiet.
/// - **A6 outcomes** — interrupted (`stop` glyph, warning amber) / failed
///   (`✕` glyph, red) rest with a coloured indicator and **no glow**.
///
/// The spotlight session's phase/outcome — which `UnifiedBars.Mode` alone can't
/// carry — arrives through `\.islandClosedPillActivity`; the pure
/// `PouredPillAmbientState.resolve(...)` folds it into the frame. Every
/// animation follows the shipped `PouredPulsingStatusDot` rule: never acquire a
/// clock under Reduce Motion — hold the peak (loudest) frame statically instead.
struct PouredClosedPill: View {
    var mode: UnifiedBars.Mode
    var label: String?
    var rightSlot: IslandRightSlotContent?
    var layout: V6ClosedLayout
    var height: CGFloat = 32
    var physicalNotchWidth: CGFloat = 0
    var minWidth: CGFloat = 70
    var showsGlyph: Bool = true

    @Environment(\.islandTokens) private var tokens
    @Environment(\.islandClosedPillActivity) private var activity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandClosedPillPaintsOwnSurface) private var paintsOwnSurface
    /// R2/R3: non-`nil` only while an R7 spotlight rotation is running.
    @Environment(\.islandClosedPillRotation) private var rotation

    private static let glyphSize: CGFloat = 24
    private static let innerGap: CGFloat = 6
    private static let notchLaneLabelGap: CGFloat = 6

    private var pad: CGFloat { height / 2 }

    private var ambient: PouredPillAmbientState {
        PouredPillAmbientState.resolve(activity: activity, mode: mode, rightSlot: rightSlot)
    }

    var body: some View {
        Group {
            switch layout {
            case .external: externalBody
            case .macbook:  macbookBody
            }
        }
    }

    // MARK: R3 / X1 — the swap

    /// X1: the shared swap opacity, or `1` when no cycle is running.
    ///
    /// Round 2 ran the fade here, in `@State`, against the pill's own 0.45 s
    /// layout crossfade — two drivers fighting over one property, which is why
    /// the outgoing label re-entered at ≈35 % and the whole swap measured 0.64 s
    /// — while the lead marker and the badge changed the instant the model's
    /// spotlight did, ≈0.15 s earlier. Both faults are gone by construction: the
    /// item now changes ONCE, upstream, in the same transaction that starts this
    /// opacity's fade-in (`PouredSpotlightRotationClock.syncDisplayedIndex`), and
    /// the marker, the badge and the label all ride this single value.
    private var swapOpacity: Double { rotation?.contentOpacity ?? 1 }

    /// R2: the label the *width* math sizes to — the widest item in the cycle
    /// while a rotation is live, so the silhouette holds still across the swap,
    /// and the live label otherwise (unchanged).
    private var widthLabel: String? {
        guard let reference = rotation?.widthReferenceLabel, !reference.isEmpty else { return label }
        return reference
    }

    /// What is drawn right now. Outside a rotation this is simply `label`; under
    /// one it is whichever item the clock has committed, which only ever changes
    /// while `swapOpacity` is `0`.
    private var visibleLabel: String? { label }

    // MARK: Background

    /// Dark stem body plus the crisp specular top line — the "glass treatment"
    /// on a deliberately dark surface. Under Reduce Transparency the specular is
    /// dropped and only the flat ink remains, keeping every glyph/label legible.
    ///
    /// PI-M-001: the light catch is now the theme's `specularHardEdge` — the
    /// reference `.pill` inherits the same `.glass` rule as `.panel`, whose only
    /// top light layer is `--specular: inset 0 1px 0 rgba(255,255,255,.14)`
    /// (`docs/design/overlay-redesign/01-poured-island.html:51,132-134,146`).
    /// The broad soft sheen that used to ride here had no reference counterpart.
    ///
    /// PI-B-002: skipped entirely when the host surface already paints the one
    /// continuous glass body under the pill (`\.islandClosedPillPaintsOwnSurface`
    /// is `false`, which only the morph container sets, and only for a theme
    /// whose material declares `morphsAsOneBody`). That body carries the very
    /// same `specularHardEdge` catch at the very same top edge, so the pill's
    /// treatment is unchanged — it is simply no longer painted twice.
    @ViewBuilder
    private var glassBackground: some View {
        if paintsOwnSurface {
            ZStack {
                V6ClosedPillShape()
                    .fill(tokens.colors.surfaceInk)

                if !reduceTransparency, let specular = tokens.material.specularHardEdge {
                    specular.color.opacity(specular.opacity)
                        .frame(height: specular.sheenHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipShape(V6ClosedPillShape())
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Left indicator (glyph / dot / outcome mark)

    /// The left wing's status indicator, always drawn inside the reserved
    /// `glyphSize` box so the pill width is unchanged whatever the state. When
    /// `showsGlyph` is false the morph owns the traveling glyph (AB-243), so the
    /// slot is a transparent placeholder exactly as before.
    @ViewBuilder
    private var leadingIndicator: some View {
        if showsGlyph {
            indicatorContent
                .frame(width: Self.glyphSize, height: Self.glyphSize)
        } else {
            Color.clear
                .frame(width: Self.glyphSize, height: Self.glyphSize)
        }
    }

    /// R1: the resting indicator and the *traveling* one are now the same leaf
    /// (`PouredClosedTravelingGlyph`), so the morph path can never render a
    /// different marker from the pill it morphs out of.
    @ViewBuilder
    private var indicatorContent: some View {
        PouredClosedTravelingGlyph(ambient: ambient, size: Self.glyphSize, tint: restingGlyphTint)
    }

    private var restingGlyphTint: Color? {
        switch ambient {
        case .idle: tokens.colors.paper.opacity(tokens.colors.tertiaryTextOpacity)
        case .working: tokens.colors.statusRunning
        case .question: tokens.colors.statusWaitingForAnswer
        case .permission: PouredPalette.attention
        case .completed(let outcome): outcomeTint(outcome)
        }
    }

    private func outcomeTint(_ outcome: SessionOutcome) -> Color {
        switch outcome {
        case .success:     tokens.colors.statusCompleted
        case .interrupted: tokens.colors.statusWarning
        case .failed:      tokens.colors.statusFailed
        }
    }

    // MARK: Label

    @ViewBuilder
    private func centerLabel(_ text: String) -> some View {
        PouredClosedPillLabel(
            text: text,
            ambient: ambient,
            // Cap at the width the fluid-layout math already reserved for this
            // label (`V6CenterLabelView.intrinsicWidth`) — which under a rotation
            // is the *widest* item's width, not this item's, so a shorter
            // sentence sits inside the held silhouette instead of shrinking it.
            maxWidth: V6CenterLabelView.intrinsicWidth(of: widthLabel ?? text)
        )
    }

    @ViewBuilder
    private func notchLaneLabel(_ text: String) -> some View {
        PouredClosedPillLabel(
            text: text,
            ambient: ambient,
            maxWidth: V6ClosedPill.notchLaneLabelWidth(
                physicalNotchWidth: physicalNotchWidth,
                height: height
            )
        )
    }

    @ViewBuilder
    private var rightSlotView: some View {
        if let rightSlot {
            // X5: the badge speaks the aggregate, kind-free, while a cycle is
            // running — see `PouredRightSlotView.attentionAccessibilityLabel`.
            PouredRightSlotView(content: rightSlot, isRotating: rotation != nil)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    // MARK: External (fluid)

    private var externalBody: some View {
        // R2: sized from `widthLabel`, which is the widest rotating item while a
        // cycle is live and the live label otherwise.
        let width = V6ClosedPill.externalOuterWidth(
            label: widthLabel,
            rightSlot: rightSlot,
            minWidth: minWidth,
            height: height
        )

        return ZStack {
            glassBackground

            HStack(spacing: 0) {
                leadingIndicator

                if let visibleLabel {
                    centerLabel(visibleLabel)
                        .padding(.leading, Self.innerGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: Self.innerGap)

                rightSlotView
            }
            .padding(.horizontal, pad)
            // X1: ONE opacity for the whole rotating payload — lead marker,
            // centre label and right-slot badge. It is driven upstream, in the
            // same transaction that commits the item, so a frame can never mix
            // item A's marker with item B's label.
            .pouredRotationSwapFade(opacity: swapOpacity, isRotating: rotation != nil)
        }
        .frame(width: width, height: height)
        // AB-330 stage 2: the ambient glow no longer rides here. It moved to the
        // `PouredClosedGlow` seam layer `IslandPanelView` renders OUTSIDE the
        // morph's content `.clipShape`, so A2/A3/A4/A5 glows actually bleed past
        // the silhouette instead of being truncated at it (stage-1 deviation).
        .animation(pillLayoutAnimation, value: pillLayoutKey)
    }

    // MARK: MacBook (notch-lane label opt-in)

    private var macbookBody: some View {
        // R2: see `externalBody`.
        let outer = V6ClosedPill.macbookOuterWidth(
            label: widthLabel,
            physicalNotchWidth: physicalNotchWidth,
            height: height
        )

        return ZStack {
            glassBackground

            HStack(spacing: 0) {
                leadingIndicator

                if let visibleLabel {
                    notchLaneLabel(visibleLabel)
                        .padding(.leading, Self.notchLaneLabelGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: 0)

                rightSlotView
            }
            .padding(.horizontal, pad)
            // X1: see `externalBody`.
            .pouredRotationSwapFade(opacity: swapOpacity, isRotating: rotation != nil)
        }
        .frame(width: outer, height: height)
        // AB-330 stage 2: glow moved to the `PouredClosedGlow` seam layer — see
        // `externalBody`.
        .animation(pillLayoutAnimation, value: pillLayoutKey)
    }

    // MARK: Layout transition

    /// The shipped 0.45 s layout crossfade — every non-rotation label change (a
    /// running row's narration updating, a state transition) still takes it,
    /// byte for byte.
    ///
    /// X1: `nil` while a cycle is live. That crossfade was the *second* driver
    /// fighting round 2's `@State` fade: because `.animation(_:value:)` wins over
    /// an ambient `withAnimation` inside its subtree, the incoming leg ran at
    /// 0.45 s instead of 0.2 s (0.2 + 0.45 ≈ the 0.64 s reviewers measured) and
    /// the outgoing label's `.transition` replayed on top of it. During a
    /// rotation there is nothing for it to do anyway — R2 pins the silhouette to
    /// the widest item, so the frame does not move — and the swap's own opacity
    /// is the only animation left.
    private var pillLayoutAnimation: Animation? {
        rotation == nil ? .timingCurve(0.4, 0, 0.2, 1, duration: 0.45) : nil
    }

    private var pillLayoutKey: AnyHashable {
        AnyHashable([
            AnyHashable(visibleLabel ?? ""),
            AnyHashable(rightSlot.map(PouredRightSlotKey.init) ?? .none),
            AnyHashable(mode),
        ])
    }
}

private enum PouredRightSlotKey: Hashable {
    case none
    case count(Int)
    case agents(Int)
    case attention(Int, IslandAttentionKind)
    case tasks(Int, Int, Int)
    case usage(Int, String, String)

    init(_ content: IslandRightSlotContent) {
        switch content {
        case .count(let n):   self = .count(n)
        case .agents(let cs): self = .agents(cs.count)
        case .attentionCount(let count, let kind):
            self = .attention(count, kind)
        case .taskCounter(let completed, let total, let subagents):
            self = .tasks(completed, total, subagents)
        case .usage(let percent, let window, let provider, _):
            self = .usage(percent, window, provider)
        }
    }
}

// MARK: - Ambient glow

/// The glow-casting seam layer (AB-330 stage 2). Renders the closed-pill
/// silhouette filled with `surfaceInk` — hidden behind the real pill, which is
/// the same ink shape drawn on top — so only its `.shadow` bleeds out around the
/// edges. `IslandPanelView` places this *behind* the morph/legacy surface and
/// **outside** the shared content `.clipShape`, which is why the glow now bleeds
/// past the silhouette instead of being truncated at it (the honest stage-1
/// deviation). The window already reserves headroom for the bloom via Poured's
/// `closedShadowHorizontalInset 40` / `closedShadowBottomInset 44`
/// (`SPEC-poured-island` §3.1).
struct PouredClosedGlow: View {
    let ambient: PouredPillAmbientState
    let width: CGFloat
    let height: CGFloat

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        V6ClosedPillShape()
            .fill(tokens.colors.surfaceInk)
            .frame(width: width, height: height)
            .modifier(PouredPillGlow(ambient: ambient))
            .allowsHitTesting(false)
    }
}

/// The six ambient states' body glow (`SPEC-poured-island` §4A · mockup §A
/// keyframes `lumen` / `attnpulse` / `settle`), applied to the glow-seam
/// silhouette (`PouredClosedGlow`) so it bleeds from the pill outline. Every
/// timing/radius/opacity comes from `PouredPillMotion`.
///
/// Motion follows the `PouredPulsingStatusDot` precedent: the breathing states
/// drive a single `@State` toggle via `repeatForever`, and the settle is a
/// one-shot `0 → 1` progress that never loops. Under Reduce Motion no animation
/// is ever started — the breathing states hold their **peak** (loudest) frame,
/// and the settle jumps straight to its quiet end (`SPEC` §K, ticket "static
/// frames at PEAK attention visibility").
private struct PouredPillGlow: ViewModifier {
    let ambient: PouredPillAmbientState

    @Environment(\.islandTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Breathing phase for `lumen` (A2) and `attnpulse` (A3): `false` = trough,
    /// `true` = peak. Held at `true` (peak) under Reduce Motion.
    @State private var breathing = false
    /// Settle one-shot progress (A5): `0` = cool-white flash, `1` = quiet. Rests
    /// at `1` so a pill that never completes shows no settle glow.
    @State private var settleProgress: Double = 1

    func body(content: Content) -> some View {
        glow(content)
            .onAppear { syncMotion() }
            .onChange(of: ambient) { _, _ in syncMotion() }
    }

    @ViewBuilder
    private func glow(_ content: Content) -> some View {
        switch ambient {
        case .idle:
            content
        case .working:
            content.shadow(
                color: tokens.colors.statusRunning.opacity(breathing ? PouredPillMotion.Working.glowOpacity : 0),
                radius: breathing ? PouredPillMotion.Working.glowRadius : 0
            )
        case .permission:
            let opacity = breathing ? PouredPillMotion.Permission.opacityMax : PouredPillMotion.Permission.opacityMin
            let radius = breathing ? PouredPillMotion.Permission.radiusMax : PouredPillMotion.Permission.radiusMin
            let spread = breathing ? PouredPillMotion.Permission.spreadMax : 0
            content
                .shadow(color: PouredPalette.attention.opacity(opacity), radius: radius)
                // Second, wider layer emulates the mockup's `spread` — no native
                // spread on SwiftUI shadows, so the extra bleed rides here.
                .shadow(color: PouredPalette.attention.opacity(opacity * 0.6), radius: radius + spread)
        case .question:
            content.shadow(
                color: tokens.colors.statusWaitingForAnswer.opacity(PouredPillMotion.Question.glowOpacity),
                radius: PouredPillMotion.Question.glowRadius
            )
        case .completed(.success):
            content
                .shadow(color: Color.white.opacity(settleWhiteOpacity), radius: PouredPillMotion.Settle.flashRadius)
                .shadow(color: tokens.colors.statusCompleted.opacity(settleGreenOpacity), radius: PouredPillMotion.Settle.greenRadius)
        case .completed:
            // A6 interrupted / failed rest with no glow — the coloured indicator
            // and outcome glyph carry the state.
            content
        }
    }

    // MARK: Settle interpolation (functions of `settleProgress`)

    /// Cool-white flash: full at `0`, gone by the green key-time.
    private var settleWhiteOpacity: Double {
        let key = PouredPillMotion.Settle.greenKeyTime
        let fade = max(0, 1 - settleProgress / key)
        return PouredPillMotion.Settle.flashOpacity * fade
    }

    /// Green bloom: rises to the key-time, then fades to nothing by `1`.
    private var settleGreenOpacity: Double {
        let key = PouredPillMotion.Settle.greenKeyTime
        let level: Double
        if settleProgress <= key {
            level = key > 0 ? settleProgress / key : 1
        } else {
            level = 1 - (settleProgress - key) / (1 - key)
        }
        return PouredPillMotion.Settle.greenOpacity * max(0, min(1, level))
    }

    // MARK: Motion lifecycle

    private func syncMotion() {
        switch ambient {
        case .working:
            startBreathing(period: PouredPillMotion.Working.period)
        case .permission:
            startBreathing(period: PouredPillMotion.Permission.period)
        case .completed(.success):
            playSettle()
        case .idle, .question, .completed:
            // Question's halo is static; idle / A6 cast nothing. Nothing to run.
            break
        }
    }

    private func startBreathing(period: TimeInterval) {
        guard !reduceMotion else {
            breathing = true // hold the peak, never acquire the clock
            return
        }
        breathing = false
        withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }

    private func playSettle() {
        guard !reduceMotion else {
            settleProgress = 1 // render the settled (quiet) frame immediately
            return
        }
        settleProgress = 0
        withAnimation(.easeOut(duration: PouredPillMotion.Settle.duration)) {
            settleProgress = 1
        }
    }
}

// MARK: - Rotation seam (R2 / R3)

/// What the collapsed pill needs to know about an R7 spotlight rotation.
///
/// R2 — **constant silhouette.** The board renders A3 and A4 at one identical
/// 352 × 40 geometry (`mapper-reference.md` §7.1/§7.2), which is board authority
/// that the waiting pill's outline does not track its content. Native sizes the
/// pill from the live label (`V6ClosedPill.*OuterWidth`), so a rotation between
/// `Approve swift build?` and `Answer needed` resized the silhouette every 3.5 s
/// — a shape change reading as a state change. `widthReferenceLabel` is the
/// widest label in the cycle; the pill lays out to that and never moves.
///
/// R3 / X1 — **no dual legibility, and one clock.** The swap must never show two
/// labels legible at once, and no frame may mix one item's lead marker or badge
/// with another item's label. Both are now guaranteed upstream: the rotation
/// clock holds the outgoing item until its fade-out has finished, then swaps
/// every consumer in a single transaction, and `contentOpacity` is the one
/// animated value all of them ride. The pill therefore no longer owns any swap
/// state of its own — it just applies this opacity.
///
/// Injected by `IslandPanelView` from `AppModel`; `nil` everywhere else, which is
/// the pre-rotation behaviour byte for byte.
struct PouredClosedPillRotation: Equatable, Sendable {
    /// The widest label the current cycle will show, used for width only.
    var widthReferenceLabel: String?

    /// X1: the shared swap opacity — `1` outside a swap, `0` at the gap between
    /// the two items. `AppModel.pouredClosedRotationContentOpacity`.
    var contentOpacity: Double

    init(widthReferenceLabel: String?, contentOpacity: Double = 1) {
        self.widthReferenceLabel = widthReferenceLabel
        self.contentOpacity = contentOpacity
    }
}

private struct PouredClosedPillRotationKey: EnvironmentKey {
    static let defaultValue: PouredClosedPillRotation? = nil
}

extension EnvironmentValues {
    /// R2/R3: the live R7 rotation, or `nil` when no cycle is running.
    ///
    /// Declared beside its only consumer, the same way
    /// `IslandQuestionPromptPreselectionKey` is — `PouredClosedPill` is the one
    /// view that reads it, and every other theme's pill never looks.
    var islandClosedPillRotation: PouredClosedPillRotation? {
        get { self[PouredClosedPillRotationKey.self] }
        set { self[PouredClosedPillRotationKey.self] = newValue }
    }
}

// MARK: - The swap fade (X1)

/// X1: applies the rotation's one shared swap opacity, with the leg's curve
/// stated **explicitly** rather than inherited from the ambient transaction.
///
/// The explicitness is load-bearing. `PouredClosedPill` carries an outer
/// `.animation(pillLayoutAnimation, value: pillLayoutKey)` whose value also
/// changes at the commit instant; an inherited `withAnimation` inside that
/// subtree can be overridden by it. Declaring the animation here — nearest the
/// leaf, keyed on the opacity itself — makes the fade immune to that, and every
/// site (pill body, morph traveling glyph, ambient glow) reads the same
/// `PouredSpotlightRotation.swapAnimation(fadingOut:)`, so they cannot drift.
///
/// A no-op when no cycle is running: opacity `1`, animation `nil`.
struct PouredRotationSwapFade: ViewModifier {
    let opacity: Double
    let isRotating: Bool

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .animation(
                isRotating
                    ? PouredSpotlightRotation.swapAnimation(fadingOut: opacity == 0)
                    : nil,
                value: opacity
            )
    }
}

extension View {
    func pouredRotationSwapFade(opacity: Double, isRotating: Bool) -> some View {
        modifier(PouredRotationSwapFade(opacity: opacity, isRotating: isRotating))
    }
}

// MARK: - Traveling glyph (R1)

/// R1: the collapsed pill's **traveling** left indicator under Poured.
///
/// In the morph path `PouredClosedPill` draws a transparent placeholder and this
/// overlay is the visible indicator (AB-243). Poured never overrode
/// `closedTravelingGlyph`, so it took the theme-agnostic `UnifiedBars` — merely
/// *tinted* per ambient state. The consequence is exactly the defect both
/// reviewers charged: a permission spotlight and a question spotlight rendered
/// the same three bars, differing only in hue, so the rotation's two items were
/// one uniform template distinguishable by colour alone. The board's A3 and A4
/// differ in **shape** first (`mapper-reference.md` §7.3: "never color alone") —
/// A3 is `.dot.approve.ring`, A4 is `.glyph.wait`.
///
/// This is the same indicator `PouredClosedPill.indicatorContent` already draws
/// at rest, lifted into its own view so the resting pill and the traveling
/// overlay cannot disagree.
struct PouredClosedTravelingGlyph: View {
    let ambient: PouredPillAmbientState
    let size: CGFloat
    let tint: Color?

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch ambient {
        case .permission:
            PouredPillRingedDot(
                fill: tokens.colors.statusWaitingForApproval,
                ring: PouredPalette.attention.opacity(PouredPillMotion.Permission.ringOpacity),
                ringWidth: PouredPillMotion.Permission.ringWidth
            )
            .frame(width: size, height: size)
        case .completed(let outcome):
            PouredPillOutcomeMark(outcome: outcome)
                .foregroundStyle(tint ?? tokens.colors.paper)
                .frame(width: size, height: size)
        case .idle, .working, .question:
            // X2: A4's lead is the board's `.glyph.wait` — THREE gold bars
            // breathing together (`01-poured-island.html:167`), not the shipped
            // two-bar pause mark. Poured-scoped opt-in; every other theme's
            // `.waiting` glyph is byte-identical.
            UnifiedBars(mode: unifiedMode, size: size, tint: tint, showsMiddleWaitBar: true)
        }
    }

    private var unifiedMode: UnifiedBars.Mode {
        switch ambient {
        case .working: .running
        case .question: .waiting
        default: .idle
        }
    }
}

// MARK: - Indicator leaves

/// A filled status dot inside a soft translucent ring — the A3 approval marker
/// (`.dot.approve.ring`). The ring is drawn as a wider filled disc behind the
/// dot so its translucency reads like the mockup's `box-shadow` spread rather
/// than a hard stroke.
/// PI-B-001: internal (was `private`) so the §B hover peek can draw the *same*
/// 8pt dot + 3pt ring the A3 pill draws, instead of a second copy that could
/// drift from `PouredPillMotion.Permission`.
struct PouredPillRingedDot: View {
    let fill: Color
    let ring: Color
    let ringWidth: CGFloat

    private let dotSize: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .fill(ring)
                .frame(width: dotSize + ringWidth * 2, height: dotSize + ringWidth * 2)
            Circle()
                .fill(fill)
                .frame(width: dotSize, height: dotSize)
        }
    }
}

/// The A6 outcome mark: a stop bar for interrupted, an ✕ for failed, and a
/// check for a (fresh) success — distinct in shape as well as hue so the state
/// never rides on colour alone. Tint is supplied by the caller.
struct PouredPillOutcomeMark: View {
    let outcome: SessionOutcome

    var body: some View {
        switch outcome {
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
        case .interrupted:
            Image(systemName: "stop.fill")
                .font(.system(size: 11, weight: .semibold))
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
        }
    }
}

// MARK: - A3 command span (R1)

/// R1: finds the command inside the collapsed pill's `Approve %@?` label.
///
/// The label arrives already localized and already substituted from
/// `IslandClosedLabelResolver`, so the command is recovered by matching the
/// *format's* own affixes around its `%@`. Doing it this way rather than
/// re-deriving the command from the session keeps the resolver the single source
/// of the sentence, and it survives a locale that puts the command first or last.
/// `nil` whenever the label is not that sentence (any other ambient state, a
/// `.sessionName` preference, an unexpected format), in which case the caller
/// falls back to the untouched two-tone split.
enum PouredClosedPillCommandSpan: Sendable {
    struct Span: Equatable, Sendable {
        var prefix: String
        var command: String
        var suffix: String
    }

    static func split(label: String, format: String) -> Span? {
        guard let marker = format.range(of: "%@") else { return nil }
        let prefix = String(format[format.startIndex..<marker.lowerBound])
        let suffix = String(format[marker.upperBound...])
        guard label.hasPrefix(prefix), label.hasSuffix(suffix),
              label.count > prefix.count + suffix.count else {
            return nil
        }
        let command = String(label.dropFirst(prefix.count).dropLast(suffix.count))
        guard !command.isEmpty else { return nil }
        return Span(prefix: prefix, command: command, suffix: suffix)
    }
}

// MARK: - Two-tone narrated label

/// The closed pill's narrated activity, split into primary / dim tone runs by
/// `PouredPillLabelTone` (verb dim + object primary, count semibold). Renders at
/// the Poured `activityLine` role but is capped at `maxWidth` — the width the
/// fluid-layout math already reserved — so it never renders wider than the pill
/// sized itself for (the `V6ClosedPill.*OuterWidth` statics are untouched).
private struct PouredClosedPillLabel: View {
    let text: String
    let ambient: PouredPillAmbientState
    let maxWidth: CGFloat
    var lang: LanguageManager = .shared

    @Environment(\.islandTokens) private var tokens

    private var primary: Color { tokens.colors.paper.opacity(0.96) }
    private var dim: Color { tokens.colors.paper.opacity(tokens.colors.secondaryTextOpacity) }

    private var composed: Text {
        // R1: A3's label is `Approve ` + the command in `--mono` at 11px + `?`
        // (`mapper-reference.md` §7.1 — the inner `.mono` span is measured
        // separately from the `.lab` runs either side of it). The whole sentence
        // used to render in the proportional `activityLine` face, so the pill
        // said "Approve sed?" with the command indistinguishable from the verb.
        if ambient == .permission,
           let span = PouredClosedPillCommandSpan.split(
               label: text,
               format: lang.t("island.closed.label.approve")
           ) {
            return Text(verbatim: span.prefix).foregroundStyle(primary)
                + Text(verbatim: span.command)
                    .font(PouredType.Role.branchDisambiguator.font)
                    .foregroundStyle(primary)
                + Text(verbatim: span.suffix).foregroundStyle(primary)
        }

        let segments = PouredPillLabelTone.segments(for: text, ambient: ambient)
        return segments.reduce(Text(verbatim: "")) { accumulated, segment in
            var piece = Text(verbatim: segment.text)
            if segment.isStrong { piece = piece.fontWeight(.semibold) }
            return accumulated + piece.foregroundStyle(segment.isDim ? dim : primary)
        }
    }

    var body: some View {
        let styled = composed
            .font(PouredType.Role.activityLine.font)
            .tracking(PouredType.Role.activityLine.spec.trackingPoints)
            .lineLimit(1)
            .truncationMode(.tail)

        // Grow to the text when it fits inside the reserved width, otherwise
        // pin to the cap and tail-truncate — mirrors `V6NotchLaneLabelView`, so
        // a long activity string is bounded instead of pushing the pill wider.
        ViewThatFits(in: .horizontal) {
            styled.fixedSize(horizontal: true, vertical: false)
            styled.frame(width: maxWidth, alignment: .leading)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }
}

// MARK: - Right slot

/// Poured Island's closed-pill right slot. AB-330 stage 2 gives each AB-322
/// content kind its own Poured rendering (`SPEC-poured-island` §4A A3/A4 · §G ·
/// §I) instead of the shipped degrade-to-`×N` fallback: an amber attention
/// badge, a gold `?` question badge, a `⏲ 2/5` task chip, and a worst-window
/// usage dial. `.count` keeps the neutral `×N` badge; `.agents` keeps the glass
/// grid. Every variant reuses `IslandRightSlotContent.fallbackBadgeAccessibilityLabel`
/// so the VoiceOver summary is unchanged. The pill's outer width math
/// (`V6ClosedPill.*OuterWidth`) is untouched — these variants render inside the
/// slot the fluid layout already reserved.
struct PouredRightSlotView: View {
    let content: IslandRightSlotContent
    var lang: LanguageManager = .shared
    /// X5: `true` only while an R7 rotation is running, i.e. only when the badge
    /// stands for a set that may hold more than one *kind* of wait.
    var isRotating: Bool = false
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch content {
        case .count:
            countBadge
        case .attentionCount(let count, let kind):
            PouredAttentionBadge(count: count, kind: kind)
                .accessibilityLabel(attentionAccessibilityLabel(count: count))
        case .taskCounter(let completed, let total, let subagents):
            PouredTaskCounterChip(completed: completed, total: total, subagents: subagents)
                .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
        case .usage(let percent, _, _, _):
            PouredUsageDialChip(percent: percent)
                .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
        case .agents(let cells):
            PouredAgentsGridBody(cells: cells)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(V6RightSlotView.agentsGridAccessibilitySummary(for: cells, lang: lang))
        }
    }

    private var countBadge: some View {
        Text("×\(content.fallbackBadgeCount ?? 0)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(tokens.colors.paper.opacity(0.72))
            .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
    }

    /// X5 (C's M-4): what VoiceOver hears on the attention badge.
    ///
    /// The shared `fallbackBadgeAccessibilityLabel` speaks the badge's **kind**
    /// over the badge's **count** — "2 waiting for an answer" / "2 waiting for
    /// approval". That is true of a single-kind set and false the moment the set
    /// is mixed, which is exactly the set R7 rotates through: with one
    /// permission and one question the pill claimed two of whichever kind held
    /// the spotlight, and the claim flipped every 3.5 s.
    ///
    /// While a rotation is live the badge therefore speaks the one thing that
    /// stays true through every hold — the aggregate — and drops the kind. R12
    /// makes this the only place the total is spoken during a question hold (the
    /// badge itself renders the board's `?` there), so the phrase carries it.
    /// Outside a rotation the shipped per-kind sentence is unchanged.
    private func attentionAccessibilityLabel(count: Int) -> String {
        guard isRotating else { return content.fallbackBadgeAccessibilityLabel(lang) }
        return lang.t("poured.a11y.rightSlot.attention.mixed", count)
    }
}

// MARK: - Right-slot variant leaves

/// A3/A4 attention badge — the loud `count.attn` amber capsule (permission) or
/// the calmer gold `?` capsule (question). The two are distinct by **hue and
/// shape/glyph**, never colour alone: permission shows the blocked-session
/// count on the bright `attention` fill with its own r14 glow; question shows a
/// `?` on the softer `statusWaitingForAnswer` gold with no extra badge glow
/// (`SPEC-poured-island` §4A A3/A4).
private struct PouredAttentionBadge: View {
    let count: Int
    let kind: IslandAttentionKind

    @Environment(\.islandTokens) private var tokens

    private var fill: Color {
        switch kind {
        case .permission: PouredPalette.attention
        case .question:   tokens.colors.statusWaitingForAnswer
        }
    }

    private var ink: Color {
        switch kind {
        case .permission: PouredPalette.attentionBadgeInk
        case .question:   PouredPalette.questionBadgeInk
        }
    }

    /// The permission badge is the "you are the blocker" state, so it carries
    /// the r14 amber glow; the question badge stays quiet (gold fill only).
    private var glowRadius: CGFloat {
        kind == .permission ? PouredPillMotion.RightSlot.attnBadgeGlowRadius : 0
    }

    private var label: String {
        switch kind {
        case .permission: "\(count)"
        case .question:   "?"
        }
    }

    var body: some View {
        Text(label)
            .font(PouredType.Role.summaryNumber.font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(ink)
            .padding(.horizontal, PouredPillMotion.RightSlot.badgeHPadding)
            // X3: `.count{min-width:20px;height:20px;border-radius:10px}` — a
            // true 20pt circle at one digit / `?`, growing into the board's
            // capsule only when the label itself is wider.
            .frame(
                minWidth: PouredPillMotion.RightSlot.badgeMinDiameter,
                minHeight: PouredPillMotion.RightSlot.badgeMinDiameter
            )
            .background(
                RoundedRectangle(cornerRadius: PouredPillMotion.RightSlot.badgeCornerRadius, style: .continuous)
                    .fill(fill)
            )
            .shadow(
                color: PouredPalette.attention.opacity(glowRadius > 0 ? PouredPillMotion.RightSlot.attnBadgeGlowOpacity : 0),
                radius: glowRadius
            )
    }
}

/// G task-counter chip — `⏲ 2/5` (or a bare `⏲ ×3` when the spotlight has
/// subagents but no todo list). Tabular digits so a ticking counter doesn't
/// jitter; drawn in the neutral paper tone since a running task list is
/// progress, not attention (`SPEC-poured-island` §G "pill: right slot `⏲ 2/5`").
private struct PouredTaskCounterChip: View {
    let completed: Int
    let total: Int
    let subagents: Int

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        HStack(spacing: PouredPillMotion.RightSlot.taskChipSpacing) {
            Image(systemName: "timer")
                .font(.system(size: 9, weight: .semibold))
            Text(fraction)
                .font(PouredType.Role.age.font)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(tokens.colors.paper.opacity(0.82))
    }

    /// A todo list is the headline (`2/5`); a pure subagent fan-out with no todos
    /// falls back to the agent count (`×3`) rather than a frozen `0/0`.
    private var fraction: String {
        total > 0 ? "\(completed)/\(total)" : "×\(subagents)"
    }
}

/// I usage dial — a small conic ring + tabular `92%`, tinted by threshold
/// (`≥90` critical red, `≥70` warn gold, else green). The pill only surfaces the
/// worst window once it is critical (`IslandRightSlotResolver.usageAlertThreshold
/// == 90`), so in practice this is always the red crit dial; the tint is still
/// computed from the value so a fixture at any percent reads truthfully
/// (`SPEC-poured-island` §I "pill compression: small red dial + `92%`").
private struct PouredUsageDialChip: View {
    let percent: Int

    @Environment(\.islandTokens) private var tokens

    private var tint: Color {
        if percent >= PouredPillMotion.RightSlot.usageCriticalThreshold {
            tokens.colors.statusFailed
        } else if percent >= PouredPillMotion.RightSlot.usageWarnThreshold {
            tokens.colors.statusWaitingForAnswer
        } else {
            tokens.colors.statusCompleted
        }
    }

    private var fraction: Double { min(1, max(0, Double(percent) / 100)) }

    var body: some View {
        HStack(spacing: PouredPillMotion.RightSlot.usageDialValueSpacing) {
            ZStack {
                Circle()
                    .stroke(tokens.colors.paper.opacity(0.14),
                            lineWidth: PouredPillMotion.RightSlot.usageDialLineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint,
                            style: StrokeStyle(lineWidth: PouredPillMotion.RightSlot.usageDialLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: PouredPillMotion.RightSlot.usageDialDiameter,
                   height: PouredPillMotion.RightSlot.usageDialDiameter)

            Text("\(percent)%")
                .font(PouredType.Role.age.font)
                .foregroundStyle(tint)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Glass restyle of the closed-island agents grid. The matrix shape (rows,
/// cell size, gap) comes from the active theme's grid strategy — Poured shares
/// Classic's, so the layout is pinned by the same `AgentsGridLayoutTests` — and
/// only the per-tile rendering changes for the frosted surface.
private struct PouredAgentsGridBody: View {
    let cells: [AgentGridCell]

    @Environment(\.islandTheme) private var theme

    var body: some View {
        let geometry = theme.agentsGridGeometry
        let rowSizes = geometry.balancedRows(cells.count)
        let geom = geometry.cellGeometry(rowSizes.count)
        let rows = V6RightSlotView.splitIntoRows(cells, rowSizes: rowSizes)

        VStack(spacing: geom.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: geom.gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        PouredAgentsTileView(cell: cell, size: geom.cell, radius: geom.radius)
                    }
                }
            }
        }
        .fixedSize()
    }
}

/// One agents-grid tile (A2′). Liveness is carried by status colour, not agent
/// brand: a running cell lights `statusRunning` with a soft halo, an idle cell
/// dims to `paper@0.5`, and a waiting cell breathes the attention amber
/// (`SPEC-poured-island` §A2′ · mockup `.agrid i.on / i.idle / i.wait`). The
/// overflow cell keeps its neutral "+N" chip.
private struct PouredAgentsTileView: View {
    let cell: AgentGridCell
    let size: CGFloat
    let radius: CGFloat
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch cell {
        case .session(_, let state):
            switch state {
            case .running:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tokens.colors.statusRunning)
                    .frame(width: size, height: size)
                    .shadow(
                        color: tokens.colors.statusRunning.opacity(PouredPillMotion.AgentsGrid.runningGlowOpacity),
                        radius: PouredPillMotion.AgentsGrid.runningGlowRadius
                    )
            case .idle:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tokens.colors.paper.opacity(PouredPillMotion.AgentsGrid.idleCellOpacity))
                    .frame(width: size, height: size)
            case .waiting:
                PouredWaitingTile(color: PouredPalette.attention, size: size, radius: radius)
            }
        case .overflow(let n):
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tokens.colors.paper.opacity(0.14))
                Text("+\(n)")
                    .font(.system(size: max(5, size * 0.55), weight: .bold, design: .monospaced))
                    .foregroundStyle(tokens.colors.paper)
            }
            .frame(width: size, height: size)
        }
    }
}

/// A waiting agent's tile: a breathing glow that pulses the halo radius and
/// opacity with motion enabled, and holds a fixed mid-glow under Reduce Motion
/// so the tile still reads as distinct from idle/running without animating.
private struct PouredWaitingTile: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let active = reduceMotion ? true : pulse
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(active ? 0.85 : 0.3), radius: active ? 4 : 1.5)
            .opacity(reduceMotion ? 0.85 : (pulse ? 1.0 : 0.55))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
