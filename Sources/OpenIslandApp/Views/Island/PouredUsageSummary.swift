import AppKit
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
    /// The §I **card** dial's unused-track alpha — `rgba(242,245,251,.1)`
    /// (`01-poured-island.html:1456`). Fainter than the §C header ring's `.12`
    /// (`:229`), which R4-8 pinned and which must not move with it.
    static let meterDialTrackOpacity: Double = 0.1
}

/// The §C header meter lane's **hard trailing bound and its overflow rule**
/// (C4-2 · PI-X-001/I1-I2, review round 1).
///
/// **The defect.** `PouredHeaderControls` hands each usage lane a fixed
/// `.frame(width:)` that never clipped, and `PouredUsageWindowRing`'s label
/// block is `.fixedSize(horizontal: true)` — so a lane holding more meters than
/// it has room for simply drew past its own frame. At the shipped 620pt notch
/// profile with the three-window fixture that put `CODEX 7D · PRO` /
/// `resets 18h 40m` **under** the mute / settings / close cluster. The board
/// never lets a meter touch the controls (`01-poured-island.html:781-796`).
///
/// **The rule.** Severity-first, deterministic, and independent of render
/// order:
/// 1. If every meter fits (`Σ widths + spacing·(n−1) ≤ availableWidth`), all of
///    them render, in board order.
/// 2. Otherwise meters are dropped one at a time from the **bottom of a
///    severity ranking** — `critical` outranks `warn` outranks `fine`, ties
///    broken by the higher percentage, then by board order — until the rest
///    fit. The worst band is therefore the last thing to go: a header that can
///    only afford one meter shows the one that matters.
/// 3. The lane never renders empty while it has a meter and a positive width:
///    the top-ranked meter always survives, clipped by the lane bound if even
///    it doesn't fit. A truncated worst-band number beats no number.
/// 4. Survivors render in **board order**, not ranked order — elision must not
///    reshuffle the lane.
///
/// R15 is untouched: this decides *what a lane shows*, never which wing a
/// window belongs to (`IslandHeaderLaneLayout.laneGroups` still owns that, and
/// both meters landing in the left wing on notch hardware stays accepted).
///
/// Visual elision only: an elided meter stays in the accessibility tree (see
/// `PouredUsageSummary.elidedMeterAccessibilityMirror`), so VoiceOver still
/// reads every window the app knows about.
enum PouredHeaderMeterLane {
    /// The gap between two meters in one lane (`PouredUsageSummary`'s `HStack`).
    static let meterSpacing: CGFloat = 12
    /// The ring → label gap inside one meter (`PouredUsageWindowRing`'s `HStack`).
    static let ringLabelSpacing: CGFloat = 8

    /// One meter's measured footprint plus the band that decides its priority.
    /// `width` is measured by the view (real font metrics) and handed in, so the
    /// rule itself stays pure arithmetic.
    struct Candidate: Equatable, Sendable {
        let id: String
        let width: CGFloat
        /// The candidate's worst window percentage — the band it is ranked by.
        let usedPercentage: Double

        init(id: String, width: CGFloat, usedPercentage: Double) {
            self.id = id
            self.width = width
            self.usedPercentage = usedPercentage
        }
    }

    /// The ids that may render in a lane of `availableWidth`, in input order.
    static func fitted(_ candidates: [Candidate], availableWidth: CGFloat) -> [String] {
        guard !candidates.isEmpty, availableWidth > 0 else { return [] }

        let ranked = candidates.indices.sorted { lhs, rhs in
            let lhsRank = severityRank(candidates[lhs].usedPercentage)
            let rhsRank = severityRank(candidates[rhs].usedPercentage)
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            if candidates[lhs].usedPercentage != candidates[rhs].usedPercentage {
                return candidates[lhs].usedPercentage > candidates[rhs].usedPercentage
            }
            return lhs < rhs
        }

        var keptCount = candidates.count
        while keptCount > 1, !fits(ranked.prefix(keptCount).map { candidates[$0] }, availableWidth: availableWidth) {
            keptCount -= 1
        }

        let kept = Set(ranked.prefix(keptCount))
        return candidates.indices.filter { kept.contains($0) }.map { candidates[$0].id }
    }

    /// Whether `candidates` laid out in one row fit `availableWidth`.
    static func fits(_ candidates: [Candidate], availableWidth: CGFloat) -> Bool {
        guard !candidates.isEmpty else { return true }
        let content = candidates.reduce(0) { $0 + $1.width }
        let gaps = meterSpacing * CGFloat(candidates.count - 1)
        return content + gaps <= availableWidth
    }

