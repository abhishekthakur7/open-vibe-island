import SwiftUI
import OpenIslandCore

/// Halo's closed-pill slot (AB-342 · T23 · SPEC-halo §5A / mockup §A/§G′/§I′).
///
/// Halo is a pure-black OLED void whose only chrome is the living perimeter
/// edge-light. The edge — the orbit, the pulse, the bloom, the idle 8%-white
/// hairline — is drawn by `IslandPanelView` via
/// `HaloTheme.surfaceEdgeOverlay(shape:context:)` on the **morphing** silhouette
/// (AB-341), *not* here: the pill must never double-render the ring. So this view
/// renders only the wing *content* on the void:
///
/// - **A1 idle** — a still 3-bar liveness glyph at `t3`; no glow (the edge is off).
/// - **A2 working** — the `wave` liveness glyph (cyan, 1.05s, bars staggered
///   .13/.26s); the narrated two-tone label (`Editing` sans/t2 + `AppModel.swift`
///   mono/t1). A2′ many-working reads `3 working` (count strong + qualifier dim).
/// - **A3 permission** — a ringed amber dot; label `Approve swift build?` with the
///   command in **mono**.
/// - **A4 question** — a breathing qgold liveness glyph; label `Answer needed`.
/// - **A5 completed** — a `✓` check mark; label `Done · the-automator`. The green
///   bloom/dissolve is the **edge's** job (AB-341); the pill casts no glow.
/// - **A6 outcomes** — interrupted = `▢` stop + `Interrupted · …`; failed = `✕`
///   cross + `Failed · …`. No pill-side glow / pulse (the edge owns failure's
///   static red segment).
///
/// Layout (glyph, centre label, notch-lane label, right slot) and the fluid-width
/// math are shared **verbatim** with `V6ClosedPill.*OuterWidth` — the same statics
/// `PouredClosedPill` / `AnnualClosedPill` reuse — so the pill's outer dimensions,
/// and therefore the closed↔opened morph frame in `IslandPanelView`, stay
/// identical across themes (`HaloClosedPillWidthRegressionTests` pins it). The
/// spotlight's phase/outcome — which `UnifiedBars.Mode` alone can't carry —
/// arrives through `\.islandClosedPillActivity`; the shared, theme-agnostic
/// `PouredPillAmbientState.resolve(...)` folds it into the frame, and
/// `HaloSessionRowFormat.pillIndicator(for:)` (the "never color alone" resolver
/// extended for the pill) picks the left-wing glyph/dot/mark. Every animated leaf
/// follows the `PouredPulsingStatusDot` rule: never acquire a clock under Reduce
/// Motion — hold a legible static frame instead.
struct HaloClosedPill: View {
    var mode: UnifiedBars.Mode
    var label: String?
    var rightSlot: IslandRightSlotContent?
    var layout: V6ClosedLayout
    var height: CGFloat = 38
    var physicalNotchWidth: CGFloat = 0
    var minWidth: CGFloat = 70
    var showsGlyph: Bool = true

    @Environment(\.islandTokens) private var tokens
    @Environment(\.islandClosedPillActivity) private var activity

    private static let glyphSize: CGFloat = 24
    private static let innerGap: CGFloat = 6
    private static let notchLaneLabelGap: CGFloat = 6

    private var pad: CGFloat { height / 2 }

    /// The resolved ambient frame (idle / working / permission / question /
    /// completed) — the shared fold every 2.0 pill uses.
    private var ambient: PouredPillAmbientState {
        PouredPillAmbientState.resolve(activity: activity, mode: mode, rightSlot: rightSlot)
    }

    /// The left-wing indicator kind for this frame — the primary non-color state
    /// channel (`HaloSessionRowFormat.pillIndicator`, keyed off the ambient's
    /// edge state so a completed session forks by outcome).
    private var indicator: HaloSessionRowFormat.PillIndicator {
        HaloSessionRowFormat.pillIndicator(for: HaloSessionRowFormat.edgeState(for: ambient))
    }

    var body: some View {
        switch layout {
        case .external: externalBody
        case .macbook:  macbookBody
        }
    }

    // MARK: Background

    /// The pure-black OLED void — an opaque `surfaceInk` fill and **nothing else**:
    /// no hairline stroke (the idle 8%-white edge is `HaloEdgeLight`'s job), no
    /// specular (the animated edge replaces the specular concept), no glow (every
    /// state's bloom bleeds from the edge overlay outside the morph clip). Fully
    /// opaque, so Reduce Transparency is a no-op.
    private var voidBackground: some View {
        V6ClosedPillShape()
            .fill(tokens.colors.surfaceInk)
    }

    // MARK: Left indicator (liveness glyph / ringed dot / outcome mark)

