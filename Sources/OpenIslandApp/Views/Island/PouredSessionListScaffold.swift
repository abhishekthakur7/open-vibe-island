import SwiftUI
import OpenIslandCore

/// Poured Island's session-list chrome (AB-301): the sessions-summary strip, the
/// section headers for all four grouping modes, the scrollable list of rows, and
/// the footer hairline.
///
/// The counting and grouping logic is identical to `IslandSessionListScaffold` —
/// the summary's total / waiting / running / done / idle tallies and the
/// per-section tint / title / count are computed the same way — so only the
/// surface treatment differs: the summary sits inside a quiet glass capsule and
/// the section headers wear a faint frosted wash so hierarchy is carried by
/// light rather than chrome, matching the rest of the poured slab.
///
/// Rows are built through the active theme's `sessionRow` factory (poured
/// returns the glass `PouredSessionRow` since AB-302), exactly as the shared
/// scaffold does.
struct PouredSessionListScaffold: View {
    /// Cap for the scrollable region.
    ///
    /// R2/C9 (PI-C-004 / PI-C-007): Poured's own cap, no longer the shared 560.
    /// The board's §C frame is **six rows visible at once** — that is the whole
    /// point of the state grouping — and at 560 the sixth row fell below the
    /// fold in the C1 capture. Poured's rows are also taller than the shared
    /// scaffold's (every row now carries a narration line plus a `.meta` flow
    /// row), so the shared cap was never sized for this list.
    ///
    /// The ceiling is the notch display's visible frame (949pt): the opened
    /// surface is this cap plus ~150pt of header / summary strip / footer
    /// chrome, so 700 lands at ~850pt with ~100pt of margin. Beyond six rows
    /// the list scrolls exactly as before — the cap moved, the behaviour didn't.
    private static let maxSessionListHeight: CGFloat = 700

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

    /// PI-C-002: whether the footer's idle roll-up is currently disclosed as a
    /// group below `Done`. Collapsed by default — the board's steady state is the
    /// bare roll-up; disclosure is the escape hatch that makes the extracted rows
    /// *reachable* rather than silently dropped.
    @State private var idleDisclosureExpanded = false

    /// Hover state for the roll-up toggle, mirroring `PouredInstallHooksHint`.
    @State private var idleDisclosureHovering = false

    /// Owner ruling R1 (PI-C-002 / PI-C-007): whether the list is showing every
    /// projected row instead of the first `PouredSectionTaxonomy.displayRowCap`.
    /// Collapsed by default — six rows is the board's frame and the owner's cap.
    @State private var listExpanded = false

    /// Hover state for the show-all / collapse affordance.
    @State private var listExpansionHovering = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens
    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                sessionSummaryStrip(referenceDate: context.date)
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

    /// PI-C-001 / PI-C-002 (§C · `01-poured-island.html:809/844/878/913`): Poured's
    /// list is **always** grouped by state — `Needs you → Working → Done` is the
    /// composition, not a preference — and idle never forms a group. When the
    /// profile's grouping is `.none` (one flat `all` section) or already `.state`,
    /// the scaffold re-sections by state locally and runs it through
    /// `PouredSectionTaxonomy`, so attention floats to the top and the idle tail
    /// leaves the table for the footer roll-up. An explicit `.agent` / `.project`
    /// grouping the user picked is honoured verbatim.
    ///
    /// **Owner ruling R1** (PI-C-001): the re-section always runs with
    /// `IslandCompletedStaleThreshold.never`, for `.state` exactly as for
    /// `.none` — a completed row ages inside `Done` and never falls out to the
    /// idle roll-up. That is why `.state` re-sections locally instead of taking
    /// the pre-built `sections` from the shared pipeline, which carry the
    /// profile's threshold. The profile preference itself is untouched *outside*
    /// this surface: it still governs every other theme, and it governs the
    /// Poured list's own chrome under `.agent` / `.project`. Inside the projected
    /// list the whole surface — rows, footer roll-up and summary strip — reads
    /// `effectiveStaleThreshold`, so no two parts of one frame disagree about
    /// whether a completed session is idle. See `PouredSectionTaxonomy`'s
    /// recorded deviations.
    private var taxonomyProjection: PouredSectionTaxonomy.Projection? {
        switch group {
        case .none, .state:
            return PouredSectionTaxonomy.project(
                IslandSessionSectioning.sections(
                    for: sessions,
                    group: .state,
                    sort: .attention,
                    completedStaleThreshold: Self.taxonomyStaleThreshold
                )
            )
        case .agent, .project:
            return nil
        }
    }

