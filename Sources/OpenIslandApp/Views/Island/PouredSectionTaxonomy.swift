import SwiftUI
import OpenIslandCore

/// Poured Island's §C **session-list taxonomy** (PI-C-001 / PI-C-002 / PI-C-007).
///
/// The live list sections by state through the shared `IslandSessionSectioning`
/// (`state-approval` / `state-answer` / `state-running` / `state-done` /
/// `state-idle`, titled by the cross-theme `island.section.*` catalog: `Needs
/// approval` / `Needs answer` / `In progress` / `Just done` / `Idle`). The Poured
/// board (`01-poured-island.html` §C) names only **three** groups — `Needs you`
/// (line 809), `Working` (844), `Done` (878) — files the permission row *and* the
/// question row under the single `Needs you` header, keeps success *and*
/// interrupted rows together under the terminal `Done` header (887 / 904), and
/// **never renders an idle group at all**: idle appears only as the footer
/// roll-up `All quiet elsewhere · N idle` (913).
///
/// This enum is that projection, and only that. The shared `island.section.*`
/// strings are untouched product copy every other theme keeps rendering; Poured
/// resolves its own `island.poured.section.*` words here and nowhere else. It
/// performs the three structural consequences of the board's taxonomy:
///
/// 1. **Merge** `state-approval` + `state-answer` into one `Needs you` group
///    (PI-C-001) — two consecutive headers both reading `NEEDS YOU` would be a
///    bug, not a skin.
/// 2. **Extract** `state-idle` out of the rendered list entirely (PI-C-002 /
///    PI-C-007), returning it as a count for the footer roll-up, so a long tail
///    of idle sessions can never grow into an unbounded table below the rows
///    that actually need the reader.
/// 3. **Fix** the group order (`Needs you → Working → Done`) and each group's
///    swatch hue, so attention is always first and a header's tint no longer
///    depends on whichever row happens to sort first inside it.
///
/// Non-state groupings (`agent-…`, `project-…`) never reach here — they carry
/// workspace / agent names, not taxonomy, and the scaffold honours an explicit
/// user grouping verbatim.
///
/// ### Recorded deviations from the reference
///
/// - **Intra-group order is fixed to recency-descending** and deliberately
///   overrides the profile's `islandSessionSort` *inside the Poured list*. The
///   board's groups read newest-first in every one of the three (§C `1m/3m`,
///   `now/8m`, `12m/22m`), so recency is a board rule, not a preference. This is
///   a known **preference override**: a user who picked another sort still sees
///   it honoured in the section *composition* upstream and in every other theme,
///   but not in the order of rows within a Poured group.
/// - **The expanded idle group is DERIVED presentation, owner-ratified**
///   (ruling R3, `docs/design/overlay-redesign/poured-owner-rulings.md`). The
///   board never renders an idle group at all — its roll-up is an interactive
///   link (line 913) with no visible destination. Extraction with no way back
///   would make those rows unreachable, so `PouredSessionListScaffold` renders
///   the extracted rows as one additional group below `Done` while the footer
///   roll-up is disclosed, using the shared `island.section.idle` title and the
///   idle tint. The affordance itself is ratified; its exact presentation is
///   still unattested by the reference.
/// - **Done never stales inside the Poured list** — owner ruling **R1**
///   (PI-C-001): *"done stays visible just we will show max 6 on screen, rest
///   can be behind 'View All' button"*. `PouredSessionListScaffold` therefore
///   re-sections with `IslandCompletedStaleThreshold.never` regardless of the
///   profile's `completedStaleThreshold`, so a completed row ages inside `Done`
///   instead of falling out to the idle roll-up. Consequences, all
///   board-faithful:
///   - the `state-idle` bucket this projection extracts is **empty in
///     practice**, so the idle disclosure above is dormant, and
///   - the footer's projection-fed readout naturally reads `0 idle` — exactly
///     what §C prints beside its 12m / 22m `Done` rows (line 913).
///   This is theme-local: the shared `completedStaleThreshold` preference and
///   every other theme are untouched, and the wider stale bucket still drives
///   the summary strip's own `idle` metric.
/// - **The 6-row display cap** (`displayRowCap` / `cappedSections`) is the other
///   half of ruling R1 and of the board's own frame: §C draws exactly six rows.
///   The ruling fixes *"max 6 + View All"*; the affordance's placement and
///   styling are DERIVED (see `PouredSessionListScaffold`).
enum PouredSectionTaxonomy {

    // MARK: - Groups

    /// The board's three groups, in the fixed order they are rendered.
    enum Group: String, CaseIterable, Sendable {
        case needsYou
        case working
        case done

        /// Identity of the projected section. `Needs you` is a synthetic merge of
        /// two shared sections and gets its own id; the other two keep the shared
        /// state identity they project from, so row-level identity is unchanged.
        var sectionID: String {
            switch self {
            case .needsYou: return "state-poured-needsYou"
            case .working:  return "state-running"
            case .done:     return "state-done"
            }
        }

        /// The Poured-scoped header word.
        var localizationKey: String {
            switch self {
            case .needsYou: return "island.poured.section.needsYou"
            case .working:  return "island.poured.section.working"
            case .done:     return "island.poured.section.done"
            }
        }

        /// The shared state-section identities this group projects from, in the
        /// order their rows are concatenated before the recency sort. `Needs you`
        /// lists approval rows ahead of question rows.
        var sourceSectionIDs: [String] {
            switch self {
            case .needsYou: return ["state-approval", "state-answer"]
            case .working:  return ["state-running"]
            case .done:     return ["state-done"]
            }
        }
    }

    /// Identity of the merged attention group (`state-approval` + `state-answer`).
    static let needsYouSectionID = Group.needsYou.sectionID