    /// The left wing's status indicator, always drawn inside the reserved
    /// `glyphSize` box so the pill width is unchanged whatever the state. When
    /// `showsGlyph` is false the morph owns the traveling glyph (AB-243), so the
    /// slot is a transparent placeholder exactly as the shipped pill.
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

    @ViewBuilder
    private var indicatorContent: some View {
        switch indicator {
        case .liveness(let mode):
            let kind = HaloLivenessGlyph.Kind(mode: mode)
            HaloLivenessGlyph(kind: kind, tint: livenessTint(kind), box: Self.glyphSize)
        case .permissionDot:
            HaloPillRingedDot(
                fill: tokens.colors.statusWaitingForApproval,
                ring: tokens.colors.statusWaitingForApproval.opacity(0.28)
            )
        case .outcome(let state):
            HaloPillOutcomeMark(state: state)
                .foregroundStyle(outcomeTint(state))
        }
    }

    private func livenessTint(_ kind: HaloLivenessGlyph.Kind) -> Color {
        switch kind {
        case .idle:    return tokens.colors.paper.opacity(tokens.colors.tertiaryTextOpacity)
        case .running: return tokens.colors.statusRunning
        case .waiting: return tokens.colors.statusWaitingForAnswer
        }
    }

    private func outcomeTint(_ state: HaloSessionRowFormat.EdgeState) -> Color {
        switch state {
        case .success:     return tokens.colors.statusCompleted
        case .interrupted: return tokens.colors.statusWarning
        case .failed:      return tokens.colors.statusFailed
        default:           return tokens.colors.paper
        }
    }

    // MARK: Label

    @ViewBuilder
    private func centerLabel(_ text: String) -> some View {
        HaloClosedPillLabel(
            text: text,
            ambient: ambient,
            // Cap at the width the fluid-layout math already reserved for this
            // label, so the two-tone leaf never renders wider than the pill sized
            // itself for.
            maxWidth: V6CenterLabelView.intrinsicWidth(of: text)
        )
    }

    @ViewBuilder
    private func notchLaneLabel(_ text: String) -> some View {
        HaloClosedPillLabel(
            text: text,
            ambient: ambient,
            maxWidth: V6ClosedPill.notchLaneLabelMaxWidth
        )
    }

    @ViewBuilder
    private var rightSlotView: some View {
        if let rightSlot {
            HaloRightSlotView(content: rightSlot)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    // MARK: External (fluid)

    private var externalBody: some View {
        let width = V6ClosedPill.externalOuterWidth(
            label: label,
            rightSlot: rightSlot,
            minWidth: minWidth,
            height: height
        )

        return ZStack {
            voidBackground

            HStack(spacing: 0) {
                leadingIndicator

                if let label {
                    centerLabel(label)
                        .padding(.leading, Self.innerGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: Self.innerGap)

                rightSlotView
            }
            .padding(.horizontal, pad)
        }
        .frame(width: width, height: height)
        .animation(pillLayoutAnimation, value: pillLayoutKey)
    }

    // MARK: MacBook (notch-lane label opt-in)

    private var macbookBody: some View {
        let outer = V6ClosedPill.macbookOuterWidth(
            label: label,
            physicalNotchWidth: physicalNotchWidth,
            height: height
        )

        return ZStack {
            voidBackground

            HStack(spacing: 0) {
                leadingIndicator

                if let label {
                    notchLaneLabel(label)
                        .padding(.leading, Self.notchLaneLabelGap)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: 0)

                rightSlotView
            }
            .padding(.horizontal, pad)
        }
        .frame(width: outer, height: height)
        .animation(pillLayoutAnimation, value: pillLayoutKey)
    }

    // MARK: Layout transition

    private var pillLayoutAnimation: Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: 0.45)
    }

    private var pillLayoutKey: AnyHashable {
        AnyHashable([
            AnyHashable(label ?? ""),
            AnyHashable(rightSlot.map(HaloRightSlotKey.init) ?? .none),
            AnyHashable(mode),
        ])
    }
}

private enum HaloRightSlotKey: Hashable {
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
        case .usage(let percent, let window, let provider):
            self = .usage(percent, window, provider)
        }
    }
}

// MARK: - "Never color alone" pill indicator (extends HaloSessionRowFormat)

extension HaloSessionRowFormat {

