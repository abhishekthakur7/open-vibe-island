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
        if reduceMotion { return glowRadius }
        return glowPulse ? glowRadius + 2 : glowRadius - 1
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: HaloUsageMetrics.arcSpan)
                .stroke(
                    Color.white.opacity(reduceTransparency ? 0.2 : 0.1),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            Circle()
                .trim(from: 0, to: valueTrim)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .shadow(
                    color: color.opacity(isCritical && !reduceMotion && glowPulse ? 0.75 : 0.6),
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

/// Halo's opened-header usage readout (AB-343 · `SPEC-halo` §5C · mockup §C): one
/// light-filament and readout per provider window, laid out around the notch by
/// `HaloHeaderControls`.
///
/// Each window shows the threshold filament beside a two-line readout — the
/// `Claude 5h` kicker (`.fk`, at floor) over the `34% · 2h 10m` value
/// (`.fv`, tabular): **percent + resets-in inline**, surfacing `resetsAt` which
/// today lives only in the `.help()` tooltip (the SPEC's "hardest detail"). The
/// same per-window summary is kept in the tooltip. Colour is the single
/// `HaloUsageThreshold` rule.
struct HaloUsageSummary: View {
    let providers: [UsageProviderPresentation]
    let lang: LanguageManager
    /// Fitted per profile by `HaloHeaderControls` (see `HaloUsageMetrics`).
    var filamentDiameter: CGFloat = HaloUsageMetrics.headerFilamentTopBar
    /// Injected so the inline reset countdowns are deterministic in previews /
    /// tests; defaults to the wall clock in the live overlay.
    var now: Date = .now

    var body: some View {
        ViewThatFits(in: .horizontal) {
            summaryRow(usesShortTitles: false)
            summaryRow(usesShortTitles: true)
        }
    }

    private func summaryRow(usesShortTitles: Bool) -> some View {
        HStack(spacing: 14) {
            ForEach(providers) { provider in
                HaloUsageProviderGroup(
                    provider: provider,
                    usesShortTitle: usesShortTitles,
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
    let usesShortTitle: Bool
    let filamentDiameter: CGFloat
    let now: Date
    let lang: LanguageManager

    private var providerTitle: String {
        usesShortTitle ? provider.shortTitle : provider.title
    }

    var body: some View {
        let summaryText = UsageSummaryAccessibilityFormatter.summary(
            for: provider,
            usesShortTitle: usesShortTitle,
            asOf: now,
            lang: lang
        )

        HStack(spacing: 12) {
            ForEach(provider.windows) { window in
                HaloUsageWindowFilament(
                    providerTitle: providerTitle,
                    window: window,
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

/// A single window's header filament and its two-line readout: the `Claude 5h`
/// kicker over `34% · 2h 10m` (percent + resets-in inline, `.monospacedDigit`).
struct HaloUsageWindowFilament: View {
    let providerTitle: String
    let window: UsageWindowPresentation
    let filamentDiameter: CGFloat
    let now: Date
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var threshold: HaloUsageThreshold {
        HaloUsageThreshold.threshold(for: window.usedPercentage)
    }

    /// `34% · 2h 10m` when a reset is known, else `34%`.
    private var valueText: String {
        let percent = "\(window.roundedUsedPercentage)%"
        if let remaining = window.remainingLabel(asOf: now) {
            return "\(percent) · \(remaining)"
        }
        return percent
    }

    var body: some View {
        HStack(spacing: 9) {
            HaloUsageFilamentArc(
                fraction: window.usedPercentage / 100,
                color: threshold.filamentColor,
                isCritical: threshold.isCritical,
                diameter: filamentDiameter,
                lineWidth: HaloUsageMetrics.headerFilamentLineWidth,
                glowRadius: 3
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("\(providerTitle) \(window.label)")
                    .font(.system(size: HaloTypography.usageKickerSize, weight: .semibold))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))

                Text(valueText)
                    .font(.system(size: HaloTypography.usageValueSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            }
        }
        .accessibilityHidden(true)
    }
}
