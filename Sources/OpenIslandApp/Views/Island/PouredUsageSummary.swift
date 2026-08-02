import SwiftUI
import OpenIslandCore

/// Sizes for Poured Island 2.0's usage surfaces (AB-331 / `SPEC-poured-island`
/// §3.2 · §4I). Pinned in `PouredThemeTests` so the header ring and the §I
/// meter dial can't drift.
///
/// The header ring grows to the mockup's **30pt** on the notch profile (whose
/// opened header occupies the ~38pt physical-notch band), but the top-bar /
/// external profile caps the opened header at the ~24pt menu-bar band
/// (`IslandPanelView.closedNotchHeight`, a frame shared across every theme and
/// tied to the morph alignment — it must not grow), so a 30pt ring there would
/// bleed into the summary strip below. The ring is therefore **fitted per
/// profile**: 30pt where the band allows it, a smaller `headerRingTopBar` where
/// it doesn't. The full §I meter card is a free surface and uses the 52pt dial.
enum PouredUsageMetrics {
    /// Header lane ring on the notch profile (fits the ~38pt notch band).
    static let headerRingNotch: CGFloat = 30
    /// Header lane ring on the top-bar / external profile (fits the ~24pt band).
    static let headerRingTopBar: CGFloat = 22
    /// Header ring stroke — proportional to the mockup's 4px donut on the 30pt
    /// ring.
    static let headerRingLineWidth: CGFloat = 3.5
    /// The full §I meter-card dial.
    static let meterDial: CGFloat = 52
    /// The §I dial stroke, proportional to the mockup's `stroke-width 5` on its
    /// `viewBox 42` dial scaled up to 52pt.
    static let meterDialLineWidth: CGFloat = 6
}

/// The **single** usage threshold rule for Poured Island 2.0 (AB-331,
/// `SPEC-poured-island` §3.2 "must be one rule" · §4I).
///
/// The shipped header ring returned raw `.red/.orange/.green` while the mockup's
/// `pct-fine/warn/crit` mapped to the token palette (`--done/--answer/--fail`).
/// This enum unifies them: the arc, the ring value, the meter percentage and the
/// meter word/shape all resolve their colour through here. The band **cut-offs
/// are unchanged** from the app-wide `usageColor` (`>= 90` / `70..<90` / else) —
/// only the colours move onto the status tokens, exactly like `PouredUsageThreshold`.
///
/// Each band also carries a **word** and a **shape marker** so the §I meter state
/// is never colour-alone (`Fine ●` / `Warn ▲` / `Critical ●`, `SPEC` §4I).
enum PouredUsageThreshold: String, CaseIterable, Sendable {
    case fine
    case warn
    case critical

    /// The band a usage percentage falls into. The cut-offs mirror the app-wide
    /// `usageColor` rule (`IslandUsageSummary`: `>= 90` critical, `70..<90` warn,
    /// else fine) so Poured can't drift from the shared usage semantics.
    static func threshold(for percentage: Double) -> PouredUsageThreshold {
        switch percentage {
        case 90...:
            .critical
        case 70..<90:
            .warn
        default:
            .fine
        }
    }

    /// `true` for the `>= 90` band — the one that lights the danger glow.
    var isCritical: Bool { self == .critical }

    /// The token status colour this band maps onto (`SPEC` §3.2 resolution:
    /// `fine → statusCompleted`, `warn → statusWaitingForAnswer`,
    /// `critical → statusFailed`). Replaces the raw `.red/.orange/.green`.
    func color(_ colors: IslandColorTokens) -> Color {
        switch self {
        case .fine:
            colors.statusCompleted
        case .warn:
            colors.statusWaitingForAnswer
        case .critical:
            colors.statusFailed
        }
    }

    /// The glyph carried beside the word so the state reads without colour
    /// (`Fine ●` / `Warn ▲` / `Critical ●`). `warn`'s triangle is what separates
    /// it from the two dot bands; the word separates `fine` from `critical`.
    var shapeMarker: String {
        switch self {
        case .fine:
            "\u{25CF}"   // ●
        case .warn:
            "\u{25B2}"   // ▲
        case .critical:
            "\u{25CF}"   // ●
        }
    }

    /// The localized band word (`island.poured.usage.fine/warn/critical`).
    var localizationKey: String { "island.poured.usage.\(rawValue)" }
}

