import SwiftUI
import OpenIslandCore

/// Halo's **full** usage meter card (AB-343 · `SPEC-halo` §5I / mockup §I).
///
/// Where the header lane compresses usage into a 30pt filament, this is the
/// expanded surface: **52pt light-filament dials**, one per provider window, each
/// carrying the `provider · window` label, an oversized tabular percentage (22pt),
/// the inline `resets in …` countdown (T06), and the threshold stated as a **word**
/// (FINE / WARN / CRITICAL, 10pt lifted) so the band is never colour-alone. Higher
/// percentage = more consumed (the filament fills proportionally). The `>= 90`
/// critical filament keeps its subtle glow-pulse, held static under Reduce Motion
/// by `HaloUsageFilamentArc`.
///
/// True to the Halo idiom the card is **chromeless** — pure void, no fill, no
/// stroked frame. Structure comes from the uppercase title, the tabular readouts
/// and whitespace alone. Colour is the single `HaloUsageThreshold` rule shared with
/// the header filament, on the unchanged `>= 90` / `70..<90` / else cut-offs.
struct HaloUsageMeterCard: View {
    /// Mockup `.meters{gap:26px}` between dial columns.
    private static let meterSpacing: CGFloat = 26
    /// The wrapped row gap (the same 16px rhythm as the card's title gap).
    private static let meterRowSpacing: CGFloat = 16

    let providers: [UsageProviderPresentation]
    let lang: LanguageManager
    /// The card's own leading/trailing inset. Defaults to the mockup's standalone
    /// `.meterc{padding:16px 18px 18px}`; when the card is mounted **inside** the
    /// opened panel it takes the panel's list inset instead, so the dials line up
    /// with the summary strip, the rows and the footer rather than hanging left of
    /// them.
    var sideInset: CGFloat = 18
    /// Injected so the reset countdowns render deterministically; defaults to the
    /// wall clock.
    var now: Date = .now

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }
    @Environment(\.islandTokens) private var tokens

    private struct Entry: Identifiable {
        let id: String
        let providerTitle: String
        let window: UsageWindowPresentation
    }

    private var entries: [Entry] {
        providers.flatMap { provider in
            provider.windows.map { window in
                Entry(
                    id: "\(provider.id)-\(window.id)",
                    providerTitle: provider.title,
                    window: window
                )
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(lang.t("island.halo.usage.metersTitle").uppercased())
                .font(.system(size: HaloTypography.summaryLabelSize, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))

            // The mockup's `.meters` is `flex-wrap:wrap` over `.meter{flex:1 1
            // 210px}` on a 520px card, which lands **two dials per row** and wraps
            // the rest (mockup §I / `ref-I-usage-meters.png`: Claude 5h + Claude 7d,
            // then Codex 7d on a second row). The panel is the same width class, so
            // the wrap is fixed at two rather than measured — three dials in one row
            // overflow the panel's side inset.
            wrappedMeters
        }
        .padding(.horizontal, sideInset)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One row of the wrap — up to two dials sharing the card width evenly
    /// (the mockup's `flex:1 1 210px` columns).
    private func meterRow(_ rowEntries: [Entry]) -> some View {
        HStack(alignment: .top, spacing: Self.meterSpacing) {
            ForEach(rowEntries) { entry in
                HaloUsageMeter(
                    providerTitle: entry.providerTitle,
                    window: entry.window,
                    now: now,
                    lang: lang
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A half-filled last row keeps its dial in the left column rather
            // than stretching it across the card (mockup §I's Codex row).
            if rowEntries.count == 1 {
                Color.clear.frame(maxWidth: .infinity)
            }
        }
    }

    /// The mockup's flex wrap: rows of two dials, in order.
    private var wrappedMeters: some View {
        let rows = stride(from: 0, to: entries.count, by: 2).map { start in
            Array(entries[start..<min(start + 2, entries.count)])
        }
        return VStack(alignment: .leading, spacing: Self.meterRowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                meterRow(row)
            }
        }
    }
}

/// One provider window's §I meter: a 52pt light-filament dial beside the label,
/// the oversized tabular percentage, the inline reset countdown, and the threshold
/// **word**. The critical filament glow-pulses (static under Reduce Motion).
struct HaloUsageMeter: View {
    let providerTitle: String
    let window: UsageWindowPresentation
    let now: Date
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var threshold: HaloUsageThreshold {
        HaloUsageThreshold.threshold(for: window.usedPercentage)
    }

    private var color: Color { threshold.filamentColor }

    var body: some View {
        HStack(spacing: 13) {
            HaloUsageFilamentArc(
                fraction: window.usedPercentage / 100,
                color: color,
                isCritical: threshold.isCritical,
                diameter: HaloUsageMetrics.meterFilament,
                lineWidth: HaloUsageMetrics.meterFilamentLineWidth,
                glowRadius: 4
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("\(providerTitle) · \(window.label)")
                    .font(.system(size: HaloTypography.meterLabelSize, weight: .medium))
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

                Text("\(window.roundedUsedPercentage)%")
                    .font(.system(size: HaloTypography.meterValueSize, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.4)
                    .foregroundStyle(color)

                if let remaining = window.remainingLabel(asOf: now) {
                    Text(lang.t("island.halo.usage.resetsIn", remaining))
                        .font(.system(size: HaloTypography.usageValueSize, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                }

                thresholdWord
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The band stated as a **word** (FINE / WARN / CRITICAL) so state survives
    /// colour-blindness / greyscale (`SPEC` §5I "never color alone"). Lifted to the
    /// 10pt floor (`thresholdPillSize`) and set in the mockup's tinted **capsule**
    /// (`.thl` — `padding:1px 7px; border-radius:20px` over the band colour at
    /// 12–14%), so the band reads as a chip on the void rather than bare coloured
    /// text (G-30).
    private var thresholdWord: some View {
        Text(lang.t(threshold.localizationKey).uppercased())
            .font(.system(size: HaloTypography.thresholdPillSize, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(threshold.pillTintOpacity)))
            .padding(.top, 5)
    }

    private var accessibilityLabel: String {
        var parts = [
            "\(providerTitle) \(window.label)",
            "\(window.roundedUsedPercentage)%",
            lang.t(threshold.localizationKey),
        ]
        if let remaining = window.remainingLabel(asOf: now) {
            parts.append(lang.t("island.halo.usage.resetsIn", remaining))
        }
        return parts.joined(separator: ", ")
    }
}
