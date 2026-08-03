import SwiftUI
import OpenIslandCore

/// Poured Island 2.0's **full** usage meter card (AB-331, `SPEC-poured-island`
/// §4I / mockup §I).
///
/// Where the header lane compresses usage into a 30pt ring, this is the
/// expanded surface: a glass card of **52pt conic dials**, one per provider
/// window, each carrying the `provider · window` label, an oversized tabular
/// percentage, the inline `resets in …` countdown (T06), and a threshold pill
/// that states the band as **word + shape** (`Fine ●` / `Warn ▲` / `Critical ●`)
/// so the state is never colour-alone. Higher percentage = more consumed (the
/// dial fills proportionally). The card is **still** — §I renders no animation
/// in the board, so the `>= 90` dial's danger breathe is gone (see
/// `PouredUsageRing`); only the sweep-in on appear remains.
///
/// Colour is the single `PouredUsageThreshold` rule shared with the header ring:
/// `fine → statusCompleted`, `warn → statusWaitingForAnswer`,
/// `critical → statusFailed`, on the unchanged `>= 90` / `70..<90` / else
/// cut-offs.
struct PouredUsageMeterCard: View {
    let providers: [UsageProviderPresentation]
    let lang: LanguageManager
    /// Injected so the reset countdowns render deterministically; defaults to
    /// the wall clock.
    var now: Date = .now

    @Environment(\.islandTokens) private var tokens
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
        VStack(alignment: .leading, spacing: 14) {
            Text(lang.t("island.poured.usage.metersTitle").uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(tokens.colors.tertiaryTextOpacity))

            // PI-I-001/I1: the board's `.meters` is `display:flex; gap:22px;
            // flex-wrap:wrap` over `.meter{flex:1 1 200px}`
            // (`01-poured-island.html:469-470`) — inside its 484pt content box
            // (520 − 18 − 18) three 200pt meters can't share a row, so the card
            // renders **2 + 1**, not a single row of three. A plain `HStack`
            // always drew one row and squeezed each meter, so a board-width card
            // never reproduced the board composition.
            PouredMeterFlowLayout(
                minItemWidth: PouredMeterFlow.minItemWidth,
                spacing: PouredMeterFlow.spacing
            ) {
                ForEach(entries) { entry in
                    PouredUsageMeter(
                        providerTitle: entry.providerTitle,
                        window: entry.window,
                        now: now,
                        lang: lang
                    )
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.metrics.openedTopRadius, style: .continuous)
        return ZStack {
            shape.fill(tokens.colors.surfaceInk)

            // The Poured body gradient carries elevation by inner luminance;
            // non-Poured tokens (no `bodyGradient`) keep the flat ink base.
            if let stops = tokens.material.bodyGradient {
                shape.fill(
                    LinearGradient(
                        stops: stops.map { Gradient.Stop(color: $0.resolvedColor, location: $0.location) },
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .overlay(
            shape.strokeBorder(.white.opacity(reduceTransparency ? 0.12 : 0.08), lineWidth: 1)
        )
    }
}

/// The board's `.meters` wrap rule as pure arithmetic (PI-I-001/I1,
/// `01-poured-island.html:469-470`), so the composition is pinnable without a
/// render: `.meter{flex:1 1 200px}` inside a `gap:22px` wrapping flex row.
///
/// A row fits `n` meters when `n * minItemWidth + (n - 1) * spacing <= width`;
/// every row then shares the width equally (flex-grow), which is why the board's
/// 484pt content box renders **2 + 1** rather than three squeezed meters.
enum PouredMeterFlow {
    /// `.meter{flex-basis:200px}`.
    static let minItemWidth: CGFloat = 200
    /// `.meters{gap:22px}` — the board applies the same gap on both axes.
    static let spacing: CGFloat = 22

    /// How many meters share one row at `width` (never below 1 — a card
    /// narrower than one meter still renders it, clipped by nothing).
    static func columns(
        forWidth width: CGFloat,
        minItemWidth: CGFloat = minItemWidth,
        spacing: CGFloat = spacing
    ) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        let fitted = Int(((width + spacing) / (minItemWidth + spacing)).rounded(.down))
        return max(1, fitted)
    }

    /// The per-row meter counts for `count` meters at `width` — `[2, 1]` for the
    /// board's three-meter card.
    static func rowCounts(
        count: Int,
        width: CGFloat,
        minItemWidth: CGFloat = minItemWidth,
        spacing: CGFloat = spacing
    ) -> [Int] {
        guard count > 0 else { return [] }
        let perRow = columns(forWidth: width, minItemWidth: minItemWidth, spacing: spacing)
        var rows: [Int] = []
        var remaining = count
        while remaining > 0 {
            let take = min(perRow, remaining)
            rows.append(take)
            remaining -= take
        }
        return rows
    }

    /// The width one meter gets on a row of `columns` (flex-grow: the row's
    /// leftover space is shared equally).
    static func itemWidth(
        forWidth width: CGFloat,
        columns: Int,
        spacing: CGFloat = spacing
    ) -> CGFloat {
        let columns = max(1, columns)
        let gaps = spacing * CGFloat(columns - 1)
        return max(0, (width - gaps) / CGFloat(columns))
    }
}

/// The `Layout` that draws `PouredMeterFlow`: equal-width columns, wrapping at
/// the 200pt flex basis, `22pt` between meters on both axes.
struct PouredMeterFlowLayout: Layout {
    var minItemWidth: CGFloat = PouredMeterFlow.minItemWidth
    var spacing: CGFloat = PouredMeterFlow.spacing

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minItemWidth
        let rows = resolvedRows(width: width, subviews: subviews)
        let itemWidth = PouredMeterFlow.itemWidth(
            forWidth: width,
            columns: PouredMeterFlow.columns(forWidth: width, minItemWidth: minItemWidth, spacing: spacing),
            spacing: spacing
        )
        let height = rowHeight(itemWidth: itemWidth, subviews: subviews) * CGFloat(rows.count)
            + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        let columns = PouredMeterFlow.columns(forWidth: width, minItemWidth: minItemWidth, spacing: spacing)
        let itemWidth = PouredMeterFlow.itemWidth(forWidth: width, columns: columns, spacing: spacing)
        var y = bounds.minY
        var index = 0
        for row in resolvedRows(width: width, subviews: subviews) {
            let indices = Array(index..<(index + row))
            for (column, subviewIndex) in indices.enumerated() {
                let x = bounds.minX + CGFloat(column) * (itemWidth + spacing)
                subviews[subviewIndex].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: itemWidth, height: nil)
                )
            }
            y += rowHeight(itemWidth: itemWidth, subviews: subviews) + spacing
            index += row
        }
    }

    private func resolvedRows(width: CGFloat, subviews: Subviews) -> [Int] {
        PouredMeterFlow.rowCounts(
            count: subviews.count,
            width: width,
            minItemWidth: minItemWidth,
            spacing: spacing
        )
    }

    /// Every row is as tall as the tallest meter, so the card's rows line up
    /// even when one window has no countdown line.
    private func rowHeight(itemWidth: CGFloat, subviews: Subviews) -> CGFloat {
        subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height
        }
        .max() ?? 0
    }
}