/// Poured Island's usage readout (AB-301 / AB-331): one ring-and-readout per
/// provider window, laid out around the notch cut-out by `PouredHeaderControls`.
///
/// Each window shows a conic-gradient ring with the numeric percentage **inside**
/// it, the `provider + window` label beside, and the **resets countdown inline**
/// (`resets 2h 10m`, T06 tabular) — visible without hover, with the same
/// per-window summary retained in the `.help()` tooltip. Threshold colour is the
/// unified `PouredUsageThreshold` rule (the ring arc + the value both light the
/// token status colour, never the retired raw `.red/.orange/.green`). Rings
/// settle with a short sweep and the danger glow breathes, both gated off under
/// Reduce Motion. Ring labels read their opacities through the token contrast
/// floor so they survive Increase Contrast.
struct PouredUsageSummary: View {
    let providers: [UsageProviderPresentation]
    let lang: LanguageManager
    /// Fitted per profile by `PouredHeaderControls` (see `PouredUsageMetrics`).
    var ringDiameter: CGFloat = PouredUsageMetrics.headerRingTopBar
    /// Injected so the inline reset countdowns are deterministic in previews /
    /// tests; defaults to the wall clock in the live overlay.
    var now: Date = .now

    /// R3/C8 (`01-poured-island.html:785`, `:790`): the wings render the **full**
    /// provider title (`CLAUDE 5H` / `CLAUDE 7D`), unconditionally.
    ///
    /// **Measured root cause** (instrumented `Layout` probe over a live
    /// `pouredGroupedSix` harness run, notch profile, 1512pt built-in display):
    /// the abbreviation was never a real width verdict. `PouredHeaderControls`
    /// hands each usage lane a **fixed, non-clipping**
    /// `.frame(width: metrics.leftUsageWidth, alignment: .leading)`; on this
    /// hardware `IslandHeaderLaneLayout.metrics` reports `leftUsageWidth =
    /// 119.5` (and `rightUsageWidth = 0` — the right wing is below the shared
    /// 58pt floor once the 46pt trailing gutter and the three 22pt controls are
    /// paid for), so **both** flattened windows are proposed 119.5pt for
    /// 224pt of content. That proposal reached the label as 68pt / 64pt against
    /// label ideals of 72pt / 64pt, and `ViewThatFits` dutifully picked the
    /// abbreviation — while the lane frame, which never clips, went on drawing
    /// the meters at their full ideal width anyway. R2 moved the `ViewThatFits`
    /// one level down; it stayed inside the same phantom proposal, so nothing
    /// changed.
    ///
    /// A candidate chosen against a width the render never enforces is noise,
    /// so the fallback is gone: the header always renders the board's own full
    /// title. (The lane-starvation finding itself — two windows crammed into one
    /// wing, overflowing it — is reported separately; it is a distribution
    /// question, not a typography one.)
    var body: some View {
        HStack(spacing: 12) {
            ForEach(providers) { provider in
                PouredUsageProviderGroup(
                    provider: provider,
                    ringDiameter: ringDiameter,
                    now: now,
                    lang: lang
                )
            }
        }
        .lineLimit(1)
    }
}

/// One provider's usage group: a ring-and-readout for each of its rate-limit
/// windows. Poured 2.0 drops the AB-301 glass capsule (the mockup's header
/// `.umeter` is bare — the chip padding also can't fit the taller 30pt ring in
/// the height-capped header band); identity is carried by the `provider window`
/// label beside each ring instead.
struct PouredUsageProviderGroup: View {
    let provider: UsageProviderPresentation
    let ringDiameter: CGFloat
    let now: Date
    let lang: LanguageManager

    var body: some View {
        // R3/C8: the header speaks the unabbreviated provider name, and so does
        // VoiceOver — the two can no longer disagree.
        let summaryText = UsageSummaryAccessibilityFormatter.summary(
            for: provider,
            usesShortTitle: false,
            asOf: now,
            lang: lang
        )

        HStack(spacing: 12) {
            ForEach(provider.windows) { window in
                PouredUsageWindowRing(
                    providerTitle: provider.title,
                    window: window,
                    ringDiameter: ringDiameter,
                    now: now,
                    lang: lang
                )
            }
        }
        .help(summaryText)
        // AB-244 / AB-301: the whole group is one VoiceOver stop — the same
        // per-window summary the app surfaces through `.help()`.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryText)
    }
}

/// A single window's conic ring with the percentage **inside** it, and beside it
/// the `provider window` label over the inline `resets 2h 10m` countdown. The
/// arc and the value both light the unified `PouredUsageThreshold` colour.
struct PouredUsageWindowRing: View {
    let providerTitle: String
    let window: UsageWindowPresentation
    let ringDiameter: CGFloat
    let now: Date
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var threshold: PouredUsageThreshold {
        PouredUsageThreshold.threshold(for: window.usedPercentage)
    }

    private var color: Color { threshold.color(tokens.colors) }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                PouredUsageRing(
                    fraction: window.usedPercentage / 100,
                    color: color,
                    isDanger: threshold.isCritical,
                    diameter: ringDiameter,
                    lineWidth: PouredUsageMetrics.headerRingLineWidth
                )