    /// The closed pill's left-wing indicator — the primary non-color state channel
    /// (SPEC §4 "never color alone" / §5A · mockup §A). One of three shapes, each
    /// distinct from the others without relying on hue: a liveness glyph (the live
    /// states), a ringed dot (a held permission), or an outcome mark
    /// (check / stop / cross for the three completions). Pure and view-free so
    /// `HaloClosedPillTests` can pin the whole state→indicator table.
    enum PillIndicator: Equatable {
        /// The 3-bar liveness glyph — still (idle) / wave (running) / breathe
        /// (question). Carries the `UnifiedBars.Mode` the glyph draws.
        case liveness(UnifiedBars.Mode)
        /// A ringed amber dot — the held-permission marker (A3).
        case permissionDot
        /// The completion outcome mark — `✓` / `▢` / `✕`, keyed off the edge
        /// state so the symbol comes from `statusGlyphName` (no duplicate table).
        case outcome(EdgeState)
    }

    /// The pill indicator for an edge state. Running/idle/question resolve to the
    /// liveness glyph in their respective mode; permission to the ringed dot; the
    /// three completions to their outcome mark. Consumes the existing `EdgeState`
    /// channel rather than minting a parallel one.
    static func pillIndicator(for state: EdgeState) -> PillIndicator {
        switch state {
        case .running:     return .liveness(.running)
        case .idle:        return .liveness(.idle)
        case .question:    return .liveness(.waiting)
        case .permission:  return .permissionDot
        case .success:     return .outcome(.success)
        case .interrupted: return .outcome(.interrupted)
        case .failed:      return .outcome(.failed)
        }
    }

    /// Bridges the shared closed-pill ambient frame onto the Halo edge state so
    /// the pill's indicator/label share one resolution. `working(manyWorking:)`
    /// collapses to `.running` (the many-working restyle is the right slot's job,
    /// not the left indicator's); a completed frame forks by outcome.
    static func edgeState(for ambient: PouredPillAmbientState) -> EdgeState {
        switch ambient {
        case .idle:        return .idle
        case .working:     return .running
        case .permission:  return .permission
        case .question:    return .question
        case .completed(let outcome):
            switch outcome {
            case .success:     return .success
            case .interrupted: return .interrupted
            case .failed:      return .failed
            }
        }
    }
}

// MARK: - Liveness glyph (SPEC §1c · mockup `.gly` filament bars)

/// The closed pill's 3-bar liveness glyph — the mockup's `.gly` filament bars.
/// Three modes carry the live states without colour: **still** (idle, short bars),
/// **wave** (running — bars rise/fall on the 1.05s `wave` period, staggered
/// .13/.26s so the light travels left→right), and **breathe** (question — the
/// outer bars pulse opacity on the 2.4s `breathe` period, the middle bar dropped).
///
/// Motion follows the `PouredPulsingStatusDot` / `HaloEdgeLight` rule: under Reduce
/// Motion no clock is ever acquired — the wave freezes to a **static wave
/// silhouette** (varied bar heights, still legible as "working") and the breathe
/// freezes to a steady mid-lit pair, so every mode is legible statically (§3c).
/// Drawn inside the shared 24pt glyph box so the pill width is unchanged.
struct HaloLivenessGlyph: View {
    enum Kind: Equatable {
        /// Still short bars (A1 idle).
        case idle
        /// The travelling wave (A2 working).
        case running
        /// Breathing outer bars (A4 question).
        case waiting

        /// Maps the `UnifiedBars.Mode` the pill indicator carries onto the glyph
        /// mode (the two share the idle/running/waiting vocabulary).
        init(mode: UnifiedBars.Mode) {
            switch mode {
            case .idle:    self = .idle
            case .running: self = .running
            case .waiting: self = .waiting
            }
        }
    }

    let kind: Kind
    let tint: Color
    var box: CGFloat = 24

    private static let barWidth: CGFloat = 2.5
    private static let spacing: CGFloat = 3
    /// Wave trough as a fraction of the crest — the bar shrinks to this on the
    /// down-beat, so the crest reads as a clear rise.
    private static let waveTroughFraction: CGFloat = 0.42

    /// The three bars, in the mockup's 24pt design box.
    static let bars: [HaloLivenessGlyphBar] = [
        HaloLivenessGlyphBar(idleH: 3, waveHigh: 12, waitH: 10, delay: HaloMotion.waveBarDelays[0]),
        HaloLivenessGlyphBar(idleH: 5, waveHigh: 16, waitH: 0,  delay: HaloMotion.waveBarDelays[1]),
        HaloLivenessGlyphBar(idleH: 3, waveHigh: 10, waitH: 10, delay: HaloMotion.waveBarDelays[2]),
    ]

    var body: some View {
        let scale = box / 24
        HStack(spacing: Self.spacing * scale) {
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { _, bar in
                HaloLivenessBar(
                    kind: kind,
                    bar: bar,
                    width: Self.barWidth * scale,
                    scale: scale,
                    troughFraction: Self.waveTroughFraction,
                    tint: tint
                )
            }
        }
        .frame(width: box, height: box)
    }
}

