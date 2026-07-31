import SwiftUI
import OpenIslandCore

/// Halo's session-list chrome (AB-343 · T24 · SPEC §5 Slot 4 · mockup §C): a
/// hairline-bounded **summary strip** (only non-zero buckets, each a tinted
/// status dot + tabular number + word), the grouped **section headers** ("Needs
/// you" first so attention floats to the top), the scrollable list of rows, and
/// a quiet **footer** carrying the `N sessions · M need you` readout plus a
/// passive `Grouped by …` caption.
///
/// This is the Halo void idiom (SPEC §0): **no fills, no cards** — every seam is
/// a 1px hairline on pure `#000`, and hierarchy comes from the type scale + case
/// + the status-tint dots, never from a wash or capsule. The counting and
/// grouping logic is identical to `IslandSessionListScaffold` / the sibling
/// `AnnualSessionListScaffold` — the buckets and the per-section title / count
/// are computed the same way (`HaloSessionListModel`, a pure format enum pinned
/// by `HaloSessionListTests`), so only the surface treatment differs.
///
/// **Rows are the AB-344 seam.** Rows route through the active theme's
/// `sessionRow` factory (the shared scaffold's exact path), which today delegates
/// to Classic's flat row. AB-344 swaps that delegation for the real void Halo row
/// (dot + monogram, edge-lit rail, permission/question heroes) with **no change
/// here** — the scaffold owns only the list-level chrome (inter-row 8%-white
/// hairlines + the white@.026 hover wash), and the row owns its own body. The
/// list-level duplicate-workspace disambiguators (T05 · `SessionDisambiguation`)
/// reach the row through the environment upstream, so they render the moment the
/// real Halo row typesets its `.disamb` (10.5pt mono @ t3) branch suffix.
struct HaloSessionListScaffold: View {
    /// Cap for the scrollable region — kept in sync with the shared scaffold so
    /// the opened surface's height math is identical across themes.
    private static let maxSessionListHeight: CGFloat = 560

    /// Hover wash on a list row (mockup §C `hover bg white@.026`). Deliberately
    /// below the 8%-white hairline so the wash reads as a whisper on the void.
    private static let rowHoverWash = Color.white.opacity(0.026)

