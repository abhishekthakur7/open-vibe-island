import SwiftUI
import OpenIslandCore

/// Flight Deck's usage readout (AB-312 → AB-338): each provider window is a
/// *continuous tape gauge* — a recessed instrument track whose fill sweeps
/// 0–100% with fixed threshold ticks at 70% and 90%, headed by a sans gauge
/// legend + a mono tabular value and trailed by an inline `RESET` countdown, in
/// the avionics-console idiom. AB-338 replaced the shipped 12-tick segmented lane
/// with this tape geometry and surfaced `resetsAt` inline (it was `.help()`-only).
///
/// The colour bands are the exact cut-offs the rest of the app ships
/// (`IslandUsageSummary`: `>= 90` / `70..<90` / else), but the colours
/// themselves are FD's own status tokens (overlay remediation F15 —
/// `statusWaitingForApproval` / `statusWaitingForAnswer` / `statusRunning`,
/// `SPEC-flight-deck.md:56-58`), not the retired raw SwiftUI
/// `.red`/`.orange`/`.green`. The placard maps onto the same bands
/// (CRIT / CAUT / NOM) so a red gauge always carries the CRIT semantics and
/// the theme can't drift from the shared meaning.
/// The fill sweeps up on appear and the CRIT band's fill blinks at the 1.2s
/// caution cadence (`FlightDeckMotion.Attention.cautionPeriod`); both are gated
/// off under Reduce Motion, where the gauge paints its final fill statically.
/// Labels read their opacities through the token contrast floor so they survive
/// Increase Contrast, and — being a flat panel — there is no transparency to
/// reduce.
struct FlightDeckUsageSummary: View {
    let providers: [UsageProviderPresentation]
    let lang: LanguageManager
    var now: Date = .now

    /// `true` for the notch-lane call site (overlay remediation Phase 5,
    /// Defect 1): every window assigned to this lane renders inside **one**
    /// bezeled box, mirroring the mockup's one `.lane` == one visual unit
    /// (`02-flight-deck.html:281-284`, which has no per-provider box at all —
    /// only the lane's own padding). Before this, `laneGroups`'s per-window
    /// `flatten` meant a lane holding 2 windows rendered as **two** separately
    /// boxed chips (2×168pt + 12pt gap = 348pt) — *wider* than the single
    /// 2-window chip (327pt) F8 set out to fix. `false` (default) keeps the
    /// legacy one-chip-per-provider row for the non-notch/top-bar header,
    /// where there's no lane to do that visual separation and "Claude" /
    /// "Codex" still read as distinct instrument groups.
    var groupsAllProvidersIntoOneChip: Bool = false

    /// The residual overflow fix (overlay remediation Phase 5, column-stack
    /// correction): the max number of flattened windows this lane's chip may
    /// render as full gauges before it must fall back to a compact "+N"
    /// affordance for the rest. Only meaningful when
    /// `groupsAllProvidersIntoOneChip` is `true` — the notch-lane call site
    /// passes the same per-item **measurement**
    /// (`FlightDeckHeaderControls.laneCapacity(for:)`) that already bounds
    /// `laneGroups`'s split, so a lane can never be handed more windows than
    /// it was capacity-planned for without this chip catching it. Defaults to
    /// `.max` (no truncation) for the top-bar / legacy call site, which has
    /// no lane-width ceiling to protect.
    var maxVisibleWindows: Int = .max

