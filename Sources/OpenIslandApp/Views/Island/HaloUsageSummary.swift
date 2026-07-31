import SwiftUI
import OpenIslandCore

/// Sizes for Halo's usage surfaces (AB-343 · `SPEC-halo` §5C / §5I · mockup §C /
/// §I). Pinned in `HaloUsageTests` so the header filament and the §I meter dial
/// can't drift from the mockup geometry.
///
/// The filament is a **270° light arc** (a 3/4 ring, gap at the top) drawn as a
/// faint track under a threshold-coloured value arc that carries a `drop-shadow`
/// glow — the same SVG idiom the mockup uses (`viewBox 40`, `r 16`, `stroke 2.2`,
/// `dasharray 75/100` under `rotate(135)`), scaled to the two Halo sizes.
///
/// The header filament grows to the mockup's **30pt** on the notch profile
/// (whose opened header rides the ~38pt physical-notch band), but the top-bar /
/// external profile caps the opened header at the ~24pt menu-bar band — a frame
/// shared across every theme and tied to the morph alignment (it must not grow) —
/// so a 30pt ring there would bleed into the summary strip below. The filament is
/// therefore **fitted per profile**, exactly as `PouredUsageMetrics` fits its
/// ring: 30pt where the band allows it, a smaller `headerFilamentTopBar` where it
/// doesn't. The full §I meter card is a free surface and uses the 52pt dial.
enum HaloUsageMetrics {
    /// Header lane filament on the notch profile (fits the ~38pt notch band).
    static let headerFilamentNotch: CGFloat = 30
    /// Header lane filament on the top-bar / external profile (fits the ~24pt band).
    static let headerFilamentTopBar: CGFloat = 22
    /// Header filament stroke — the mockup's 2.2px arc on the 30pt filament.
    static let headerFilamentLineWidth: CGFloat = 2.2
    /// The I′ closed-pill filament (mockup §I′: a 15pt `svg` box, `r 9`,
    /// `stroke 2.4`). Named here beside its siblings because the header's
    /// narrowest lane rung (`HaloUsageLaneRung.minimal`) borrows exactly this
    /// size — it is the theme's proven "smallest arc that still reads".
    static let pillFilament: CGFloat = 15
    /// Full §I meter-card filament dial.
    static let meterFilament: CGFloat = 52
    /// The §I dial stroke — the mockup's 3px arc on the 52pt dial.
    static let meterFilamentLineWidth: CGFloat = 3

    /// The filament is a 3/4 circle (270°): the fraction of the full circumference
    /// the arc spans. The mockup's `dasharray "75 100"` on `pathLength 100`.
    static let arcSpan: CGFloat = 0.75
    /// The filament's rotation so its gap sits at the top (mockup `rotate(135)`).
    static let arcRotationDegrees: Double = 135
}

/// The **single** usage threshold rule for Halo (AB-343 · `SPEC-halo` §5I · mockup
/// §I). The band a usage percentage falls into, the filament colour it lights, and
/// the word it prints (FINE / WARN / CRITICAL) all resolve through here so Halo
/// can't drift from the shared usage semantics.
///
/// The band **cut-offs are unchanged** from the app-wide `usageColor` rule
/// (`IslandUsageSummary`: `>= 90` critical, `70..<90` warn, else fine) — exactly
/// like `AnnualUsageVerdict` / `PouredUsageThreshold`. The colours are Halo's own
/// `HaloEdge` usage filaments (`usageFine #5FE39A` / `usageWarn #FFCF7A` /
/// `usageCrit #FF6B6B`), pinned to the SPEC hex by `HaloUsageTests`.
enum HaloUsageThreshold: String, CaseIterable, Sendable {
    case fine
    case warn
    case critical

    /// The band a usage percentage falls into. The cut-offs mirror the app-wide
    /// `usageColor` rule so Halo can't drift from the shared usage semantics.
    static func threshold(for percentage: Double) -> HaloUsageThreshold {
        switch percentage {
        case 90...:
            .critical
        case 70..<90:
            .warn
        default:
            .fine
        }
    }

    /// `true` for the `>= 90` band — the one filament allowed to pulse.
    var isCritical: Bool { self == .critical }

    /// The tint the §I threshold capsule (`.thl`) fills with — the band colour at
    /// the mockup's per-band alpha (`fine .12` / `warn .13` / `crit .14`).
    var pillTintOpacity: Double {
        switch self {
        case .fine:
            0.12
        case .warn:
            0.13
        case .critical:
            0.14
        }
    }