    let sessions: [AgentSession]
    let sections: [IslandSessionSection]
    let group: IslandSessionGroup
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    let sideInset: CGFloat
    let isInteractive: Bool
    let actionableSessionID: String?
    let lang: LanguageManager
    let keyboardCoordinator: OverlayUICoordinator?
    let pulseClock: PulseClock?
    let makeActions: (AgentSession) -> RowActions

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens
    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                sessionPanelHeader(referenceDate: context.date)
            }

            AutoHeightScrollView(maxHeight: Self.maxSessionListHeight) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    sessionRowsContent()
                }
            }

            TimelineView(.periodic(from: .now, by: 30)) { context in
                sessionPanelFooter(referenceDate: context.date)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Rows (the AB-344 seam)

    /// G-09 (mockup §C): Halo's list is **always** grouped — `NEEDS YOU → RUNNING →
    /// DONE` is the composition, not a preference. When the profile's grouping is
    /// `.none` (one flat `all` section) the scaffold re-sections by state locally,
    /// so the headers the file already draws actually render. Any explicit grouping
    /// the user picked is honoured verbatim.
    private var displaySections: [IslandSessionSection] {
        guard group == .none else { return sections }
        return IslandSessionSectioning.sections(
            for: sessions,
            group: .state,
            sort: .attention,
            completedStaleThreshold: completedStaleThreshold
        )
    }

    /// The identity of the current list, in order — the value M-21's animation
    /// watches so an insert / reorder / removal (or a phase change that moves a row
    /// between buckets) animates instead of hard-cutting.
    private var sessionListIdentity: [String] {
        displaySections.flatMap { section in section.sessions.map { "\(section.id)/\($0.id)" } }
    }

    private func sessionRowsContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionSectionsContent()
        }
        // M-21 (mockup §C / §K "content is still, light moves"): rows fade + slide
        // from the top on insert / reorder / removal rather than popping. Halo-only
        // — this scaffold is Halo's alone (`HaloTheme.sessionList`).
        .animation(.easeInOut(duration: 0.22), value: sessionListIdentity)
    }

    @ViewBuilder
    private func sessionSectionsContent() -> some View {
        ForEach(displaySections) { section in
            VStack(alignment: .leading, spacing: 0) {
                sessionSectionHeader(section)

                ForEach(Array(section.sessions.enumerated()), id: \.element.id) { index, session in
                    SessionRowContainer(isInteractive: isInteractive) { isHighlighted in
                        theme.sessionRow(
                            session: session,
                            stateIndicator: stateIndicator,
                            completedStaleThreshold: completedStaleThreshold,
                            isActionable: session.phase.requiresAttention || session.id == actionableSessionID,
                            useDrawingGroup: isInteractive,
                            isInteractive: isInteractive,
                            isHighlighted: isHighlighted,
                            presentation: .list,
                            sideInset: sideInset,
                            lang: lang,
                            actions: makeActions(session),
                            keyboardCoordinator: keyboardCoordinator,
                            pulseClock: pulseClock
                        )
                        // List-level chrome the scaffold owns (mockup §C): the
                        // white@.026 hover wash on the void. The row body draws
                        // no fill of its own, so this is the only ground it gets.
                        .background(isHighlighted ? Self.rowHoverWash : Color.clear)
                    }
                    // 8%-white hairline between rows within a section. The first
                    // row is capped by the section header's rule (grouped) or the
                    // summary strip's bottom rule (ungrouped), so it takes none.
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle()
                                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                                .frame(height: 1)
                        }
                    }
                    // M-21: the per-row insert / removal transition the list-level
                    // `.animation` above drives.
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - Summary strip (hairline-bounded, non-zero buckets)

    private func sessionPanelHeader(referenceDate: Date) -> some View {
        let buckets = HaloSessionListModel.summaryBuckets(
            sessions: sessions,
            referenceDate: referenceDate,
            threshold: completedStaleThreshold
        )

        // G-06: no list title — the mockup's `.summary` is buckets only, and the
        // grouped section headers below are what name the list.
        return HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                summaryStrip(buckets, spacing: 12)
                summaryStrip(buckets, spacing: 8)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        // G-15 (mockup `.summary{padding:8px 16px}`): intrinsic height with 8pt of
        // vertical padding, bounded by a hairline **top and bottom**.
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summaryAccessibilityLabel(buckets))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    private func summaryStrip(_ buckets: [HaloSessionListModel.Bucket], spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(buckets, id: \.kind) { bucket in
                HStack(spacing: 4) {
                    if let tint = tint(for: bucket.kind) {
                        Circle()
                            .fill(tint)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Text("\(bucket.count)")
                        .font(.system(size: HaloTypography.summaryNumberSize, weight: .bold).monospacedDigit())
                        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.9, increaseContrast: increasesContrast)))
                    Text(lang.t(bucket.kind.labelKey))
                        .font(.system(size: HaloTypography.summaryLabelSize, weight: .regular))
                        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
                }
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func summaryAccessibilityLabel(_ buckets: [HaloSessionListModel.Bucket]) -> String {
        buckets.map { "\($0.count) \(lang.t($0.kind.labelKey))" }.joined(separator: ", ")
    }

    // MARK: - Section header (.grp — tinted dot + uppercase caps + count)

    private func sessionSectionHeader(_ section: IslandSessionSection) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sectionTint(for: section))
                .frame(width: HaloMetrics.dot * 0.75, height: HaloMetrics.dot * 0.75)
                .accessibilityHidden(true)
            Text(sessionSectionTitle(for: section).uppercased())
                .font(.system(size: HaloTypography.sectionHeaderSize, weight: .bold))
                .tracking(HaloTypography.sectionHeaderSize * 0.10)
                .foregroundStyle(sectionLabelColor(for: section))
            // G-09 (mockup `.gn{margin-left:auto}`): the count is pushed to the
            // trailing edge, not parked next to the title.
            Spacer(minLength: 8)
            Text("\(section.sessions.count)")
                .font(.system(size: HaloTypography.sectionHeaderSize, weight: .medium).monospacedDigit())
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    private func sessionSectionTitle(for section: IslandSessionSection) -> String {
        if section.title.hasPrefix("island.") {
            return lang.t(section.title)
        }
        return section.title
    }

    /// The section-header dot tint reads against the pure-black void with no fill
    /// (SPEC §5 Slot 4 "hardest detail"): the status hue alone carries meaning.
    private func sectionTint(for section: IslandSessionSection) -> Color {
        guard let first = section.sessions.first else { return tokens.colors.statusIdle }
        if section.id == "state-idle" { return tokens.colors.statusIdle }
        return tokens.colors.statusTint(for: first.phase, outcome: first.outcome)
    }

    /// Attention sections ("Needs you" — a permission request, a pending
    /// question) spend the status tint on their caps title; every calm section is
    /// warm paper. Accent discipline at the section level.
    private func sectionLabelColor(for section: IslandSessionSection) -> Color {
        switch section.id {
        case "state-approval":
            return tokens.colors.statusWaitingForApproval
        case "state-answer":
            return tokens.colors.statusWaitingForAnswer
        default:
            return tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast))
        }
    }

    // MARK: - Footer (readout + passive grouping caption)

    /// The quiet footer over a single top hairline: a leading `N sessions · M
    /// need you` tabular readout and a trailing, **passive** `Grouped by …`
    /// caption (no interactive control — grouping is chosen elsewhere).
    private func sessionPanelFooter(referenceDate: Date) -> some View {
        let need = HaloSessionListModel.needCount(sessions: sessions)

        return HStack(spacing: 8) {
            Text(lang.t("island.halo.footer.summary", sessions.count, need))
                .font(.system(size: HaloTypography.summaryLabelSize).monospacedDigit())
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))

            Spacer(minLength: 0)

            if let key = HaloSessionListModel.groupedByLocalizationKey(group) {
                Text(lang.t(key))
                    .font(.system(size: HaloTypography.summaryLabelSize))
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            }
        }
        .lineLimit(1)
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    // MARK: - Tint mapping (semantic bucket kind → status token)

    private func tint(for kind: HaloSessionListModel.BucketKind) -> Color? {
        switch kind {
        case .total:   return nil
        case .waiting: return tokens.colors.statusWaitingAggregate
        case .running: return tokens.colors.statusRunning
        case .done:    return tokens.colors.statusCompleted
        case .idle:    return tokens.colors.statusIdle
        }
    }
}