/// One provider window's §I meter: a 52pt conic dial beside the label, oversized
/// percentage, inline reset countdown, and the word+shape threshold pill.
struct PouredUsageMeter: View {
    let providerTitle: String
    let window: UsageWindowPresentation
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
        HStack(spacing: 12) {
            PouredUsageRing(
                fraction: window.usedPercentage / 100,
                color: color,
                diameter: PouredUsageMetrics.meterDial,
                lineWidth: PouredUsageMetrics.meterDialLineWidth,
                trackOpacity: PouredUsageMetrics.meterDialTrackOpacity
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("\(providerTitle) · \(window.label)")
                    .font(PouredType.Role.usageMeterLabel.font)
                    .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

                Text("\(window.roundedUsedPercentage)%")
                    .font(PouredType.Role.displayNumeral.font)
                    .tracking(PouredType.Role.displayNumeral.spec.trackingPoints)
                    .foregroundStyle(color)

                if let remaining = window.remainingLabel(asOf: now) {
                    Text(lang.t("island.poured.usage.resetsIn", remaining))
                        .font(PouredType.Role.age.font)
                        .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                }

                thresholdPill
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The band stated as **shape + word** so state survives colour-blindness /
    /// greyscale (`SPEC` §4I "never color alone").
    private var thresholdPill: some View {
        HStack(spacing: 5) {
            Text(threshold.shapeMarker)
                .font(.system(size: 9, weight: .bold))
            Text(lang.t(threshold.localizationKey))
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 1)
        // Per-band fill (`.thlabel.fine/.warn` `.14`, `.crit` `.16` —
        // `01-poured-island.html:481-483`), not one uniform alpha.
        .background(color.opacity(threshold.pillFillOpacity), in: Capsule())
        .padding(.top, 2)
    }

    private var accessibilityLabel: String {
        var parts = [
            "\(providerTitle) \(window.label)",
            "\(window.roundedUsedPercentage)%",
            lang.t(threshold.localizationKey),
        ]
        if let remaining = window.remainingLabel(asOf: now) {
            parts.append(lang.t("island.poured.usage.resetsIn", remaining))
        }
        return parts.joined(separator: ", ")
    }
}