/// One filament bar. Each bar owns its own animation (so the wave stagger is a
/// per-bar `.delay`) and never acquires a clock under Reduce Motion.
private struct HaloLivenessBar: View {
    let kind: HaloLivenessGlyph.Kind
    let bar: HaloLivenessGlyphBar
    let width: CGFloat
    let scale: CGFloat
    let troughFraction: CGFloat
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waveUp = false
    @State private var breathing = false

    /// The bar's height (in design pt, scaled) for the current mode. The wave
    /// animates between trough and crest; idle rests short; question uses the
    /// waiting height (0 = the dropped middle bar).
    private var height: CGFloat {
        switch kind {
        case .idle:
            return bar.idleH * scale
        case .running:
            let crest = bar.waveHigh * scale
            let trough = crest * troughFraction
            if reduceMotion {
                // Frozen wave silhouette — the crest/trough midpoint per bar, so
                // the three bars still read as a wave shape without motion.
                return (crest + trough) / 2
            }
            return waveUp ? crest : trough
        case .waiting:
            return bar.waitH * scale
        }
    }

    /// Question-mode opacity breathe (the middle, dropped bar stays hidden).
    private var opacity: Double {
        guard kind == .waiting, bar.waitH > 0 else {
            return kind == .waiting ? 0 : 1
        }
        if reduceMotion { return 0.7 }        // steady mid-lit, never a clock
        return breathing ? 1.0 : 0.45
    }

    var body: some View {
        Capsule(style: .continuous)
            .fill(tint)
            .frame(width: width, height: max(0, height))
            .frame(height: 24 * scale)           // vertically centred in the box
            .opacity(opacity)
            .onAppear { start() }
    }

    private func start() {
        guard !reduceMotion else { return }
        switch kind {
        case .running:
            withAnimation(
                .easeInOut(duration: HaloMotion.wave / 2)
                    .repeatForever(autoreverses: true)
                    .delay(bar.delay)
            ) { waveUp = true }
        case .waiting where bar.waitH > 0:
            withAnimation(
                .easeInOut(duration: HaloMotion.breathe / 2)
                    .repeatForever(autoreverses: true)
                    .delay(bar.delay)
            ) { breathing = true }
        case .idle, .waiting:
            break
        }
    }
}

/// One filament bar's geometry in the 24pt design box. `idleH` is the still/rest
/// height, `waveHigh` the wave crest, `waitH` the question-mode height (0 = the
/// mockup's dropped middle bar), `delay` the per-bar wave/breathe stagger.
struct HaloLivenessGlyphBar {
    let idleH: CGFloat
    let waveHigh: CGFloat
    let waitH: CGFloat
    let delay: TimeInterval
}

// MARK: - Indicator leaves

/// A filled status dot inside a soft translucent ring — the A3 permission marker
/// (mockup `.dot.perm`). The ring is a wider filled disc behind the dot so its
/// translucency reads like the mockup's soft halo rather than a hard stroke. No
/// glow (the amber bloom is the edge's job); no motion (the pulse rides the edge).
private struct HaloPillRingedDot: View {
    let fill: Color
    let ring: Color

    private var dotSize: CGFloat { HaloMetrics.dot }
    private let ringWidth: CGFloat = 3

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

/// The A5/A6 outcome mark — `✓` success / `▢` interrupted / `✕` failed. The symbol
/// name comes straight from `HaloSessionRowFormat.statusGlyphName` (the shared
/// "never color alone" glyph channel — no duplicate table), so the pill and the
/// rows can never disagree on a completion's shape. Tint is supplied by the caller.
private struct HaloPillOutcomeMark: View {
    let state: HaloSessionRowFormat.EdgeState

    var body: some View {
        Image(systemName: HaloSessionRowFormat.statusGlyphName(state))
            .font(.system(size: weightAndSize.size, weight: weightAndSize.weight))
    }