    /// Whether the *inline* overflow "+N" badge may draw when this lane's
    /// windows exceed `maxVisibleWindows` (Phase 5, "no zero gauges"
    /// correction). The notch-lane call site
    /// (`FlightDeckHeaderControls.usageLaneView`) computes this from real
    /// lane-width geometry (`IslandHeaderLaneLayout.overflowBadgeFits`) —
    /// `min(assignedCount, capacity)` gauges always render regardless of this
    /// flag; it only ever *adds* the inline badge alongside them, never
    /// displaces a gauge to make room. Defaults to `true` for the top-bar /
    /// legacy call site, which passes `maxVisibleWindows: .max` and therefore
    /// never has overflow to badge in the first place.
    ///
    /// Overlay remediation E3: `false` no longer means "draw nothing." A lane
    /// can have real overflow (`overflowCount > 0`) with no room left for the
    /// inline badge's 37pt footprint — FD's real notch-hardware capacity (one
    /// gauge per lane, the canonical 3-window fixture) leaves only ~4-5pt of
    /// genuine slack. `FlightDeckUsageProviderChip.OverflowAffordance` falls
    /// back to a corner-hanging indicator in exactly that case, since an
    /// `.overlay` costs the lane no width at all — the one thing the inline
    /// badge could never do.
    var allowsOverflowBadge: Bool = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            summaryRow(usesShortTitles: false)
            summaryRow(usesShortTitles: true)
        }
    }

    @ViewBuilder
    private func summaryRow(usesShortTitles: Bool) -> some View {
        let gaugeWidth = usesShortTitles
            ? FlightDeckUsageWindowGauge.compactGaugeWidth
            : FlightDeckUsageWindowGauge.gaugeWidth

        if groupsAllProvidersIntoOneChip {
            FlightDeckUsageProviderChip(
                providers: providers,
                usesShortTitle: usesShortTitles,
                lang: lang,
                gaugeWidth: gaugeWidth,
                maxVisibleWindows: maxVisibleWindows,
                allowsOverflowBadge: allowsOverflowBadge,
                now: now
            )
            .fixedSize(horizontal: true, vertical: false)
        } else {
            HStack(alignment: .top, spacing: 12) {
                ForEach(providers) { provider in
                    FlightDeckUsageProviderChip(
                        providers: [provider],
                        usesShortTitle: usesShortTitles,
                        lang: lang,
                        gaugeWidth: gaugeWidth,
                        now: now
                    )
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// A flat avionics chip: a row of tape gauges — one per rate-limit window,
/// laid out side by side (overlay remediation F8; each mockup `.gauge` box is
/// one window, `02-flight-deck.html:888-909`) — boxed by a single hairline
/// bezel rule. Each gauge folds its provider's title into its legend
/// (`Claude · 5H`) per the mockup, so the chip itself carries no separate
/// title line.
///
/// Takes `providers` **plural** (Phase 5, Defect 1): the top-bar / legacy
/// call site passes a single-element array per provider (one box each, same
/// as before F8); the notch-lane call site
/// (`FlightDeckUsageSummary.groupsAllProvidersIntoOneChip`) passes every
/// window already assigned to that lane — possibly from more than one source
/// provider — so they share **one** box instead of one box per flattened
/// array element.
struct FlightDeckUsageProviderChip: View {
    /// The chip's own fixed chrome — shared with `FlightDeckHeaderControls`'s
    /// capacity computation (Defect 1) so the two can't drift apart.
    static let horizontalPadding: CGFloat = 9
    static let interGaugeSpacing: CGFloat = 9
    /// The overflow "+N" affordance's own approximate footprint (padding +
    /// two mono digits) — a principled estimate, not a measured render, same
    /// spirit as `FlightDeckUsageWindowGauge.compactGaugeWidth`. Deliberately
    /// much narrower than `compactGaugeWidth` (96pt): that gap is what
    /// `IslandHeaderLaneLayout.overflowBadgeFits` checks against the lane's
    /// own leftover width — the badge only ever draws *alongside* the full
    /// set of visible gauges, in whatever sliver of width `capacity`'s floor
    /// division didn't use, never by displacing one of them.
    static let overflowBadgeWidth: CGFloat = 28

    let providers: [UsageProviderPresentation]
    let usesShortTitle: Bool
    let lang: LanguageManager
    /// The per-gauge drawing width — defaults to the full
    /// `FlightDeckUsageWindowGauge.gaugeWidth`; the notch-lane call site
    /// passes the compact tier when `usesShortTitle` is true, so the
    /// `ViewThatFits` fallback is a real narrower render (Defect 1: the
    /// previous `usesShortTitle` only shortened legend text drawn in the same
    /// fixed 150pt frame — "provably cosmetic-only").
    var gaugeWidth: CGFloat = FlightDeckUsageWindowGauge.gaugeWidth

    /// See `FlightDeckUsageSummary.maxVisibleWindows`. Defaults to `.max` —
    /// no truncation — for the top-bar / legacy call site.
    var maxVisibleWindows: Int = .max

    /// See `FlightDeckUsageSummary.allowsOverflowBadge`. Defaults to `true`.
    var allowsOverflowBadge: Bool = true
    var now: Date = .now

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var windowEntries: [(provider: UsageProviderPresentation, window: UsageWindowPresentation)] {
        providers.flatMap { provider in provider.windows.map { (provider, $0) } }
    }

    /// The windows this chip actually draws as full gauges —
    /// `windowEntries` truncated to
    /// `IslandHeaderLaneLayout.visibleItemCount(assignedCount:capacity:)`,
    /// which is `min(windowEntries.count, maxVisibleWindows)` (Phase 5, "no
    /// zero gauges" correction) — **never fewer than every window this chip
    /// can actually fit**, unlike the retired reserved-slot behaviour that
    /// always sacrificed one gauge's slot for the overflow badge whenever
    /// there was any overflow at all, even at `maxVisibleWindows == 1` (where
    /// that left zero real gauges on screen).
    private var visibleWindowEntries: [(provider: UsageProviderPresentation, window: UsageWindowPresentation)] {
        let visibleCount = IslandHeaderLaneLayout.visibleItemCount(
            assignedCount: windowEntries.count,
            capacity: maxVisibleWindows
        )
        return Array(windowEntries.prefix(visibleCount))
    }

    /// How many windows aren't drawn as a full gauge. `0` means no
    /// truncation happened. Whether the "+N" badge actually renders for a
    /// non-zero count is `allowsOverflowBadge` — the caller's own width-fit
    /// decision (`IslandHeaderLaneLayout.overflowBadgeFits`), since adding
    /// the badge *in addition to* a full `maxVisibleWindows` set of gauges
    /// could overflow the lane (there is still no `.clipped()` in this
    /// chain) unless the caller already proved there's leftover room for it.
    private var overflowCount: Int {
        windowEntries.count - visibleWindowEntries.count
    }

    /// Which overflow affordance (if any) this chip must render for
    /// `overflowCount` hidden windows.
    ///
    /// Overlay remediation E3, confirmed in live pixel captures: the
    /// canonical 3-window fixture (Claude 5h 34%, Claude 7d 78%, Codex 7d
    /// 92%) rendered exactly 2 gauges at real notch-hardware geometry — the
    /// Claude 7d window was silently dropped with **no badge, no ellipsis, no
    /// dimmed placeholder, nothing**. Root cause: `allowsOverflowBadge`
    /// (`IslandHeaderLaneLayout.overflowBadgeFits`) correctly refused to draw
    /// the inline "+N" badge — it needs 37pt (9pt spacing + 28pt badge) and a
    /// capacity-planned lane only ever has ~4-5pt of genuine slack left over
    /// — but declining the badge left the hidden window with no visual trace
    /// at all. `.corner` is the fix: exactly one case applies whenever
    /// `overflowCount > 0`, so "some window is hidden" and "some affordance
    /// renders" can never come apart again.
    enum OverflowAffordance: Equatable {
        /// No windows are hidden — nothing to signal.
        case none
        /// The lane had room for the inline "+N" badge alongside the visible
        /// gauge(s) (`allowsOverflowBadge == true`).
        case inline(count: Int)
        /// The lane did *not* have room for the inline badge. Renders as a
        /// corner-hanging indicator instead — an `.overlay`, not an `HStack`
        /// child, so it costs the lane no width and is always available
        /// regardless of how tight the fit is.
        case corner(count: Int)

        static func decide(overflowCount: Int, allowsOverflowBadge: Bool) -> OverflowAffordance {
            guard overflowCount > 0 else { return .none }
            return allowsOverflowBadge ? .inline(count: overflowCount) : .corner(count: overflowCount)
        }
    }

    private var overflowAffordance: OverflowAffordance {
        OverflowAffordance.decide(overflowCount: overflowCount, allowsOverflowBadge: allowsOverflowBadge)
    }

    var body: some View {
        // F8: was `VStack(alignment: .leading, spacing: 9)` — height-unconstrained,
        // so a 2-window chip (~75-83pt) overflowed the fixed, non-clipping
        // `closedNotchHeight` header band and bled into the control-button row
        // (`IslandPanelView.openedSurfaceContent`). Both sibling themes already
        // lay windows out horizontally (`HaloUsageProviderGroup`,
        // `PouredUsageProviderGroup`); FD's chip was the only VStack of the
        // three. Growth now moves from height to width — bounded by F7's
        // capacity-aware lane split plus the compact gauge tier above.
        HStack(alignment: .top, spacing: Self.interGaugeSpacing) {
            ForEach(visibleWindowEntries, id: \.window.id) { entry in
                FlightDeckUsageWindowGauge(label: legend(for: entry), window: entry.window, width: gaugeWidth)
            }
            if case .inline(let count) = overflowAffordance {
                overflowBadge(count: count)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tokens.colors.paper.opacity(increasesContrast ? 0.06 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(
                            tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)),
                            lineWidth: 1
                        )
                )
        )
        // E3 fix: the corner indicator draws as an `.overlay`, which never
        // participates in the `HStack`'s width math above — it straddles the
        // bezel's own top edge, centered horizontally over the head row's
        // `Spacer` (the one place already guaranteed empty of legend/value
        // text), so it never competes for lane width and never covers either
        // gauge's legend or numeric readout.
        .overlay(alignment: .top) {
            if case .corner(let count) = overflowAffordance {
                hiddenWindowIndicator(count: count)
                    .offset(y: -7)
            }
        }
        .help(summaryText)
        // One VoiceOver stop per chip — the same per-window summary the app
        // surfaces through `.help()`, matching Classic / Poured
        // (AB-244).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryText)
    }

    /// The reserved-slot "+N" affordance for windows this chip's lane doesn't
    /// have room to draw as full gauges (the F7/F8 residual: FD's real
    /// capacity is ~1 gauge per lane, and the canonical 3-window fixture
    /// needs 2 in one of them). Deliberately terse mono — matching the
    /// EICAS-placard idiom of `FlightDeckUsagePlacard` — and narrower than a
    /// single gauge slot, which is what keeps `visibleWindowEntries`'s
    /// reserved-slot arithmetic sound. Hidden from accessibility: the
    /// count is redundant with the chip-level `.help()`/`accessibilityLabel`,
    /// which already names every window (visible or not) via the unfiltered
    /// `windowEntries` — never `visibleWindowEntries` — so no window's data
    /// is actually lost, only its dedicated on-screen gauge.
    ///
    /// Only rendered when `OverflowAffordance` resolves to `.inline` — i.e.
    /// `allowsOverflowBadge` already proved this exact text fits alongside
    /// the visible gauge(s) without exceeding the lane. See
    /// `hiddenWindowIndicator(count:)` for the fallback when it doesn't.
    private func overflowBadge(count: Int) -> some View {
        Text("+\(count)")
            .font(FlightDeckTypography.microLabel)
            .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.66, increaseContrast: increasesContrast)))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(minWidth: Self.overflowBadgeWidth, minHeight: 18, maxHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(
                        tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)),
                        lineWidth: 1
                    )
            )
            .accessibilityHidden(true)
    }

    /// The E3 fix: `overflowBadge(count:)`'s corner-hanging counterpart, drawn
    /// for exactly the case that function's caller (`allowsOverflowBadge ==
    /// false`) ruled out — a lane too narrow to spare the inline badge's 37pt.
    /// Costs zero lane width (an `.overlay`, not an `HStack` child), so it's
    /// always available regardless of how tight the fit is — the previous
    /// code path's only option at that point was to draw nothing at all.
    /// Same bordered mono-digit language as `overflowBadge(count:)` (no new
    /// colour, no gradient — Flight Deck's flat/opaque body is correct by
    /// design), just smaller, since it only ever needs to survive alongside a
    /// single visible gauge's own chrome. Hidden from accessibility for the
    /// same reason as `overflowBadge(count:)`: the chip-level `.help()` /
    /// `accessibilityLabel` already names every window via the unfiltered
    /// `windowEntries`.
    private func hiddenWindowIndicator(count: Int) -> some View {
        Text("+\(count)")
            .font(FlightDeckTypography.microLabel)
            .foregroundStyle(tokens.colors.paper)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 14, maxHeight: 14)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tokens.colors.paper.opacity(increasesContrast ? 0.32 : 0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(
                                tokens.colors.paper.opacity(
                                    min(1, tokens.colors.hairline(increaseContrast: increasesContrast) + 0.3)
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .accessibilityHidden(true)
    }

    /// The gauge legend — the owning provider's title (full or short) joined
    /// to the window's window-label, uppercased Latin per the EICAS placard
    /// idiom (`Claude · 5H`). The title itself is left in its native casing.
    private func legend(for entry: (provider: UsageProviderPresentation, window: UsageWindowPresentation)) -> String {
        let title = usesShortTitle ? entry.provider.shortTitle : entry.provider.title
        return "\(title) · \(entry.window.label.uppercased())"
    }

    private var summaryText: String {
        UsageSummaryAccessibilityFormatter.summary(
            for: providers,
            usesShortTitles: usesShortTitle,
            asOf: now,
            lang: lang
        )
    }
}

/// A single window's continuous tape gauge: its sans legend + mono tabular
/// percentage on the head row, the recessed tape track (fill + 70/90 threshold
/// ticks) beneath, and — when the window carries a reset time — an inline
/// `RESET <countdown>` readout at the foot. The value colours by the shared
/// usage cut-offs; a critical (≥90) window's fill crosses the 90 tick and blinks.
struct FlightDeckUsageWindowGauge: View {
    /// The gauge legend (`Claude · 5H`), built by the enclosing chip so the tape
    /// gauge stays agnostic of provider identity.
    let label: String
    let window: UsageWindowPresentation

    /// The gauge's drawing width, so the summary keeps an intrinsic size under
    /// `fixedSize(horizontal:)` (a bare `GeometryReader` would collapse to
    /// zero). Defaults to `gaugeWidth`; the enclosing chip passes
    /// `compactGaugeWidth` for the `ViewThatFits` short-title fallback
    /// (Phase 5, Defect 1).
    var width: CGFloat = Self.gaugeWidth

    /// The full-size drawing width — wide enough for the longest legend +
    /// value on the head row and a `RESET 4D 06H` foot row.
    static let gaugeWidth: CGFloat = 150

    /// The compact tier (Phase 5, Defect 1): a real second width the
    /// `ViewThatFits` short-title fallback renders at, not merely a shorter
    /// legend string drawn in the same 150pt frame (the previous
    /// `usesShortTitle` was "provably cosmetic-only" — it changed no widths).
    /// Sized for the shortest legend ("Cl · 5H" / "Cx · 7D",
    /// `FlightDeckTypography.gaugeLabelSize` 10pt semibold sans) plus a
    /// 3-digit value (`countSize` 11pt bold mono) with headroom for the
    /// `Spacer(minLength: 4)` between them — a principled estimate, not a
    /// measured render (this ticket derives numbers, it doesn't capture the
    /// app); visual confirmation belongs to a later capture-owning pass.
    static let compactGaugeWidth: CGFloat = 96

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var color: Color { Self.usageColor(for: window.usedPercentage, tokens: tokens.colors) }
    private var placard: FlightDeckUsagePlacard { Self.placard(for: window.usedPercentage) }
    private var isCritical: Bool { window.usedPercentage >= 90 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headRow
            FlightDeckTapeGauge(
                fraction: window.usedPercentage / 100,
                color: color,
                isCritical: isCritical
            )
            if let resets = window.remainingLabel(asOf: Date()) {
                resetRow(resets)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var headRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(FlightDeckTypography.gaugeLabel)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.78, increaseContrast: increasesContrast)))
                .lineLimit(1)

            Spacer(minLength: 4)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(window.roundedUsedPercentage)")
                    .font(FlightDeckTypography.gaugeValue)
                Text("%")
                    // F18: was `countSize - 2` (9pt, below the theme's own
                    // 10pt floor and invisible to the floor test — it wasn't a
                    // named role). Now the dedicated `gaugeUnit` role, ≥10pt
                    // and pinned by `everyReadableTypographyRoleHoldsTheTenPointFloor`.
                    .font(FlightDeckTypography.gaugeUnit)
                    .baselineOffset(0)
            }
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// The inline `RESET <countdown>` readout. `RESET` is a Latin placard (EICAS
    /// legend rule — kept Latin in every locale, like CRIT / CAUT / NOM); the
    /// countdown is the shared AB-324 formatting uppercased to mono tabular
    /// (`RESET 2H 10M`). The tooltip retains the full per-window summary.
    private func resetRow(_ countdown: String) -> some View {
        HStack(spacing: 4) {
            Text("RESET")
                .font(FlightDeckTypography.microLabel)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.5, increaseContrast: increasesContrast)))
            Spacer(minLength: 4)
            Text(countdown.uppercased())
                .font(FlightDeckTypography.resetCountdown)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.58, increaseContrast: increasesContrast)))
        }
        .lineLimit(1)
        // The reset readout is redundant with the provider chip's VoiceOver
        // summary (built from the same `remainingLabel`), so it stays out of the
        // accessibility tree to avoid double-reading.
        .accessibilityHidden(true)
    }

    /// The exact cut-offs the app ships (`IslandUsageSummary`): `>= 90` /
    /// `70..<90` / else — the theme must not drift. Overlay remediation F15:
    /// resolves onto FD's own status tokens (`SPEC-flight-deck.md:56-58`) —
    /// `statusWaitingForApproval` (#E04A42) / `statusWaitingForAnswer`
    /// (#E6AA42) / `statusRunning` (#4AC99E) — mirroring
    /// `PouredUsageThreshold.color(_:)`. Replaces the retired raw
    /// `.red`/`.orange`/`.green` (sampled caution fill was #E39244 vs the FD
    /// token #E6AA42, ΔG = -24). Both call sites (this gauge's head-row value
    /// and `FlightDeckUsageMiniTape.tint` on the closed pill) thread the
    /// already-present `@Environment(\.islandTokens)`.
    static func usageColor(for percentage: Double, tokens: IslandColorTokens) -> Color {
        switch percentage {
        case 90...:
            tokens.statusWaitingForApproval
        case 70..<90:
            tokens.statusWaitingForAnswer
        default:
            tokens.statusRunning
        }
    }

    /// The status placard over the same bands as `usageColor`, so a red gauge
    /// always reads CRIT and a green gauge NOM. Retained for parity tests and the
    /// shared band semantics; the tape gauge conveys the band through fill + value
    /// colour rather than a rendered glyph (per the mockup).
    static func placard(for percentage: Double) -> FlightDeckUsagePlacard {
        switch percentage {
        case 90...:
            .crit
        case 70..<90:
            .caut
        default:
            .nom
        }
    }
}