    /// `critical` 2 › `warn` 1 › `fine` 0 — the same cut-offs as
    /// `PouredUsageThreshold`, which is the app-wide usage rule.
    static func severityRank(_ usedPercentage: Double) -> Int {
        switch PouredUsageThreshold.threshold(for: usedPercentage) {
        case .critical: 2
        case .warn: 1
        case .fine: 0
        }
    }
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

    /// The §I threshold pill's fill alpha over the band colour. The board tints
    /// each band separately — `.thlabel.fine` and `.warn` at `.14`, `.crit` at
    /// `.16` (`01-poured-island.html:481-483`) — where the card painted one
    /// uniform `0.15`, so the critical pill read a shade too faint and the two
    /// calm bands a shade too loud.
    var pillFillOpacity: Double {
        switch self {
        case .fine, .warn:
            0.14
        case .critical:
            0.16
        }
    }
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
/// settle with a short sweep, gated off under Reduce Motion — the critical
/// band's breathing glow is gone (see `PouredUsageRing`). Ring labels read their
/// opacities through the token contrast floor so they survive Increase Contrast.
struct PouredUsageSummary: View {
    let providers: [UsageProviderPresentation]
    let lang: LanguageManager
    /// Fitted per profile by `PouredHeaderControls` (see `PouredUsageMetrics`).
    var ringDiameter: CGFloat = PouredUsageMetrics.headerRingTopBar
    /// Injected so the inline reset countdowns are deterministic in previews /
    /// tests; defaults to the wall clock in the live overlay.
    var now: Date = .now
    /// C4-2: the lane's hard bound. `nil` (previews, any caller that is not a
    /// header lane) renders every meter exactly as before; a header lane passes
    /// its real frame width and gets `PouredHeaderMeterLane`'s severity-first
    /// elision instead of an overrun into the control cluster.
    var laneWidth: CGFloat?

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
        let visibleIDs = fittedProviderIDs
        let visible = providers.filter { visibleIDs.contains($0.id) }
        let elided = providers.filter { !visibleIDs.contains($0.id) }

        return HStack(spacing: PouredHeaderMeterLane.meterSpacing) {
            ForEach(visible) { provider in
                PouredUsageProviderGroup(
                    provider: provider,
                    ringDiameter: ringDiameter,
                    now: now,
                    lang: lang
                )
            }
        }
        .lineLimit(1)
        .overlay(alignment: .leading) {
            elidedMeterAccessibilityMirror(elided)
        }
    }

    /// The ids `PouredHeaderMeterLane` allows this lane to draw. Every id when
    /// the caller set no bound.
    private var fittedProviderIDs: Set<String> {
        guard let laneWidth else { return Set(providers.map(\.id)) }
        let candidates = providers.map { provider in
            PouredHeaderMeterLane.Candidate(
                id: provider.id,
                width: measuredWidth(of: provider),
                usedPercentage: provider.windows.map(\.usedPercentage).max() ?? 0
            )
        }
        return Set(PouredHeaderMeterLane.fitted(candidates, availableWidth: laneWidth))
    }

    /// One provider group's rendered footprint: its windows' meters plus the
    /// `HStack` gaps between them (the group and the lane share one spacing).
    private func measuredWidth(of provider: UsageProviderPresentation) -> CGFloat {
        let meters = provider.windows.map { window in
            PouredUsageWindowRing.measuredWidth(
                providerTitle: provider.title,
                window: window,
                ringDiameter: ringDiameter,
                now: now,
                lang: lang
            )
        }
        guard !meters.isEmpty else { return 0 }
        return meters.reduce(0, +) + PouredHeaderMeterLane.meterSpacing * CGFloat(meters.count - 1)
    }