    /// The check reads at a slightly larger, bolder stroke than the stop/cross,
    /// matching the mockup's heavier `✓` (stroke-width 2.4 vs 2.2).
    private var weightAndSize: (size: CGFloat, weight: Font.Weight) {
        switch state {
        case .success: return (13, .bold)
        case .interrupted, .failed: return (12, .semibold)
        default: return (12, .semibold)
        }
    }
}

// MARK: - Two-tone narrated label

/// The closed pill's narrated activity / attention / outcome label, split into
/// tone runs by `HaloPillLabelTone` (SPEC §5A · mockup §A). Halo's split is the
/// mono-object one: the verb reads sans/secondary and the **object / command reads
/// mono/primary** (`Editing` + `AppModel.swift`; `Approve` + `swift build` + `?`),
/// the aggregate count reads primary/strong, and an outcome prefix (`Done ·`) reads
/// dim with the workspace primary. Rendered at the pill-label role but capped at
/// `maxWidth` — the width the fluid layout already reserved via the **unchanged**
/// `V6ClosedPill.*OuterWidth` math — so it never renders wider than the pill sized
/// itself for (mirrors `PouredClosedPillLabel` / `V6NotchLaneLabelView`).
private struct HaloClosedPillLabel: View {
    let text: String
    let ambient: PouredPillAmbientState
    let maxWidth: CGFloat
    var lang: LanguageManager = .shared

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    /// The `Approve %@?` template's prefix/suffix around the command placeholder,
    /// so the embedded command can be lifted into a mono run without re-parsing
    /// localized words. Computed by formatting the shared template with a sentinel
    /// (locale-correct: works for `Approve %@?` and `批准 %@？`).
    private var commandAffixes: (prefix: String, suffix: String)? {
        guard ambient == .permission else { return nil }
        let sentinel = "\u{2063}HALOCMD\u{2063}"
        let template = lang.t("island.closed.label.approve", sentinel)
        guard let range = template.range(of: sentinel) else { return nil }
        return (String(template[..<range.lowerBound]), String(template[range.upperBound...]))
    }

    private var composed: Text {
        let segments = HaloPillLabelTone.segments(for: text, ambient: ambient, commandAffixes: commandAffixes)
        return segments.reduce(Text(verbatim: "")) { accumulated, segment in
            accumulated + Text(verbatim: segment.text)
                .font(font(for: segment.role))
                .foregroundStyle(color(for: segment.role))
        }
    }

    var body: some View {
        let styled = composed
            .lineLimit(1)
            .truncationMode(.tail)

        ViewThatFits(in: .horizontal) {
            styled.fixedSize(horizontal: true, vertical: false)
            styled.frame(width: maxWidth, alignment: .leading)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private func font(for role: HaloPillLabelTone.Segment.Role) -> Font {
        switch role {
        case .mono:
            return .system(size: HaloTypography.pillValueSize, weight: .regular, design: .monospaced)
        case .count:
            return .system(size: HaloTypography.pillLabelSize, weight: .semibold, design: .default)
        case .dim, .primary:
            return .system(size: HaloTypography.pillLabelSize, weight: .regular, design: .default)
        }
    }

    private func color(for role: HaloPillLabelTone.Segment.Role) -> Color {
        switch role {
        case .dim:
            return tokens.colors.paper.opacity(
                tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)
            )
        case .primary, .mono, .count:
            // t1 primary is white@.95 applied ad hoc (SPEC §1a); IC lifts it.
            return tokens.colors.paper.opacity(
                tokens.colors.text(0.95, increaseContrast: increasesContrast)
            )
        }
    }
}

// MARK: - Right slot (Part 2 · SPEC §5A A2′/A3/A4 · §G′ · §I′)

/// Halo's closed-pill right slot. Each AB-322 content kind gets its own Halo
/// rendering on the void (SPEC-halo §5A A2′/A3/A4 · §G′ · §I′ · mockup `.agrid` /
/// `.cnt.hot` / `.cnt.q`), replacing the Part-1 interim `×N` degrade:
///
/// - **`.agents`** — the A2′ bloomed-circle mini agents-grid (one light per
///   session; running = cyan + halo, waiting = amber breathing, idle = t3).
/// - **`.attentionCount(_, .permission)`** — the loudest badge, the `.cnt.hot`
///   amber→magenta gradient capsule (ink `#241203`) with its r16 coral glow.
/// - **`.attentionCount(_, .question)`** — the calmer `.cnt.q` qgold `?` badge
///   (ink `#241A03`, **no** glow) — distinct from permission by hue AND behavior.
/// - **`.taskCounter`** — the G′ roll-up: a subagent count + cyan nodes glyph, or
///   the `2/5` todo fraction when there is no fan-out.
/// - **`.usage`** — the I′ worst-window crit filament + `Codex 92%` (only ever
///   surfaced at ≥90 — the shared `usageAlertThreshold`).
/// - **`.count`** — keeps the neutral mono `×N` badge.
///
/// The switch is spelled out (no `default:`) so a future content kind fails the
/// build here rather than silently rendering wrong. Every variant reuses the
/// shared `IslandRightSlotContent.fallbackBadge…` VoiceOver summary, and the
/// pill's outer width math (`V6ClosedPill.*OuterWidth`) is untouched — these
/// render inside the slot the fluid layout already reserved (the grid's 6pt cells
/// fit within the width V6 reserves, exactly as the sibling themes' grids do).
struct HaloRightSlotView: View {
    let content: IslandRightSlotContent
    var lang: LanguageManager = .shared
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch content {
        case .count:
            countBadge
                .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
        case .agents(let cells):
            HaloAgentsGridBody(cells: cells)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(V6RightSlotView.agentsGridAccessibilitySummary(for: cells, lang: lang))
        case .attentionCount(let count, let kind):
            HaloAttentionBadge(count: count, kind: kind)
                .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
        case .taskCounter(let completed, let total, let subagents):
            HaloTaskCounter(form: HaloRightSlotForm.task(completed: completed, total: total, subagents: subagents))
                .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
        case .usage(let percent, let window, let provider):
            HaloUsageFilament(percent: percent, windowLabel: window, providerTitle: provider)
                .accessibilityLabel(content.fallbackBadgeAccessibilityLabel(lang))
        }
    }