/// The CRIT / CAUT / NOM status placard banded onto a usage percentage.
/// `rawValue` is the rendered mono glyph — deliberately terse and script-neutral
/// (avionics placards, not prose, so they stay Latin in every locale, the same
/// way EICAS legends do).
enum FlightDeckUsagePlacard: String {
    case crit = "CRIT"
    case caut = "CAUT"
    case nom = "NOM"
}

/// The continuous tape gauge itself (AB-338): a recessed instrument track sunk
/// into the panel (`FlightDeckSurfaces.well`) whose fill bar sweeps the band
/// colour from 0 to the current fraction, crossed by two fixed threshold ticks —
/// a hairline tier-2 rule at 70% and a red `crit` rule at 90% — drawn at fixed x
/// regardless of the fill. The fill sweeps up on appear; a critical gauge's fill
/// blinks at the 1.2s caution cadence. Both are disabled under Reduce Motion,
/// where the fill paints its final width steadily, fully lit. The blink is a
/// `@State` peak/trough toggle (the `FlightDeckAnnunciatorLamp` precedent), so it
/// never advances under a disabled-animation transaction — a snapshot captures
/// the steady lit frame.
struct FlightDeckTapeGauge: View {
    let fraction: Double
    let color: Color
    let isCritical: Bool

    /// The fixed threshold tick positions (fraction of the track width), drawn
    /// regardless of the fill: the 70% hairline caution tick and the 90% red
    /// critical tick. Pinned by `FlightDeckThemeTests` (replacing the retired
    /// `tickGaugeIsTwelveSegments` segment-count pin).
    static let hairlineTickPosition: Double = 0.70
    static let criticalTickPosition: Double = 0.90
    static let thresholdTicks: [Double] = [hairlineTickPosition, criticalTickPosition]