    /// The Halo filament colour this band lights (`HaloEdge` usage table).
    var filamentColor: Color {
        switch self {
        case .fine:
            HaloEdge.usageFine
        case .warn:
            HaloEdge.usageWarn
        case .critical:
            HaloEdge.usageCrit
        }
    }

    /// The localized band word (`island.halo.usage.fine/warn/critical`). The §I
    /// meter card prints it uppercased (FINE / WARN / CRITICAL); the header lane
    /// leaves it to the numeric readout.
    var localizationKey: String { "island.halo.usage.\(rawValue)" }
}

/// Halo's living light-filament arc: a faint 3/4-circle track under a
/// threshold-coloured value arc that fills in proportion to usage and casts a
/// `drop-shadow` glow. Reused at both the header lane size and the §I meter dial.
///
/// **Glow / drawing-group note (AC).** The value arc's glow is a SwiftUI
/// `.shadow` that bleeds past the arc's bounds — the same luminous bleed that
/// makes Halo rows `rowIsDrawingGroupSafe == false`. This view therefore **never**
/// applies `.drawingGroup()`; an off-screen render would flatten/clip the glow to
/// the frame. The panel composes the filament without a drawing group so the bleed
/// survives.
///
/// The arc sweeps in on appear and the critical band's glow breathes subtly; both
/// are gated off under Reduce Motion, where the filament paints its final fraction
/// with a steady glow. The track opacity lifts under Reduce Transparency so the
/// gauge stays readable.
struct HaloUsageFilamentArc: View {
    let fraction: Double
    let color: Color
    let isCritical: Bool
    var diameter: CGFloat = HaloUsageMetrics.headerFilamentTopBar
    var lineWidth: CGFloat = HaloUsageMetrics.headerFilamentLineWidth
    /// The steady glow radius (mockup `drop-shadow(0 0 3-5px …)`); the critical
    /// band pulses around it.
    var glowRadius: CGFloat = 3

    @State private var animatedFraction: Double = 0
    @State private var glowPulse = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var clampedFraction: Double { min(1, max(0, fraction)) }

    /// The value arc spans `arcSpan` of the circle (270°); the fill is that span
    /// scaled by usage.
    private var valueTrim: CGFloat {
        HaloUsageMetrics.arcSpan * CGFloat(min(1, max(0.0001, animatedFraction)))
    }

    private var effectiveGlowRadius: CGFloat {
        guard isCritical else { return glowRadius }
        if reduceMotion { return glowRadius + 1 }
        return glowPulse ? glowRadius + 1 : glowRadius
    }

    /// The mockup's ring path spans 80.8% of its box (`r=21` in a 52 viewBox,
    /// `r=16` in 40) — the remainder is breathing room for the glow. A full-frame
    /// `Circle()` plus a centered stroke would overshoot the box instead.
    private var ringInset: CGFloat { diameter * 0.096 }