    private var countBadge: some View {
        Text("×\(content.fallbackBadgeCount ?? 0)")
            .font(.system(size: HaloTypography.pillValueSize, weight: .regular, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(tokens.colors.paper.opacity(0.72))
    }
}

// MARK: - Right-slot content decisions (pure · SPEC §G′)

/// The pure, view-free decisions the Halo right-slot leaves draw from, so the
/// `HaloClosedPillTests` can pin them without standing up a view. Mirrors
/// `HaloPillLabelTone` — the paint lives in the leaves, the *shape* of what shows
/// lives here.
enum HaloRightSlotForm {
    /// The `.taskCounter` roll-up (SPEC §G′). A running fan-out surfaces the
    /// **subagent count + nodes glyph**; with no fan-out it falls back to the
    /// **todo fraction** (`2/5`) — never a frozen `0/0` beside a nodes glyph.
    enum Task: Equatable {
        /// `subagents > 0` — the G′ nodes roll-up (carries the subagent count).
        case nodes(Int)
        /// `subagents == 0` — the `completed/total` todo fraction.
        case fraction(completed: Int, total: Int)
    }

    static func task(completed: Int, total: Int, subagents: Int) -> Task {
        subagents > 0 ? .nodes(subagents) : .fraction(completed: completed, total: total)
    }
}

// MARK: - Right-slot leaves

/// The A2′ mini agents-grid — one **bloomed light circle** per session in the
/// theme's `(6pt cell, 3.5 gap, radius 3)` geometry (`HaloTheme.agentsGridGeometry`),
/// laid out with the shared balanced-row algorithm so the matrix shape matches
/// every other theme (only the per-tile rendering — a glowing circle, not a flat
/// square — differs). The circles are always 6pt, so the grid fits within the
/// width the fluid layout reserved via `V6RightSlotView.intrinsicWidth`.
private struct HaloAgentsGridBody: View {
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
                        HaloAgentsCircle(cell: cell, size: geom.cell, radius: geom.radius)
                    }
                }
            }
        }
        .fixedSize()
    }
}

/// One agents-grid circle (A2′ · mockup `.agrid i`). Liveness is carried by
/// status colour + light, never agent brand (Halo's identity discipline): a
/// **running** cell lights cyan with the `rgba(80,180,255,.7)` r5 halo, an **idle**
/// cell dims to the tertiary paper wash (`--t3`), and a **waiting** cell breathes
/// the attention amber (2s, steady under Reduce Motion). Overflow keeps the
/// neutral `+N` chip.
private struct HaloAgentsCircle: View {
    let cell: AgentGridCell
    let size: CGFloat
    let radius: CGFloat
    @Environment(\.islandTokens) private var tokens

    /// The running cell's halo — `rgba(80,180,255,.7)` r5 (mockup `.agrid i.on`),
    /// a cooler blue than the cyan fill so it reads as light bleeding past the dot.
    static let runningGlow = Color(red: 80 / 255.0, green: 180 / 255.0, blue: 255 / 255.0)
    static let runningGlowRadius: CGFloat = 5

    var body: some View {
        switch cell {
        case .session(_, let state):
            switch state {
            case .running:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tokens.colors.statusRunning)
                    .frame(width: size, height: size)
                    .shadow(color: Self.runningGlow.opacity(0.7), radius: Self.runningGlowRadius)
            case .idle:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tokens.colors.paper.opacity(tokens.colors.tertiaryTextOpacity))
                    .frame(width: size, height: size)
            case .waiting:
                HaloWaitingDot(color: tokens.colors.statusWaitingForApproval, size: size, radius: radius)
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

/// A waiting agent's grid circle: the `breathe-dot` opacity pulse (`.4 ↔ 1` over
/// `HaloMotion.gridDot` = 2s). Under Reduce Motion it never acquires the clock —
/// it holds the peak (fully lit) so the tile stays distinct from idle/running
/// without animating (the `PouredPulsingStatusDot` rule).
private struct HaloWaitingDot: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat

    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var opacity: Double {
        if reduceMotion { return 1 }          // steady peak, never a clock
        return breathing ? 1.0 : 0.4
    }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .opacity(opacity)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: HaloMotion.gridDot / 2).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

/// The A3/A4 attention badge — the `.cnt.hot` amber→magenta gradient capsule
/// (permission, the loudest) or the `.cnt.q` qgold capsule (question). The two are
/// distinct by **hue and glyph and behavior**, never colour alone: permission
/// shows the blocked-session **count** on the amber→magenta gradient with its r16
/// coral glow; question shows a **`?`** on the flat qgold with **no** glow. Dark
/// inks (`#241203` / `#241A03`) keep the digit legible on the bright fills.
private struct HaloAttentionBadge: View {
    let count: Int
    let kind: IslandAttentionKind