    var trackHeight: CGFloat = 8
    /// How far each threshold tick overhangs the track top and bottom (mockup
    /// `.tick { top:-2px; bottom:-2px }`).
    private static let tickOverhang: CGFloat = 2

    @State private var blinkPhase = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens

    private var clampedFraction: Double { min(1, max(0, fraction)) }

    /// The fill's live opacity: fully lit, unless a critical gauge is mid-blink
    /// (and motion is allowed), where it dips to the caution trough. Reduce Motion
    /// and the non-critical bands hold it fully lit.
    private var fillOpacity: Double {
        guard isCritical, !reduceMotion, blinkPhase else { return FlightDeckMotion.Attention.opacityMax }
        return FlightDeckMotion.Attention.opacityMin
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                // Recessed well track (sunk into the panel) + faint bezel rule.
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(FlightDeckSurfaces.well)
                    .overlay(
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .strokeBorder(
                                FlightDeckSurfaces.hairline(tier: 1, increaseContrast: increasesContrast),
                                lineWidth: 1
                            )
                    )
                    .frame(height: trackHeight)

                // Continuous fill 0 → fraction, in the band colour.
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(color)
                    .frame(width: max(0, width * clampedFraction), height: trackHeight)
                    .opacity(fillOpacity)

                // Fixed threshold ticks — at 70% (hairline tier-2) and 90% (crit
                // red), at fixed x regardless of fill.
                tick(
                    at: Self.hairlineTickPosition,
                    trackWidth: width,
                    color: FlightDeckSurfaces.hairline(tier: 2, increaseContrast: increasesContrast)
                )
                tick(
                    at: Self.criticalTickPosition,
                    trackWidth: width,
                    color: .red.opacity(0.65)
                )
            }
        }
        .frame(height: trackHeight)
        .onAppear { startBlinkIfNeeded() }
        .onChange(of: isCritical) { _, _ in startBlinkIfNeeded() }
        .accessibilityHidden(true)
    }

    /// A 1pt threshold rule positioned at `position` of the track width,
    /// overhanging the track top and bottom by `tickOverhang`.
    private func tick(at position: Double, trackWidth: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 1, height: trackHeight + Self.tickOverhang * 2)
            .offset(x: trackWidth * position - 0.5)
    }

    /// Starts (or clears) the critical blink — a peak/trough toggle on a
    /// half-cadence ease-in-out that autoreverses forever, so `fillOpacity`
    /// bounces between the caution peak and trough over one `cautionPeriod`. A
    /// non-critical gauge or Reduce Motion pins it lit and never acquires the
    /// animation.
    private func startBlinkIfNeeded() {
        guard isCritical, !reduceMotion else {
            blinkPhase = false
            return
        }
        blinkPhase = false
        withAnimation(
            .easeInOut(duration: FlightDeckMotion.Attention.cautionPeriod / 2).repeatForever(autoreverses: true)
        ) {
            blinkPhase = true
        }
    }
}