    /// Ruling R1: Done never stales inside the Poured list.
    static let taxonomyStaleThreshold = IslandCompletedStaleThreshold.never.seconds

    /// The completed-stale window **every** part of the Poured list must read.
    ///
    /// R1 is a property of the surface, not of one view: the list re-sections at
    /// `taxonomyStaleThreshold`, so the row chrome, the footer roll-up and the
    /// summary strip have to agree or the same frame contradicts itself (an old
    /// completed session reading `Done` in the list while the strip counts it as
    /// `idle`). Under `.agent` / `.project` no taxonomy runs, so the profile's
    /// own preference stays in force — the `nil` branch below.
    private var effectiveStaleThreshold: TimeInterval {
        taxonomyProjection == nil ? completedStaleThreshold : Self.taxonomyStaleThreshold
    }

    /// Everything the row area needs for one render pass: the sections to draw,
    /// each group's **full** row count (a capped group renders partially but
    /// still counts truthfully), and whether the show-all affordance belongs
    /// under them.
    private struct ListContent {
        var sections: [IslandSessionSection]
        var groupTotals: [String: Int]
        var totalRows: Int
        var showsExpansionAffordance: Bool
    }

    private var listContent: ListContent {
        guard let projection = taxonomyProjection else {
            // `.agent` / `.project`: the user's own grouping, passed through
            // verbatim — no taxonomy, no cap (ruling R1 scopes the cap to the
            // state-projected list the board draws).
            return ListContent(
                sections: sections,
                groupTotals: [:],
                totalRows: sections.reduce(0) { $0 + $1.sessions.count },
                showsExpansionAffordance: false
            )
        }

        var projected = projection.sections
        if idleDisclosureExpanded, let idle = idleDisclosureSection(projection) {
            projected.append(idle)
        }

        let capped = PouredSectionTaxonomy.cappedSections(projected)
        return ListContent(
            sections: listExpanded
                ? projected
                : Self.pinningActionableSession(
                    capped.visible,
                    projected: projected,
                    actionableSessionID: actionableSessionID
                ),
            groupTotals: capped.groupTotals,
            totalRows: capped.total,
            showsExpansionAffordance: capped.isCapped
        )
    }