    @Environment(\.islandTokens) private var tokens

    /// `.cnt.hot` ink `#241203` — a near-black warm brown that reads on the bright
    /// amber→magenta gradient.
    static let hotInk = Color(red: 0x24 / 255.0, green: 0x12 / 255.0, blue: 0x03 / 255.0)
    /// `.cnt.q` ink `#241A03` — the question badge's dark ink on qgold.
    static let questionInk = Color(red: 0x24 / 255.0, green: 0x1A / 255.0, blue: 0x03 / 255.0)
    /// `.cnt.hot` glow `rgba(255,150,90,.6)` r16 — a hot coral bleed, the only
    /// right-slot badge that glows (permission is the loudest ambient state).
    static let hotGlow = Color(red: 255 / 255.0, green: 150 / 255.0, blue: 90 / 255.0)
    static let hotGlowRadius: CGFloat = 16

    private var text: String { kind == .permission ? "\(count)" : "?" }
    private var ink: Color { kind == .permission ? Self.hotInk : Self.questionInk }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .default))
            .monospacedDigit()
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 20, minHeight: 20)
            .padding(.horizontal, 6)
            .background(badgeFill)
            .shadow(
                color: kind == .permission ? Self.hotGlow.opacity(0.6) : .clear,
                radius: kind == .permission ? Self.hotGlowRadius : 0
            )
    }

    @ViewBuilder
    private var badgeFill: some View {
        switch kind {
        case .permission:
            Capsule(style: .continuous)
                .fill(LinearGradient(
                    colors: [tokens.colors.statusWaitingForApproval, HaloEdge.magenta],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        case .question:
            Capsule(style: .continuous)
                .fill(tokens.colors.statusWaitingForAnswer)
        }
    }
}

/// The G′ task-counter roll-up. A subagent fan-out surfaces as a **cyan nodes
/// glyph + count** (`⌗ 3` in spirit — the orbiting working-light already says
/// "alive", so no nested clutter); with no fan-out it falls back to the todo
/// **fraction** (`2/5`, tabular, neutral paper — progress, not attention).
private struct HaloTaskCounter: View {
    let form: HaloRightSlotForm.Task

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        switch form {
        case .nodes(let count):
            HStack(spacing: 4) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.colors.statusRunning)
                Text("\(count)")
                    .font(.system(size: HaloTypography.pillLabelSize, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(tokens.colors.paper.opacity(0.9))
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        case .fraction(let completed, let total):
            Text("\(completed)/\(total)")
                .font(.system(size: HaloTypography.pillLabelSize, weight: .regular, design: .default))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(tokens.colors.paper.opacity(0.82))
        }
    }
}

/// The I′ usage compression — the single **worst** window, surfaced only once it
/// is critical (`IslandRightSlotResolver.usageAlertThreshold == 90`). A thin
/// **light-filament** arc (threshold-tinted, with a soft same-hue glow) + the
/// provider and percent (`Codex 92%`) in the threshold tint + the window label.
///
/// **Deviation (resets-in).** SPEC I′ pairs the percent with an inline resets-in
/// countdown (`19h`). That needs the window's `resetsAt`, which the shared
/// `IslandRightSlotContent.usage(percent:windowLabel:providerTitle:)` payload does
/// **not** carry (it is `.help()`-tooltip-only today — SPEC §5A "hardest detail").
/// Threading `resetsAt` in would change that shared enum's shape, breaking the
/// Part-1 width-regression fixture that pins the 3-tuple signature and rippling
/// across all six themes' pills — out of this Halo-scoped ticket. So the honest
/// third token is the **window label** (`7d`) the payload does carry, dim; the
/// full inline countdown lands with the shared payload change (tracked separately).
private struct HaloUsageFilament: View {
    let percent: Int
    let windowLabel: String
    let providerTitle: String

    @Environment(\.islandTokens) private var tokens

    /// Threshold tint — crit `≥90`, warn `70…90`, else fine. Computed from the
    /// value so a fixture at any percent reads truthfully, though in production the
    /// pill only ever shows the crit red (usage earns pill space only at ≥90).
    private var tint: Color {
        if percent >= 90 { return HaloEdge.usageCrit }
        if percent >= 70 { return HaloEdge.usageWarn }
        return HaloEdge.usageFine
    }

    private var fraction: Double { min(1, max(0, Double(percent) / 100)) }

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(tokens.colors.paper.opacity(0.12), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.6), radius: 3)
            }
            .frame(width: 14, height: 14)

            Text("\(providerTitle) \(percent)%")
                .font(.system(size: HaloTypography.pillLabelSize, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(tint)

            Text(windowLabel)
                .font(.system(size: HaloTypography.usageKickerSize, weight: .regular, design: .default))
                .monospacedDigit()
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.tertiaryTextOpacity))
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Label tone (pure · SPEC §5A mono-object split)