// MARK: - Pure format model (pinned by HaloSessionListTests)

/// The counting / grouping rules behind `HaloSessionListScaffold`, kept pure
/// (no SwiftUI, no `Color`) so `HaloSessionListTests` can pin the non-zero-bucket
/// filter, the `total`-always ordering, the "need you" tally, and the grouping
/// caption keys without rendering. Mirrors the shared scaffold's tallies exactly.
enum HaloSessionListModel {
    /// The five summary buckets in stable display order. `total` always shows;
    /// the four state buckets show only when non-zero.
    enum BucketKind: String, CaseIterable, Sendable {
        case total, waiting, running, done, idle

        /// Localization key for the bucket's trailing word.
        var labelKey: String {
            switch self {
            case .total:   return "island.sessionOverview.total"
            case .waiting: return "island.sessionOverview.waiting"
            case .running: return "island.sessionOverview.running"
            case .done:    return "island.sessionOverview.done"
            case .idle:    return "island.sessionOverview.idle"
            }
        }
    }

    struct Bucket: Equatable, Sendable {
        let kind: BucketKind
        let count: Int
    }

    /// The summary strip's buckets: `total` (always) followed by every non-zero
    /// state bucket, in `waiting → running → done → idle` order.
    static func summaryBuckets(
        sessions: [AgentSession],
        referenceDate: Date,
        threshold: TimeInterval
    ) -> [Bucket] {
        guard !sessions.isEmpty else { return [] }

        let waiting = sessions.filter(\.phase.requiresAttention).count
        let running = sessions.filter { $0.phase == .running }.count
        let done = sessions.filter {
            $0.phase == .completed
                && !isIdle($0, referenceDate: referenceDate, threshold: threshold)
        }.count
        let idle = sessions.filter {
            isIdle($0, referenceDate: referenceDate, threshold: threshold)
        }.count

        return [
            Bucket(kind: .total, count: sessions.count),
            Bucket(kind: .waiting, count: waiting),
            Bucket(kind: .running, count: running),
            Bucket(kind: .done, count: done),
            Bucket(kind: .idle, count: idle),
        ].filter { $0.kind == .total || $0.count > 0 }
    }

    /// The "need you" tally in the footer — sessions demanding attention.
    static func needCount(sessions: [AgentSession]) -> Int {
        sessions.filter(\.phase.requiresAttention).count
    }

    /// The passive footer caption key for the active grouping, or `nil` when the
    /// list is ungrouped (nothing to say). Each mode is a whole localized phrase.
    static func groupedByLocalizationKey(_ group: IslandSessionGroup) -> String? {
        switch group {
        case .none:    return nil
        case .state:   return "island.halo.footer.groupedByState"
        case .agent:   return "island.halo.footer.groupedByAgent"
        case .project: return "island.halo.footer.groupedByProject"
        }
    }

    /// The idle bucket rule, identical to the shared scaffold: a completed
    /// session that is stale for the island or whose presence has gone inactive.
    static func isIdle(
        _ session: AgentSession,
        referenceDate: Date,
        threshold: TimeInterval
    ) -> Bool {
        guard session.phase == .completed else { return false }
        return session.isStaleCompletedForIsland(at: referenceDate, threshold: threshold)
            || session.islandPresence(at: referenceDate) == .inactive
    }
}
