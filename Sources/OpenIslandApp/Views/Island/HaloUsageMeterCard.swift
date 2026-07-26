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
    let providers: [UsageProviderPresentation]
    let lang: LanguageManager
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

            HStack(alignment: .top, spacing: 26) {
                ForEach(entries) { entry in
                    HaloUsageMeter(
                        providerTitle: entry.providerTitle,
                        window: entry.window,
                        now: now,
                        lang: lang
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
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
                    .font(.system(size: HaloTypography.metadataValueSize, weight: .medium))
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
    /// 10pt floor (`thresholdPillSize`).
    private var thresholdWord: some View {
        Text(lang.t(threshold.localizationKey).uppercased())
            .font(.system(size: HaloTypography.thresholdPillSize, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(color)
            .padding(.top, 3)
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