/// Splits the closed pill's resolved label into Halo's tone runs (SPEC §5A ·
/// mockup §A). The label arrives as one already-localized string from
/// `IslandClosedLabelResolver`, so the split is keyed off the resolved ambient
/// frame (which produced that string) rather than re-parsing localized words —
/// a pure function `HaloClosedPillTests` pins against the resolver's own output.
///
/// - **A2 working** — `Editing AppModel.swift` → **verb** sans/dim + **object**
///   mono/primary; the aggregate `3 working` → **count** primary/strong +
///   qualifier dim.
/// - **A3 permission** — `Approve swift build?` → the command lifted into a mono
///   run (via `commandAffixes`), the rest primary; when the affixes don't match
///   (the `Approval needed` fallback) the whole label renders primary.
/// - **A4 question** — `Answer needed` → the lead word dim, the rest primary.
/// - **A5/A6 completion** — `Done · the-automator` → the `Done ·` prefix dim, the
///   workspace primary (sans — a workspace name is not code, so it is **not** mono).
enum HaloPillLabelTone {
    struct Segment: Equatable {
        enum Role: Equatable {
            /// Sans, secondary (`t2`) — the A2 verb, the A4 lead word, the A5
            /// `Done ·` prefix.
            case dim
            /// Sans, primary (`t1`) — the workspace, the permission prefix/suffix,
            /// any unsplit label.
            case primary
            /// Mono, primary (`t1`) — the A2 object/file, the A3 command (the
            /// scanned code roles).
            case mono
            /// Sans, primary, one weight heavier — the A2′ aggregate count.
            case count
        }

        var text: String
        var role: Role
    }

    static func segments(
        for text: String,
        ambient: PouredPillAmbientState,
        commandAffixes: (prefix: String, suffix: String)? = nil
    ) -> [Segment] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        switch ambient {
        case .working:
            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                return [Segment(text: trimmed, role: .primary)]
            }
            if parts[0].allSatisfy(\.isNumber) {
                // "3 working" — count strong, qualifier dim.
                return [
                    Segment(text: parts[0], role: .count),
                    Segment(text: " " + parts[1], role: .dim),
                ]
            }
            // "Editing AppModel.swift" — verb sans/dim, object mono/primary.
            return [
                Segment(text: parts[0], role: .dim),
                Segment(text: " " + parts[1], role: .mono),
            ]

        case .permission:
            // "Approve swift build?" — lift the command into a mono run.
            if let affixes = commandAffixes,
               trimmed.hasPrefix(affixes.prefix),
               trimmed.hasSuffix(affixes.suffix),
               trimmed.count > affixes.prefix.count + affixes.suffix.count {
                let command = String(
                    trimmed.dropFirst(affixes.prefix.count).dropLast(affixes.suffix.count)
                )
                var out: [Segment] = []
                if !affixes.prefix.isEmpty { out.append(Segment(text: affixes.prefix, role: .primary)) }
                out.append(Segment(text: command, role: .mono))
                if !affixes.suffix.isEmpty { out.append(Segment(text: affixes.suffix, role: .primary)) }
                return out
            }
            return [Segment(text: trimmed, role: .primary)]

        case .question:
            // "Answer needed" — lead word dim, the rest primary.
            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                return [Segment(text: trimmed, role: .primary)]
            }
            return [
                Segment(text: parts[0], role: .dim),
                Segment(text: " " + parts[1], role: .primary),
            ]

        case .completed:
            // "Done · the-automator" — prefix dim, workspace primary (sans).
            if let range = trimmed.range(of: " · ") {
                let prefix = String(trimmed[..<range.lowerBound]) + " ·"
                let object = String(trimmed[range.upperBound...])
                return [
                    Segment(text: prefix, role: .dim),
                    Segment(text: " " + object, role: .primary),
                ]
            }
            return [Segment(text: trimmed, role: .primary)]

        case .idle:
            return [Segment(text: trimmed, role: .primary)]
        }
    }
}