    /// The display cap must never hide the one row the surface was opened *for*.
    ///
    /// The panel opens on a permission / question event with
    /// `.sessionList(actionableSessionID:)`, and the cap cuts in group order — so
    /// an actionable row that sorts past the sixth row (a `Done` row the user
    /// jumped to, or an attention row behind five older ones) would be silently
    /// absent from the frame that exists to show it.
    ///
    /// **Chosen fix: splice, not expand.** Falling back to the expanded list
    /// would be one line, but it throws away the owner's cap for the exact case
    /// where focus matters most (a 40-session list would render all forty because
    /// one row is actionable). Splicing keeps the six-row frame and adds the
    /// pinned row to it: appended to its own group when that group is already on
    /// screen, otherwise re-materialising that group — header and all, in
    /// projection order — with the single pinned row. The group header's count
    /// still comes from `groupTotals` (the group's full size), so nothing lies.
    /// The collapsed list can therefore render seven rows in this one case; that
    /// is the cost of the guarantee, and it is bounded at +1.
    nonisolated static func pinningActionableSession(
        _ visible: [IslandSessionSection],
        projected: [IslandSessionSection],
        actionableSessionID: String?
    ) -> [IslandSessionSection] {
        guard let actionableSessionID else { return visible }
        guard !visible.contains(where: { $0.sessions.contains { $0.id == actionableSessionID } }) else {
            return visible
        }
        guard
            let sourceIndex = projected.firstIndex(where: {
                $0.sessions.contains { $0.id == actionableSessionID }
            }),
            let session = projected[sourceIndex].sessions.first(where: { $0.id == actionableSessionID })
        else {
            return visible
        }

        let source = projected[sourceIndex]
        var spliced = visible

        if let slot = spliced.firstIndex(where: { $0.id == source.id }) {
            spliced[slot] = IslandSessionSection(
                id: source.id,
                title: source.title,
                sessions: spliced[slot].sessions + [session]
            )
            return spliced
        }

        // The whole group was cut away: reinsert it, holding only the pinned row,
        // at the position the projection gives it relative to the visible groups.
        let projectedOrder = projected.map(\.id)
        let insertion = spliced.firstIndex {
            (projectedOrder.firstIndex(of: $0.id) ?? .max) > sourceIndex
        } ?? spliced.endIndex
        spliced.insert(
            IslandSessionSection(id: source.id, title: source.title, sessions: [session]),
            at: insertion
        )
        return spliced
    }

    /// PI-C-002 (**derived**, pending owner ratification — see
    /// `PouredSectionTaxonomy`): the extracted idle rows re-materialised as one
    /// group below `Done` while the footer roll-up is disclosed. It reuses the
    /// shared `state-idle` identity, the cross-theme `island.section.idle` title
    /// and the existing idle tint, so the group is the list's own chrome — no new
    /// surface is invented for it.
    private func idleDisclosureSection(
        _ projection: PouredSectionTaxonomy.Projection
    ) -> IslandSessionSection? {
        guard !projection.idleSessions.isEmpty else { return nil }
        return IslandSessionSection(
            id: PouredSectionTaxonomy.idleSourceSectionID,
            title: "island.section.idle",
            sessions: PouredSectionTaxonomy.recencyDescending(projection.idleSessions)
        )
    }