                // Percentage inside the ring, per PouredType (`.monospacedDigit`).
                //
                // R4-7 (PI-I-001 · `01-poured-island.html:231`): `.uring .uv` is
                // `--t1` paper (`rgba(242,245,251,.96)`), **not** the threshold
                // colour. Only the arc carries the band — the numeral stays
                // neutral so two rings in the same header read as one readout
                // with two values, not two differently-coloured widgets.
                Text("\(window.roundedUsedPercentage)")
                    .font(PouredType.Role.usageRingValue.font)
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.96, increaseContrast: increasesContrast)))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            // PI-I-001 · the board's `.umeter .ut` block
            // (`01-poured-island.html:233-234`): an uppercase tracked micro-label
            // over a heavier, *non*-uppercase countdown that reads as the line
            // the eye actually lands on. Line 1 holds the theme's 10pt readable
            // floor rather than the board's 9px (the same lift `metadataKey`
            // documents); its tracking is the board's own `.07em`.
            //
            // R3/C8: no abbreviation candidate — see `PouredUsageSummary.body`
            // for the measured reason the old `ViewThatFits` could only ever
            // answer the wrong question here.
            labelBlock(title: providerTitle)
        }
        .accessibilityHidden(true)
    }

    private func labelBlock(title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(title) \(window.label)".uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(0.7)
                .lineLimit(1)
                .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))

            if let remaining = headerCountdownLabel {
                Text(lang.t("island.poured.usage.resets", remaining))
                    .font(PouredType.Role.usageResetLabel.font)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// PI-I-001: the **header** countdown is coarser than the §I meter card's.
    /// The board renders `resets 2h 10m` for the 5-hour window but `resets 3d`
    /// for the weekly one (`01-poured-island.html:785`, `:790`), while the §I
    /// card spells the same window out as `resets in 3d 4h` (`:1471`). Both are
    /// rendered, so both are golden in their own frame: in a header wing the
    /// whole-day answer is what a glance needs, so anything a day or more out
    /// coarsens to days here — and only here.
    private var headerCountdownLabel: String? {
        guard let resetsAt = window.resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        guard interval >= 86_400 else {
            return UsageCountdownFormatter.remainingLabel(forRemaining: interval)
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day]
        formatter.maximumUnitCount = 1
        return formatter.string(from: interval)
    }
}

/// The ring itself: a faint track under a conic-gradient progress arc. The arc
/// sweeps in on appear and the danger band's glow breathes — both disabled under
/// Reduce Motion, where the ring paints its final fraction statically. The track
/// opacity lifts under Reduce Transparency so the gauge stays readable. Reused at
/// both the header lane size and the §I meter dial.
struct PouredUsageRing: View {
    let fraction: Double
    let color: Color
    let isDanger: Bool
    var diameter: CGFloat = 16
    var lineWidth: CGFloat = 2.6

    @State private var animatedFraction: Double = 0
    @State private var glowPulse = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var clampedFraction: Double { min(1, max(0, fraction)) }

    private var glowRadius: CGFloat {
        guard isDanger else { return 0 }
        if reduceMotion { return 2.5 }
        return glowPulse ? 3.5 : 1.5
    }

    var body: some View {
        ZStack {
            // R4-8 (PI-I-001 · `01-poured-island.html:228-229`, `:1456`): the
            // unused track is a **neutral** `rgba(242,245,251,.12)` over the
            // ring's dark disc — a tinted track (the old `color.opacity(0.18)`)
            // painted a second, dimmer copy of the band colour around the whole
            // circle and measured green-grey at 34%.
            Circle()
                .stroke(
                    Color.white.opacity(reduceTransparency ? 0.24 : 0.12),
                    lineWidth: lineWidth
                )

            // R4-8: the value arc is the band colour **flat**. The angular ramp
            // from `color.opacity(0.55)` desaturated the arc's first half, so a
            // `#6fb982` ring measured a dull `(103,144,111)` — the board draws
            // one solid `conic-gradient(<colour> calc(p*1%), track 0)` stop.
            Circle()
                .trim(from: 0, to: max(0.0001, animatedFraction))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: isDanger ? color.opacity(reduceMotion ? 0.7 : (glowPulse ? 0.85 : 0.4)) : .clear, radius: glowRadius)
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion {
                animatedFraction = clampedFraction
            } else {
                withAnimation(.easeOut(duration: 0.6)) {
                    animatedFraction = clampedFraction
                }
                if isDanger {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        glowPulse = true
                    }
                }
            }
        }
        .onChange(of: fraction) { _, _ in
            if reduceMotion {
                animatedFraction = clampedFraction
            } else {
                withAnimation(.easeOut(duration: 0.4)) {
                    animatedFraction = clampedFraction
                }
            }
        }
        .accessibilityHidden(true)
    }
}