    /// The shared section identity the board never renders as a group — extracted
    /// into `Projection.idleSessions` for the footer roll-up.
    static let idleSourceSectionID = "state-idle"

    // MARK: - Projection

    /// The rendered sections plus the idle rows lifted out of them.
    struct Projection {
        /// `Needs you → Working → Done`, empty groups omitted (the board never
        /// draws a zero-count header).
        let sections: [IslandSessionSection]
        /// The `state-idle` rows, which are **not** rendered as a group.
        let idleSessions: [AgentSession]

        var idleCount: Int { idleSessions.count }
    }

    /// Projects the shared five state sections onto the board's three groups.
    ///
    /// Group order is fixed by `Group.allCases` and does not depend on the order
    /// of `sections`. Within each group rows are sorted most-recent-first by
    /// `islandActivityDate`, stably — equal timestamps keep the order they
    /// arrived in, which is the deterministic attention order upstream produced.
    static func project(_ sections: [IslandSessionSection]) -> Projection {
        var byID: [String: [AgentSession]] = [:]
        for section in sections {
            byID[section.id, default: []].append(contentsOf: section.sessions)
        }

        let projected = Group.allCases.compactMap { group -> IslandSessionSection? in
            let rows = group.sourceSectionIDs.flatMap { byID[$0] ?? [] }
            guard !rows.isEmpty else { return nil }
            return IslandSessionSection(
                id: group.sectionID,
                title: group.localizationKey,
                sessions: recencyDescending(rows)
            )
        }

        return Projection(
            sections: projected,
            idleSessions: byID[idleSourceSectionID] ?? []
        )
    }

    /// Most-recent-first by `islandActivityDate`, stable for ties (Swift's `sort`
    /// is not stable, so the original index is the explicit tiebreak).
    static func recencyDescending(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.islandActivityDate
                let r = rhs.element.islandActivityDate
                if l == r { return lhs.offset < rhs.offset }
                return l > r
            }
            .map(\.element)
    }

    // MARK: - Display cap (owner ruling R1 · PI-C-002 / PI-C-007)

    /// How many rows the collapsed Poured list shows at once. Six is the board's
    /// own frame (§C draws exactly six rows) and the number the owner fixed:
    /// *"we will show max 6 on screen, rest can be behind 'View All' button"*.
    static let displayRowCap = 6

    /// The result of cutting a projection down to the display cap.
    struct CappedSections {
        /// The sections to render while collapsed, in projection order. A group
        /// can be rendered **partially** (the cut falls inside it) and a group
        /// whose rows are entirely past the cut is omitted.
        let visible: [IslandSessionSection]
        /// Rows the cut removed — `0` when nothing was cut.
        let hiddenCount: Int
        /// Rows across every projected section, before the cut.
        let total: Int
        /// Section id → that group's **full** row count, before the cut. The
        /// header count renders from this so a partially-rendered group still
        /// tells the truth about how many rows it holds: the cap hides rows, it
        /// does not change what exists.
        let groupTotals: [String: Int]

        var isCapped: Bool { hiddenCount > 0 }
    }

    /// Cuts `sections` to at most `limit` rows in group order.
    ///
    /// Group order is the projection's, so the attention rows — always first —
    /// are the last thing a cut can ever reach. Exactly `limit` rows is **not**
    /// a cut: `hiddenCount` is `0` and the caller shows no affordance, matching
    /// the board's own six-row frame with no control under it.
    static func cappedSections(
        _ sections: [IslandSessionSection],
        limit: Int = displayRowCap
    ) -> CappedSections {
        let totals = Dictionary(
            sections.map { ($0.id, $0.sessions.count) },
            uniquingKeysWith: +
        )
        let total = sections.reduce(0) { $0 + $1.sessions.count }

        guard total > limit else {
            return CappedSections(visible: sections, hiddenCount: 0, total: total, groupTotals: totals)
        }

        var remaining = max(0, limit)
        var visible: [IslandSessionSection] = []
        for section in sections {
            guard remaining > 0 else { break }
            let take = min(remaining, section.sessions.count)
            visible.append(
                IslandSessionSection(
                    id: section.id,
                    title: section.title,
                    sessions: Array(section.sessions.prefix(take))
                )
            )
            remaining -= take
        }

        return CappedSections(
            visible: visible,
            hiddenCount: total - max(0, limit),
            total: total,
            groupTotals: totals
        )
    }

    // MARK: - Lookups

    /// The group a projected section identity belongs to, or `nil` when the
    /// section isn't part of the Poured taxonomy (agent / project groupings).
    static func group(forSectionID id: String) -> Group? {
        Group.allCases.first { $0.sectionID == id }
    }

    /// The Poured header word for a section identity, or `nil` when the section
    /// keeps its shared title.
    static func localizationKey(forSectionID id: String) -> String? {
        group(forSectionID: id)?.localizationKey
    }

    /// The fixed swatch hue per group — the board's `--attn` `#ffb14d`, `--run`
    /// `#6ea7ff`, `--done` `#6fb982`. All three already exist as tokens
    /// (`PouredPalette.attention` is the exact attention amber; Poured's
    /// `statusRunning` / `statusCompleted` are the exact blue and green), so
    /// nothing new is minted here. Fixing the hue per group is the point: the
    /// old header tint was derived from whichever row sorted first, so a `Done`
    /// group led by an interrupted row wore the interrupted amber.
    static func tint(for group: Group, tokens: IslandColorTokens) -> Color {
        switch group {
        case .needsYou: return PouredPalette.attention
        case .working:  return tokens.statusRunning
        case .done:     return tokens.statusCompleted
        }
    }
}