    @ViewBuilder
    private func sessionRowsContent() -> some View {
        let content = listContent

        ForEach(content.sections) { section in
            VStack(alignment: .leading, spacing: 0) {
                sessionSectionHeader(section, totalRowCount: content.groupTotals[section.id])

                ForEach(Array(section.sessions.enumerated()), id: \.element.id) { index, session in
                    SessionRowContainer(isInteractive: isInteractive) { isHighlighted in
                        theme.sessionRow(
                            session: session,
                            stateIndicator: stateIndicator,
                            completedStaleThreshold: effectiveStaleThreshold,
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
                    }
                    // AB-332: rise+fade spring settle when a row is inserted into
                    // the already-mounted list. The transition never plays on the
                    // list's initial appearance (that arrives under the panel's
                    // own open-morph), only on a genuine insert; the drive
                    // animation is nil under Reduce Motion, so a reduced-motion
                    // insert simply snaps — no clock is touched.
                    .transition(PouredRowEntrance.transition)
                    // R4-6 (`01-poured-island.html:257`): the board's only list
                    // rule is `.row + .row`, and the `.grp` between groups breaks
                    // adjacency — so the first row of every group draws no top
                    // hairline (rows 1, 3, 5 in the §C frame).
                    .environment(\.pouredRowIsFirstInGroup, index == 0)
                }
            }
            // Keyed to the section's row-id set so an insert/remove animates the
            // matching row's transition (and the neighbours settling around it).
            .animation(
                reduceMotion ? nil : PouredRowEntrance.animation,
                value: section.sessions.map(\.id)
            )
        }

        if content.showsExpansionAffordance {
            listExpansionToggle(total: content.totalRows)
        }
    }

    /// Owner ruling R1 (PI-C-002 / PI-C-007): *"we will show max 6 on screen,
    /// rest can be behind 'View All' button"*. The collapsed list renders the
    /// first `PouredSectionTaxonomy.displayRowCap` rows in group order; this row
    /// is the way to the rest, and reads `Collapse list` once expanded.
    ///
    /// **DERIVED placement and styling** — the board renders no such control at
    /// all (§C's frame simply *is* six rows), so only the behaviour is attested
    /// by the ruling. This mirrors `idleDisclosureToggle`: a `.plain` `Button`
    /// (focusable, space/return-activated under Full Keyboard Access) whose
    /// hover only lifts existing paper opacity — no new colour, no new surface.
    /// It sits inside the scroll content, below the last visible group, as a
    /// full-width quiet row on the same side inset and hairline rhythm as a
    /// section header, so it reads as part of the list rather than as chrome
    /// bolted under it. The visible strings are the existing full-phrase
    /// `island.showAll` / `island.collapseList`, so they double as the
    /// accessibility label with no new keys.
    private func listExpansionToggle(total: Int) -> some View {
        let title = listExpanded
            ? lang.t("island.collapseList")
            : lang.t("island.showAll", total)

        return Button {
            listExpanded.toggle()
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        tokens.colors.paper.opacity(
                            tokens.colors.text(
                                listExpansionHovering ? 0.92 : tokens.colors.secondaryTextOpacity,
                                increaseContrast: increasesContrast
                            )
                        )
                    )
                Image(systemName: listExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tokens.colors.paper.opacity(listExpansionHovering ? 0.6 : 0.4))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .padding(.leading, sideInset)
            .padding(.trailing, sideInset)
            .padding(.top, 10)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { listExpansionHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: listExpansionHovering)
        .accessibilityLabel(title)
    }

    /// PI-C-004 (§C · `01-poured-island.html:801-806`, `.summary` at `:243-246`):
    /// the list's chrome is a **shallow band**, not a titled header. The board
    /// carries no "SESSIONS" word anywhere — the panel is already the session
    /// list — and the buckets are not a capsule but a flat full-width strip
    /// fenced by a hairline above *and* below, `8pt` vertical padding, `16pt`
    /// between buckets, no fixed height. Everything the reader needs to triage
    /// the list is in the numbers; the chrome gets out of the way.
    private func sessionSummaryStrip(referenceDate: Date) -> some View {
        let overview = sessionOverviewItems(referenceDate: referenceDate)

        return ViewThatFits(in: .horizontal) {
            sessionOverviewView(overview, compact: false)
            sessionOverviewView(overview, compact: true)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    /// The list footer (§C · mockup `.p-foot`): a leading `Grouped by <mode>`
    /// caption (only while grouping is on) and a trailing `All quiet elsewhere ·
    /// N idle` readout with a tabular count, over the retained top hairline.
    /// Together they close the list with the same "quiet confidence" the empty
    /// state carries.
    ///
    /// PI-C-002: while the taxonomy is active the roll-up is a **disclosure**
    /// (the board's own roll-up is an `<a>`, line 913), because the rows it
    /// counts have been lifted out of the list and would otherwise be
    /// unreachable. Under `.agent` / `.project` — where nothing is extracted —
    /// it stays the inert readout it has always been.
    private func sessionPanelFooter(referenceDate: Date) -> some View {
        let projection = taxonomyProjection
        // PI-C-002: the readout must count exactly the rows the projection
        // removed. The local `idleSessionCount` is a *wider* bucket (completed
        // and stale **or** inactive) than the sectioning's state-idle, so
        // reading it while the taxonomy is active desynced the footer from the
        // list. It remains the answer for agent / project, which extract nothing.
        let idleCount = projection?.idleCount ?? idleSessionCount(referenceDate: referenceDate)
        let canDisclose = projection != nil && idleCount > 0

        return HStack(spacing: 8) {
            if let groupedByText {
                Text(groupedByText)
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            }

            Spacer(minLength: 0)

            if canDisclose {
                idleDisclosureToggle(count: idleCount)
            } else {
                idleRollUpText(count: idleCount)
            }
        }
        .lineLimit(1)
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.vertical, 9)
        .accessibilityElement(children: canDisclose ? .contain : .combine)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    private func idleRollUpText(count: Int) -> some View {
        Text(lang.t("island.poured.footer.idle", count))
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
    }

    /// The roll-up as a press/click toggle. Mirrors `PouredInstallHooksHint` /
    /// `PouredHeaderButton` — a `.plain` `Button` (so it is focusable and
    /// space/return-activated under Full Keyboard Access) with an `onHover`
    /// brightening that settles without easing under Reduce Motion. No new
    /// colour: hover only lifts the existing paper opacity toward full.
    private func idleDisclosureToggle(count: Int) -> some View {
        Button {
            idleDisclosureExpanded.toggle()
        } label: {
            HStack(spacing: 5) {
                idleRollUpText(count: count)
                    .foregroundStyle(
                        tokens.colors.paper.opacity(
                            tokens.colors.text(
                                idleDisclosureHovering ? 0.92 : tokens.colors.secondaryTextOpacity,
                                increaseContrast: increasesContrast
                            )
                        )
                    )
                Image(systemName: idleDisclosureExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tokens.colors.paper.opacity(idleDisclosureHovering ? 0.6 : 0.4))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .onHover { idleDisclosureHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: idleDisclosureHovering)
        .accessibilityLabel(
            lang.t(
                idleDisclosureExpanded ? "a11y.poured.footer.hideIdle" : "a11y.poured.footer.showIdle",
                count
            )
        )
    }

    /// The leading footer caption naming the active grouping (§C · board line 912
    /// `Grouped by state`). PI-C-001: under `.none` the list is still projected by
    /// state through `PouredSectionTaxonomy`, so the caption tells the truth about
    /// what the reader is looking at rather than going silent. Each mode is a whole
    /// localized phrase so it reads naturally in every language (CJK does not
    /// case-fold a word inserted mid-sentence).
    private var groupedByText: String? {
        switch group {
        case .none, .state: return lang.t("island.poured.footer.groupedByState")
        case .agent:        return lang.t("island.poured.footer.groupedByAgent")
        case .project:      return lang.t("island.poured.footer.groupedByProject")
        }
    }

    /// Idle sessions at `referenceDate` — the same stale/inactive bucket the
    /// summary strip counts, surfaced in the footer's trailing readout.
    private func idleSessionCount(referenceDate: Date) -> Int {
        Self.overviewBuckets(
            sessions: sessions,
            referenceDate: referenceDate,
            threshold: effectiveStaleThreshold
        ).idle
    }

    /// The summary strip's five tallies, split out of the view so the numbers the
    /// strip prints are executable (R1's cross-surface agreement is a claim about
    /// these counts, not about the capsule they render in).
    nonisolated struct OverviewBuckets: Equatable {
        var total: Int
        var waiting: Int
        var running: Int
        var done: Int
        var idle: Int
    }

    nonisolated static func overviewBuckets(
        sessions: [AgentSession],
        referenceDate: Date,
        threshold: TimeInterval
    ) -> OverviewBuckets {
        OverviewBuckets(
            total: sessions.count,
            waiting: sessions.filter(\.phase.requiresAttention).count,
            running: sessions.filter { $0.phase == .running }.count,
            done: sessions.filter {
                $0.phase == .completed
                    && !isIdleSessionOverviewItem($0, referenceDate: referenceDate, threshold: threshold)
            }.count,
            idle: sessions.filter {
                isIdleSessionOverviewItem($0, referenceDate: referenceDate, threshold: threshold)
            }.count
        )
    }

    private func sessionOverviewItems(referenceDate: Date) -> [PouredSessionOverviewItem] {
        guard !sessions.isEmpty else { return [] }

        let buckets = Self.overviewBuckets(
            sessions: sessions,
            referenceDate: referenceDate,
            threshold: effectiveStaleThreshold
        )

        return [
            PouredSessionOverviewItem(id: "total", title: lang.t("island.sessionOverview.total"), compactTitle: "", count: buckets.total, tint: nil),
            // R4-1 (PI-C-004 · `01-poured-island.html:803`): the strip's waiting
            // dot is the board's `.dot.approve` salmon (`#f4a4a4`), not the
            // aggregate amber — which collided with the `NEEDS YOU` group chip's
            // `--attn` and made two different things read as one colour.
            PouredSessionOverviewItem(id: "waiting", title: lang.t("island.sessionOverview.waiting"), compactTitle: lang.t("island.sessionOverview.waitingCompact"), count: buckets.waiting, tint: tokens.colors.statusWaitingForApproval),
            PouredSessionOverviewItem(id: "running", title: lang.t("island.sessionOverview.running"), compactTitle: lang.t("island.sessionOverview.runningCompact"), count: buckets.running, tint: tokens.colors.statusRunning),
            PouredSessionOverviewItem(id: "done", title: lang.t("island.sessionOverview.done"), compactTitle: lang.t("island.sessionOverview.done"), count: buckets.done, tint: tokens.colors.statusCompleted),
            PouredSessionOverviewItem(id: "idle", title: lang.t("island.sessionOverview.idle"), compactTitle: lang.t("island.sessionOverview.idle"), count: buckets.idle, tint: tokens.colors.statusIdle),
        ].filter { $0.id == "total" || $0.count > 0 }
    }

    nonisolated private static func isIdleSessionOverviewItem(
        _ session: AgentSession,
        referenceDate: Date,
        threshold: TimeInterval
    ) -> Bool {
        guard session.phase == .completed else { return false }
        // R1: an infinite window means "completed rows never age out", so the
        // strip's *second* idle clause — a 20-minute presence decay that the
        // shared state sectioning does not apply at all — must fall away too.
        // Otherwise the C1 frame reads `Done` for its 22-minute row in the table
        // and `1 idle` in the strip above it. Every finite window (agent /
        // project, and every other theme) keeps the wider bucket unchanged.
        guard threshold.isFinite else { return false }
        return session.isStaleCompletedForIsland(at: referenceDate, threshold: threshold)
            || session.islandPresence(at: referenceDate) == .inactive
    }

    private func sessionOverviewView(_ items: [PouredSessionOverviewItem], compact: Bool) -> some View {
        // PI-C-004: the board's `.summary` is a bare flex row at `gap:16px` —
        // no capsule, no fill, no inner padding of its own.
        HStack(spacing: compact ? 10 : 16) {
            ForEach(items) { item in
                sessionOverviewMetric(item, compact: compact)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private func sessionOverviewMetric(_ item: PouredSessionOverviewItem, compact: Bool) -> some View {
        let label = sessionOverviewMetricLabel(item, compact: compact)

        // §2 splits the bucket into a bold tabular number (`summaryNumber`
        // 12/700) and a proportional word (`summaryLabel` 11/400); the tinted
        // dot carries the status colour, so the mono chrome is retired.
        // PI-C-004: `.summary .b { gap: 6px }` with a 6×6 dot (the board
        // overrides the base 8px `.dot` inline for the strip).
        return HStack(spacing: 6) {
            if let tint = item.tint {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 6) {
                Text("\(item.count)")
                    .font(PouredType.Role.summaryNumber.font)
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.96, increaseContrast: increasesContrast)))

                if !label.isEmpty {
                    Text(label)
                        .font(PouredType.Role.summaryLabel.font)
                        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
                }
            }
        }
    }

    /// The bucket's word (without the count) for the current density: the
    /// `total` bucket drops its word entirely in the compact strip, leaving just
    /// the number.
    private func sessionOverviewMetricLabel(_ item: PouredSessionOverviewItem, compact: Bool) -> String {
        if item.id == "total" {
            return compact ? "" : item.title
        }
        return compact ? item.compactTitle : item.title
    }

    /// `totalRowCount` is the group's row count **before** the display cap, so a
    /// partially-rendered group still prints how many rows it holds (ruling R1:
    /// View All hides rows, it does not change what exists). `nil` for agent /
    /// project groupings, which are never capped.
    private func sessionSectionHeader(
        _ section: IslandSessionSection,
        totalRowCount: Int? = nil
    ) -> some View {
        HStack(spacing: 8) {
            // R4-5 (PI-C-005 · `01-poured-island.html:251`): `.grp .gc` is a
            // 6×6 **rounded square** (`border-radius:2px`), not a circle — the
            // board's own shape-carries-state rule applied to the group chip.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(sectionTint(for: section))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(sessionSectionTitle(for: section).uppercased())
                // §2 `sectionHeader` role: SF Pro 10.5/650, tracking 0.09em
                // uppercase — mono retired, tracking from the pinned spec.
                .font(PouredType.Role.sectionHeader.font)
                .tracking(PouredType.Role.sectionHeader.spec.trackingPoints)
                .foregroundStyle(sectionLabelColor(for: section))
            // R4-5 (`:252`): `.grp .gn { margin-left:auto }` — the count sits at
            // the panel's trailing inset, not tucked against the label.
            Spacer(minLength: 8)
            Text("\(totalRowCount ?? section.sessions.count)")
                // Drop mono, keep the digits tabular so counts line up column-wise.
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.top, 10)
        .padding(.bottom, 7)
        // R4-6 (PI-C-005 · `:249-252`, `:257`): `.grp` carries **no** fill band
        // and **no** hairline. The board's only list rule is `.row + .row`, and a
        // group header breaks that adjacency — so the header paints nothing and
        // the group's first row draws no top hairline either.
        .accessibilityElement(children: .combine)
    }

    /// PI-C-001: a taxonomy group wears its **fixed** board hue (`--attn` / `--run`
    /// / `--done`), not a hue derived from whichever row happens to sort first —
    /// which used to make a `Done` group led by an interrupted row wear the
    /// interrupted amber. Agent / project groupings keep the first-row derivation,
    /// which is all they can do.
    private func sectionTint(for section: IslandSessionSection) -> Color {
        if let group = PouredSectionTaxonomy.group(forSectionID: section.id) {
            return PouredSectionTaxonomy.tint(for: group, tokens: tokens.colors)
        }
        guard let first = section.sessions.first else { return tokens.colors.statusIdle }
        if section.id == "state-idle" { return tokens.colors.statusIdle }
        return tokens.colors.statusTint(for: first.phase, outcome: first.outcome)
    }

    private func sessionSectionTitle(for section: IslandSessionSection) -> String {
        if let key = PouredSectionTaxonomy.localizationKey(forSectionID: section.id) {
            return lang.t(key)
        }
        if section.title.hasPrefix("island.") {
            return lang.t(section.title)
        }
        return section.title
    }

    // The `state-approval` / `state-answer` tinted-label cases are gone: those
    // ids never reach a rendered header any more — `PouredSectionTaxonomy` merges
    // both into `Needs you` and owns that group's chrome.
    private func sectionLabelColor(for section: IslandSessionSection) -> Color {
        tokens.colors.paper.opacity(0.72)
    }
}

private struct PouredSessionOverviewItem: Identifiable {
    let id: String
    let title: String
    let compactTitle: String
    let count: Int
    let tint: Color?
}

/// R4-6 (PI-C-005 · `01-poured-island.html:257`): Poured-local seam telling a
/// row it is the **first** row of its group, so it can suppress the `.row + .row`
/// top hairline the board only draws between *adjacent* rows. Set by
/// `PouredSessionListScaffold` alone; every other theme's scaffold leaves the
/// default (`false`) in place and is unaffected.
private struct PouredRowIsFirstInGroupKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var pouredRowIsFirstInGroup: Bool {
        get { self[PouredRowIsFirstInGroupKey.self] }
        set { self[PouredRowIsFirstInGroupKey.self] = newValue }
    }
}