    var body: some View {
        ZStack {
            Circle()
                .inset(by: ringInset)
                .trim(from: 0, to: HaloUsageMetrics.arcSpan)
                .stroke(
                    Color.white.opacity(reduceTransparency ? 0.2 : 0.1),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            Circle()
                .inset(by: ringInset)
                .trim(from: 0, to: valueTrim)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .shadow(
                    color: color.opacity(isCritical && !reduceMotion && glowPulse ? 0.6 : 0.55),
                    radius: effectiveGlowRadius
                )
        }
        .rotationEffect(.degrees(HaloUsageMetrics.arcRotationDegrees))
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion {
                animatedFraction = clampedFraction
            } else {
                withAnimation(.easeOut(duration: 0.6)) {
                    animatedFraction = clampedFraction
                }
                if isCritical {
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
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

/// How much of the §C filament a header lane has room to draw (parity V9).
///
/// The board gives each lane ~196pt (a 520pt panel, a 96pt `.ngap`); this
/// MacBook's physical notch is ~185pt, so the real right-of-notch lane is
/// ~59.5pt even after Halo spends both of its geometry knobs (see
/// `HaloHeaderControls.notchHeaderTrailingPadding` /
/// `.notchHeaderControlButtonSize`). Rather than pick one fixed compromise for
/// every display, the lane walks this ladder through `ViewThatFits` and renders
/// the **richest rung its measured width admits** — the left lane (~150pt) keeps
/// the board's full `CLAUDE 5H` / `34%` form, the starved right lane degrades to
/// a smaller arc and a shorter kicker rather than vanishing (which is what it did
/// before: `rightUsageWidth` snapped to 0 and the window silently moved to the §I
/// meter card).
///
/// Widths at the notch profile, measured at Halo's own type sizes (10pt kicker
/// with `.07em` tracking, 11pt value): full 103.7 · shortTitle 72.0 ·
/// windowOnly 64.6 · compact 56.6 · minimal 46.6.
enum HaloUsageLaneRung: CaseIterable {
    /// The board's own form: `CLAUDE 5H` over `34%`, profile-size arc.
    case full
    /// `CL 5H` — the shared `shortTitle` abbreviation (F7).
    case shortTitle
    /// `5H` — the window label alone; the provider is inferable from the lane
    /// beside it (and always carried by the `.help()` / VoiceOver summary).
    case windowOnly
    /// `5H` over `34%` on the smaller top-bar arc — the first rung that fits a
    /// real notch's right lane.
    case compact
    /// Percent only, on the pill's own 15pt filament size (`HaloUsageFilament`,
    /// §I′) — the narrowest form that still carries a number.
    case minimal
    /// The bare arc. The last resort so `ViewThatFits` — which renders its final
    /// candidate whether or not it fits — can never overflow a lane into the
    /// physical cutout: the fill fraction still reads as a gauge without colour
    /// doing the work alone, and the exact number stays one hover (`.help`) and
    /// one §I meter card away.
    case arcOnly

    /// Whether the kicker prints the provider, and how.
    var showsProvider: Bool {
        switch self {
        case .full, .shortTitle: true
        case .windowOnly, .compact, .minimal, .arcOnly: false
        }
    }

    /// `false` for `.arcOnly` — the one rung that drops the readout entirely.
    var showsReadout: Bool { self != .arcOnly }

    /// The `shortTitle` abbreviation (`Cl` / `Cx`) instead of the full name.
    var usesShortTitle: Bool { self == .shortTitle }

    /// `false` from `.minimal` down, where the kicker line is dropped.
    var showsKicker: Bool {
        switch self {
        case .full, .shortTitle, .windowOnly, .compact: true
        case .minimal, .arcOnly: false
        }
    }

    /// The arc this rung draws, given the profile-fitted diameter the lane was
    /// handed (30pt under the notch, 22pt on the top bar). Never *grows* the
    /// profile size — a rung only ever trades size for fit.
    func filamentDiameter(profile: CGFloat) -> CGFloat {
        switch self {
        case .full, .shortTitle, .windowOnly:
            profile
        case .compact:
            min(profile, HaloUsageMetrics.headerFilamentTopBar)
        case .minimal, .arcOnly:
            min(profile, HaloUsageMetrics.pillFilament)
        }
    }

    /// The board's `.fil{gap:9px}`, tightened only on the narrowest rung.
    var readoutGap: CGFloat {
        showsKicker ? 9 : 6
    }
}

/// Halo's opened-header usage readout (AB-343 · `SPEC-halo` §5C · mockup §C): one
/// light-filament and readout per provider window, laid out around the notch by
/// `HaloHeaderControls`.
///
/// Each window shows the threshold filament beside a two-line readout — the
/// `CLAUDE 5H` kicker (`.fk`, at floor) over the `34%` value (`.fv`, tabular;
/// G-54 keeps the reset countdown in the §I meter card, not here). The full
/// per-window summary, resets included, stays in the `.help()` tooltip and the
/// single grouped VoiceOver stop. Colour is the single `HaloUsageThreshold` rule.
///
/// **V9**: the row is chosen by `ViewThatFits` from the `HaloUsageLaneRung`
/// ladder, so a lane the physical notch has starved degrades (smaller arc,
/// shorter kicker) instead of being dropped from the header entirely.
struct HaloUsageSummary: View {
    let providers: [UsageProviderPresentation]
    let lang: LanguageManager
    /// Fitted per profile by `HaloHeaderControls` (see `HaloUsageMetrics`).
    var filamentDiameter: CGFloat = HaloUsageMetrics.headerFilamentTopBar
    /// Injected so the inline reset countdowns are deterministic in previews /
    /// tests; defaults to the wall clock in the live overlay.
    var now: Date = .now

    var body: some View {
        // V9: the ladder replaces the old two-rung (full title / short title)
        // `ViewThatFits` — same mechanism, three more rungs below it so a lane
        // the physical notch has starved degrades instead of disappearing.
        // Spelled out rather than looped: `ViewThatFits` picks between its own
        // *literal* children, so a `ForEach` would hand it one candidate.
        ViewThatFits(in: .horizontal) {
            summaryRow(.full)
            summaryRow(.shortTitle)
            summaryRow(.windowOnly)
            summaryRow(.compact)
            summaryRow(.minimal)
            summaryRow(.arcOnly)
        }
    }

    private func summaryRow(_ rung: HaloUsageLaneRung) -> some View {
        HStack(spacing: 14) {
            ForEach(providers) { provider in
                HaloUsageProviderGroup(
                    provider: provider,
                    rung: rung,
                    filamentDiameter: filamentDiameter,
                    now: now,
                    lang: lang
                )
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// One provider's usage group: a filament-and-readout for each of its rate-limit
/// windows. No box, no pill — set off by the void and type alone (Halo idiom).
struct HaloUsageProviderGroup: View {
    let provider: UsageProviderPresentation
    let rung: HaloUsageLaneRung
    let filamentDiameter: CGFloat
    let now: Date
    let lang: LanguageManager

    private var providerTitle: String {
        rung.usesShortTitle ? provider.shortTitle : provider.title
    }

    var body: some View {
        // The spoken summary never degrades with the rung: whatever the lane has
        // room to *draw*, VoiceOver and the tooltip still name the provider, its
        // windows and their resets.
        let summaryText = UsageSummaryAccessibilityFormatter.summary(
            for: provider,
            usesShortTitle: false,
            asOf: now,
            lang: lang
        )

        HStack(spacing: 12) {
            ForEach(provider.windows) { window in
                HaloUsageWindowFilament(
                    providerTitle: providerTitle,
                    window: window,
                    rung: rung,
                    filamentDiameter: filamentDiameter,
                    now: now,
                    lang: lang
                )
            }
        }
        .help(summaryText)
        // One VoiceOver stop per provider — the same per-window summary the app
        // surfaces through `.help()`, matching the other themes (AB-244).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryText)
    }
}

/// A single window's header filament and its two-line readout: the `CLAUDE 5H`
/// kicker over the `34%` value (`.monospacedDigit`), shrunk and shortened per
/// `HaloUsageLaneRung` when the lane it landed in can't hold the full form.
struct HaloUsageWindowFilament: View {
    let providerTitle: String
    let window: UsageWindowPresentation
    /// How much of the readout this lane has room for (V9) — `.full` is the
    /// board's own form and the default every un-starved lane picks.
    var rung: HaloUsageLaneRung = .full
    let filamentDiameter: CGFloat
    let now: Date
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var threshold: HaloUsageThreshold {
        HaloUsageThreshold.threshold(for: window.usedPercentage)
    }

    /// The mockup's `.fil .fv` is the **percent only** (G-54) — the reset
    /// countdown belongs to the §I meter card's `resets in …` line, not the
    /// header lane, which stays a two-token glance (`CLAUDE 5H` / `34%`).
    private var valueText: String {
        "\(window.roundedUsedPercentage)%"
    }

    /// The kicker this rung prints: the board's `CLAUDE 5H`, its abbreviated
    /// `CL 5H`, or the bare `5H` once the lane can't hold a provider name.
    private var kickerText: String {
        rung.showsProvider ? "\(providerTitle) \(window.label)" : window.label
    }

    var body: some View {
        HStack(spacing: rung.readoutGap) {
            HaloUsageFilamentArc(
                fraction: window.usedPercentage / 100,
                color: threshold.filamentColor,
                isCritical: threshold.isCritical,
                diameter: rung.filamentDiameter(profile: filamentDiameter),
                lineWidth: HaloUsageMetrics.headerFilamentLineWidth,
                glowRadius: 3
            )

            if rung.showsReadout {
                VStack(alignment: .leading, spacing: 1) {
                    if rung.showsKicker {
                        Text(kickerText)
                            .font(.system(size: HaloTypography.usageKickerSize, weight: .medium))
                            .tracking(0.7)
                            .textCase(.uppercase)
                            .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                    }

                    Text(valueText)
                        .font(.system(size: HaloTypography.usageValueSize, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