    /// C4-2: a meter elided for width is elided **visually only**. It keeps its
    /// VoiceOver stop — the same one-per-group `.help()`/label the visible
    /// meters expose — inside a zero-size, fully transparent, non-hit-testable
    /// overlay, so the lane's hard bound can never delete a usage number from
    /// the accessibility tree.
    @ViewBuilder
    private func elidedMeterAccessibilityMirror(_ elided: [UsageProviderPresentation]) -> some View {
        if elided.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: PouredHeaderMeterLane.meterSpacing) {
                ForEach(elided) { provider in
                    PouredUsageProviderGroup(
                        provider: provider,
                        ringDiameter: ringDiameter,
                        now: now,
                        lang: lang
                    )
                }
            }
            .lineLimit(1)
            // How it stays invisible matters. `.fixedSize()` first, so the
            // mirror keeps its **real** layout size and every group resolves a
            // real accessibility frame; the zero-size frame then takes it back
            // out of the lane's layout; the clip hides the drawing. Measured on
            // the `usageMeters` capture: squeezing the groups to a 0×0 proposal
            // — and likewise a transparent `opacity` — deleted the elided meters
            // from `overlay.ax.json` outright. Clipping a real layout is the one
            // form that hides the pixels and keeps the VoiceOver stops.
            .fixedSize()
            .frame(width: 0, height: 0, alignment: .leading)
            .clipped()
            .allowsHitTesting(false)
        }
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

    /// C4-2: this meter's rendered width — the ring, the ring→label gap, and
    /// whichever of the two label lines is wider — measured against the real
    /// font metrics the two `Text`s below render in (title: 10pt medium with
    /// 0.7pt tracking; countdown: the `usageResetLabel` role). The label block
    /// is `.fixedSize(horizontal: true)`, so this *is* the footprint the lane
    /// has to pay for. Feeds `PouredHeaderMeterLane.fitted`.
    static func measuredWidth(
        providerTitle: String,
        window: UsageWindowPresentation,
        ringDiameter: CGFloat,
        now: Date,
        lang: LanguageManager
    ) -> CGFloat {
        let title = "\(providerTitle) \(window.label)".uppercased()
        let titleWidth = textWidth(
            title,
            font: .systemFont(ofSize: 10, weight: .medium),
            tracking: 0.7
        )

        var countdownWidth: CGFloat = 0
        if let remaining = headerCountdownLabel(for: window, now: now) {
            let spec = PouredType.Role.usageResetLabel.spec
            countdownWidth = textWidth(
                lang.t("island.poured.usage.resets", remaining),
                font: .systemFont(ofSize: spec.size, weight: .semibold)
            )
        }

        return ringDiameter + PouredHeaderMeterLane.ringLabelSpacing + max(titleWidth, countdownWidth)
    }

    private static func textWidth(_ string: String, font: NSFont, tracking: CGFloat = 0) -> CGFloat {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if tracking != 0 {
            attributes[.kern] = tracking
        }
        return NSAttributedString(string: string, attributes: attributes).size().width.rounded(.up)
    }

    var body: some View {
        HStack(spacing: PouredHeaderMeterLane.ringLabelSpacing) {
            ZStack {
                PouredUsageRing(
                    fraction: window.usedPercentage / 100,
                    color: color,
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

            if let remaining = Self.headerCountdownLabel(for: window, now: now) {
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
    static func headerCountdownLabel(for window: UsageWindowPresentation, now: Date) -> String? {
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
/// sweeps in on appear, disabled under Reduce Motion, where the ring paints its
/// final fraction statically. The track opacity lifts under Reduce Transparency
/// so the gauge stays readable. Reused at both the header lane size and the §I
/// meter dial.
///
/// Slice 6 (PI-I-001/I2) **dropped the critical danger glow** — a 0.8s repeating
/// breathe on the `>= 90` dial. The board's §I dials are static SVG with no
/// animation rule anywhere in the section (`01-poured-island.html:1455-1483`),
/// and the §C header rings carry none either, so the pulse was un-referenced
/// motion under R5. Both surfaces lost it together rather than one drifting from
/// the other. (Adjudicated by the root pending owner ratification.)
struct PouredUsageRing: View {
    let fraction: Double
    let color: Color
    var diameter: CGFloat = 16
    var lineWidth: CGFloat = 2.6
    /// The unused-track alpha. The §C header ring keeps
    /// `rgba(242,245,251,.12)` (`01-poured-island.html:229`); the §I **card**
    /// dial is a touch fainter at `rgba(242,245,251,.1)` (`:1456`), so the card
    /// passes its own value rather than the two surfaces sharing one number
    /// (R4-8 ruled the header's track — it must not move).
    var trackOpacity: Double = 0.12

    @State private var animatedFraction: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var clampedFraction: Double { min(1, max(0, fraction)) }

    var body: some View {
        ZStack {
            // R4-8 (PI-I-001 · `01-poured-island.html:228-229`, `:1456`): the
            // unused track is a **neutral** `rgba(242,245,251,.12)` over the
            // ring's dark disc — a tinted track (the old `color.opacity(0.18)`)
            // painted a second, dimmer copy of the band colour around the whole
            // circle and measured green-grey at 34%.
            Circle()
                .stroke(
                    Color.white.opacity(reduceTransparency ? trackOpacity * 2 : trackOpacity),
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
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion {
                animatedFraction = clampedFraction
            } else {
                withAnimation(.easeOut(duration: 0.6)) {
                    animatedFraction = clampedFraction
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
