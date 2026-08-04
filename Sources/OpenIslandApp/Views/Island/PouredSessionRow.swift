import AppKit
import SwiftUI
import OpenIslandCore

/// Poured Island's session row (AB-302 · AB-303).
///
/// The glass re-skin of `IslandSessionRow` for **every** row state — collapsed,
/// running, done, idle/stale (AB-302) and the actionable approval / question /
/// completion interiors (AB-303) — across the `.list` and `.notification`
/// presentations. Status is expressed as luminous glow rather than a chip: a
/// running row carries a breathing green dot (static under Reduce Motion), a
/// done row settles to a quiet check, and an idle row recedes into the
/// material; hover lifts the row with a lighter glass tint in `.list` only.
///
/// **Actionable rows are now fully Poured (AB-303).** A permission request
/// radiates a pulsing warm-amber glow above the glass — the loudest surface in
/// the panel — with a filled Allow and a quiet Deny; the question and completion
/// bodies reuse the shared, token-driven `StructuredQuestionPromptView` /
/// completion card, which already read cleanly on the frosted surface. The
/// behaviours that are contract-level — approve / answer / reply callbacks, the
/// ⌘Y / ⌘⇧Y / ⌘N keyboard wiring (driven globally from `OverlayPanelController`),
/// the 1–9 / Enter question shortcuts, and the grouped VoiceOver summary — are
/// preserved verbatim; only the surfaces change.
struct PouredSessionRow: View {
    let session: AgentSession
    var stateIndicator: IslandSessionStateIndicator = .animatedDot
    var completedStaleThreshold: TimeInterval = AgentSession.staleCompletedDisplayThreshold
    var isActionable: Bool = false
    var useDrawingGroup: Bool = true
    var isInteractive: Bool = true
    /// Hover highlight, owned by the enclosing `SessionRowContainer` (AB-297).
    let isHighlighted: Bool
    var presentation: IslandSessionRowPresentation = .list
    var sideInset: CGFloat = 16
    var lang: LanguageManager = .shared
    let actions: RowActions
    /// Lets the visible question card register its option-selection state with
    /// `OverlayPanelController`'s keyboard shortcut handler (AB-227).
    var keyboardCoordinator: OverlayUICoordinator?
    /// Shared 15fps clock for the breathing status dot (AB-228) and the amber
    /// approval glow (AB-303). Passed through to the leaf views that animate;
    /// rows that don't animate never touch it.
    var pulseClock: PulseClock?

    var body: some View {
        PouredRowContent(
            session: session,
            stateIndicator: stateIndicator,
            completedStaleThreshold: completedStaleThreshold,
            isActionable: isActionable,
            isInteractive: isInteractive,
            isHighlighted: isHighlighted,
            presentation: presentation,
            sideInset: sideInset,
            lang: lang,
            actions: actions,
            keyboardCoordinator: keyboardCoordinator,
            pulseClock: pulseClock
        )
    }
}

/// The one place outside a Poured row that can see — and undo — an **in-place
/// hero the user deliberately opened inside the list** (R9's mechanism).
///
/// `detailOverride` is per-row `@State` and therefore unreachable from
/// `OverlayPanelController`, but R8 makes Escape two-stage: the first Esc must
/// collapse an open hero back to its compact row (list preserved), and only the
/// second Esc closes the panel. The same fact routes R8's sibling gap — ⌘Y /
/// ⌘⇧Y / ⌘N and the digit keys currently key off `activeIslandCardSession`, so
/// an in-list hero can advertise keycaps that fire against a different session
/// (`mapper-native.md` gap 8); `openHeroSessionID` is the session those
/// shortcuts should actuate instead.
///
/// Shaped as a `@MainActor @Observable` shared object on the `PulseClock`
/// precedent rather than a preference key, because the consumer is an AppKit
/// event monitor, not a view — and because `IslandPanelView` (the only view
/// between the row and the panel controller) must stay untouched.
///
/// Deliberately records **only** deliberate, in-list openings: a notification
/// surface auto-expands its single row (`PouredRowExpansion.resolved`), and
/// that is not "a hero open inside the list", so Esc there keeps its existing
/// close-the-panel meaning.
@MainActor
@Observable
final class PouredHeroExpansion {
    static let shared = PouredHeroExpansion()

    /// The session whose in-list hero is currently open, if any.
    private(set) var openHeroSessionID: String?

    /// Monotonic collapse-request counter. The owning row observes it and
    /// collapses itself; a counter (rather than a flag) means repeated requests
    /// are never swallowed and no view ever writes back into this object during
    /// its own update.
    private(set) var collapseRequests: Int = 0

    init() {}

    func heroDidOpen(sessionID: String) {
        openHeroSessionID = sessionID
    }

    func heroDidClose(sessionID: String) {
        guard openHeroSessionID == sessionID else { return }
        openHeroSessionID = nil
    }

    /// R8 stage 1. Returns `false` when no in-list hero is open, which is the
    /// caller's signal to fall through to stage 2 (close the panel).
    @discardableResult
    func requestCollapse() -> Bool {
        guard openHeroSessionID != nil else { return false }
        collapseRequests &+= 1
        return true
    }
}

/// Pure expansion-state resolver shared by the Poured row's summary and detail
/// branches. Production rows begin collapsed, the harness may force a row open,
/// and actionable approval/question/completion rows auto-expand. Once the user
/// toggles the chevron, that explicit choice wins until interactivity resets it.
enum PouredRowExpansion {
    /// PI-C-006: an actionable row auto-expands into its hero **only where the
    /// board renders a hero** — the dedicated §E/§F notification surface, which
    /// is a 440pt panel holding one session. Inside the grouped §C list the same
    /// permission/question row stays compact (`01-poured-island.html:812-841`),
    /// carrying inline Approve/Deny or an `Answer` chip instead; the hero opens
    /// only on a deliberate gesture (chevron / `Answer`).
    static func resolved(
        isInteractive: Bool,
        expandedByDefault: Bool,
        isActionable: Bool,
        autoExpandsActionable: Bool,
        detailOverride: Bool?
    ) -> Bool {
        guard isInteractive else { return false }
        return detailOverride ?? (expandedByDefault || (isActionable && autoExpandsActionable))
    }

    /// Human fallback for an expanded inactive/aged row after the normal
    /// time-filtered spotlight activity has disappeared. The same resolved
    /// expansion state controls this fallback, so harness-forced and manually
    /// expanded rows behave identically while an explicit collapse stays quiet.
    static func fallbackActivityLine(
        isExpanded: Bool,
        lastAssistantMessage: String?,
        hasJumpTarget: Bool
    ) -> String? {
        guard isExpanded else { return nil }
        let trimmed = lastAssistantMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return hasJumpTarget ? "Ready" : "Completed"
    }
}

/// PI-C-005: what a **collapsed** Poured row narrates on its `.act` line. The
/// board gives every one of the six §C rows an activity line
/// (`01-poured-island.html:818/835/852/868/886/903`), including a 22-minute-old
/// interrupted row — but the shared `spotlightActivityLineText` deliberately
/// falls silent past `collapsedDetailAgeThreshold`, and it hands back raw
/// Markdown for a settled row. Rather than relax that cross-theme contract
/// (Classic / Flight Deck / Halo read it too), Poured resolves its own compact
/// line here.
///
/// Pure and `nonisolated` so the contract is testable off the main actor.
enum PouredCompactActivity {
    /// Preference order:
    /// 1. a **settled** row's own one-line `summary` — already human, already one
    ///    line, and it never ages out (board row 6, `Stopped while editing …`);
    /// 2. the shared spotlight line (a live row's narration);
    /// 3. the last assistant message, flattened to one plain-text line;
    /// 4. the shared `Ready` / `Completed` fallback.
    nonisolated static func text(
        isSettled: Bool,
        summary: String?,
        spotlight: String?,
        lastAssistantMessage: String?,
        hasJumpTarget: Bool
    ) -> String? {
        if isSettled, let settled = plainText(summary) {
            return settled
        }
        if let spotlight = plainText(spotlight) {
            return spotlight
        }
        if let message = plainText(lastAssistantMessage) {
            return message
        }
        return PouredRowExpansion.fallbackActivityLine(
            isExpanded: true,
            lastAssistantMessage: nil,
            hasJumpTarget: hasJumpTarget
        )
    }

    /// One plain line: Markdown emphasis / code fences / list bullets / heading
    /// hashes removed and every whitespace run (including newlines) collapsed, so
    /// a `**bold**` multi-paragraph message can never leak literal asterisks into
    /// a `lineLimit(1)` row.
    nonisolated static func plainText(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let lines = raw.split(whereSeparator: \.isNewline).map { line -> String in
            var trimmed = String(line).trimmingCharacters(in: .whitespaces)
            while let first = trimmed.first, first == "#" || first == ">" {
                trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            for bullet in ["- ", "* ", "+ "] where trimmed.hasPrefix(bullet) {
                trimmed = String(trimmed.dropFirst(bullet.count))
                break
            }
            return trimmed
        }

        var text = lines.filter { !$0.isEmpty }.joined(separator: " ")
        for marker in ["```", "**", "__", "`", "*", "_"] {
            text = text.replacingOccurrences(of: marker, with: "")
        }
        text = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}

/// The glass body for every Poured row. Renders the shared summary / auxiliary
/// chrome (verbatim from Classic so the two rows stay interchangeable inside one
/// list) plus, for actionable rows, the Poured approval / question / completion
/// interiors.
private struct PouredRowContent: View {
    let session: AgentSession
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    let isActionable: Bool
    let isInteractive: Bool
    let isHighlighted: Bool
    let presentation: IslandSessionRowPresentation
    let sideInset: CGFloat
    let lang: LanguageManager
    let actions: RowActions
    let keyboardCoordinator: OverlayUICoordinator?
    let pulseClock: PulseClock?

    @State private var detailOverride: Bool?
    @State private var replyText: String = ""
    /// PI-X-001/H1: the §H rail's `Reply` ghost is a *disclosure* — the inline
    /// field only exists once it has been pressed, and it folds away again with
    /// the hero so a re-opened card is back to the board's four calm controls.
    @State private var isReplyDisclosed = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    /// AB-333: Reduce Transparency flattens the question gold wash to opaque
    /// `surfaceInk` (so text keeps contrast without the translucent amber tint),
    /// mirroring the approval hero's own `reduceTransparency` branch.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Slice 5 (`PI-A11Y-001`): the compact ⇄ hero disclosure was the last
    /// un-gated motion on the Poured row — `toggleDetail` animated
    /// unconditionally. Read here (not inside `PouredApprovalCard`, which has its
    /// own read for the glow) because the row owns `detailOverride`.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// AB-332: list-level duplicate-workspace disambiguators (AB-323), injected
    /// by `IslandPanelView`. Empty (the default) means "no collisions" and the
    /// title line renders the workspace name alone.
    @Environment(\.islandSessionDisambiguators) private var sessionDisambiguators

    /// Harness/debug seam shared with Flight Deck and Halo. Production leaves
    /// this `false`; `subagentsExpanded` sets it so the same ordinary running row
    /// can deliberately render its §4D/§4G detail.
    @Environment(\.islandRowExpandedByDefault) private var expandedByDefault

    /// R4-6: set by `PouredSessionListScaffold` on the first row of each group.
    @Environment(\.pouredRowIsFirstInGroup) private var isFirstRowInGroup

    /// Each row owns its own age refresh (AB-228) so a tick invalidates only
    /// this row, not its siblings or the list header.
    private static let ageRefreshInterval: TimeInterval = 30

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.ageRefreshInterval)) { context in
            rowBody(referenceDate: context.date)
        }
    }

    private func rowBody(referenceDate: Date) -> some View {
        let rawPresence = session.islandPresence(at: referenceDate)
        let isStaleCompleted = session.isStaleCompletedForIsland(
            at: referenceDate,
            threshold: completedStaleThreshold
        )
        let showsDetail = PouredRowExpansion.resolved(
            isInteractive: isInteractive,
            expandedByDefault: expandedByDefault,
            isActionable: isActionable,
            autoExpandsActionable: presentation == .notification,
            detailOverride: detailOverride
        )
        let presence: IslandSessionPresence = isStaleCompleted
            ? .inactive
            : ((showsDetail && rawPresence == .inactive) ? .active : rawPresence)

        return VStack(alignment: .leading, spacing: 0) {
            rowSummary(presence: presence, showsDetail: showsDetail, referenceDate: referenceDate)

            if showsDetail {
                // §4G nested lists always ride at the top of the detail — a
                // fan-out is worth seeing whether the row is an actionable hero
                // or a quiet running session.
                subagentsAndTasksNests(presence: presence)

                if shouldShowEmbeddedDetailBody {
                    // Actionable interiors (approval / question / completion)
                    // are AB-333's to restyle — Poured renders them verbatim
                    // here, with the transcript kept as a footnote beneath.
                    embeddedDetailBody
                        .padding(.leading, detailLeadingInset)
                        .padding(.trailing, sideInset)
                        .padding(.bottom, 13)
                    // A completed row carries its transcript inside the §4H action
                    // rail, so the shared footnote would double it up — only the
                    // approval / question heroes keep the transcript as a footnote.
                    if session.phase != .completed {
                        transcriptFootnote
                    }
                } else {
                    // §4D's metadata grid + assistant prose + action rail use
                    // the same resolved expansion state as the summary rollups
                    // and §4G nests. That state may come from a user toggle or
                    // the harness seam; ordinary production rows remain
                    // collapsed, while actionable heroes take the branch above.
                    sessionDetailBody(presence: presence, referenceDate: referenceDate)
                }
            }
        }
        .background(rowFillColor(for: presence))
        // PI-C-006 (`01-poured-island.html:300-302`, `:830`): inside the list an
        // actionable row is loud through a flat radial wash on the row itself —
        // never a hero sub-card. Amber for a permission, the lower-alpha gold
        // for a question.
        .background(actionableRowWash)
        .overlay(alignment: .top) {
            // R4-6 (`01-poured-island.html:257`): `.row + .row` only — a group
            // header breaks adjacency, so a group's first row draws nothing.
            if !isFirstRowInGroup {
                Rectangle()
                    .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                    .frame(height: 1)
            }
        }
        .overlay(alignment: .leading) {
            if showsLeadingStatusBar {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(statusTint(for: presence))
                    // Poured's leading bar reads as poured light: a soft glow
                    // bleeds off the bar into the glass rather than a hard chip.
                    .shadow(color: statusTint(for: presence).opacity(presence == .inactive ? 0 : 0.5), radius: 4)
                    .frame(width: 3)
                    .padding(.vertical, showsDetail ? 10 : 8)
                    .padding(.leading, 14)
            }
        }
        // Idle / stale rows recede into the material — the same threshold
        // behaviour as Classic, expressed a touch deeper to read as "sunk into
        // the glass".
        .opacity(isStaleCompleted ? 0.62 : 1)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        .animation(.easeInOut(duration: 0.2), value: session.phase)
        .animation(.easeInOut(duration: 0.2), value: session.outcome)
        .animation(.easeInOut(duration: 0.2), value: presence)
        .onTapGesture(perform: handlePrimaryTap)
        // The §H reply disclosure is scoped to one open hero: collapsing the row
        // resets it (and drops any half-typed draft's affordance with it).
        .onChange(of: showsDetail) { _, open in
            if !open { isReplyDisclosed = false }
        }
        .onChange(of: isInteractive) { _, interactive in
            if !interactive {
                detailOverride = nil
                PouredHeroExpansion.shared.heroDidClose(sessionID: session.id)
            }
        }
        // R8 stage 1: something outside the row (the Esc handler) asked the open
        // in-list hero to collapse. Only the row that actually owns the open hero
        // reacts, so a list holding several toggled-open rows collapses the one
        // the user opened last — "the open hero", not all of them.
        .onChange(of: PouredHeroExpansion.shared.collapseRequests) { _, _ in
            guard presentation == .list,
                  detailOverride == true,
                  PouredHeroExpansion.shared.openHeroSessionID == session.id else { return }
            setDetailOpen(false)
        }
        .onDisappear {
            PouredHeroExpansion.shared.heroDidClose(sessionID: session.id)
        }
    }

    // MARK: - Summary

    private func rowSummary(presence: IslandSessionPresence, showsDetail: Bool, referenceDate: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if showsLeadingStatusIndicator {
                statusIndicator(for: presence)
                    .frame(width: 20, alignment: .top)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                // R4-2 (PI-C-006): the row's *narrative* is the grouped stop —
                // title, disambiguator and activity line collapsed into one
                // label carrying the row's traits and its hover-only controls'
                // rotor actions. It no longer swallows the row's controls: the
                // inline Approve / Deny buttons, the `Answer` chip and the
                // `Jump ↗` chip sit beside it as their own accessibility
                // elements (see `rowSummary`'s `children: .contain` below), so
                // the primary affordance of an attention row is reachable by
                // element navigation and not only by the actions rotor.
                VStack(alignment: .leading, spacing: 3) {
                    titleLine(presence: presence, showsDetail: showsDetail)

                    // PI-C-005: the board narrates on **every** row, collapsed or
                    // not (`01-poured-island.html:818/835/852/868/886/903`) — a row
                    // that only prints a workspace name says nothing.
                    activityLine(referenceDate: referenceDate, showsDetail: showsDetail)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityRowSummaryText(referenceDate: referenceDate, showsDetail: showsDetail))
                .modifier(NestedWorkAccessibilityValue(
                    value: nestedWorkAccessibilityValue(isExpanded: showsDetail)
                ))
                .accessibilityAddTraits(isInteractive ? .isButton : [])
                .accessibilityAction {
                    guard isInteractive else { return }
                    actions.jump()
                }
                .accessibilityAction(named: Text(lang.t(showsDetail ? "a11y.session.collapseDetail" : "a11y.session.expandDetail"))) {
                    toggleDetail(currentlyOpen: showsDetail)
                }
                .modifier(PouredOptionalNamedAccessibilityAction(name: actions.dismiss != nil ? lang.t("a11y.session.dismiss") : nil, action: { actions.dismiss?() }))

                metaRow(showsDetail: showsDetail)

                compactActionableAffordances(showsDetail: showsDetail)
            }

            Spacer(minLength: 10)

            // PI-C-005: on a **collapsed** row the trailing column is only
            // `.age` + the chevron + the hover-revealed `.dismiss`
            // (`01-poured-island.html:270`, `:273`) — model, permission mode,
            // nested rollups and SSH / terminal moved into the `.meta` flow row
            // under the activity line, where the board puts them.
            //
            // R2/D2 supersedes R3/C12. The board's §D row is the panel's sole
            // child and its `.body` is the FULL 464pt content width: there is no
            // trailing column at all — no `.age` ("There is no `.age` element in
            // §D", `mapper-reference.md` §4.2), no model / permission / transport
            // chips. Every fact those chips carried is re-stated one block below
            // in the `.meta-grid` (AGENT / MODEL / PERMISSION / BRANCH / LIVE /
            // DIRECTORY), and keeping them here cost `.act` ~46% of its width and
            // truncated the board's own narration to "AppModel.swift · liv…".
            // Only the collapse chevron survives — it is a native affordance the
            // board expresses as "tap the row", and it is the sole way back.
            HStack(spacing: IslandSessionRowMetrics.badgeSpacing) {
                if !showsDetail {
                    Text(ageBadgeText(at: referenceDate))
                        // AB-332: §2 `age` role — SF Pro 11/500 `.monospacedDigit()`
                        // at tertiary. The mono chrome is retired; only the digits
                        // stay tabular so ages line up column-to-column.
                        .font(PouredType.Role.age.font)
                        .foregroundStyle(summaryAgeColor(for: presence))
                        .frame(minWidth: IslandSessionRowMetrics.ageColumnWidth, alignment: .trailing)
                }
                // R4-9 (PI-C-005 · `01-poured-island.html:812-910`): at rest the
                // board's trailing slot holds `.age` and nothing else — every
                // trailing control (`.dismiss`, and by the same root rule the
                // detail chevron) is hover/focus-revealed. Both are dropped from
                // the flow at rest so `.age` actually reaches the panel's trailing
                // inset instead of floating two control widths inside it. The
                // expand/collapse rotor action on the row keeps the chevron's
                // behaviour reachable without a mouse.
                if showsDetail || isHighlighted {
                    detailToggleButton(isOpen: showsDetail)
                }
                // PI-C-006 (`01-poured-island.html:859/874/894/909`): the board
                // puts `.dismiss` on rows 3-6 only. An actionable row's answer is
                // Approve / Deny / Answer, never "make it go away" — the rotor
                // action below still exposes dismiss to VoiceOver.
                if let dismiss = actions.dismiss, !isActionable, isHighlighted {
                    // AB-332: hover-reveal — hidden at rest, fades in on the row's
                    // `isHighlighted` (which never becomes true in `.notification`,
                    // where `actions.dismiss` is nil anyway). The row's grouped
                    // VoiceOver summary already exposes dismiss as a named rotor
                    // action, so it stays reachable while visually hidden.
                    DismissButton(action: dismiss, lang: lang)
                        .opacity(isHighlighted ? PouredRowMotion.Dismiss.revealedOpacity : PouredRowMotion.Dismiss.hiddenOpacity)
                        .accessibilityHidden(true)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            // R4-2: age and the hover-only trailing controls are chrome — the
            // age is already spoken inside the row's narrative label, and both
            // controls survive as named rotor actions on it.
            .accessibilityHidden(true)
        }
        .padding(.leading, rowLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.top, 11)
        .padding(.bottom, showsDetail ? 8 : 11)
        // R4-2 (PI-C-006 · a11y): the row is a *container* now, not one opaque
        // stop. It holds the narrative element built above plus whatever
        // controls the row kind renders (Approve / Deny / Answer / Jump), each
        // with its own label and activation action. The pre-R4 `children:
        // .ignore` here exposed six bare row buttons and nothing nested, so an
        // attention row's primary affordance existed only in the actions rotor.
        .accessibilityElement(children: .contain)
    }

    // MARK: - Meta row (PI-C-005 · mockup `.meta`)

    /// The board's `.meta` flow row (`01-poured-island.html:268`): `gap:10px`,
    /// `margin-top:6px`, wrapping, sitting under `.act` inside the row body.
    /// It carries the row's facts — identity/model, permission mode, nested-work
    /// rollups, transport, the outcome pill and the `Jump ↗` affordance — at the
    /// board's own per-kind ordering. Rendered only while the row is collapsed:
    /// an open row states the same facts in the §D metadata grid below, and the
    /// board never renders both.
    ///
    /// The permission row is the one row with **no** `.meta` at all (board lines
    /// 814-825) — its Approve / Deny pair replaces it.
    @ViewBuilder
    private func metaRow(showsDetail: Bool) -> some View {
        if !showsDetail, !(isActionable && session.phase == .waitingForApproval) {
            let items = metaItems
            if !items.isEmpty {
                PouredFlowLayout(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        item.view
                    }
                }
                // `.meta{margin-top:6px}` less the body stack's own 3pt.
                .padding(.top, 3)
            }
        }
    }

    private struct MetaItem {
        let view: AnyView
    }

    private var metaItems: [MetaItem] {
        var items: [MetaItem] = []
        func add<V: View>(_ view: V) { items.append(MetaItem(view: AnyView(view))) }

        switch session.phase {
        case .waitingForAnswer:
            // Board row 2 (line 836-838): the agent chip, then the gold `Answer`
            // chip that opens the hero.
            add(metaChip(agentIdentityChipLabel, dot: agentBrandColor))
            if isActionable, isInteractive, presentation == .list {
                add(compactAnswerChip)
            }

        case .running, .waitingForApproval:
            // Board rows 3-4 (lines 853-856, 869-872).
            if let model = session.displayModelName {
                add(metaChip(model, dot: agentBrandColor))
            }
            add(permissionModeMetaChip)
            // R2/C4: the subagent count is **identity**, not a fact chip — the
            // board carries it in the `.disamb` (`main · 3 subagents`, line 867)
            // and gives the `.meta` row no subagent chip at all (lines 869-872).
            if let taskRollup = collapsedTaskRollup {
                add(metaChip("⏲ " + lang.t("poured.tasks.chip", taskRollup.done, taskRollup.total)))
            }
            if session.isRemote {
                // R4-10 (`01-poured-island.html:871`): the board's SSH chip leads
                // with a 9×9 filled three-bar glyph, so the transport reads as a
                // shape before it reads as three letters.
                add(metaChip("SSH", leadingBars: true))
            }
            // R2/C5: no terminal-name chip on any compact row (the board's
            // `.meta` rows carry none — lines 853-856 / 869-872 / 887-892 /
            // 904-907); terminal identity stays in the expanded detail grid.
            //
            // R2/C6: `Jump ↗` renders on **local** rows only — board row 3 (a
            // local session) carries it, row 4 (SSH) does not. A remote session
            // has no terminal on this Mac to be sent back to, so the derived
            // rule is `jumpTarget != nil && !isRemote`.
            if session.jumpTarget != nil, !session.isRemote {
                add(jumpChip)
            }

        case .completed:
            // Board rows 5-6 (lines 887-892, 904-907): the outcome pill leads.
            // The identity chip appears only when the run did **not** succeed —
            // that is the board's own split (row 5 carries none, row 6 carries
            // `● cursor`), and it reads as a rule: when something went wrong,
            // *which* agent stopped is worth a glance.
            add(outcomeMetaBadge)
            if session.outcome != .success {
                add(metaChip(agentIdentityChipLabel, dot: agentBrandColor))
            }
            if let duration = completionDurationText {
                add(metaChip(duration))
            }
            // Row 6 carries no `Jump` — an interrupted run is not somewhere the
            // reader is being sent back to.
            if session.outcome == .success, session.jumpTarget != nil, !session.isRemote {
                add(jumpChip)
            }
        }

        return items
    }

    private var agentBrandColor: Color {
        Color(hex: session.tool.brandColorHex) ?? tokens.colors.paper
    }

    /// The board's `.chip` (lines 287-289): 10.5/500 at secondary on a paper@.06
    /// fill, radius 6, padding `2px 7px`, with an optional 6px agent dot at gap 5.
    /// R4-11 (`01-poured-island.html:837`, `:906`): the board's agent-identity
    /// chips read `codex` / `cursor` in lower case — the chip is a quiet fact
    /// beside the workspace title, not a brand mark. Display transform only, and
    /// scoped to this one chip: the model chip (`Opus 4.8`) keeps its casing, as
    /// does every other surface that prints `session.tool.displayName`.
    private var agentIdentityChipLabel: String {
        session.tool.displayName.lowercased()
    }

    private func metaChip(_ title: String, dot: Color? = nil, leadingBars: Bool = false) -> some View {
        HStack(spacing: 5) {
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            if leadingBars {
                PouredTransportBarsGlyph()
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(PouredType.Role.metaChip.font)
                .lineLimit(1)
        }
        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.06))
        )
        // R4-2: a fact chip is not a control. Its content is already inside the
        // row's narrative label, so it stays out of element navigation and the
        // only nested elements the row exposes are its actual affordances.
        .accessibilityHidden(true)
    }

    /// PI-C-005: the board prints the permission mode verbatim as an ordinary
    /// chip (`acceptEdits`, board line 855), so the compact row now surfaces
    /// **every** non-default mode rather than only plan / bypass. `bypass` keeps
    /// its warning treatment — it is not a neutral fact.
    @ViewBuilder
    private var permissionModeMetaChip: some View {
        if let value = permissionModeValueText {
            switch session.claudeMetadata?.permissionMode {
            case .plan:
                metaChip(lang.t("badge.planMode"))
            case .bypassPermissions:
                Text(lang.t("badge.bypassPermissions"))
                    .font(PouredType.Role.metaChip.font)
                    .lineLimit(1)
                    .foregroundStyle(tokens.colors.statusWarning.opacity(0.94))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tokens.colors.statusWarning.opacity(0.16))
                    )
                    .accessibilityHidden(true)
            default:
                metaChip(value)
            }
        }
    }

    private var outcomeMetaBadge: some View {
        // R4-2: the outcome pill states a fact the narrative label already
        // carries — hidden from element navigation like the other meta chips.
        PouredOutcomeBadge(
            glyphName: completionOutcomeGlyphName,
            label: completionOutcomeLabel,
            tint: completionOutcomeTint.opacity(completionDoneOpacity),
            fill: completionOutcomeFill
        )
        .accessibilityHidden(true)
    }

    /// The board's `.jump` chip (lines 280-284): 11.5/600, `padding:3px 9px`,
    /// radius 8, on the same paper@.06 fill as `.chip`, with the trailing arrow.
    /// It fires the row's own jump — the same call the row tap and the ⌘J
    /// shortcut make — using the previously-defined-but-unused `jumpChip` role.
    private var jumpChip: some View {
        Button(action: handlePrimaryTap) {
            HStack(spacing: 6) {
                Text(lang.t("poured.row.jump"))
                    .font(PouredType.Role.jumpChip.font)
                    .lineLimit(1)
                Image(systemName: "arrow.up.forward")
                    .font(PouredType.Role.jumpChip.font)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t("poured.row.jump"))
    }

    // MARK: - Compact attention (PI-C-006 · mockup §C rows 1-2)

    /// What a **collapsed, in-list** actionable row carries instead of the hero
    /// (`01-poured-island.html:812-841`): the permission row's inline
    /// `Approve ⌘Y` / `Deny ⌘N` pair, or the question row's amber `Answer 1–N`
    /// chip. Never both, never in the `.notification` presentation (there the
    /// hero *is* the surface), and never once the row is open.
    @ViewBuilder
    private func compactActionableAffordances(showsDetail: Bool) -> some View {
        if showsCompactApprovalActions(showsDetail: showsDetail) {
            compactApprovalActions
                // `.actions{margin-top:9px}` (board line 819) against the body
                // stack's own 3pt rhythm.
                .padding(.top, 6)
        }
    }

    /// A row is in its compact attention state when it is actionable, in the
    /// list, interactive and closed. The question row's `Answer` chip rides the
    /// `.meta` row instead; only the permission pair sits on its own line.
    private func showsCompactActionable(showsDetail: Bool) -> Bool {
        presentation == .list && isActionable && isInteractive && !showsDetail
    }

    private func showsCompactApprovalActions(showsDetail: Bool) -> Bool {
        showsCompactActionable(showsDetail: showsDetail)
            && session.phase == .waitingForApproval
            && actions.approve != nil
    }

    /// The board's compact `.btn` pair — the same `PouredApprovalButtonLabel` +
    /// `PouredFullSizeButtonStyle` the hero uses, only at the row override
    /// (`padding:6px 12px; font-size:12px`, board lines 820/822). Approve sits
    /// left of Deny, and both fire exactly the callbacks ⌘Y / ⌘N fire, so the
    /// global shortcuts and the visible controls can never disagree.
    ///
    /// **R11 (per-surface verbs), applied here as it is on the §E hero.** The
    /// board's §C row prints `Approve` / `Deny` (lines 819/821) where the hero
    /// prints `Allow once` / `Deny` — two surfaces, two verbs, both rendered
    /// verbatim. Until now this row printed the *agent's* `primaryActionTitle`,
    /// so it read "Approve" only because the C1 fixture happens to say so; a live
    /// Claude request saying "Allow" rendered "Allow". The request's own titles
    /// survive where they carry real information — as the VoiceOver **hint** (E8:
    /// the accessible *name* must be the visible label) — the same split
    /// `PouredApprovalCard.actionButtons` uses.
    private var compactApprovalActions: some View {
        HStack(spacing: 8) {
            Button {
                actions.approve?(.allowOnce)
            } label: {
                PouredApprovalButtonLabel(
                    title: lang.t("poured.approval.approve"),
                    shortcut: .allowOnce,
                    kind: .allow,
                    usesStandaloneChrome: false
                )
            }
            .buttonStyle(PouredFullSizeButtonStyle(kind: .event, isCompact: true))
            // E8: label-in-name — the visible `Approve` is the accessible name;
            // the agent's own verb becomes the hint.
            .accessibilityLabel(lang.t("poured.approval.approve"))
            .modifier(PouredOptionalAccessibilityHint(session.permissionRequest?.primaryActionTitle))

            Button {
                actions.approve?(.deny)
            } label: {
                PouredApprovalButtonLabel(
                    title: lang.t("poured.approval.deny"),
                    shortcut: .deny,
                    kind: .deny,
                    usesStandaloneChrome: false
                )
            }
            .buttonStyle(PouredFullSizeButtonStyle(kind: .deny, isCompact: true))
            // E8: same rule on the compact row.
            .accessibilityLabel(lang.t("poured.approval.deny"))
            .modifier(PouredOptionalAccessibilityHint(session.permissionRequest?.secondaryActionTitle))
        }
    }

    /// The question row's single affordance (board lines 836-838): a `.jump`-class
    /// chip in gold, advertising the digit keys the hero registers. Pressing it is
    /// the **deliberate open** — it flips `detailOverride`, mounting the §F hero
    /// (and with it the `keyboardCoordinator` registration the digits need).
    private var compactAnswerChip: some View {
        Button {
            toggleDetail(currentlyOpen: false)
        } label: {
            HStack(spacing: 6) {
                Text(lang.t("poured.row.answer"))
                    .font(PouredType.Role.jumpChip.font)
                    .lineLimit(1)
                if let glyphs = questionOptionKeycapGlyphs {
                    PouredKeycapRow(
                        glyphs: glyphs,
                        separator: glyphs.count > 1 ? "–" : nil,
                        separatorInk: PouredQuestionColors.answerChipInk
                    )
                }
            }
            .foregroundStyle(PouredQuestionColors.answerChipInk)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PouredQuestionColors.answerChipFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t("poured.row.answer"))
    }

    /// `1`–`N` for an N-option question (board renders `1–3`); a single-option
    /// question advertises just `1`, and a question with no options advertises
    /// nothing rather than an empty range.
    private var questionOptionKeycapGlyphs: [String]? {
        let count = session.questionPrompt?.options.count ?? 0
        guard count > 0 else { return nil }
        return count == 1 ? ["1"] : ["1", "\(count)"]
    }

    /// The flat radial wash an actionable row wears **in the list**
    /// (`.actionable`, board lines 300-302; the question row's own inline
    /// override at line 830 is gold at a lower alpha). Suppressed under Reduce
    /// Transparency / Increase Contrast, where the hero's own wash flattens too.
    @ViewBuilder
    private var actionableRowWash: some View {
        if let tint = actionableRowWashTint {
            EllipticalGradient(
                gradient: Gradient(colors: [tint, tint.opacity(0)]),
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadiusFraction: 0,
                endRadiusFraction: 0.6
            )
        }
    }

    private var actionableRowWashTint: Color? {
        guard presentation == .list, isActionable, !reduceTransparency, !increasesContrast else {
            return nil
        }
        switch session.phase {
        case .waitingForApproval: return PouredApprovalColors.rowWash
        case .waitingForAnswer: return PouredQuestionColors.rowWash
        case .running, .completed: return nil
        }
    }

    // MARK: - Title line (identity tick + workspace + disambiguator)

    /// The mockup's `.title-line` (SPEC §C): a 2pt brand-coloured identity tick,
    /// the workspace name at the `workspaceTitle` role, and — only when a
    /// duplicate workspace name in the list demands it — the T05 branch/recency
    /// disambiguator as a mono span at tertiary. The workspace name yields
    /// (tail-truncates) before the disambiguator, which pins its intrinsic width,
    /// so a long name never squeezes the branch out of view.
    private func titleLine(presence: IslandSessionPresence, showsDetail: Bool = false) -> some View {
        HStack(spacing: 8) {
            identityTick(presence: presence)

            Text(session.spotlightDisplayName)
                .font(PouredType.Role.workspaceTitle.font)
                .tracking(PouredType.Role.workspaceTitle.spec.trackingPoints)
                .foregroundStyle(titleColor(for: presence))
                .lineLimit(1)
                .truncationMode(.tail)

            if let disambiguator = disambiguatorSuffix(showsDetail: showsDetail) {
                Text(disambiguator)
                    .font(PouredType.Role.branchDisambiguator.font)
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    /// The 2×13 brand-colour tick that replaces the capsule agent badge in the
    /// collapsed row. Radius 1, brand hue from `AgentSession.brandColorHex`; it
    /// dims with the row when a stale/inactive row recedes into the glass.
    ///
    /// `height` is overridden by the §H hero, whose in-card title line runs the
    /// same tick one point taller (`height:14px`, `01-poured-island.html:1396`)
    /// against its larger 15pt workspace name.
    private func identityTick(
        presence: IslandSessionPresence,
        height: CGFloat = PouredRowMotion.IdentityTick.height
    ) -> some View {
        RoundedRectangle(cornerRadius: PouredRowMotion.IdentityTick.cornerRadius, style: .continuous)
            .fill(Color(hex: session.tool.brandColorHex) ?? tokens.colors.paper)
            .frame(
                width: PouredRowMotion.IdentityTick.width,
                height: height
            )
            .opacity(presence == .inactive ? 0.7 : 1)
            .accessibilityHidden(true)
    }

    // MARK: - Activity line (T03 narration · mockup `.act`)

    /// The mockup's `.act` line (SPEC §C / §4C): the narrated activity, split so
    /// the verb reads at secondary opacity and the object (file / command / host)
    /// at primary. A running session narrates verb+object via the T03 layer
    /// (`AgentSession.narratedActivity`); every other row speaks a human summary
    /// (permission/question text, last message, outcome) wholly at secondary —
    /// never a raw tool id or a `$ …` command echo.
    ///
    /// D2: on an **open** row the line is the board's §D `.act`, which "carries no
    /// elapsed either — elapsed lives in the `Live` metadata cell"
    /// (`mapper-reference.md` §4.2). `showsDetail` therefore suppresses the
    /// `· live 1m 42s` tail a collapsed §C running row keeps.
    @ViewBuilder
    private func activityLine(referenceDate: Date, showsDetail: Bool = false) -> some View {
        if let ask = actionableAskText() {
            // R2/C1 · C2 (`01-poured-island.html:818`, `:835`): an actionable
            // row's `.act` is the **ask itself**, in the board's own warm ink —
            // never the generic "Ask User" / "Running …" narration the shared
            // spotlight line hands back for the same session.
            ask
                .font(PouredType.Role.activityLine.font)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            let segments = activitySegments(referenceDate: referenceDate, showsDetail: showsDetail)
            if !segments.isEmpty {
                composedActivityText(segments)
                    .font(PouredType.Role.activityLine.font)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// The board's actionable `.act` copy, or `nil` for every non-actionable row.
    ///
    /// - permission (`:818`): `Wants to run ` + the command in `--mono`, the
    ///   whole line `#ffd9a8` at weight 550.
    /// - question (`:835`): the question **text** (byte-identical to the §F
    ///   hero's `.q-text`, which is what makes the row its compact projection),
    ///   in `#fff0cf`.
    private func actionableAskText() -> Text? {
        switch session.phase {
        case .waitingForApproval:
            let ink = PouredApprovalColors.askInk
            guard let command = permissionCommandText else {
                guard let summary = PouredCompactActivity.plainText(session.permissionRequest?.summary)
                    ?? PouredCompactActivity.plainText(session.permissionRequest?.title) else { return nil }
                return Text(verbatim: summary).foregroundStyle(ink)
            }
            return Text(lang.t("poured.row.wantsToRun") + " ").foregroundStyle(ink)
                + Text(verbatim: command)
                    .font(PouredType.Role.commandBlock.font)
                    .foregroundStyle(ink)

        case .waitingForAnswer:
            guard let question = PouredCompactActivity.plainText(
                session.questionPrompt?.questions.first?.question
            ) else { return nil }
            return Text(verbatim: question).foregroundStyle(PouredQuestionColors.askInk)

        case .running, .completed:
            return nil
        }
    }

    /// The bare shell command a permission request is asking about — the board's
    /// `swift build` mono span. Reuses the same preview the §E hero's `$ …` block
    /// reads, so the row and the hero can never disagree about the command.
    private var permissionCommandText: String? {
        guard session.permissionRequest != nil else { return nil }
        return PouredCompactActivity.plainText(session.currentCommandPreviewText)
    }

    /// Tone-split runs for the `.act` line. Running rows narrate verb+object;
    /// the rest fall back to the human activity summary (never the `$` echo,
    /// which lived only in the retired running command block).
    private func activitySegments(referenceDate: Date, showsDetail: Bool) -> [PouredRowActivityTone.Segment] {
        if let narrated = session.narratedActivity {
            return PouredRowActivityTone.segments(
                verb: narrated.localizedVerb(lang),
                object: detailNarrationObject(base: narrated.object, showsDetail: showsDetail),
                fallback: nil,
                liveSuffix: showsDetail
                    ? liveSubagentsSuffix(showsDetail: showsDetail)
                    : liveElapsedSuffix(at: referenceDate)
            )
        }
        // PI-C-005: expansion no longer gates the line — a collapsed row
        // narrates too, through the Poured-local compact resolver.
        return PouredRowActivityTone.segments(
            verb: nil,
            object: nil,
            fallback: PouredCompactActivity.text(
                isSettled: session.phase == .completed,
                summary: settledSummaryText,
                spotlight: session.spotlightActivityLineText,
                lastAssistantMessage: session.lastAssistantMessageText,
                hasJumpTarget: session.jumpTarget != nil
            ),
            liveSuffix: liveSubagentsSuffix(showsDetail: showsDetail)
        )
    }

    /// PI-X-001/G1 (`01-poured-island.html:1286`): an **expanded** fanned-out
    /// row's `.act` reads `Refactoring hook installers · 3 subagents live` — the
    /// nest below states *which* subagents, the line states *how many are still
    /// going*. It rides the same `· ` middot join the `live 1m 42s` tail uses.
    ///
    /// Collapsed rows are untouched: there the fan-out is identity and lives in
    /// the disambiguator (R2/C4, `disambiguatorSuffix`), and the board's §G′ row
    /// carries no such suffix.
    private func liveSubagentsSuffix(showsDetail: Bool) -> String? {
        guard let live = PouredLiveSubagents.liveCount(
            session.claudeMetadata?.activeSubagents ?? [],
            isExpanded: showsDetail
        ) else { return nil }
        return lang.t("poured.subagents.live", live)
    }

    /// X11 (C's M-12): the board's §D `.act` is
    /// `Editing` + ` AppModel.swift · narrating the bridge lifecycle change`
    /// (`01-poured-island.html:940`) — the narrated object **plus** a human
    /// clause saying what the change is about. That clause only exists on the
    /// expanded row: R2/D2 gave §D's `.body` the full 464pt content width, and
    /// with native's bare `Editing AppModel.swift` there was nothing long enough
    /// on screen to show the width fix had actually landed.
    ///
    /// The clause is the session's own one-line `summary` — the field an agent
    /// already fills with "what I am doing" — appended only when it says
    /// something the narration does not already say. The collapsed §C row is
    /// untouched (it has no room, and the board gives it none either).
    private func detailNarrationObject(base: String?, showsDetail: Bool) -> String? {
        guard showsDetail else { return base }
        return PouredDetailNarration.object(
            base: base,
            summary: settledSummaryText.flatMap(PouredCompactActivity.plainText(_:)),
            narratedLine: session.narratedActivityLineText
        )
    }

    /// The session's own one-line `summary`, unless it is merely the phase's
    /// display name (`Completed`), which narrates nothing the state dot doesn't.
    private var settledSummaryText: String? {
        let summary = session.summary.trimmedForRow
        return summary == SessionPhase.completed.displayName ? nil : summary
    }

    /// R2/C3 (`01-poured-island.html:852`): the `· live 1m 42s` tail a running
    /// row hangs off its narration.
    ///
    /// It is spoken **only when the age column reads `now`** — i.e. when the row
    /// was just refreshed and its age can no longer answer "for how long has
    /// this been going?". That is exactly the board's own split: row 3 (`now`)
    /// carries the tail, row 4 (`8m`) does not. Recorded as a derived rule.
    private func liveElapsedSuffix(at referenceDate: Date) -> String? {
        guard session.phase == .running, isJustRefreshed(at: referenceDate) else { return nil }
        let elapsed = referenceDate.timeIntervalSince(session.firstSeenAt)
        guard elapsed >= 1 else { return nil }
        return lang.t("poured.row.live", PouredLiveElapsed.text(seconds: elapsed))
    }

    private func isJustRefreshed(at referenceDate: Date) -> Bool {
        referenceDate.timeIntervalSince(session.islandActivityDate) < 60
    }

    private func composedActivityText(_ segments: [PouredRowActivityTone.Segment]) -> Text {
        let live = tokens.colors.statusRunning
        let secondary = tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity))
        return segments.reduce(Text(verbatim: "")) { accumulated, segment in
            accumulated + Text(verbatim: segment.text)
                .foregroundStyle(segment.tone == .live ? live : secondary)
        }
    }

    /// The bare branch / recency disambiguator for this row, or `nil` when its
    /// workspace name is unique among the visible sessions. Rendered as its own
    /// mono span (no parentheses) — see `PouredRowDisambiguation`.
    ///
    /// D5: an **open** row always carries the branch, whether or not the list
    /// needed it to disambiguate. The board's §D title line renders
    /// `open-vibe-island` `feat/theme-poured` with a single session on screen
    /// (`mapper-reference.md` §4.2/§4.3), so the branch is part of §D's identity
    /// statement, not only the list's duplicate-workspace tie-breaker. The
    /// `.meta-grid`'s BRANCH cell restating it is the board's own redundancy.
    private func disambiguatorSuffix(showsDetail: Bool = false) -> String? {
        // R2/C4 (`01-poured-island.html:866-867`): when a row is fanned out into
        // subagents, the board composes the disambiguator as
        // `<branch> · <N> subagents` — the fan-out is part of *which* row this
        // is, not a fact chip beside it. Reuses the same localized count string
        // the expanded §4G nest header speaks.
        //
        // C4-4 (PI-X-001/G1 · review round 1): **collapsed only**. The board's
        // §G *expanded* frame prints the title-line disambiguator as `main`
        // alone (`01-poured-island.html:1284-1286`) — once the row is open the
        // fan-out is stated twice below it, by the `.act` line
        // (`· 3 subagents live`) and by the nest header (`3 subagents`), so a
        // third copy on the title line is redundancy the board never draws. The
        // compressed composition above is untouched (it is under owner
        // escalation E2).
        var base = PouredRowDisambiguation.suffix(sessionDisambiguators[session.id])
        if base == nil, showsDetail, let branch = SessionDisambiguation.branch(for: session) {
            base = PouredRowDisambiguation.suffix(SessionDisambiguation.displayBranch(branch))
        }
        guard !showsDetail, let subagentCount = collapsedSubagentCount else { return base }
        let fanOut = lang.t("poured.subagents.count", subagentCount)
        guard let base else { return fanOut }
        return base + " \u{00B7} " + fanOut
    }

    // MARK: - Subagents & tasks nests (§4G · mockup §G)

    /// The expanded §4G nests: a subagent sub-list with live `M:SS` timers and
    /// the Claude todo list with real done/doing/pending state — each wrapped in
    /// a quiet "nest" slab (mockup `.nest`, an inset-hairline card) so the
    /// fan-out reads as one grouped surface rather than loose rows.
    @ViewBuilder
    private func subagentsAndTasksNests(presence: IslandSessionPresence) -> some View {
        if let subagents = session.claudeMetadata?.activeSubagents, !subagents.isEmpty {
            subagentNest(subagents)
                .padding(.leading, detailLeadingInset)
                .padding(.trailing, sideInset)
                .padding(.bottom, 10)
        }

        if let tasks = session.claudeMetadata?.activeTasks, !tasks.isEmpty {
            taskNest(tasks)
                .padding(.leading, detailLeadingInset)
                .padding(.trailing, sideInset)
                .padding(.bottom, 10)
        }
    }

    private func subagentNest(_ subagents: [ClaudeSubagentInfo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // PI-X-001/G1 (`01-poured-island.html:1289`): the board's nest
                // header leads with the three-bar `.glyph.run` at `10×11`, not
                // an SF branch icon — the fan-out is *live work*, and the run
                // glyph is the theme's own word for that.
                PouredRunBarsGlyph(
                    tint: tokens.colors.statusRunning,
                    height: PouredRunGlyphMetrics.nestHeaderHeight
                )
                .frame(width: 10, alignment: .leading)
                Text(pouredUppercased(lang.t("poured.subagents.count", subagents.count)))
                    .font(PouredType.Role.nestHeader.font)
                    .tracking(PouredType.Role.nestHeader.spec.trackingPoints)
            }
            .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
            .padding(.horizontal, 9)
            .padding(.top, 7)
            .padding(.bottom, 4)

            ForEach(Array(subagents.enumerated()), id: \.element.agentID) { index, sub in
                if index > 0 {
                    Rectangle()
                        .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                        .frame(height: 1)
                }
                subagentRow(sub)
            }
        }
        .background(nestBackground)
    }

    private func subagentRow(_ sub: ClaudeSubagentInfo) -> some View {
        let isRunning = sub.summary == nil
        return HStack(spacing: 10) {
            Circle()
                .fill(isRunning ? tokens.colors.statusRunning : tokens.colors.statusCompleted)
                .frame(width: 6, height: 6)
                .accessibilityLabel(lang.t(isRunning ? "a11y.subagent.running" : "subagents.completed"))

            VStack(alignment: .leading, spacing: 1) {
                Text(sub.agentType ?? sub.agentID)
                    .font(PouredType.Role.subagentType.font)
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.96)))
                    .lineLimit(1)
                if let desc = sub.taskDescription?.trimmedForRow, !desc.isEmpty {
                    Text(desc)
                        .font(PouredType.Role.subagentTask.font)
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 6)

            subagentTiming(sub, isRunning: isRunning)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func subagentTiming(_ sub: ClaudeSubagentInfo, isRunning: Bool) -> some View {
        let elapsedColor = tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
        if isRunning, let started = sub.startedAt {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(PouredSubagentTiming.clockLabel(
                    seconds: Int(timeline.date.timeIntervalSince(started))
                ))
                .font(PouredType.Role.subagentElapsed.font)
                .foregroundStyle(elapsedColor)
            }
        } else if !isRunning {
            Text(lang.t("subagents.completed"))
                .font(PouredType.Role.subagentElapsed.font)
                .foregroundStyle(elapsedColor)
        }
    }

    private func taskNest(_ tasks: [ClaudeTaskInfo]) -> some View {
        let rollup = PouredTaskRollup(statuses: tasks.map(\.status))
        return VStack(alignment: .leading, spacing: 0) {
            Text(pouredUppercased(lang.t("poured.tasks.header", rollup.done, rollup.total)))
                .font(PouredType.Role.nestHeader.font)
                .tracking(PouredType.Role.nestHeader.spec.trackingPoints)
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
                .padding(.horizontal, 9)
                .padding(.top, 7)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(tasks) { task in
                    taskRow(task)
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 8)
        }
        .background(nestBackground)
    }

    private func taskRow(_ task: ClaudeTaskInfo) -> some View {
        HStack(spacing: 8) {
            taskStatusIcon(task.status)
                .frame(width: 14, height: 14)

            Text(task.title)
                .font(PouredType.Role.todo.font)
                .foregroundStyle(taskTitleColor(task.status))
                .strikethrough(task.status == .completed)
                .lineLimit(1)
                .truncationMode(.tail)

            if task.status == .inProgress {
                Spacer(minLength: 6)
                Text(lang.t("poured.tasks.doing"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.colors.statusRunning)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func taskTitleColor(_ status: ClaudeTaskInfo.Status) -> Color {
        switch status {
        case .completed:
            tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
        case .inProgress:
            tokens.colors.paper.opacity(contrastText(0.96))
        case .pending:
            tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity))
        }
    }

    private var nestBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.025))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1)
            )
    }

    /// Collapsed-row rollup counts (mockup §G′): only present when there is real
    /// nested work to summarise, so a plain row invents nothing.
    private var collapsedSubagentCount: Int? {
        guard let subagents = session.claudeMetadata?.activeSubagents, !subagents.isEmpty else {
            return nil
        }
        return subagents.count
    }

    private var collapsedTaskRollup: PouredTaskRollup? {
        guard let tasks = session.claudeMetadata?.activeTasks, !tasks.isEmpty else {
            return nil
        }
        return PouredTaskRollup(statuses: tasks.map(\.status))
    }

    private func nestedWorkAccessibilityValue(isExpanded: Bool) -> String? {
        NestedWorkAccessibility.value(
            activeSubagentCount: collapsedSubagentCount ?? 0,
            completedTaskCount: collapsedTaskRollup?.done ?? 0,
            totalTaskCount: collapsedTaskRollup?.total ?? 0,
            isExpanded: isExpanded,
            lang: lang
        )
    }

    // MARK: - Session detail body (§4D · mockup §D)

    /// The quiet expanded detail for a non-actionable row: the metadata cell
    /// grid, the last assistant message as rich prose, and the action rail
    /// (jump-primary + transcript ghost + pane-attachment chip). Actionable rows
    /// route to `embeddedDetailBody` (AB-333) instead and never reach here.
    @ViewBuilder
    private func sessionDetailBody(presence: IslandSessionPresence, referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            metadataGrid(presence: presence, referenceDate: referenceDate)

            if let message = lastAssistantMessageForDetail {
                assistantMessageCard(message)
                    .padding(.top, 10)
            }

            detailActionRail
                .padding(.top, 12)
        }
        .padding(.leading, detailLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.bottom, 13)
    }

    // MARK: - Metadata grid (§4D · mockup `.meta-grid`)

    /// The mockup's calm cell grid. Each cell is a key (10pt uppercase tertiary,
    /// lifted to the Poured floor) over a 12.5 value. Absent fields render
    /// **nothing** — no `—` dashes (BRIEF §1.3): Model appears only with a
    /// resolved model name, Permission / Branch only for Claude, Live only while
    /// running, Directory only with a working directory.
    private func metadataGrid(presence: IslandSessionPresence, referenceDate: Date) -> some View {
        PouredFlowLayout(spacing: 8) {
            metadataCell(
                key: lang.t("poured.detail.meta.agent"),
                spokenValue: session.tool.displayName
            ) {
                agentIdentityChip
            }

            if let model = session.displayModelName {
                metadataTextCell(key: lang.t("poured.detail.meta.model"), value: model)
            }

            if let permission = permissionModeValueText {
                metadataTextCell(key: lang.t("poured.detail.meta.permission"), value: permission)
            }

            if let branch = SessionDisambiguation.branch(for: session) {
                metadataTextCell(
                    key: lang.t("poured.detail.meta.branch"),
                    value: SessionDisambiguation.displayBranch(branch),
                    mono: true
                )
            }

            if session.phase == .running {
                // D3: the board's LIVE cell reads `1m 42s` at second precision
                // (`mapper-reference.md` §4.3/§4.5), not the age column's coarse
                // `1m`. `PouredLiveElapsed` is the same formatter the §C row's
                // `· live 1m 42s` tail uses, so the two can never disagree —
                // `elapsedRunningLabel` floors to whole minutes and printed "1m".
                metadataTextCell(
                    key: lang.t("poured.detail.meta.live"),
                    value: PouredLiveElapsed.text(
                        seconds: referenceDate.timeIntervalSince(session.firstSeenAt)
                    ),
                    tabular: true
                )
            }

            if let directory = directoryDisplayText {
                metadataTextCell(
                    key: lang.t("poured.detail.meta.directory"),
                    value: directory,
                    mono: true
                )
            }
        }
        .padding(.top, 11)
    }

    private func metadataTextCell(key: String, value: String, mono: Bool = false, tabular: Bool = false) -> some View {
        let baseFont = mono ? PouredType.Role.metadataValueMono.font : PouredType.Role.metadataValue.font
        return metadataCell(key: key, spokenValue: value) {
            Text(value)
                .font(tabular ? baseFont.monospacedDigit() : baseFont)
                .foregroundStyle(metadataValueColor)
                .lineLimit(1)
                .truncationMode(mono ? .middle : .tail)
        }
    }

    /// D6 (PI-A11Y-001): every `.mcell` is **one** accessibility element reading
    /// `"<key>, <value>"` ("Agent, Claude Code"). Before this the grid exposed the
    /// uppercase key and its value as two separate stops per cell — twelve stops
    /// for the board's six facts, and the key's `.uppercased()` chrome was spoken
    /// as its own word.
    private func metadataCell<Content: View>(
        key: String,
        spokenValue: String,
        @ViewBuilder value: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pouredUppercased(key))
                .font(PouredType.Role.metadataKey.font)
                .tracking(PouredType.Role.metadataKey.spec.trackingPoints)
                .foregroundStyle(metadataKeyColor)
            value()
        }
        .modifier(MetadataCellChrome())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PouredMetadataCellCopy.accessibilityLabel(key: key, value: spokenValue))
    }

    /// The dot+label agent chip that resurfaces the agent's full identity in the
    /// grid — the whisper of §7 becomes a plain statement once the row is open.
    private var agentIdentityChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: session.tool.brandColorHex) ?? tokens.colors.paper)
                .frame(width: 7, height: 7)
            Text(session.tool.displayName)
                .font(PouredType.Role.metadataValue.font)
                .foregroundStyle(metadataValueColor)
                .lineLimit(1)
        }
    }

    private var metadataKeyColor: Color {
        tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
    }

    private var metadataValueColor: Color {
        tokens.colors.paper.opacity(contrastText(0.96))
    }

    /// Claude-only permission mode, surfaced verbatim (`acceptEdits`, `plan`,
    /// `bypassPermissions`). The implicit `.default` mode carries no information,
    /// so it renders nothing rather than a noisy "default" cell.
    private var permissionModeValueText: String? {
        guard session.tool == .claudeCode,
              let mode = session.claudeMetadata?.permissionMode,
              mode != .default else {
            return nil
        }
        return mode.rawValue
    }

    /// Home-abbreviated, middle-truncated working directory (mockup
    /// `~/…/open-vibe-island`). `nil` when the session carries no directory.
    private var directoryDisplayText: String? {
        guard let raw = session.jumpTarget?.workingDirectory?.trimmedForRow, !raw.isEmpty else {
            return nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var abbreviated = raw
        if raw == home {
            abbreviated = "~"
        } else if raw.hasPrefix(home + "/") {
            abbreviated = "~" + raw.dropFirst(home.count)
        }
        return ActivityNarrator.middleTruncated(abbreviated, maxLength: 34)
    }

    // MARK: - Last assistant message (§4D · mockup `.assistant`)

    /// The last assistant message rendered as rich prose (Markdown + the
    /// `.pouredAssistant` style — D1: 12.5/400 at `paper@0.66`, `+4pt` leading,
    /// `**strong**` lifted to 0.96/640 and inline `code` on the board's
    /// `white@.06` / `#c9d3e6` 11pt chip) — never the raw single-line dump the
    /// shipped detail echoed, and no longer `.completionCard`'s 13.5/medium
    /// borrow. Capped in an `AutoHeightScrollView` so a long message can't run
    /// the row off the panel.
    private func assistantMessageCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // The board's `.amh` byline reads `Last message · Claude`
            // (`01-poured-island.html:953`) — the agent's concise vendor name,
            // not the full product name the AGENT metadata cell carries
            // (`Claude Code`, `:944`). `shortName` is that concise form.
            Text(pouredUppercased(lang.t("poured.detail.lastMessage", session.tool.shortName)))
                .font(PouredType.Role.assistantLabel.font)
                .tracking(PouredType.Role.assistantLabel.spec.trackingPoints)
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))

            AutoHeightScrollView(maxHeight: 150) {
                LocalMarkdownText(message, style: .pouredAssistant, colors: assistantInkColors)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.045), lineWidth: 1)
                )
        )
    }

    /// X12 (D's F-08): the board's §D `.assistant` block is **paper** ink at
    /// fractional alpha — body `rgba(242,245,251,.66)`, `strong`
    /// `rgba(242,245,251,.96)` (`01-poured-island.html:433,437`) — the same
    /// `#f2f5fb` the `.mv` metadata values already resolve from. The shared
    /// `LocalMarkdownText` renderer takes its ink from `colors.surfaceText`,
    /// which every theme's token table sets to pure `.white`, so the r2 report's
    /// "paper@0.66" claim was true of the *opacity* and false of the *base*.
    ///
    /// Fixed by handing the renderer a Poured-local token copy whose
    /// `surfaceText` **is** paper, rather than editing the shared style table —
    /// so Halo's, Flight Deck's and Classic's assistant blocks are byte-identical.
    private var assistantInkColors: IslandColorTokens {
        var colors = tokens.colors
        colors.surfaceText = colors.paper
        return colors
    }

    private var lastAssistantMessageForDetail: String? {
        guard let text = session.lastAssistantMessageText?.trimmedForRow, !text.isEmpty else {
            return nil
        }
        return text
    }

    // MARK: - Detail action rail (§4D · mockup `.actions`)

    /// Jump-to-terminal as the primary CTA (a blue gradient button, mockup §D),
    /// the transcript as a ghost affordance, and the pane-attachment chip pushed
    /// to the trailing edge.
    private var detailActionRail: some View {
        // Board `.actions{display:flex; gap:8px; margin-top:12px}` (L346) — the
        // §D button row is measured at an 8px gap (`mapper-reference.md` §4.5),
        // the same `.actions` rule §E's Allow/Deny pair already uses.
        HStack(spacing: 8) {
            Button(action: handlePrimaryTap) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward")
                        .accessibilityHidden(true)
                    Text(lang.t("poured.detail.jump"))
                        .lineLimit(1)
                }
            }
            .buttonStyle(PouredFullSizeButtonStyle(kind: .detailPrimary))
            .accessibilityLabel(lang.t("poured.detail.jump"))

            if let transcriptPath = trimmedTranscriptPath {
                // D4: the board's `.btn.ghost` fill (rgba(242,245,251,.08), r11,
                // 32pt), not the 0.4-opacity text form that read as disabled.
                TranscriptAffordance(
                    path: transcriptPath,
                    workspace: session.spotlightWorkspaceName,
                    lang: lang,
                    pouredGhost: true
                )
            }

            Spacer(minLength: 8)

            attachmentChip
        }
    }

    /// `Pane attached` (green dot) / `Pane stale` / `Detached` from
    /// `attachmentState` — AB-332 is the first surface to render this field.
    private var attachmentChip: some View {
        let chip = PouredAttachmentChip(session.attachmentState)
        let label = lang.t(chip.localizationKey)
        // Board `.chip` (L286-287): `padding:2px 7px; border-radius:6px;
        // background:rgba(242,245,251,.06); color:var(--t2); gap:5px` at 10.5/500
        // — the same recipe `metaChip` already draws, not a capsule. The dot is
        // §D's own inline 9×9 `--done` circle (L971), wider than `.chip .cd`'s
        // 6px, so it is not folded into `metaChip`.
        return HStack(spacing: 5) {
            Circle()
                .fill(chip.isLive ? tokens.colors.statusCompleted : tokens.colors.paper.opacity(0.3))
                .frame(width: 9, height: 9)
            Text(label)
                .font(PouredType.Role.metaChip.font)
                .lineLimit(1)
        }
        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    /// The transcript kept as a footnote beneath an actionable hero (approval /
    /// question / completion), where it can't ride the §4D action rail.
    @ViewBuilder
    private var transcriptFootnote: some View {
        if let transcriptPath = trimmedTranscriptPath {
            TranscriptAffordance(
                path: transcriptPath,
                workspace: session.spotlightWorkspaceName,
                lang: lang
            )
            .padding(.leading, detailLeadingInset)
            .padding(.trailing, sideInset)
            .padding(.bottom, 10)
        }
    }

    private var trimmedTranscriptPath: String? {
        guard let path = session.trackingTranscriptPath?.trimmedForRow, !path.isEmpty else {
            return nil
        }
        return path
    }

    // MARK: - Embedded detail body (actionable interiors)

    /// Attention phases always earn the body; a completed row only when it's the
    /// actionable card with something to show. A **running** row no longer earns
    /// an embedded body — its activity is narrated in the `.act` line above, and
    /// the shipped boxed `$ command` echo (a raw preview the Poured direction
    /// explicitly bans) is retired with it (AB-332 · SPEC §C). The permission /
    /// question / completion interiors are stage 2's to restyle.
    private var shouldShowEmbeddedDetailBody: Bool {
        if session.phase.requiresAttention {
            return true
        }
        if session.phase == .completed {
            return isActionable && completionHasExpandedBody
        }
        return false
    }

    @ViewBuilder
    private var embeddedDetailBody: some View {
        switch session.phase {
        case .waitingForApproval:
            PouredApprovalCard(
                session: session,
                lang: lang,
                actions: actions,
                pulseClock: pulseClock,
                presentation: presentation
            )
        case .waitingForAnswer:
            questionActionBody
        case .completed:
            completionActionBody
        case .running:
            // Running rows narrate in `.act`; no boxed command echo (see above).
            EmptyView()
        }
    }

    // MARK: - Question action area

    /// The T07 shared interior (`StructuredQuestionPromptView`) wrapped in the
    /// Poured `.q-hero` gold chrome (`SPEC` §4F · mockup `.q-hero`): a gold-tinted
    /// vertical wash (`rgba(52,44,22,.4)→rgba(26,22,12,.5)`) under a 1pt inset
    /// `rgba(255,213,138,.24)` ring at radius 18. The interior's semantics are
    /// untouched — the gold header (`statusWaitingForAnswer` = `#ffd58a`) and the
    /// `1.5pt rgba(255,213,138,.5)` selection ring are already token-driven inside
    /// the shared view (AB-325), and the digit-select / Enter keyboard wiring keeps
    /// flowing through `keyboardCoordinator` exactly as before. Under Reduce
    /// Transparency the wash flattens to opaque `surfaceInk` so the amber tint can
    /// never erode the option text's contrast.
    @ViewBuilder
    private var questionActionBody: some View {
        let interior = StructuredQuestionPromptView(
            prompt: session.questionPrompt,
            lang: lang,
            keyboardCoordinator: keyboardCoordinator,
            headContext: pouredQuestionHeadContext,
            onAnswer: { actions.answer?($0) }
        )

        if isCompactQuestion {
            // F″ is bare glass (`01-poured-island.html:1248-1256`): the board draws
            // no `.q-hero` gradient card and no inset ring for the compact single —
            // the gold tint comes from the row's own radial wash. Only the wrapper
            // is dropped; the interior and its digit/Enter registration stay intact.
            interior
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // B4 · the `.q-hero` inset, split explicitly.
            //
            // The board's hero is `padding:14px 16px 15px` (`.q-hero`, L379-381).
            // The shared interior already applies its own `10 / 8` for Poured and is
            // owned by another part this round, so the wrapper contributes the
            // remainder — 6 horizontal, 6 top, 7 bottom — and the two halves sum to
            // the board's numbers exactly. Documented rather than folded together so
            // a later round that zeroes the interior padding knows to move 10/8 here
            // rather than re-deriving the inset.
            interior
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .padding(.bottom, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(questionHeroWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(PouredQuestionColors.ring, lineWidth: 1)
                )
            // Y6, honoured: `.q-hero` has NO pulse variant anywhere in the board's
            // stylesheet and §F contains no CSS animation at all — no
            // `PouredAmberGlow`, no breathing ring, no clock is acquired here. The
            // asymmetry against §E's `heropulse` is the board's, and it is kept.
        }
    }

    /// F″ (`01-poured-island.html:1245-1256`): the board's compact single-question
    /// frame — one non-multi question, two option-only Yes/No choices. Derived from
    /// the prompt's shape, exactly as `PouredCompactQuestionLayout` selects the
    /// compact interior itself (`IslandPanelView.swift`), so a live agent prompt
    /// reaches it without anyone wiring a per-frame flag.
    private var isCompactQuestion: Bool {
        PouredCompactQuestionLayout.applies(to: session.questionPrompt?.questions ?? [])
    }

    /// The `.q-head`'s workspace span (`[dot] niche-radar`), or `nil` where the
    /// board draws none.
    ///
    /// The board carries it on §F only. F′ renders `[TARGETS] ——— Select all
    /// that apply` with "**no workspace tag, no 'Question x of y'**"
    /// (`01-poured-island.html:1218-1219`), and F″'s head is the chip and the
    /// sentence alone (`:1248-1249`). The span therefore rides with the
    /// *paginated* progress readout, and a prompt holding a single question has
    /// neither — which is exactly the shape of both frames that drop it, and is
    /// derived from the prompt rather than from a per-frame flag for the same
    /// reason `PouredCompactQuestionLayout` is (`IslandPanelView.swift:2930`):
    /// a live agent prompt reaches these states without anyone wiring a case.
    /// Neither fact lives on `QuestionPrompt`, so the hero — which owns the
    /// session — injects them through Part A's seam.
    private var pouredQuestionHeadContext: QuestionPromptHeadContext? {
        guard let prompt = session.questionPrompt, prompt.questions.count > 1 else { return nil }
        return QuestionPromptHeadContext(
            workspaceName: session.spotlightDisplayName,
            brandColor: Color(hex: session.tool.brandColorHex) ?? tokens.colors.paper
        )
    }

    @ViewBuilder
    private var questionHeroWash: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if reduceTransparency || increasesContrast {
            shape.fill(tokens.colors.surfaceInk)
        } else {
            shape.fill(
                LinearGradient(
                    colors: [PouredQuestionColors.washTop, PouredQuestionColors.washBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Completion action area

    /// The completion card, rebuilt to `SPEC` §4H (mockup §H): a tinted-pill
    /// outcome badge with tabular duration + `finished … ago`, the result as rich
    /// prose (the shared `.completionCard` Markdown path — `<strong>` + inline
    /// `code`), the reply input where supported, and a calm action rail (Jump
    /// primary, Transcript / Dismiss ghosts). The badge now renders for **every**
    /// outcome — `Success` too — so a clean completion is as legible as a failed
    /// one; the markdown / link / code colours still resolve from
    /// `.completionCard(tokens.colors)` and the reply stays wired to
    /// `actions.reply` exactly as Classic.
    ///
    /// R14 board conformance (PI-X-001/H1, `01-poured-island.html:1389-1429`):
    /// the card is one padded block (`14px 16px 12px`), not a divided stack —
    /// a 30×30 tinted outcome tile beside the in-card title line and its
    /// `<model> · finished Xm ago` sub-line, the result under a `Result` kicker,
    /// then a footer meta strip (`⏱ 43m duration` · `● Claude Code`) and the
    /// action rail. Duration moved out of the header into that footer; the reply
    /// field is disclosed by the rail's `Reply` ghost rather than always shown.
    private var completionActionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            completionHeroHeader
                .padding(.bottom, 10)

            if !completionMessageText.trimmedForRow.isEmpty {
                completionResultBlock
            }

            completionFooterMeta
                .padding(.top, 12)

            completionActionRail
                .padding(.top, 12)

            if isReplyDisclosed, actions.reply != nil {
                completionReplyInput
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.09))
        )
    }

    private var completionHasExpandedBody: Bool {
        // Every completed actionable row now earns the expanded card — the
        // outcome badge + action rail are always worth showing, and a non-success
        // outcome must never be indistinguishable from a plain "Completed" row.
        true
    }

    private var completionDoneOpacity: Double {
        presentation == .notification ? 0.82 : 0.96
    }

    /// §4H header (`01-poured-island.html:1390-1403`): the tinted outcome tile,
    /// the in-card identity line, its model / finished-ago sub-line, and the
    /// outcome badge pinned to the trailing edge.
    private var completionHeroHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            completionOutcomeTile

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    identityTick(presence: .active, height: 14)

                    Text(session.spotlightDisplayName)
                        .font(PouredType.Role.completionHeaderTitle.font)
                        .tracking(PouredType.Role.completionHeaderTitle.spec.trackingPoints)
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(completionDoneOpacity)))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let disambiguator = disambiguatorSuffix(showsDetail: true) {
                        Text(disambiguator)
                            .font(PouredType.Role.branchDisambiguator.font)
                            .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text(completionHeroSublineText)
                    .font(PouredType.Role.heroSubtitle.font)
                    .monospacedDigit()
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PouredOutcomeBadge(
                glyphName: completionOutcomeGlyphName,
                label: completionOutcomeLabel,
                tint: completionOutcomeTint.opacity(completionDoneOpacity),
                fill: completionOutcomeFill,
                isHero: true
            )
        }
    }

    /// The board's 30×30 radius-9 outcome tile (`:1391-1394`): the outcome's own
    /// tinted fill — the same `.outcome.ok/.intr/.fail` alpha the badge wears —
    /// under the outcome glyph at 16pt. State is glyph + colour, never colour
    /// alone; the badge beside it already speaks the word, so the tile is chrome.
    private var completionOutcomeTile: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(completionOutcomeFill)
            .frame(width: 30, height: 30)
            .overlay(
                Image(systemName: completionOutcomeGlyphName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(completionOutcomeTint.opacity(completionDoneOpacity))
            )
            .accessibilityHidden(true)
    }

    /// `Fable 5 · finished 12m ago` (`:1399`) — the model the §C compact row
    /// prints in its chip, joined to the row's own finished-ago vocabulary. A
    /// session with no model metadata drops the segment *and* the middot.
    private var completionHeroSublineText: String {
        PouredCompletionSubline.text(
            model: session.displayModelName,
            finishedAgo: lang.t("poured.completion.finishedAgo", session.spotlightAgeBadge)
        )
    }

    /// The result prose under the board's `Result` kicker (`.assistant .amh`,
    /// `:1406`) — the §D assistant slab's chrome **and its prose style**, reused
    /// so the two prose blocks read as one component.
    ///
    /// C4-1 (PI-X-001/H1 · review round 1): the renderer used to take the
    /// default `.completionCard` style (13.5/medium at 0.88 ink, no strong lift,
    /// no inline-code chip) while §D's identical slab already passed
    /// `.pouredAssistant`. The board draws **one** `.assistant` rule for both
    /// (`01-poured-island.html:433-441`): 12.5/400 at `paper@.66`, `**strong**`
    /// lifted to `.96`/640, inline `code` on a `white@.06` 4px chip in `#c9d3e6`.
    /// The style — and `assistantInkColors`, the Poured-local paper-ink token
    /// copy the §D slab hands the shared renderer — are now shared too.
    private var completionResultBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pouredUppercased(lang.t("poured.completion.result")))
                .font(PouredType.Role.assistantLabel.font)
                .tracking(PouredType.Role.assistantLabel.spec.trackingPoints)
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))

            AutoHeightScrollView(maxHeight: 160) {
                LocalMarkdownText(completionMessageText, style: .pouredAssistant, colors: assistantInkColors)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.045), lineWidth: 1)
                )
        )
    }

    /// The board's footer meta strip (`:1413-1418`): `⏱ 43m duration` and the
    /// agent's own dot + display name, `gap:14px` at 11pt tertiary. Duration is
    /// derived from `firstSeenAt → updatedAt` (the run's own length, frozen at
    /// completion, so it never drifts with wall-clock time) and is shown only
    /// when the run actually lasted a minute or more.
    private var completionFooterMeta: some View {
        HStack(spacing: 14) {
            if let duration = completionDurationText {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .medium))
                        .accessibilityHidden(true)
                    Text(lang.t("poured.completion.duration", duration))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(agentBrandColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(session.tool.displayName)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .font(PouredType.Role.heroSubtitle.font)
        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
        // R4-2: the strip restates facts the row's narrative label already
        // carries — a fact line, not a control.
        .accessibilityHidden(true)
    }

    /// Run length (`43m`), or `nil` for a sub-minute run where a duration chip
    /// would read as noise.
    private var completionDurationText: String? {
        let seconds = session.updatedAt.timeIntervalSince(session.firstSeenAt)
        guard seconds >= 60 else { return nil }
        return session.elapsedRunningLabel(at: session.updatedAt)
    }

    /// §4H action rail (`01-poured-island.html:1421-1428`): Jump primary, then
    /// the `Reply` / `Transcript` ghosts, then `Dismiss` right-aligned at
    /// tertiary ink. The transcript rides here (not the shared footnote) for
    /// completed rows, so it isn't shown twice.
    private var completionActionRail: some View {
        HStack(spacing: 8) {
            Button(action: handlePrimaryTap) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward")
                        .accessibilityHidden(true)
                    Text(lang.t("poured.detail.jump"))
                        .lineLimit(1)
                }
            }
            .buttonStyle(PouredFullSizeButtonStyle(kind: .wayfinding))
            .accessibilityLabel(lang.t("poured.detail.jump"))

            // The board's `Reply` is a ghost *button* (`:1426`), not a standing
            // text field: it discloses the field in place. The field, its send
            // button and the keyboard semantics are unchanged — only their entry
            // point moved, so a completed card at rest is a rail of four calm
            // controls instead of a rail plus an empty input.
            if actions.reply != nil, !isReplyDisclosed {
                Button {
                    isReplyDisclosed = true
                } label: {
                    Text(lang.t("poured.completion.reply"))
                        .lineLimit(1)
                }
                .buttonStyle(PouredFullSizeButtonStyle(kind: .ghost))
                .accessibilityLabel(lang.t("poured.completion.reply"))
            }

            if let transcriptPath = trimmedTranscriptPath {
                completionTranscriptButton(path: transcriptPath)
            }

            Spacer(minLength: 8)

            if let dismiss = actions.dismiss {
                Button(action: dismiss) {
                    Text(lang.t("poured.completion.dismiss"))
                        .lineLimit(1)
                }
                // C4-3: the same ghost chip, its label dropped to `--t3`
                // (`01-poured-island.html:1428`).
                .buttonStyle(PouredFullSizeButtonStyle(kind: .ghost, isDimmed: true))
                .accessibilityLabel(lang.t("a11y.session.dismiss"))
            }
        }
    }

    /// C4-3 (PI-X-001/H1 · `01-poured-island.html:1427`): §H's `Transcript` is a
    /// plain `.btn.ghost` — the *same* chip as `Reply` beside it, and with **no**
    /// document glyph: the board draws one only in §D's rail (`:967`), never
    /// here. Native rendered it as `TranscriptAffordance`'s bare 10.5pt / 0.4-ink
    /// text form, which inverted the rail's weights — the throwaway `Dismiss`
    /// looked like the live control and `Transcript` like a disabled one.
    ///
    /// §D's rail is untouched: it keeps the shared affordance in its Poured
    /// ghost mode, glyph and all (Slice 5 · D4, dual-PASSed), as do the footnote
    /// form and every other theme. The tooltip, the open/reveal/copy context menu
    /// and the workspace-qualified VoiceOver label are the affordance's, reused
    /// verbatim through the same file-scope seams.
    private func completionTranscriptButton(path: String) -> some View {
        Button {
            openTranscriptFile(at: path)
        } label: {
            Text(lang.t("island.transcript.label"))
                .lineLimit(1)
        }
        .buttonStyle(PouredFullSizeButtonStyle(kind: .ghost))
        .help(path)
        .accessibilityLabel(lang.t("a11y.transcript", session.spotlightWorkspaceName))
        .contextMenu {
            Button(lang.t("island.transcript.open")) {
                openTranscriptFile(at: path)
            }
            Button(lang.t("island.transcript.reveal")) {
                revealTranscriptFileInFinder(at: path)
            }
            Button(lang.t("island.transcript.copyPath")) {
                copyTranscriptPath(path)
            }
        }
    }

    private var completionOutcomeGlyphName: String {
        switch session.outcome {
        case .success: "checkmark"
        case .interrupted: "stop.fill"
        case .failed: "xmark"
        }
    }

    private var completionOutcomeTint: Color {
        tokens.colors.statusTint(for: .completed, outcome: session.outcome)
    }

    /// The tinted-pill background under the outcome badge (`.outcome.ok/.intr/.fail`).
    private var completionOutcomeFill: Color {
        switch session.outcome {
        case .success: PouredCompletionColors.successFill
        case .interrupted: PouredCompletionColors.interruptedFill
        case .failed: PouredCompletionColors.failedFill
        }
    }

    private var completionOutcomeLabel: String {
        switch session.outcome {
        case .success:
            lang.t("poured.completion.success")
        case .interrupted:
            lang.t("completion.interrupted")
        case .failed:
            lang.t("completion.failed")
        }
    }

    @ViewBuilder
    private var completionReplyInput: some View {
        HStack(spacing: 8) {
            ReplyTextField(
                placeholder: lang.t("completion.replyPlaceholder", session.completionReplyRecipientName),
                text: $replyText,
                onSubmit: { submitReply() },
                // The field only exists once `Reply` disclosed it, so it takes
                // the caret immediately — the click that revealed it *was* the
                // intent to type.
                focusesOnAppear: true
            )
            .frame(height: 32)

            Button {
                submitReply()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel(lang.t("a11y.completion.sendReply"))
        }
    }

    private func submitReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyText = ""
        actions.reply?(text)
    }

    private var completionMessageText: String {
        if let text = session.completionAssistantMessageText?.trimmedForRow, !text.isEmpty {
            return text
        }
        let summary = session.summary.trimmedForRow
        return summary == SessionPhase.completed.displayName ? "" : summary
    }

    // MARK: - Status indicator (all four preferences)

    @ViewBuilder
    private func statusIndicator(for presence: IslandSessionPresence) -> some View {
        let tint = statusTint(for: presence)
        switch stateIndicator {
        case .animatedDot:
            animatedIndicator(tint: tint, presence: presence)
        case .bar:
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(tint)
                .frame(width: 4, height: isActionable ? 34 : 28)
                .shadow(color: tint.opacity(presence == .inactive ? 0 : 0.5), radius: 4)
                .padding(.top, 2)
        case .glyph:
            Image(systemName: statusGlyphName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(presence == .inactive ? 0 : 0.45), radius: 4)
                .frame(width: 14, height: 20)
                .padding(.top, 1)
        case .tint:
            Circle()
                .fill(tint.opacity(presence == .inactive ? 0.54 : 0.92))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
        }
    }

    /// R4-4 (PI-C-005 · `01-poured-island.html:847/863/881/898`, `:160-170`,
    /// `:204-212`): the board's `.lead` vocabulary, one marker per row kind.
    ///
    /// - **working** → the three-bar `.glyph.run` in `--run`, never a plain dot;
    ///   the bars are the theme's own liveness glyph (`UnifiedBars`, the same
    ///   component the closed pill draws), fitted to the row's lead column.
    /// - **done / success** → a plain `.dot.done`. The check glyph the shipped
    ///   row drew here is gone: `✓ Success` already sits in the row's outcome
    ///   pill, so the row was stating the same fact twice.
    /// - **interrupted** → `.dot.interrupt` `#d98c26` (see `leadMarkerTint`).
    /// - permission / question keep their approve+ring and answer dots.
    @ViewBuilder
    private func animatedIndicator(tint: Color, presence: IslandSessionPresence) -> some View {
        let markerTint = leadMarkerTint(fallback: tint)
        // R5 / PI-C-006: `.dot.approve.ring` — only the permission row carries
        // the board's hard band. Everything else is a bare `.dot`.
        let wantsApproveRing = session.phase == .waitingForApproval
        if session.phase == .running {
            PouredRunBarsGlyph(tint: tokens.colors.statusRunning)
                .frame(width: 20, height: 24, alignment: .top)
        } else if let pulseClock, stateIndicator.pulses(presence: presence, isActionable: isActionable) {
            PouredPulsingStatusDot(pulseClock: pulseClock, tint: markerTint, ring: wantsApproveRing)
                .frame(width: 12, height: 24, alignment: .top)
        } else {
            pouredStatusDotView(tint: markerTint, pulse: 0, ring: wantsApproveRing)
                .frame(width: 12, height: 24, alignment: .top)
        }
    }

    /// R4-4: a **completed** row's lead marker states its outcome, not its
    /// recency. `statusTint(for:presence:outcome:)` collapses any `.inactive`
    /// presence to the idle grey, which made the board's interrupted row (22
    /// minutes old) read as an idle session — the exact opposite of `⏹
    /// Interrupted` printed beside it. Age is already carried by `.age` and the
    /// stale-row opacity; the marker carries the state.
    private func leadMarkerTint(fallback: Color) -> Color {
        guard session.phase == .completed else { return fallback }
        return tokens.colors.statusTint(for: .completed, outcome: session.outcome)
    }

    // MARK: - Badges

    /// R2/C7 (`01-poured-island.html:858`): every Poured row's `.age` reads
    /// **recency** — how long since this session last said anything — and a
    /// running row that just spoke reads the board's `now` rather than `<1m`.
    ///
    /// Running rows used to read `elapsedRunningLabel` (run *duration*) here,
    /// which made the same column mean two different things depending on phase
    /// and left no way to render the board's row 3, which is simultaneously
    /// `now` in the age column and `live 1m 42s` in the narration. Duration now
    /// lives where the board puts it — the `.act` tail (see
    /// `liveElapsedSuffix(at:)`).
    private func ageBadgeText(at referenceDate: Date) -> String {
        if session.phase == .running, isJustRefreshed(at: referenceDate) {
            return lang.t("poured.age.now")
        }
        return session.spotlightAgeBadge(at: referenceDate)
    }

    // MARK: - Trailing controls

    private func detailToggleButton(isOpen: Bool) -> some View {
        Button {
            toggleDetail(currentlyOpen: isOpen)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isOpen || isHighlighted ? .white.opacity(0.68) : .white.opacity(0.42))
                .frame(
                    width: IslandSessionRowMetrics.detailToggleColumnWidth,
                    height: IslandSessionRowMetrics.trailingControlHeight
                )
                .background(
                    Circle()
                        .fill(.white.opacity(detailToggleFillOpacity(isOpen: isOpen)))
                )
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t(isOpen ? "a11y.session.collapseDetail" : "a11y.session.expandDetail"))
    }

    private func toggleDetail(currentlyOpen: Bool) {
        guard isInteractive else { return }
        setDetailOpen(!currentlyOpen)
    }

    /// The single write path for the in-place disclosure. Reduce Motion removes
    /// the transition outright (`PouredRowMotion.HeroDisclosure`), and — for a
    /// hero the user deliberately opened **inside the list** — the registry is
    /// kept in step so `OverlayPanelController` can implement R8's two-stage Esc
    /// without reaching into this view's `@State`.
    private func setDetailOpen(_ open: Bool) {
        if let duration = PouredRowMotion.HeroDisclosure.duration(reduceMotion: reduceMotion) {
            withAnimation(.easeInOut(duration: duration)) { detailOverride = open }
        } else {
            detailOverride = open
        }

        guard presentation == .list else { return }
        if open {
            PouredHeroExpansion.shared.heroDidOpen(sessionID: session.id)
        } else {
            PouredHeroExpansion.shared.heroDidClose(sessionID: session.id)
        }
    }

    private func detailToggleFillOpacity(isOpen: Bool) -> Double {
        if isHighlighted {
            return isOpen ? 0.09 : 0.07
        }
        return isOpen ? 0.055 : 0.025
    }

    private func handlePrimaryTap() {
        guard isInteractive else { return }
        actions.jump()
    }

    // MARK: - Accessibility (identical wording to Classic)

    private func accessibilityRowSummaryText(referenceDate: Date, showsDetail: Bool) -> String {
        let base = lang.t(
            "a11y.session.summary",
            session.tool.displayName,
            session.spotlightWorkspaceName,
            accessibilityPhaseText,
            accessibilityElapsedText(at: referenceDate)
        )
        // PI-C-005: the row now narrates on screen, so the single grouped
        // VoiceOver stop must say the same thing rather than stopping at the
        // workspace + phase.
        guard let narrative = accessibilityActivityNarrative(
            referenceDate: referenceDate,
            showsDetail: showsDetail
        ) else { return base }
        return "\(base), \(narrative)"
    }

    /// R2/C1 · C2: VoiceOver hears the same ask the row prints — the permission's
    /// `Wants to run swift build` / the question's own text — not the generic
    /// narration the shared spotlight line would produce for the same session.
    ///
    /// X11: and it hears the row's **own** line, so an expanded §D row no longer
    /// speaks a `· live 1m 42s` tail the board removed from `.act` and moved into
    /// the `LIVE` metadata cell (which VoiceOver reaches separately). The
    /// argument used to be hard-coded `false`, so the AX text and the printed
    /// text disagreed on exactly one row state.
    private func accessibilityActivityNarrative(referenceDate: Date, showsDetail: Bool) -> String? {
        if let ask = accessibilityAskText { return ask }
        let joined = activitySegments(referenceDate: referenceDate, showsDetail: showsDetail)
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private var accessibilityAskText: String? {
        switch session.phase {
        case .waitingForApproval:
            guard let command = permissionCommandText else {
                return PouredCompactActivity.plainText(session.permissionRequest?.summary)
                    ?? PouredCompactActivity.plainText(session.permissionRequest?.title)
            }
            return lang.t("poured.row.wantsToRun") + " " + command
        case .waitingForAnswer:
            return PouredCompactActivity.plainText(session.questionPrompt?.questions.first?.question)
        case .running, .completed:
            return nil
        }
    }

    private var accessibilityPhaseText: String {
        switch session.phase {
        case .running:
            lang.t("a11y.phase.running")
        case .waitingForApproval:
            lang.t("a11y.phase.waitingForApproval")
        case .waitingForAnswer:
            lang.t("a11y.phase.waitingForAnswer")
        case .completed:
            switch session.outcome {
            case .success: lang.t("a11y.phase.completed")
            case .interrupted: lang.t("a11y.phase.interrupted")
            case .failed: lang.t("a11y.phase.failed")
            }
        }
    }

    private func accessibilityElapsedText(at referenceDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: lang.language.resolvedCode)
        formatter.unitsStyle = .full
        let reference = session.phase == .running ? session.firstSeenAt : session.islandActivityDate
        return formatter.localizedString(for: reference, relativeTo: referenceDate)
    }

    // MARK: - Text / tint helpers

    private var showsLeadingStatusIndicator: Bool {
        presentation == .list && stateIndicator != .tint && stateIndicator != .bar
    }

    private var showsLeadingStatusBar: Bool {
        presentation == .list && stateIndicator == .bar
    }

    private var rowLeadingInset: CGFloat {
        if presentation == .notification {
            return sideInset
        }
        return stateIndicator == .bar ? max(28, sideInset) : sideInset
    }

    private var detailLeadingInset: CGFloat {
        if presentation == .notification {
            return sideInset
        }
        switch stateIndicator {
        case .bar:
            return max(28, sideInset)
        case .tint:
            return sideInset
        case .animatedDot, .glyph:
            return sideInset + 30
        }
    }

    private func titleColor(for presence: IslandSessionPresence) -> Color {
        if stateIndicator == .tint && presence != .inactive {
            return statusTint(for: presence)
        }
        return presence == .inactive
            ? tokens.colors.paper.opacity(0.78)
            : tokens.colors.paper
    }

    /// AB-332: age reads at tertiary on every row (mockup `.age{color:var(--t3)}`)
    /// — the shipped presence-dependent secondary/tertiary split is retired so
    /// the right rail stays quiet and consistent.
    private func summaryAgeColor(for presence: IslandSessionPresence) -> Color {
        tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
    }

    private func contrastText(_ base: Double) -> Double {
        tokens.colors.text(base, increaseContrast: increasesContrast)
    }

    private func statusTint(for presence: IslandSessionPresence) -> Color {
        tokens.colors.statusTint(for: session.phase, presence: presence, outcome: session.outcome)
    }

    private var statusGlyphName: String {
        switch session.phase {
        case .waitingForApproval:
            "exclamationmark.triangle.fill"
        case .waitingForAnswer:
            "questionmark.circle.fill"
        case .running:
            "circle.dashed"
        case .completed:
            switch session.outcome {
            case .success: "checkmark.circle.fill"
            case .interrupted: "stop.circle.fill"
            case .failed: "xmark.circle.fill"
            }
        }
    }

    /// Poured's hover is a lighter glass tint that lifts the row (list only).
    /// `.notification` never highlights (`SessionRowContainer` never sets it
    /// there, and this guards it a second time).
    private func rowFillColor(for presence: IslandSessionPresence) -> Color {
        if presentation == .notification {
            return .clear
        }

        let base = isHighlighted ? Color.white.opacity(isActionable ? 0.07 : 0.06) : Color.clear
        guard stateIndicator == .tint else { return base }

        let tintOpacity: Double
        if isHighlighted {
            tintOpacity = isActionable ? 0.15 : 0.13
        } else {
            tintOpacity = presence == .inactive ? 0.035 : 0.08
        }
        return statusTint(for: presence).opacity(tintOpacity)
    }

    // MARK: - Small formatters

    /// Uppercases a role's copy for the consuming view (metadata keys, nest
    /// headers, assistant-message label) — the `isUppercase` treatment travels
    /// with the role in `PouredType`, applied here since a `Font` can't carry
    /// case. A no-op for CJK strings.
    private func pouredUppercased(_ text: String) -> String {
        text.uppercased()
    }

    /// §4G todo glyphs — icon+text, never colour alone (a11y): done reads as a
    /// green check (#6FB982) with the title struck through, doing as the running
    /// bars in the run tint, pending as a hollow circle at tertiary.
    @ViewBuilder
    private func taskStatusIcon(_ status: ClaudeTaskInfo.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tokens.colors.statusCompleted)
                .accessibilityLabel(lang.t("a11y.task.completed"))
        case .inProgress:
            // PI-X-001/G1 (`01-poured-island.html:1313`): the doing tick is the
            // three-bar `.glyph.run` at `8×9` inside the 14×14 `.tk` box — the
            // same mark the nest header and the row's lead carry, so "in
            // progress" reads as one shape everywhere. Replaces the pulsing dot,
            // which was a marker vocabulary the board's todo list never uses.
            PouredRunBarsGlyph(
                tint: tokens.colors.statusRunning,
                height: PouredRunGlyphMetrics.todoTickHeight,
                isDecorative: false
            )
            .accessibilityLabel(lang.t("a11y.task.inProgress"))
        case .pending:
            Circle()
                .strokeBorder(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)), lineWidth: 1.4)
                .frame(width: 11, height: 11)
                .accessibilityLabel(lang.t("a11y.task.pending"))
        }
    }
}

// MARK: - Poured approval hero card

/// The permission request rendered as Poured Island's hero: an amber-glow card
/// that radiates a pulsing warm glow above everything else on the glass (static
/// under Reduce Motion), a command preview in a mono block, an affected-path
/// line, an optional `IslandDiffRenderer`, and a prominent filled Allow next
/// to a quiet Deny — or the always-allow options / Codex terminal CTA.
///
/// Isolated in its own `View` so the amber glow's 15fps pulse (read off the
/// shared `PulseClock` via `PouredAmberGlow`) invalidates only the glow, and so
/// the approve / deny callbacks stay exactly the ones ⌘Y / ⌘⇧Y / ⌘N fire
/// against from `OverlayPanelController`.
private struct PouredApprovalCard: View {
    let session: AgentSession
    let lang: LanguageManager
    let actions: RowActions
    let pulseClock: PulseClock?
    var presentation: IslandSessionRowPresentation = .list

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.islandSuppressesNotificationCountdown) private var suppressesCountdown
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    /// E3: a Codex terminal-approval request can't round-trip through the bridge
    /// (the ⌘Y / ⌘⇧Y / ⌘N handler deliberately no-ops for it), so the hero drops
    /// every Approve/Deny affordance for a single honest "jump to approve" CTA and
    /// re-tints cool blue.
    private var requiresTerminalApproval: Bool {
        session.permissionRequest?.requiresTerminalApproval == true
    }

    /// The hero's accent: amber `PouredPalette.attention` for a normal request,
    /// Codex blue `#4aa3df` for the terminal-approval variant (`SPEC` §4E E1/E3).
    private var accent: Color {
        requiresTerminalApproval ? PouredApprovalColors.codexBlue : PouredPalette.attention
    }

    private var borderOpacity: Double {
        (reduceTransparency || increasesContrast) ? 0.7 : PouredPillMotion.Hero.borderOpacity
    }

    /// The board's §E vertical rhythm is **not** uniform — each block carries its
    /// own top margin (`mapper-reference.md` §5.7/§5.8, verified against the
    /// measured offsets): `.hero-head{margin-bottom:10}`, the E1 effect line's
    /// inline `margin-top:8`, `.actions{margin-top:12}`, `.scopes{margin-top:11}`,
    /// `.codex-note{margin-top:10}`, and E4's footer `padding:9px 4px 2px`. The
    /// card used to stack everything at a flat 10, which drifted `.actions` by 2
    /// and `.scopes` by 1 on every frame.
    /// E7: `.amber-hero{border-radius:18px}` (`01-poured-island.html:302`), the
    /// same value `.q-hero` (`:379`) uses. One constant so the fill and the
    /// stroke can never drift apart again.
    static let cornerRadius: CGFloat = 18

    /// X13: `.amber-hero{padding:14px 16px 15px}` — all three axes differ, so they
    /// are stated separately (and pinned by `PouredSlice5CorrectionsTests`). The
    /// bottom is the board's 15, one point past the 14 top (X13 took only the
    /// horizontal 16 last round).
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 14
    static let bottomPadding: CGFloat = 15

    private enum HeroRhythm {
        static let headToBody: CGFloat = 10
        static let commandToEffect: CGFloat = 8
        static let toActions: CGFloat = 12
        static let toScopes: CGFloat = 11
        static let toCodexNote: CGFloat = 10
        static let toCountdownFooter: CGFloat = 9
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroHead

            if let commandText {
                commandBlock(commandText)
                    .padding(.top, HeroRhythm.headToBody)
            }

            if let effectText {
                Text(effectText)
                    .font(PouredType.Role.heroSubtitle.font)
                    .foregroundStyle(PouredApprovalColors.effectInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, commandText == nil ? HeroRhythm.headToBody : HeroRhythm.commandToEffect)
            }

            // AB-235 / E2: the shared renderer owns the gutter and structural
            // marker column; Poured supplies its exact rounded-card palette.
            if let diffResult = permissionDiffResult {
                // E1: the rows are clamped to whole `.dl` lines so the block never
                // ends mid-glyph; the remainder is stated as "+N more lines" — but
                // the board keeps a "+N more" compression *inside* the surface it
                // summarizes (`01-poured-island.html:729`), so the count rides
                // inside the diff well via `additionalHiddenLines`, not as a line
                // floating below it.
                let clamped = PouredHeroDiff.clamp(diffResult)
                IslandDiffRenderer(
                    result: clamped.result,
                    lang: lang,
                    style: .poured(
                        tokens: tokens,
                        reduceTransparency: reduceTransparency,
                        fileName: session.permissionRequest?.affectedPath,
                        hunk: session.permissionRequest?.diffHunkDescription,
                        additionalHiddenLines: clamped.hiddenLineCount
                    )
                )
                .padding(.top, HeroRhythm.headToBody)
            }

            if requiresTerminalApproval {
                codexNote
                    .padding(.top, HeroRhythm.toCodexNote)
                terminalApprovalCTA
                    .padding(.top, HeroRhythm.toActions)
            } else {
                actionButtons
                    .padding(.top, HeroRhythm.toActions)
                // `.scopes`' own top margin is applied *inside* the builder —
                // an absent scope list must contribute no space at all, and a
                // modified `EmptyView` no longer collapses in a `VStack`.
                alwaysAllowOptions
            }

            // E4: the shared `IslandNotificationCard` stays unchanged, so the
            // honest auto-collapse countdown is printed here, inside the hero, when
            // it renders in the notification presentation — and only where the
            // board draws one, which is E4 alone
            // (`01-poured-island.html:1140-1143`; E1/E2/E3 carry no footer).
            if presentation == .notification, !suppressesCountdown {
                notificationCountdownFooter
                    .padding(.top, HeroRhythm.toCountdownFooter)
            }
        }
        // X13 (D's F-07): `.amber-hero{padding:14px 16px 15px}`
        // (`01-poured-island.html:302`) — 16 on each side, 14 top, 15 bottom.
        .padding(.top, Self.verticalPadding)
        .padding(.bottom, Self.bottomPadding)
        .padding(.horizontal, Self.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .overlay(
            // E7: `.amber-hero{border-radius:18px}` (`01-poured-island.html:302`).
            // The card carried a 15 inherited from the pre-2.0 hero; the board
            // states 18 for every §E frame and for `.q-hero`.
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(accent.opacity(borderOpacity), lineWidth: PouredPillMotion.Hero.borderWidth)
        )
        .modifier(PouredAmberGlow(tint: accent, pulseClock: pulseClock))
        // The buttons carry their own labels/actions; group the surrounding
        // copy so VoiceOver reads the card, then reaches Allow / Deny.
        .accessibilityElement(children: .contain)
    }

    // MARK: Hero head

    /// The event "headline" (`mapper-reference.md` §5.2/§5.7 · board
    /// `.hero-head`): a 24×24 accent glyph chip, then a two-line stack of the
    /// per-variant **intent sentence** (`.ht`) over the scope subtitle (`.hs`),
    /// then the agent tag pushed to the trailing edge by `margin-left:auto`.
    /// `display:flex; align-items:center; gap:9px`.
    ///
    /// R10 (ask-first): the head reads the ask itself — `Run a shell command?` /
    /// `Edit a file?` / `Approval needed in Codex` — not the generic
    /// `Tool permission requested` the card used to print for every variant.
    private var heroHead: some View {
        HStack(alignment: .center, spacing: 9) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.16))
                .frame(width: 24, height: 24)
                .overlay(heroIcon)
                .accessibilityHidden(true)

            // `.ht` over `.hs` — the board's `<div>` wrapper, `margin-top:1px`.
            VStack(alignment: .leading, spacing: 1) {
                Text(intentTitle)
                    .font(PouredType.Role.heroTitle.font)
                    .tracking(PouredType.Role.heroTitle.spec.trackingPoints)
                    .foregroundStyle(requiresTerminalApproval ? PouredApprovalColors.codexTitleInk : PouredApprovalColors.titleInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let heroSubtitleText {
                    Text(heroSubtitleText)
                        .font(PouredType.Role.heroSubtitle.font)
                        .foregroundStyle(requiresTerminalApproval ? PouredApprovalColors.codexSubtitleInk : PouredApprovalColors.subtitleInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if let agentTagText {
                agentTag(agentTagText)
            }
        }
        // PI-A11Y-001: one VoiceOver stop for the whole headline — intent, scope
        // and agent read as a sentence, and the card still reaches Allow / Deny
        // after it (card-then-controls order preserved).
        .accessibilityElement(children: .combine)
    }

    /// E2: the board draws **two** `.hero-icon` glyphs and native drew a third.
    ///
    /// - E1 and E3 carry the same terminal chevron — `M4 17l6-6-6-6` (a bare
    ///   right-pointing chevron) over `M12 19h8` (an underscore rule), 14×14,
    ///   `stroke-width:2` (`01-poured-island.html:1003-1004`, `:1092`).
    /// - E2 carries a pencil — `M12 20h9` + the nib path (`:1046-1047`).
    ///
    /// Native rendered `chevron.left.forwardslash.chevron.right` (`</>`, a *code*
    /// mark) for E1/E2 alike and `arrow.up.forward.app.fill` for E3. There is no
    /// bare `>_` in SF Symbols — `terminal` wraps it in a second rounded box that
    /// would double the 24pt chip the glyph already sits in — so the chevron is
    /// drawn as a `Path` pair straight off the board's own SVG coordinates, which
    /// is more shape-faithful than any available symbol. The pencil is SF
    /// `pencil`, whose silhouette is the board path.
    @ViewBuilder
    private var heroIcon: some View {
        if PouredApprovalHeroCopy.intent(
            requiresTerminalApproval: requiresTerminalApproval,
            hasFileDiff: session.permissionRequest?.fileDiffSource != nil,
            hasCommand: commandText != nil
        ) == .editFile {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
        } else {
            PouredTerminalChevron()
                .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 14)
        }
    }

    /// `.agent-tag` — a 7px brand dot beside the model name, `gap:5px`,
    /// `font-size:10.5px`, pushed right by `margin-left:auto`.
    private func agentTag(_ text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: session.tool.brandColorHex) ?? tokens.colors.paper)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(text)
                .font(PouredType.Role.agentChipLabel.font)
                .foregroundStyle(requiresTerminalApproval ? PouredApprovalColors.codexAgentTagInk : PouredApprovalColors.agentTagInk)
                .lineLimit(1)
        }
        .fixedSize()
    }

    private var intentTitle: String {
        let intent = PouredApprovalHeroCopy.intent(
            requiresTerminalApproval: requiresTerminalApproval,
            hasFileDiff: session.permissionRequest?.fileDiffSource != nil,
            hasCommand: commandText != nil
        )
        switch intent {
        case .terminalApproval:
            return lang.t(intent.localizationKey, session.tool.displayName)
        case .editFile, .runCommand, .generic:
            return lang.t(intent.localizationKey)
        }
    }

    private var heroSubtitleText: String? {
        PouredApprovalHeroCopy.subtitle(
            workspace: session.spotlightDisplayName,
            affectedPath: session.permissionRequest?.affectedPath
        )
    }

    /// `.agent-tag` copy — `Sonnet 5` / `Opus 4.8` / `codex`.
    ///
    /// E4 (correction round 2): the board's E3 head **does** carry a tag, and its
    /// copy is the agent brand name (`codex`) with the codex dot beside it, not a
    /// model name — a Codex terminal-approval request reports no
    /// `displayModelName`, so the tag vanished entirely. The fallback is scoped to
    /// the terminal-approval variant on purpose: E4's rendered state really is
    /// *no* `.agent-tag`, so a blanket fallback would have invented one there.
    /// Lower-cased for the same reason the §C identity chip is
    /// (`agentIdentityChipLabel`) — the board prints `codex`, not `Codex`.
    private var agentTagText: String? {
        if let model = session.displayModelName { return model }
        guard requiresTerminalApproval else { return nil }
        let name = session.tool.displayName.trimmedForRow
        return name.isEmpty ? nil : name.lowercased()
    }

    // MARK: Command block (syntax spans — T10)

    /// The command awaiting approval, syntax-highlighted through the shipped
    /// `ShellCommandTokenizer` (T10 / AB-328): command `#f2f5fb`/600, subcommand
    /// `#8fd0ff`, flags `#6ea7ff`, strings `#7fd39a`, paths `#f2f5fb`@0.55; plain
    /// runs inherit the block's `#c9cedb` (`SPEC` §4E / mockup `.cmd`).
    private func commandBlock(_ command: String) -> some View {
        let highlighted = ShellCommandTokenizer.attributed(
            command,
            palette: PouredApprovalColors.syntaxPalette,
            weights: [.command: .semibold],
            baseFont: PouredType.Role.commandBlock.font
        )
        return (Text("$ ").foregroundStyle(accent.opacity(0.7)) + Text(highlighted))
            .font(PouredType.Role.commandBlock.font)
            .foregroundStyle(PouredApprovalColors.commandInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(reduceTransparency ? tokens.colors.surfaceInk : PouredApprovalColors.codeSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .textSelection(.enabled)
    }

    // MARK: Buttons + keycaps

    /// `Allow once ⌘Y` (amber gradient, LEFT) beside `Deny ⌘N` (RIGHT) — the
    /// board's measured order and its 8px gap (`mapper-reference.md` §5.2:
    /// x 113.75 vs 260.89). The keycap glyphs are sourced from
    /// `PouredApprovalShortcut`, which mirrors the real `OverlayPanelController`
    /// handler (⌘Y / ⌘N), never the mockup's ⏎/⎋.
    ///
    /// R11 (per-surface verbs): the hero prints the board's own `Allow once` /
    /// `Deny` rather than the request's `primaryActionTitle`, which is
    /// agent-supplied and renders "Allow"/"Yes"/"Approve" depending on the hook.
    /// The agent's wording is kept where it still helps — the VoiceOver label —
    /// exactly as Halo does (`HaloSessionRow.swift:2333-2337`).
    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                actions.approve?(.allowOnce)
            } label: {
                PouredApprovalButtonLabel(
                    title: lang.t("poured.approval.allowOnce"),
                    shortcut: .allowOnce,
                    kind: .allow,
                    usesStandaloneChrome: false
                )
            }
            .buttonStyle(PouredFullSizeButtonStyle(kind: .event))
            // E8 (PI-A11Y-001, WCAG 2.5.3 label-in-name): the accessible name is
            // the **visible** label. Part B routed the agent-supplied
            // `primaryActionTitle` here as the label, which meant a request whose
            // hook says "Yes" was announced as "Yes" while the button reads
            // "Allow once" — a voice-control user saying what they see would
            // miss. The agent's own wording is still useful context, so it moves
            // to the hint, where it supplements rather than replaces.
            .accessibilityLabel(lang.t("poured.approval.allowOnce"))
            .modifier(PouredOptionalAccessibilityHint(session.permissionRequest?.primaryActionTitle))

            Button {
                actions.approve?(.deny)
            } label: {
                PouredApprovalButtonLabel(
                    title: lang.t("poured.approval.deny"),
                    shortcut: .deny,
                    kind: .deny,
                    usesStandaloneChrome: false
                )
            }
            .buttonStyle(PouredFullSizeButtonStyle(kind: .deny))
            // E8: same rule for Deny — visible label is the name, agent verb is
            // the hint.
            .accessibilityLabel(lang.t("poured.approval.deny"))
            .modifier(PouredOptionalAccessibilityHint(session.permissionRequest?.secondaryActionTitle))
        }
    }

    // MARK: Scoped always-allow rows

    /// AB-235 / E1: scoped always-allow options rendered from the request's real
    /// `suggestedUpdates` (their human `displayLabel`s), or the generic
    /// session-scoped fallback. The FIRST row carries the `⌘⇧Y` key-hint the
    /// always-allow shortcut fires. Each choice sends exactly its update — the
    /// same call `⌘⇧Y` drives.
    @ViewBuilder
    private var alwaysAllowOptions: some View {
        if let updates = session.permissionRequest?.suggestedUpdates, !updates.isEmpty {
            VStack(spacing: 1) {
                ForEach(Array(updates.enumerated()), id: \.offset) { index, update in
                    PouredScopeRow(parts: scopeParts(for: update), showsKeycap: index == 0) {
                        actions.approve?(.allowWithUpdates([update]))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1)
            )
            .padding(.top, HeroRhythm.toScopes)
        } else if let toolName = session.permissionRequest?.toolName,
                  let chip = PouredScopeCopy.genericScopeChip(
                      toolName: toolName,
                      commandPreview: session.currentCommandPreviewText
                  ) {
            VStack(spacing: 1) {
                // E6: the generic fallback is the board's second scope row —
                // "Always allow all `<tool>` commands" — never the shipped
                // `Always Allow (Bash)` with its Title-Cased verb and the raw
                // tool name in parentheses.
                //
                // X7: and never a raw tool **identifier** on the gold chip
                // either. The board's chip is the executable (`swift`); native
                // printed `permissionRequest.toolName`, which for a shell call
                // is the harness id `exec_command`. `genericScopeChip` resolves
                // the honest command word, or `nil` — in which case no generic
                // row is drawn at all rather than one that lies.
                PouredScopeRow(
                    parts: PouredScopeCopy.parts(
                        format: lang.t("poured.approval.scope.allCommands"),
                        code: chip
                    ),
                    showsKeycap: true
                ) {
                    let rule = ClaudePermissionRuleValue(toolName: toolName)
                    let update = ClaudePermissionUpdate.addRules(
                        destination: .session,
                        rules: [rule],
                        behavior: .allow
                    )
                    actions.approve?(.allowWithUpdates([update]))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1)
            )
            .padding(.top, HeroRhythm.toScopes)
        }
    }

    /// E6: the board's scope sentence for one update, or the shipped
    /// `displayLabel` as a whole-sentence fallback for the update kinds the board
    /// never draws (mode changes, directory grants) — those carry no code chip.
    private func scopeParts(for update: ClaudePermissionUpdate) -> PouredScopeCopy.Parts {
        guard let shape = PouredScopeCopy.shape(for: update) else {
            return PouredScopeCopy.Parts(prefix: update.displayLabel, code: "", suffix: "")
        }
        return PouredScopeCopy.parts(format: lang.t(shape.key), code: shape.code)
    }

    // MARK: Codex (E3)

    /// E3: the blue "approves in-app" note that makes the terminal-approval
    /// variant honest about where the decision actually happens.
    private var codexNote: some View {
        HStack(alignment: .top, spacing: 10) {
            // E3 `.codex-note` glyph (`01-poured-island.html:1100-1101`) is a down
            // arrow dropping into a tray, not an external-link box.
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PouredApprovalColors.codexBlue)
                .accessibilityHidden(true)
            Text(lang.t("approval.codexApprovesInApp"))
                .font(PouredType.Role.optionDesc.font)
                .foregroundStyle(PouredApprovalColors.codexNoteInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PouredApprovalColors.codexBlue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(PouredApprovalColors.codexBlue.opacity(0.25), lineWidth: 1)
                )
        )
    }

    /// E3: the single honest CTA when `requiresTerminalApproval` is set.
    ///
    /// E5 (correction round 2): the board prints `⌘Y` on this blue primary
    /// (`01-poured-island.html:1106-1108`) and the rendered board is golden, so
    /// the cap is drawn. **Open follow-up, deliberately recorded rather than
    /// hidden:** the binding itself lives in
    /// `OverlayPanelController.handleApprovalShortcut`, which bails on
    /// `requiresTerminalApproval` (`OverlayPanelController.swift:405-406`) and is
    /// outside this round's file ownership. Routing that case to
    /// `handleJumpShortcut` — one guard — is what makes the printed cap fire; the
    /// card's own CTA and ⌘J already perform the identical jump today.
    private var terminalApprovalCTA: some View {
        Button {
            actions.jump()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.forward")
                    .accessibilityHidden(true)
                Text(terminalApprovalCTATitle)
                // X9 (C's M-7), Y4 replicated as rendered: `.btn.primary .kc kbd`
                // (board L360) is never overridden per variant, so E3's *blue*
                // primary carries the same amber-derived caps E1's amber and F2's
                // gold primaries do — brown glyphs on a darkened chip, not the
                // dark-surface white-on-grey pair. `onAmber` is the name of that
                // one `.btn.primary` recipe, not a hue claim.
                PouredKeycapRow(glyphs: PouredApprovalShortcut.allowOnce.glyphs, onAmber: true)
            }
        }
        .buttonStyle(PouredFullSizeButtonStyle(kind: .wayfinding))
        // E8: the visible label IS the accessible name. The agent's own verb
        // survives as the hint, never as a replacement for what the user sees.
        .accessibilityLabel(terminalApprovalCTATitle)
    }

    private var terminalApprovalCTATitle: String {
        session.tool == .codex ? lang.t("approval.jumpToCodex") : lang.t("approval.respondInTerminal")
    }

    // MARK: Notification footer (E4)

    /// E4: the honest auto-collapse countdown printed under the hero in the
    /// notification presentation. The value is read from the coordinator's real
    /// delay (10s), not the mockup's stale "8s".
    private var notificationCountdownFooter: some View {
        Text(lang.t("approval.autoCollapseCountdown", Int(OverlayUICoordinator.notificationSurfaceAutoCollapseDelay)))
            .font(PouredType.Role.heroSubtitle.font)
            .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Fill

    /// The accent wash over the frosted slab. Under Reduce Transparency the wash
    /// sits on an opaque ink base so the card never relies on the glass showing
    /// through to stay legible (AB-303).
    private var cardFill: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        // Reduce Transparency floors the translucent well on opaque `surfaceInk`
        // so it can't sample the desktop; the board has no such mode, so the
        // well stops are the board's own either way.
        return ZStack {
            if reduceTransparency {
                shape.fill(tokens.colors.surfaceInk)
            }
            shape.fill(heroWellGradient)
        }
    }

    private var heroWellGradient: LinearGradient {
        let stops = requiresTerminalApproval
            ? [PouredApprovalColors.heroWellBlueTop, PouredApprovalColors.heroWellBlueBottom]
            : [PouredApprovalColors.heroWellTop, PouredApprovalColors.heroWellBottom]
        return LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    // MARK: Content

    private var commandText: String? {
        let preview = session.currentCommandPreviewText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let preview, !preview.isEmpty else { return nil }
        return preview
    }

    /// E3: the plain-English effect line — **E1 only**, and never a restatement
    /// of the ask. The rule is pure (`PouredApprovalHeroCopy.effect`) so the
    /// suppressions are pinnable without a view.
    private var effectText: String? {
        PouredApprovalHeroCopy.effect(
            summary: session.permissionRequest?.summary ?? session.summary,
            command: commandText,
            intentTitle: intentTitle,
            hasFileDiff: session.permissionRequest?.fileDiffSource != nil,
            requiresTerminalApproval: requiresTerminalApproval
        )
    }

    /// Computes the diff lazily from the request's captured old/new text
    /// (AB-235). `nil` when there's nothing to diff or old/new are identical.
    private var permissionDiffResult: PermissionDiffResult? {
        guard let source = session.permissionRequest?.fileDiffSource else {
            return nil
        }
        let result = PermissionDiff.compute(oldText: source.oldText, newText: source.newText)
        return result.isEmpty ? nil : result
    }
}

/// The three approval decisions the Poured hero exposes, each paired with the
/// **real** registered `OverlayPanelController` shortcut it fires. The glyph
/// strings printed on the keycaps must stay in lock-step with that handler
/// (`⌘Y` / `⌘⇧Y` / `⌘N`), never the mockup's ⏎/⎋.
///
/// Not `private` (overlay remediation Phase 2A-follow-up · F1): the now
/// module-internal `PouredApprovalButtonLabel.shortcut: PouredApprovalShortcut?`
/// property can't be more visible than its own type.
/// The pure copy decisions behind the §E hero head (`.ht` / `.hs`), lifted out
/// of the view so `PouredRowMotionTests` can pin them.
///
/// R10 (ask-first): the head reads the ask, and which ask it is comes from the
/// **request**, never from fixture wording — a terminal-approval request names
/// the app the decision happens in (E3), a request carrying a file diff is an
/// edit (E2), a request carrying a command is a shell run (E1). Anything else
/// keeps the generic sentence; the board renders no fourth variant, so inventing
/// one would be fabrication.
enum PouredApprovalHeroCopy {
    enum Intent: Equatable {
        /// E3 — `Approval needed in Codex` (takes the agent's display name).
        case terminalApproval
        /// E2 — `Edit a file?`
        case editFile
        /// E1 — `Run a shell command?`
        case runCommand
        /// No board frame: the shipped `Tool permission requested`.
        case generic

        var localizationKey: String {
            switch self {
            case .terminalApproval: "poured.approval.intent.terminalApproval"
            case .editFile: "poured.approval.intent.editFile"
            case .runCommand: "poured.approval.intent.runCommand"
            case .generic: "approval.toolPermissionRequested"
            }
        }
    }

    static func intent(
        requiresTerminalApproval: Bool,
        hasFileDiff: Bool,
        hasCommand: Bool
    ) -> Intent {
        if requiresTerminalApproval { return .terminalApproval }
        if hasFileDiff { return .editFile }
        if hasCommand { return .runCommand }
        return .generic
    }

    /// `.hs` — `the-automator · project root`, `open-vibe-island · adds two
    /// agents`, `niche-radar · run tests`, and (E4) the workspace alone.
    ///
    /// The board's second segment is prose scope; the honest native equivalent is
    /// the request's own `affectedPath` **leaf** — the file or target the decision
    /// is actually about. It is dropped when it merely repeats the workspace name,
    /// which reproduces E4's shape (workspace alone) instead of a stuttering
    /// `the-automator · the-automator`.
    static func subtitle(workspace: String, affectedPath: String?) -> String? {
        let workspace = workspace.trimmedForRow
        guard let scope = scope(workspace: workspace, affectedPath: affectedPath) else {
            return workspace.isEmpty ? nil : workspace
        }
        return workspace.isEmpty ? scope : "\(workspace) · \(scope)"
    }

    private static func scope(workspace: String, affectedPath: String?) -> String? {
        guard let raw = affectedPath?.trimmedForRow, !raw.isEmpty else { return nil }
        let leaf = (raw as NSString).lastPathComponent
        guard !leaf.isEmpty, leaf != workspace else { return nil }
        return leaf
    }

    /// E3: which `.hero-icon` the frame carries — E1/E3 the terminal chevron,
    /// E2 the pencil. Derived from `intent` so the icon can never disagree with
    /// the title the same classification produced.

    /// E3 (correction round 2): the plain-English **effect** line, or `nil`.
    ///
    /// The board renders it on **E1 only** — one 11.5px amber-ivory sentence
    /// between `.cmd` and `.actions` (`01-poured-island.html:1010-1011`).
    /// E2 has none (the diff *is* the statement of effect) and E3 has none
    /// (the blue `.codex-note` occupies that slot, and nothing amber may appear
    /// inside the blue card). Native printed the request summary on all three.
    ///
    /// On E1 the line must say what running the command *does* — never restate
    /// the ask. A summary that merely echoes the command, the intent title, or
    /// wraps the command in "wants to run …" is suppressed rather than printed,
    /// because a restatement is worse than silence: it costs a line and the
    /// reader learns nothing.
    static func effect(
        summary: String?,
        command: String?,
        intentTitle: String?,
        hasFileDiff: Bool,
        requiresTerminalApproval: Bool
    ) -> String? {
        guard !hasFileDiff, !requiresTerminalApproval else { return nil }
        guard let summary = summary?.trimmedForRow, !summary.isEmpty else { return nil }

        let folded = summary.lowercased()
        if let intentTitle = intentTitle?.trimmedForRow, !intentTitle.isEmpty,
           folded == intentTitle.lowercased() {
            return nil
        }
        guard let command = command?.trimmedForRow, !command.isEmpty else { return summary }

        let foldedCommand = command.lowercased()
        // An exact echo, or a sentence whose only content is the command with a
        // "wants to run"-shaped wrapper around it.
        if folded == foldedCommand { return nil }
        if folded.contains(foldedCommand) {
            let residue = folded
                .replacingOccurrences(of: foldedCommand, with: " ")
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            // ≤ 4 remaining words means the summary is a wrapper, not an effect
            // ("Claude wants to run swift build", "Run: swift build").
            if residue.count <= 4 { return nil }
        }
        return summary
    }
}

// MARK: - Countdown suppression seam (§E · capture)

private struct IslandSuppressesNotificationCountdownKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// Slice 5 · §E: drops the `Auto-collapses in Ns · hover pauses` footer from
    /// the Poured permission hero. The board carries it on E4 only; the E1/E2/E3
    /// scenarios set it so their frames match, and so a capture round can take an
    /// E-still without the countdown. `false` (the default) is the shipped
    /// behaviour on every other path — a real notification surface really does
    /// auto-collapse and must keep saying so.
    ///
    /// Declared beside its only consumer, the same way
    /// `IslandQuestionPromptPreselectionKey` is.
    var islandSuppressesNotificationCountdown: Bool {
        get { self[IslandSuppressesNotificationCountdownKey.self] }
        set { self[IslandSuppressesNotificationCountdownKey.self] = newValue }
    }
}

// MARK: - Hero diff clamp (§E2 `.diff` · E1)

/// E1: the §E hero's inline diff must end on a **whole `.dl` row**.
///
/// `IslandDiffRenderer` bounds a long diff with `AutoHeightScrollView(maxHeight:
/// 180)`, which cuts wherever 180pt lands — in the candidate that was through the
/// middle of a line's glyphs, with the row below half-drawn and no statement that
/// anything was elided. The board's E2 renders four complete rows and stops
/// (`mapper-reference.md` §5.3).
///
/// So the *rows* are clamped here, at the Poured call site, and the remainder is
/// stated as `…and N more lines` — the affordance the correction contract offers
/// as the alternative to sub-row clipping. `maxRows` is the board's four rows plus
/// two of headroom: at 11.5pt over a 384pt content width six unwrapped rows plus
/// the 30pt file header sit comfortably inside the renderer's own 180pt cap, so
/// the scroll view never engages and nothing can be sliced.
enum PouredHeroDiff: Sendable {
    /// Board E2 draws 4 `.dl` rows; 6 keeps a live diff informative while staying
    /// under the shared renderer's scroll cap.
    static let maxRows = 6

    struct Clamped: Sendable, Equatable {
        var result: PermissionDiffResult
        var hiddenLineCount: Int
    }

    static func clamp(_ result: PermissionDiffResult, maxRows: Int = maxRows) -> Clamped {
        guard result.lines.count > maxRows else {
            return Clamped(result: result, hiddenLineCount: 0)
        }
        let kept = Array(result.lines.prefix(maxRows))
        return Clamped(
            result: PermissionDiffResult(
                lines: kept,
                addedCount: result.addedCount,
                removedCount: result.removedCount
            ),
            hiddenLineCount: result.lines.count - kept.count
        )
    }
}

// MARK: - §D narration clause (X11)

/// X11 (C's M-12): how the **expanded** §D row's `.act` gets the board's second
/// half.
///
/// The board prints `Editing` + ` AppModel.swift · narrating the bridge lifecycle
/// change` (`01-poured-island.html:940`). Native narrated only the verb+object
/// pair, so §D's `.act` was a short phrase floating in the 464pt content width
/// R2/D2 had just given it — the fix landed with nothing on screen long enough
/// to show it.
///
/// The clause is the session's own one-line `summary`: the field an agent
/// already fills with "what I am doing", which the collapsed §C row has no room
/// for (and which the board gives it none of either). Pure, so the exact
/// composed sentence is a test rather than a screenshot.
enum PouredDetailNarration {
    /// The narrated object, plus the summary clause when the summary adds
    /// something the narration does not already say.
    static func object(base: String?, summary: String?, narratedLine: String?) -> String? {
        guard let clause = clause(base: base, summary: summary, narratedLine: narratedLine) else {
            return base
        }
        guard let base, !base.isEmpty else { return clause }
        return "\(base) \u{00B7} \(clause)"
    }

    /// The clause itself, or `nil` when the summary merely echoes what the
    /// narration already prints — the common case, e.g.
    /// `summary: "Editing AppModel.swift."` beside `Editing AppModel.swift`.
    static func clause(base: String?, summary: String?, narratedLine: String?) -> String? {
        let trimmed = (summary ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()
        if let base, !base.isEmpty, normalized.contains(base.lowercased()) { return nil }
        if let narratedLine, !narratedLine.isEmpty, normalized.contains(narratedLine.lowercased()) {
            return nil
        }
        return trimmed
    }
}

// MARK: - Scope-row copy (§E `.scope` · E6)

/// E6: the board's `.scope` rows are **sentences with a code chip inside them**,
/// not raw rule dumps:
///
/// - `Always allow ` `swift build` ` from this project` (`01-poured-island.html:1021-1022`)
/// - `Always allow all ` `swift` ` commands` (`:1025`)
/// - `Always allow edits to ` `README.md` (E2, `:1067-1068`)
///
/// Native printed `ClaudePermissionUpdate.displayLabel` verbatim — `Yes, allow
/// running swift build in this project` — and the generic fallback printed
/// `Always Allow (Bash)`, a Title-Cased verb with the raw tool name in
/// parentheses. Both are the shipped copy of four other surfaces, so rather than
/// re-writing `displayLabel` (which other themes read) this decomposes the
/// *update* into the board's three parts, Poured-side only.
///
/// The localized strings carry the full sentence with a `%@` where the chip goes;
/// `Parts` splits each one at that marker so a locale can move the chip.
enum PouredScopeCopy: Sendable, Equatable {
    struct Parts: Sendable, Equatable {
        var prefix: String
        var code: String
        var suffix: String
    }

    /// Splits a localized format at its single `%@`, so the chip can be composed
    /// in the middle of a sentence the translator controls end to end.
    static func parts(format: String, code: String) -> Parts {
        guard let marker = format.range(of: "%@") else {
            return Parts(prefix: format, code: code, suffix: "")
        }
        return Parts(
            prefix: String(format[format.startIndex..<marker.lowerBound]),
            code: code,
            suffix: String(format[marker.upperBound...])
        )
    }

    /// Which sentence an update takes, and what goes on its chip. `nil` for the
    /// updates the board never renders as a scope row (mode changes, directory
    /// grants) — those keep `displayLabel`.
    static func shape(for update: ClaudePermissionUpdate) -> (key: String, code: String)? {
        guard case let .addRules(destination, rules, _) = update, let rule = rules.first else {
            return nil
        }
        let content = rule.ruleContent?.trimmedForRow
        guard let content, !content.isEmpty else {
            // No rule content — the grant is the whole tool. Board: "Always allow
            // all `swift` commands".
            return ("poured.approval.scope.allCommands", rule.toolName)
        }
        if rule.toolName == "Edit" || rule.toolName == "Write" {
            return ("poured.approval.scope.edits", content)
        }
        switch destination {
        case .projectSettings, .localSettings:
            return ("poured.approval.scope.fromProject", content)
        default:
            return ("poured.approval.scope.thisSession", content)
        }
    }

    /// X7: what goes on the gold chip of the generic
    /// "Always allow all `%@` commands" fallback row.
    ///
    /// The board's chip is the **executable** (`swift`,
    /// `01-poured-island.html:1025`), never the harness's tool identifier.
    /// Native handed it `permissionRequest.toolName`, which for a shell call is
    /// `exec_command` — a raw internal id printed in the one place the board
    /// puts a real command word. The rule:
    ///
    /// - a shell-exec tool is not itself a command, so the chip becomes the
    ///   first meaningful token of the request's own command preview;
    /// - a tool name that still reads as an identifier (`snake_case`) with no
    ///   usable preview yields `nil`, and the caller draws no row at all;
    /// - everything else keeps the tool name (`Edit`, `Write`, `git`, …).
    static func genericScopeChip(toolName: String?, commandPreview: String?) -> String? {
        let tool = (toolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let executable = executableName(in: commandPreview)
        if shellExecToolNames.contains(tool.lowercased()) { return executable }
        guard !tool.isEmpty else { return executable }
        // Still an identifier rather than a word a user typed — prefer the real
        // command, and print nothing if there isn't one.
        if tool.contains("_") { return executable }
        return tool
    }

    /// Tool identifiers whose payload — not their name — carries the command.
    private static let shellExecToolNames: Set<String> = [
        "bash", "exec_command", "shell", "run_command", "run_terminal_cmd", "terminal",
    ]

    /// The bare executable at the head of a shell command — `sed` from
    /// `sed -i '' -e 's/…/…/g' …`. A leading `FOO=bar` environment assignment is
    /// skipped, and an absolute path (`/usr/bin/sed`) is reduced to its last
    /// component, so the chip is always the word the user would recognise.
    static func executableName(in commandPreview: String?) -> String? {
        let preview = (commandPreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preview.isEmpty else { return nil }
        for token in preview.split(separator: " ") {
            let word = String(token)
            if word.contains("=") { continue }
            let bare = word.split(separator: "/").last.map(String.init) ?? word
            guard !bare.isEmpty else { continue }
            return bare
        }
        return nil
    }
}

/// §F keycap glyphs that are not permission decisions. Pinned here (rather than
/// inline at the theme seam) so `PouredThemeTests` can assert the Submit cap
/// stays `↵` — the board's `&#8629;` — and never drifts to `⏎`/`Enter`.
enum PouredQuestionKeycaps {
    /// `.q-foot .btn.primary .kc kbd` — `↵` (`01-poured-island.html:1194`).
    static let submit = ["\u{21B5}"]
}

enum PouredApprovalShortcut {
    case allowOnce
    case alwaysAllow
    case deny

    /// The key-hint glyphs printed on the keycap, in order.
    var glyphs: [String] {
        switch self {
        case .allowOnce: ["⌘", "Y"]
        case .alwaysAllow: ["⌘", "⇧", "Y"]
        case .deny: ["⌘", "N"]
        }
    }
}

/// The Poured keycap chip (`SPEC` §2 `.kc kbd` role, 10pt/600) — first keycap
/// rendering in Poured. Two visual variants: a light chip for dark buttons /
/// scope rows, an ink chip for the amber primary (so it reads on the light
/// gradient), per the mockup `.kc kbd` / `.btn.primary .kc kbd`.
private struct PouredKeycapRow: View {
    let glyphs: [String]
    /// PI-C-006: the board's `Answer` chip prints a *range* — `1`–`3` with the
    /// en-dash **outside** the two keycaps (`01-poured-island.html:838`).
    var separator: String?
    /// R4-3: the separator is chip text, not keycap text — it takes the hosting
    /// chip's ink so `Answer 1–3` reads as one phrase.
    var separatorInk: Color?
    var onAmber: Bool = false

    init(shortcut: PouredApprovalShortcut, onAmber: Bool = false) {
        self.glyphs = shortcut.glyphs
        self.separator = nil
        self.onAmber = onAmber
    }

    init(glyphs: [String], separator: String? = nil, separatorInk: Color? = nil, onAmber: Bool = false) {
        self.glyphs = glyphs
        self.separator = separator
        self.separatorInk = separatorInk
        self.onAmber = onAmber
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(glyphs.enumerated()), id: \.offset) { index, glyph in
                if index > 0, separator != nil {
                    // R4-3 (`01-poured-island.html:838`): the range separator
                    // between the two caps — the board's `&#8211;`, which renders
                    // **6.5 × 1.5pt** in the §C frame (measured on
                    // `frame-C-2x.png`: a 13×3px rule at 2×), in the hosting
                    // chip's ink.
                    //
                    // **Deviation, recorded.** Drawn as a rule rather than set as
                    // `Text("\u{2013}")`. Typeset at the keycap role it rendered
                    // 2×3px and at the chip role 4×4px — a speck that reads as an
                    // interpunct ("Answer 1 · 3"), which is exactly the defect
                    // R4-3 names. The dash is chrome joining two keycaps, not
                    // prose, so its geometry is stated directly and now matches
                    // the reference at the pixel.
                    Capsule(style: .continuous)
                        .fill(separatorInk ?? PouredApprovalColors.keycapInk)
                        .frame(width: 6.5, height: 1.5)
                }
                Text(glyph)
                    .font(PouredType.Role.keycap.font)
                    .foregroundStyle(onAmber ? PouredApprovalColors.keycapInkOnAmber : PouredApprovalColors.keycapInk)
                    .frame(minWidth: 15, minHeight: 16)
                    .padding(.horizontal, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(onAmber ? PouredApprovalColors.keycapFillOnAmber : PouredApprovalColors.keycapFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(onAmber ? PouredApprovalColors.keycapStrokeOnAmber : PouredApprovalColors.keycapStroke, lineWidth: 1)
                            )
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

/// The Allow / Deny button label: title + keycap, filled per its kind. Amber
/// gradient for `.allow` (`#ffce8a→#ffb14d`, ink `#3a2405`), red-wash for
/// `.deny` (`rgba(219,82,82,.14)`, text `#f0a8a8`) — `SPEC` §4E.
///
/// Not `private` (overlay remediation Phase 2A-follow-up · F1):
/// `PouredIslandTheme.questionSubmitButton` constructs this directly from
/// `PouredIslandTheme.swift` for the shared question card's Submit CTA, via
/// three additive parameters instead of a fork: `shortcut` is now optional
/// (Submit has no registered digit shortcut of its own), `expands: false` keeps
/// shared `.btn` sizing intrinsic (`display:inline-flex`,
/// `01-poured-island.html:1192`) while the reusable label style owns its chrome,
/// and `fillOverride` supplies the board's own, slightly lighter Submit stops
/// (`#ffe0a8→#ffd58a`, ink `#2a2205`) — distinct from `.allow`'s
/// `#ffce8a→#ffb14d`, so this is not just Allow's literal gradient reused.
/// `kind: .allow` is passed for Submit by convention (closest existing
/// semantic — an affirmative default action); it only resolves the keycap's
/// `onAmber` tint and the `fillOverride == nil` fallback, neither of which
/// Submit exercises. `isEnabled` dims + desaturates the resolved fill in place
/// (`IslandQuestionSubmitDisabledStyle`) — Allow/Deny never pass `false` (both
/// are only ever shown while actionable), so this path is new and, in
/// practice, Submit-only.
struct PouredApprovalButtonLabel: View {
    enum Kind { case allow, deny }

    let title: String
    var shortcut: PouredApprovalShortcut?
    /// Slice 5 · §F: a keycap that is **not** one of the three approval
    /// decisions — the question submit's `↵` (`01-poured-island.html:1194`,
    /// `:1234`), which `OverlayPanelController`'s Return handler really fires
    /// (`handleQuestionSubmitKey`). Kept as glyphs rather than a fourth
    /// `PouredApprovalShortcut` case so the approval enum stays exactly the three
    /// permission decisions it documents.
    var keycapGlyphs: [String]?
    let kind: Kind
    var expands: Bool = true
    var fillOverride: (top: Color, bottom: Color, ink: Color)?
    var isEnabled: Bool = true
    /// The question-submit seam owns its special fill override; the six row
    /// CTAs delegate their chrome to `PouredFullSizeButtonStyle` instead.
    var usesStandaloneChrome: Bool = true

    var body: some View {
        if usesStandaloneChrome {
            standaloneLabel
        } else {
            labelContent
        }
    }

    private var labelContent: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
            if let shortcut {
                PouredKeycapRow(shortcut: shortcut, onAmber: capsOnAmber)
            } else if let keycapGlyphs, !keycapGlyphs.isEmpty {
                // Y4, replicated as rendered: `.btn.primary .kc kbd` (board
                // L360) is never overridden per variant, so the amber-derived
                // cap tint leaks onto the gold Submit exactly as the board draws
                // it — brown caps on a `#ffd58a` face. Recorded as an escalation
                // candidate; NOT "fixed" here (R5: rendered is golden).
                PouredKeycapRow(glyphs: keycapGlyphs, onAmber: capsOnAmber)
            }
        }
    }

    private var standaloneLabel: some View {
        labelContent
        .font(PouredType.Role.heroButtonLabel.font)
        .foregroundStyle(ink)
        .frame(maxWidth: expands ? .infinity : nil)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(buttonBackground)
        // X6: no blanket `.saturation()/.opacity()` dim any more — see
        // `PouredQuestionColors.submitDisabled*`. The disabled state is painted,
        // not faded, because fading a dark ink on a light fill onto a dark panel
        // collapses both toward the same tone (measured 1.18:1).
    }

    /// X6: the board's brown `.btn.primary .kc kbd` recipe is a *light-face*
    /// treatment. A disabled Poured Submit no longer has a light face, so its
    /// caps take the dark-surface pair (white ink on a black chip) — otherwise
    /// `#5a3a0c` on `#3e3629` would be an invisible keycap. Enabled buttons are
    /// untouched.
    private var capsOnAmber: Bool { isEnabled && kind == .allow }

    private var ink: Color {
        guard isEnabled else { return PouredQuestionColors.submitDisabledInk }
        if let fillOverride { return fillOverride.ink }
        return kind == .allow ? PouredApprovalColors.allowInk : PouredApprovalColors.denyInk
    }

    @ViewBuilder
    private var buttonBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        if !isEnabled {
            // X6: Poured's own disabled face — opaque, so what the user sees is
            // exactly the pair the contrast test measures, whatever is behind it.
            shape.fill(
                LinearGradient(
                    colors: [
                        PouredQuestionColors.submitDisabledTop,
                        PouredQuestionColors.submitDisabledBottom,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else if let fillOverride {
            shape.fill(
                LinearGradient(
                    colors: [fillOverride.top, fillOverride.bottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            switch kind {
            case .allow:
                shape.fill(
                    LinearGradient(
                        colors: [PouredApprovalColors.allowTop, PouredApprovalColors.allowBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            case .deny:
                shape.fill(PouredApprovalColors.denyFill)
            }
        }
    }
}

/// One scoped always-allow row (mockup `.scope`): a lock glyph, the real human
/// `displayLabel`, and — on the first row — the `⌘⇧Y` key-hint.
private struct PouredScopeRow: View {
    /// E6: the row's copy, decomposed the way the board sets it — a sentence with
    /// a gold mono code chip inside. `nil` code keeps the plain-sentence form for
    /// the updates the board never draws as a scope row.
    let parts: PouredScopeCopy.Parts
    let showsKeycap: Bool
    let action: () -> Void

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    /// The full sentence, chip included — what VoiceOver hears, since the chip is
    /// a typographic treatment and not a separate control.
    private var spokenLabel: String {
        (parts.prefix + parts.code + parts.suffix)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                    .accessibilityHidden(true)
                sentence
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if showsKeycap {
                    PouredKeycapRow(shortcut: .alwaysAllow)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.02))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
    }

    /// `.scope code{font-family:var(--mono); font-size:11px; color:#ffd9a8;
    /// background:rgba(255,177,77,.1); padding:1px 5px; border-radius:4px}`
    /// (`01-poured-island.html:369-370`). SwiftUI `Text` concatenation carries no
    /// per-run background, so the chip's fill rides on an `AttributedString` run
    /// — the same technique `LocalMarkdownText` uses for inline `code`.
    private var sentence: Text {
        var chip = AttributedString(parts.code)
        chip.font = PouredType.Role.assistantInlineCode.font
        chip.foregroundColor = PouredApprovalColors.scopeCodeInk
        chip.backgroundColor = PouredPalette.attention.opacity(0.1)
        return Text(parts.prefix) + Text(chip) + Text(parts.suffix)
    }
}

/// The Poured permission hero's literal colour palette (`SPEC` §4E / mockup
/// `01-poured-island.html`). Theme-local like `PouredPalette` — these are exact
/// hero hexes, not status tokens, so they live beside the view rather than on the
/// token layer.
private enum PouredApprovalColors {
    // Hero head / effect line
    static let titleInk = Color(red: 0xFF/255, green: 0xE6/255, blue: 0xC2/255)             // #ffe6c2
    static let codexTitleInk = Color(red: 0xCF/255, green: 0xE8/255, blue: 0xFB/255)        // #cfe8fb
    static let effectInk = Color(red: 0xFF/255, green: 0xD6/255, blue: 0xA0/255).opacity(0.75) // rgba(255,214,160,.75)
    /// `.hero-head .hs` — `rgba(255,214,160,.7)` (a hair quieter than the
    /// effect line's .75; the board sets both separately).
    static let subtitleInk = Color(red: 0xFF/255, green: 0xD6/255, blue: 0xA0/255).opacity(0.7)
    /// `.hero-head .agent-tag` — `rgba(255,214,160,.85)`.
    static let agentTagInk = Color(red: 0xFF/255, green: 0xD6/255, blue: 0xA0/255).opacity(0.85)
    /// E3's blue re-tint of the same two roles — `rgba(190,224,246,.7)` / `.85`.
    static let codexSubtitleInk = Color(red: 0xBE/255, green: 0xE0/255, blue: 0xF6/255).opacity(0.7)
    static let codexAgentTagInk = Color(red: 0xBE/255, green: 0xE0/255, blue: 0xF6/255).opacity(0.85)

    /// `.scope code{color:#ffd9a8}` on a `rgba(255,177,77,.1)` chip (`:369-370`).
    static let scopeCodeInk = Color(red: 0xFF/255, green: 0xD9/255, blue: 0xA8/255)         // #ffd9a8

    // `.amber-hero` interior — the board's near-black warm well
    // `linear-gradient(180deg, rgba(58,42,20,.55), rgba(30,22,12,.6))` (`:303`),
    // the amber peer of `PouredQuestionColors.wash*`. The shipped fill lit the
    // interior with bright amber at low alpha (`accent@0.16→.08`), which read
    // ~3× above the board's rgb(44,36,27) well; these are the board's own stops.
    static let heroWellTop = Color(red: 0x3A/255, green: 0x2A/255, blue: 0x14/255).opacity(0.55)     // rgba(58,42,20,.55)
    static let heroWellBottom = Color(red: 0x1E/255, green: 0x16/255, blue: 0x0C/255).opacity(0.6)   // rgba(30,22,12,.6)
    // E3's blue `.amber-hero` override — `linear-gradient(180deg, rgba(24,40,54,.5), rgba(14,24,34,.55))` (`:1089`).
    static let heroWellBlueTop = Color(red: 0x18/255, green: 0x28/255, blue: 0x36/255).opacity(0.5)     // rgba(24,40,54,.5)
    static let heroWellBlueBottom = Color(red: 0x0E/255, green: 0x18/255, blue: 0x22/255).opacity(0.55) // rgba(14,24,34,.55)

    // Command block
    static let commandInk = Color(red: 0xC9/255, green: 0xCE/255, blue: 0xDB/255)           // #c9cedb (plain runs)
    static let codeSurface = Color(red: 0x06/255, green: 0x08/255, blue: 0x0D/255).opacity(0.6) // rgba(6,8,13,.6)
    static let syntaxPalette: [ShellCommandTokenizer.Kind: Color] = [
        .command: Color(red: 0xF2/255, green: 0xF5/255, blue: 0xFB/255),                    // #f2f5fb
        .subcommand: Color(red: 0x8F/255, green: 0xD0/255, blue: 0xFF/255),                 // #8fd0ff
        .flag: Color(red: 0x6E/255, green: 0xA7/255, blue: 0xFF/255),                       // #6ea7ff
        .string: Color(red: 0x7F/255, green: 0xD3/255, blue: 0x9A/255),                     // #7fd39a
        .path: Color(red: 0xF2/255, green: 0xF5/255, blue: 0xFB/255).opacity(0.55),         // rgba(242,245,251,.55)
    ]

    // Buttons
    static let allowTop = Color(red: 0xFF/255, green: 0xCE/255, blue: 0x8A/255)             // #ffce8a
    static let allowBottom = Color(red: 0xFF/255, green: 0xB1/255, blue: 0x4D/255)          // #ffb14d
    static let allowInk = Color(red: 0x3A/255, green: 0x24/255, blue: 0x05/255)             // #3a2405
    static let denyFill = Color(red: 0xDB/255, green: 0x52/255, blue: 0x52/255).opacity(0.14) // rgba(219,82,82,.14)
    static let denyInk = Color(red: 0xF0/255, green: 0xA8/255, blue: 0xA8/255)              // #f0a8a8

    /// PI-C-006 · `.actionable` row wash — `rgba(255,177,77,.16)`.
    static let rowWash = Color(red: 0xFF/255, green: 0xB1/255, blue: 0x4D/255).opacity(0.16)

    /// R2/C2 · the compact permission row's `.act` ink — `#ffd9a8` (line 818).
    static let askInk = Color(red: 0xFF/255, green: 0xD9/255, blue: 0xA8/255)

    // Keycaps
    static let keycapFill = Color.black.opacity(0.28)
    static let keycapStroke = Color.white.opacity(0.14)
    static let keycapInk = Color.white.opacity(0.75)
    static let keycapFillOnAmber = Color(red: 0x3A/255, green: 0x24/255, blue: 0x05/255).opacity(0.25) // rgba(58,36,5,.25)
    static let keycapStrokeOnAmber = Color(red: 0x3A/255, green: 0x24/255, blue: 0x05/255).opacity(0.3)
    static let keycapInkOnAmber = Color(red: 0x5A/255, green: 0x3A/255, blue: 0x0C/255)     // #5a3a0c

    // §D detail primary (Slice 5 · board L963-964) — its OWN blue, not E3's.
    static let detailButtonTop = Color(red: 0x8F/255, green: 0xBC/255, blue: 0xFF/255)      // #8fbcff
    static let detailButtonBottom = Color(red: 0x6E/255, green: 0xA7/255, blue: 0xFF/255)   // #6ea7ff
    static let detailButtonInk = Color(red: 0x0A/255, green: 0x1A/255, blue: 0x35/255)      // #0a1a35

    // Codex (E3)
    static let codexBlue = Color(red: 0x4A/255, green: 0xA3/255, blue: 0xDF/255)            // #4aa3df
    static let codexButtonTop = Color(red: 0x8F/255, green: 0xCC/255, blue: 0xF0/255)       // #8fccf0
    static let codexButtonInk = Color(red: 0x06/255, green: 0x21/255, blue: 0x33/255)       // #062133
    static let codexNoteInk = Color(red: 0xBF/255, green: 0xE0/255, blue: 0xF6/255)         // #bfe0f6

    // Diff (E2)
    static let diffDelFill = Color(red: 0xDB/255, green: 0x52/255, blue: 0x52/255).opacity(0.13) // rgba(219,82,82,.13)
    static let diffDelInk = Color(red: 0xF0/255, green: 0xB3/255, blue: 0xB3/255)           // #f0b3b3
    static let diffDelGutter = Color(red: 0xDB/255, green: 0x52/255, blue: 0x52/255).opacity(0.6)
    static let diffAddFill = Color(red: 0x6F/255, green: 0xB9/255, blue: 0x82/255).opacity(0.14) // rgba(111,185,130,.14)
    static let diffAddInk = Color(red: 0xA8/255, green: 0xE0/255, blue: 0xBB/255)           // #a8e0bb
    static let diffAddGutter = Color(red: 0x6F/255, green: 0xB9/255, blue: 0x82/255).opacity(0.7)
    static let diffContextInk = Color(red: 0xF2/255, green: 0xF5/255, blue: 0xFB/255).opacity(0.55)
    static let diffContextGutter = Color(red: 0xF2/255, green: 0xF5/255, blue: 0xFB/255).opacity(0.3)
}

extension IslandDiffStyle {
    /// E2's original Poured treatment, factored into the shared renderer's
    /// style input. The component keeps the gutter and marker structural while
    /// this factory retains the Poured card's exact palette and transparency
    /// fallback.
    static func poured(
        tokens: IslandThemeTokens,
        reduceTransparency: Bool,
        fileName: String? = nil,
        hunk: String? = nil,
        additionalHiddenLines: Int = 0
    ) -> Self {
        // E2 (X8): a request carrying a hunk description renders the board's
        // `<file> · <hunk>` `.fname` line; without one the header stays on the
        // shipped `Updated +N −N` treatment (a header-less style), so a missing
        // hunk never leaves a dangling separator. The header treatment otherwise
        // matches the pre-X8 poured header exactly — only the copy differs.
        let headerColor = tokens.colors.paper.opacity(0.6)
        let headerBackground = Color.white.opacity(0.03)
        let normalizedHunk = hunk?.trimmingCharacters(in: .whitespacesAndNewlines)
        // P5: the board's `.fname` (`01-poured-island.html:342`) carries
        // `padding:6px 10px` and a `border-bottom:1px solid rgba(242,245,251,.09)`
        // — Slice 5 X8 left both out as copy-only scope; they land here now.
        let header: HeaderStyle? = (normalizedHunk?.isEmpty == false)
            ? HeaderStyle(
                title: .pouredFile(fileName: fileName, hunk: normalizedHunk),
                font: PouredType.Role.diff.font,
                iconFont: PouredType.Role.diff.font,
                iconOpacity: 1,
                color: headerColor,
                background: headerBackground,
                horizontalPadding: 10,
                verticalPadding: 6,
                bottomBorder: Border(color: tokens.colors.paper.opacity(0.09), width: 1)
            )
            : nil
        return Self(
            gutterWidth: 26,
            markerWidth: 10,
            horizontalPadding: 8,
            font: PouredType.Role.diff.font,
            typography: Typography(size: 11.5, weight: .regular, design: .monospaced),
            added: LineColors(
                gutter: PouredApprovalColors.diffAddGutter,
                marker: PouredApprovalColors.diffAddInk,
                content: PouredApprovalColors.diffAddInk,
                background: PouredApprovalColors.diffAddFill
            ),
            removed: LineColors(
                gutter: PouredApprovalColors.diffDelGutter,
                marker: PouredApprovalColors.diffDelInk,
                content: PouredApprovalColors.diffDelInk,
                background: PouredApprovalColors.diffDelFill
            ),
            context: LineColors(
                gutter: PouredApprovalColors.diffContextGutter,
                marker: PouredApprovalColors.diffContextInk,
                content: PouredApprovalColors.diffContextInk,
                background: .clear
            ),
            headerColor: headerColor,
            headerBackground: headerBackground,
            containerBackground: reduceTransparency ? tokens.colors.surfaceInk : PouredApprovalColors.codeSurface,
            containerBorder: Border(color: .white.opacity(0.06), width: 1),
            containerShape: .rounded(cornerRadius: 10),
            additionalHiddenLines: additionalHiddenLines,
            header: header
        )
    }
}

/// The question hero (`.q-hero`) gold chrome (`SPEC` §4F · mockup `.q-hero`).
/// The header chip fill and selection ring live inside the shared
/// `StructuredQuestionPromptView` (token-driven, `statusWaitingForAnswer`), so
/// this table only carries the outer wash + ring the Poured wrapper adds.
///
/// Not `private` (overlay remediation Phase 2A-follow-up · F1):
/// `PouredIslandTheme.questionSubmitButton` reads `submitTop`/`submitBottom`
/// /`submitInk` from `PouredIslandTheme.swift`.
enum PouredQuestionColors {
    /// `.q-hero` gradient top — `rgba(52,44,22,.4)`.
    static let washTop = Color(red: 0x34/255, green: 0x2C/255, blue: 0x16/255).opacity(0.4)
    /// `.q-hero` gradient bottom — `rgba(26,22,12,.5)`.
    static let washBottom = Color(red: 0x1A/255, green: 0x16/255, blue: 0x0C/255).opacity(0.5)
    /// `.q-hero` inset ring — `rgba(255,213,138,.24)` (the `#ffd58a` gold at .24).
    static let ring = Color(red: 0xFF/255, green: 0xD5/255, blue: 0x8A/255).opacity(0.24)

    /// The Submit button's own stops (overlay remediation Phase 2A-follow-up ·
    /// F1, Decision 1): `01-poured-island.html:1192` inline-overrides
    /// `.btn.primary`'s default Allow gradient (`#ffce8a→#ffb14d`) with a
    /// lighter `linear-gradient(180deg,#ffe0a8,#ffd58a)` and ink `#2a2205` for
    /// the question card's Submit specifically — the board specifies the two
    /// CTAs separately, so this is not `PouredApprovalButtonLabel.allow`'s
    /// literal gradient reused.
    static let submitTop = Color(red: 0xFF/255, green: 0xE0/255, blue: 0xA8/255)    // #ffe0a8
    static let submitBottom = Color(red: 0xFF/255, green: 0xD5/255, blue: 0x8A/255) // #ffd58a
    static let submitInk = Color(red: 0x2A/255, green: 0x22/255, blue: 0x05/255)    // #2a2205

    // MARK: X6 — the disabled Submit

    /// X6 (C's M-1): the §F Submit's **disabled** paint.
    ///
    /// The shared recipe (`IslandQuestionSubmitDisabledStyle` —
    /// `.saturation(0.35).opacity(0.5)` over the enabled paint) desaturates the
    /// gold face *and* the near-black ink toward the same mid tone and then
    /// half-composites both onto the dark panel: reviewer C measured the
    /// resulting label-on-fill contrast at **1.18:1**, i.e. an unreadable
    /// button, which is worse than useless on the one control that tells the
    /// user what Return will do.
    ///
    /// Poured therefore paints its own disabled state instead of dimming the
    /// enabled one: an opaque, quiet gold-brown face carrying a muted gold ink.
    /// Both stops clear ≥ 3:1 against the ink they carry
    /// (`PouredSlice5CorrectionsTests` computes the WCAG ratio from these
    /// literals, so a future retint fails the build rather than the eye), and
    /// the button still reads unmistakably quieter than the lit `#ffd58a` face.
    /// Poured-scoped — the shared constants are untouched, so Halo and Flight
    /// Deck keep the recipe they shipped with.
    static let submitDisabledTop = Color(red: 0x3E/255, green: 0x36/255, blue: 0x29/255)    // #3e3629
    static let submitDisabledBottom = Color(red: 0x33/255, green: 0x2C/255, blue: 0x21/255) // #332c21
    static let submitDisabledInk = Color(red: 0xC7/255, green: 0xA8/255, blue: 0x71/255)    // #c7a871

    /// The same three literals as sRGB components, so the contrast test can do
    /// the arithmetic without reaching into `Color`'s opaque storage.
    static let submitDisabledTopRGB: (Double, Double, Double) = (0x3E/255, 0x36/255, 0x29/255)
    static let submitDisabledBottomRGB: (Double, Double, Double) = (0x33/255, 0x2C/255, 0x21/255)
    static let submitDisabledInkRGB: (Double, Double, Double) = (0xC7/255, 0xA8/255, 0x71/255)

    /// PI-C-006 · the question row's own inline wash — `rgba(255,213,138,.13)`
    /// (`01-poured-island.html:830`): gold, and a touch quieter than the
    /// permission row's amber.
    static let rowWash = Color(red: 0xFF/255, green: 0xD5/255, blue: 0x8A/255).opacity(0.13)
    /// R2/C1 · the compact question row's `.act` ink — `#fff0cf` (line 835).
    static let askInk = Color(red: 0xFF/255, green: 0xF0/255, blue: 0xCF/255)
    /// `Answer` chip fill / ink — `rgba(255,213,138,.14)` on `#ffe6b8` (line 837).
    static let answerChipFill = Color(red: 0xFF/255, green: 0xD5/255, blue: 0x8A/255).opacity(0.14)
    static let answerChipInk = Color(red: 0xFF/255, green: 0xE6/255, blue: 0xB8/255)
}

/// The completion outcome badge (`.outcome`) fills (`SPEC` §4H · mockup
/// `.outcome.ok/.intr/.fail`). Text tints come from the shared status tokens
/// (`statusCompleted` / `statusWarning` / `statusFailed`); only the tinted pill
/// backgrounds are Poured-local here.
private enum PouredCompletionColors {
    /// `.outcome.ok` background — `rgba(111,185,130,.14)`.
    static let successFill = Color(red: 0x6F/255, green: 0xB9/255, blue: 0x82/255).opacity(0.14)
    /// `.outcome.intr` background — `rgba(217,140,38,.16)`.
    static let interruptedFill = Color(red: 0xD9/255, green: 0x8C/255, blue: 0x26/255).opacity(0.16)
    /// `.outcome.fail` background — `rgba(219,82,82,.16)`.
    static let failedFill = Color(red: 0xDB/255, green: 0x52/255, blue: 0x52/255).opacity(0.16)
}

/// Wraps the approval card in Poured's pulsing hero glow (`heropulse`, `SPEC`
/// §4E E1). Isolated as a modifier so the 15fps `PulseClock` read invalidates
/// only the glow (not the buttons inside), and so Reduce Motion — or a missing
/// clock — renders a static-but-still-loud glow (the wide ambient layer is
/// always present) rather than a breathing one. The tint is supplied by the
/// card (amber `attention`, or Codex blue), keeping this geometry-only.
private struct PouredAmberGlow: ViewModifier {
    let tint: Color
    let pulseClock: PulseClock?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { !reduceMotion && pulseClock != nil }

    private var pulse: Double {
        animates ? (pulseClock?.phase ?? 0) : 0
    }

    func body(content: Content) -> some View {
        let hero = PouredPillMotion.Hero.self
        let ambientOpacity = hero.ambientOpacityMin + (hero.ambientOpacityMax - hero.ambientOpacityMin) * pulse
        content
            // Wide ambient "event" bloom (mockup 0 0 42px -6px), always present.
            .shadow(color: tint.opacity(ambientOpacity), radius: hero.ambientRadius)
            // Retuned breathing layers (r10+8·pulse / r20+10·pulse), retinted.
            .shadow(color: tint.opacity(hero.innerOpacityBase + pulse * hero.innerOpacityPulse),
                    radius: hero.innerRadiusBase + pulse * hero.innerRadiusPulse)
            .shadow(color: tint.opacity(hero.outerOpacityBase + pulse * hero.outerOpacityPulse),
                    radius: hero.outerRadiusBase + pulse * hero.outerRadiusPulse)
            .onAppear { if animates { pulseClock?.acquire() } }
            .onDisappear { if animates { pulseClock?.release() } }
    }
}

// MARK: - Row entrance

/// AB-332: the one-shot rise+fade a Poured row plays when it is **inserted** into
/// an already-mounted list (`PouredRowMotion.Entrance`, mockup `rowin`).
///
/// Expressed as a SwiftUI insertion `.transition` (applied per row by
/// `PouredSessionListScaffold`, driven by the scaffold's `entranceAnimation`
/// keyed to the row-id set) rather than an `onAppear` state machine. Two things
/// fall out for free: a container's **initial** appearance never plays insertion
/// transitions, so the whole list arrives at its settled frame under the panel's
/// own open-morph (and a first-render snapshot pins that settled frame); and the
/// scaffold gates the driving animation on Reduce Motion, so a reduced-motion
/// insert simply snaps in — no clock is ever touched.
enum PouredRowEntrance {
    /// Rise (`translateY`) + fade + top-anchored scale, from the mockup `rowin`
    /// keyframe. Removal is a plain fade so a dismissed row doesn't lurch.
    static var transition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: PouredRowMotion.Entrance.riseOffset)
                .combined(with: .opacity)
                .combined(with: .scale(scale: PouredRowMotion.Entrance.initialScale, anchor: .top)),
            removal: .opacity
        )
    }

    /// The settle spring the scaffold drives the insertion with (nil under
    /// Reduce Motion → the insert snaps).
    static let animation: Animation = .spring(
        response: PouredRowMotion.Entrance.springResponse,
        dampingFraction: PouredRowMotion.Entrance.springDamping,
        blendDuration: 0
    )
}

// MARK: - Glow dot

/// Poured's status dot: a filled circle wrapped in a soft luminous glow so
/// status reads as light bleeding into the glass rather than a flat chip.
/// `pulse` (0…1, from the shared `PulseClock`) breathes both the scale and the
/// glow radius. A little softer/larger than Classic's dot to match the frosted
/// surface.
/// R4-4 (`01-poured-island.html:160-166`, `:847`): the working row's `.lead`
/// marker — the board's `.glyph.run`, three bottom-aligned bars at `width:12px`
/// in `--run`, measured off the rendered §C frame at 2.5pt wide, 2.5pt apart,
/// `14 / 14 / 11` tall.
///
/// **Deviation, recorded.** The correction asked for the closed pill's
/// `UnifiedBars`. That component draws the same three bars but drives them with
/// a `CAKeyframeAnimation` wave, so the marker's height is whatever phase the
/// frame happens to catch — in a harness capture it landed at the wave's floor
/// and rendered three 2×3pt specks, which is not the board's glyph at any
/// amplitude. The lead marker is a *state* mark rather than a liveness meter
/// (the row's `.act` already carries `live 1m 42s`), so it is drawn statically at
/// the board's own frame and reads identically in every capture.
/// **Scaling.** The board draws the same glyph at four sizes — `width:12px`
/// (`.lead`), `10×11` (`.nest-h`, `:1289`), `9×10` (a rollup chip) and `8×9`
/// (`.todo.doing .tk`, `:1313`) — by shrinking the box while leaving `.glyph i`
/// at its literal `2.5px`/`5px` metrics, so the bars overflow every reduced box
/// (mapper contradiction C-7). Native scales the *bars* with the box instead:
/// `height` is the glyph's rendered height and every metric rides the same
/// `height / 15` factor, so a 9pt tick reads as the same mark, one size down.
private struct PouredRunBarsGlyph: View {
    let tint: Color

    /// Rendered height. `15` is the board's unscaled `.glyph` box.
    var height: CGFloat = PouredRunGlyphMetrics.referenceHeight

    /// `false` when the glyph *is* the status statement for its row (the §G
    /// todo tick), so the call site can label it and the row's combined
    /// VoiceOver stop keeps speaking done / doing / pending.
    var isDecorative: Bool = true

    var body: some View {
        let barWidth = PouredRunGlyphMetrics.barWidth(height: height)
        HStack(alignment: .bottom, spacing: barWidth) {
            ForEach(Array(PouredRunGlyphMetrics.barHeights(height: height).enumerated()), id: \.offset) { _, barHeight in
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: barWidth, height: barHeight)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(isDecorative)
    }
}

/// R4-10 (`01-poured-island.html:871`): the SSH chip's leading mark — the
/// board's 9×9 filled three-bar SVG, drawn in the chip's own ink
/// (`fill=currentColor`) rather than as an SF Symbol, so it keeps the board's
/// squat proportions at chip scale.
private struct PouredTransportBarsGlyph: View {
    var side: CGFloat = 9

    var body: some View {
        VStack(spacing: side * 0.19) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: side * 0.09, style: .continuous)
                    .frame(height: side * 0.18)
            }
        }
        .frame(width: side, height: side)
    }
}

/// `rgba(255,177,77,.22)` — the board's `.ring` band colour, literal.
private let pouredApproveRingColor = Color(
    red: 255 / 255,
    green: 177 / 255,
    blue: 77 / 255
).opacity(0.22)

/// R5 / PI-C-006 (`01-poured-island.html:204-212`): the board's list marker dot.
///
/// The board draws exactly two things here and nothing else:
/// `.dot{width:8px;height:8px;border-radius:50%}` filled in the state colour,
/// and — for the permission row only — `.ring{box-shadow:0 0 0 3px
/// rgba(255,177,77,.22)}`. A CSS *spread* shadow with zero blur is a **hard**
/// band: it paints the ±3px offset silhouette behind the disc, so the ring runs
/// from r=4 to r=7 with crisp edges on both sides. That ring is the shape
/// discriminator between a permission marker and a question marker — same
/// family of disc, different silhouette.
///
/// The soft monotonic bloom this helper used to draw (a 9px disc plus two
/// `.shadow` layers) exists nowhere on the board's list markers; the only glow
/// in the board's list is the running row's `.glyph.run`, which is a different
/// component entirely (`PouredRunBarsGlyph`). It is gone. What survives is the
/// pulse *scale* — the breathing semantics the shipped row had — applied to the
/// disc and its ring together so the marker keeps one silhouette.
private func pouredStatusDotView(
    tint: Color,
    pulse: Double,
    ring: Bool = false
) -> some View {
    // `.dot` — 8×8 in the state colour, so the disc's own radius is 4.
    let core: CGFloat = 8
    // `.ring` — `0 0 0 3px`: a band 3pt wide starting at the disc's edge, i.e.
    // r=4…7. `strokeBorder` draws inward from the frame, so the frame is the
    // band's *outer* diameter: 14.
    let bandWidth: CGFloat = 3
    let ringOuterDiameter = core + (bandWidth * 2)

    return Circle()
        .fill(tint)
        .frame(width: core, height: core)
        .overlay {
            if ring {
                Circle()
                    .strokeBorder(pouredApproveRingColor, lineWidth: bandWidth)
                    .frame(width: ringOuterDiameter, height: ringOuterDiameter)
            }
        }
        .scaleEffect(1 + (pulse * 0.2))
}

/// The breathing variant of `pouredStatusDotView`, isolated in its own `View`
/// so Observation's per-view tracking invalidates only this dot at 15fps
/// (AB-228), and so Reduce Motion never even acquires the shared clock — it
/// renders the settled (`pulse: 0`) dot instead (AB-244).
private struct PouredPulsingStatusDot: View {
    let pulseClock: PulseClock
    let tint: Color
    var ring: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            pouredStatusDotView(tint: tint, pulse: 0, ring: ring)
        } else {
            pouredStatusDotView(tint: tint, pulse: pulseClock.phase, ring: ring)
                .onAppear { pulseClock.acquire() }
                .onDisappear { pulseClock.release() }
        }
    }
}

/// AB-302: attaches a named VoiceOver action only when `name` is non-nil —
/// the row's "Dismiss" rotor action, present only for dismissible rows. A
/// local copy of the same modifier Classic's row uses (that one is file-private
/// to `IslandPanelView`).
/// E8: attaches an accessibility **hint** only when the supplementary text
/// exists and actually adds something the visible label does not already say.
/// The agent-supplied verb ("Yes", "Allow", "Approve") rides here so the
/// accessible *name* can stay the visible one.
struct PouredOptionalAccessibilityHint: ViewModifier {
    let hint: String?

    init(_ hint: String?) {
        self.hint = hint
    }

    func body(content: Content) -> some View {
        if let hint = hint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
            content.accessibilityHint(Text(hint))
        } else {
            content
        }
    }
}

private struct PouredOptionalNamedAccessibilityAction: ViewModifier {
    let name: String?
    let action: () -> Void

    func body(content: Content) -> some View {
        if let name {
            content.accessibilityAction(named: Text(name), action)
        } else {
            content
        }
    }
}

private extension String {
    var trimmedForRow: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Hero icon shapes (§E `.hero-icon` · E2)

/// The board's terminal-chevron `.hero-icon`, drawn from its own SVG paths in a
/// 24-unit viewBox: `M4 17l6-6-6-6` (the chevron) and `M12 19h8` (the underscore)
/// — `01-poured-island.html:1003-1004`. Scales to whatever frame it is given, so
/// the 14×14 the board states is a `.frame`, not a magic number in here.
struct PouredTerminalChevron: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24
        let sy = rect.height / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        var path = Path()
        // M4 17 l6-6 -6-6
        path.move(to: point(4, 17))
        path.addLine(to: point(10, 11))
        path.addLine(to: point(4, 5))
        // M12 19 h8
        path.move(to: point(12, 19))
        path.addLine(to: point(20, 19))
        return path
    }
}

// MARK: - Metadata cell copy (§D `.mcell` · D6)

/// The one sentence a §D metadata cell speaks. Pure so `PouredThemeTests` can pin
/// it without standing up a row: the cell is a *key/value pair*, and VoiceOver
/// should hear `"Agent, Claude Code"` — one stop, the key in its authored case
/// (never the `.uppercased()` chrome), the value verbatim.
enum PouredMetadataCellCopy: Sendable {
    static func accessibilityLabel(key: String, value: String) -> String {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty { return trimmedValue }
        if trimmedValue.isEmpty { return trimmedKey }
        return "\(trimmedKey), \(trimmedValue)"
    }
}

// MARK: - Metadata cell chrome (mockup §D `.mcell`)

/// The quiet cell slab every metadata entry sits in — a faint fill with an
/// inset hairline and a floor width so the grid reads as an even lattice rather
/// than ragged pills. Isolated as a modifier so every cell (text, agent chip,
/// live timer) wears the identical frame.
private struct MetadataCellChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Board `.mcell{min-width:88px}` (L445-446) under the sheet's
            // `box-sizing:border-box`, and the Model cell measures **exactly 88**
            // (`mapper-reference.md` §4.5). SwiftUI applies `minWidth` to the
            // content *before* padding, so the floor is the box minus the two
            // 11pt insets — 66 — where it used to be 84 and forced a 106pt cell.
            .frame(minWidth: 66, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(.white.opacity(0.045), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Full-size button contract (mockup `.btn`)

/// The four semantic treatments of Poured's one full-size `.btn` primitive.
/// The compact inline `.jump` chip remains a separate 11.5pt / r8 affordance;
/// only full-size Jump-to-terminal CTAs use this contract.
enum PouredFullSizeButtonKind: CaseIterable, Equatable {
    case event
    case wayfinding
    /// Slice 5 (§D): the detail card's `Jump to terminal` primary. The board
    /// overrides the amber `.btn.primary` with its OWN blue
    /// (`linear-gradient(180deg,#8fbcff,#6ea7ff)`, ink `#0a1a35`, glow
    /// `rgba(110,167,255,.6)` — `01-poured-island.html:963-964`), which is a
    /// different blue from E3's Codex CTA (`#8fccf0→#4aa3df`, ink `#062133`,
    /// `:1080`). Native collapsed both onto `.wayfinding` and rendered §D in
    /// E3's colour; splitting them is the whole reason this case exists.
    /// `.wayfinding` keeps E3 **and** §H's completion jump, whose board blue
    /// this round never extracted — §H is out of Slice 5, so it stays put.
    case detailPrimary
    case ghost
    case deny

    static let cornerRadius: CGFloat = 11
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 8

    /// PI-C-006: the §C list row overrides the same `.btn` to `padding:6px 12px;
    /// font-size:12px` (`01-poured-island.html:820`, `:822`) — a size, not a new
    /// treatment: radius, fill, ink and glow all stay the button's own.
    static let compactHorizontalPadding: CGFloat = 12
    static let compactVerticalPadding: CGFloat = 6

    var usesGradient: Bool {
        self == .event || self == .wayfinding || self == .detailPrimary
    }

    var showsButtonGlow: Bool {
        self == .event || self == .wayfinding || self == .detailPrimary
    }
}

/// The single full-size Poured button treatment. Every kind shares the `.btn`
/// base (r11, 14/8 padding, `heroButtonLabel` 13/600 sans, no border); kind
/// only changes semantic fill, ink and whether the primary glow is present.
private struct PouredFullSizeButtonStyle: ButtonStyle {
    let kind: PouredFullSizeButtonKind
    /// PI-C-006: the in-list compact override of the same button.
    var isCompact: Bool = false
    /// C4-3 (PI-X-001/H1 · `01-poured-island.html:1428`): §H's `Dismiss` is the
    /// **same** ghost chip as `Reply` / `Transcript` beside it with one inline
    /// override — `color:var(--t3)`. The chip is unchanged; only the label ink
    /// drops to tertiary, which is what makes the rail read left-to-right in
    /// descending weight instead of ending on its brightest control.
    var isDimmed: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        PouredFullSizeButtonChrome(
            kind: kind,
            isCompact: isCompact,
            isDimmed: isDimmed,
            configuration: configuration
        )
    }

    private struct PouredFullSizeButtonChrome: View {
        let kind: PouredFullSizeButtonKind
        let isCompact: Bool
        let isDimmed: Bool
        let configuration: Configuration

        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.islandTokens) private var tokens
        @Environment(\.colorSchemeContrast) private var colorSchemeContrast
        @State private var isHovering = false

        var body: some View {
            let base = configuration.label
                .font(isCompact ? PouredType.Role.compactButtonLabel.font : PouredType.Role.heroButtonLabel.font)
                .foregroundStyle(ink)
                .padding(.horizontal, isCompact ? PouredFullSizeButtonKind.compactHorizontalPadding : PouredFullSizeButtonKind.horizontalPadding)
                .padding(.vertical, isCompact ? PouredFullSizeButtonKind.compactVerticalPadding : PouredFullSizeButtonKind.verticalPadding)
                .background(background)
                .opacity(configuration.isPressed ? 0.82 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { isHovering = $0 }

            if kind.showsButtonGlow {
                base.shadow(color: reduceTransparency ? .clear : glowColor, radius: 10, y: 4)
            } else {
                base
            }
        }

        private var ink: Color {
            switch kind {
            case .event:
                return PouredApprovalColors.allowInk
            case .wayfinding:
                return PouredApprovalColors.codexButtonInk
            case .detailPrimary:
                return PouredApprovalColors.detailButtonInk
            case .ghost:
                // C4-3: `.btn.ghost{color:var(--t1)}` — `rgba(242,245,251,.96)`
                // (`01-poured-island.html:352`). The ghost is a *filled* chip,
                // not a dimmed one; only a call site that opts into `isDimmed`
                // (§H's `Dismiss`, whose inline rule is `color:var(--t3)`) drops
                // to tertiary. Native had the two inverted: every ghost painted
                // tertiary, so Dismiss and Transcript could not be told apart by
                // weight.
                let increased = colorSchemeContrast == .increased
                let alpha = isDimmed ? tokens.colors.tertiaryTextOpacity : 0.96
                return tokens.colors.paper.opacity(
                    tokens.colors.text(alpha, increaseContrast: increased)
                )
            case .deny:
                return PouredApprovalColors.denyInk
            }
        }

        private var glowColor: Color {
            switch kind {
            case .event:
                return PouredApprovalColors.allowBottom.opacity(0.5)
            case .wayfinding:
                return PouredApprovalColors.codexBlue.opacity(0.5)
            case .detailPrimary:
                // `box-shadow:0 4px 16px -4px rgba(110,167,255,.6)` — the board
                // states §D's glow alpha explicitly, so it is taken verbatim
                // rather than inheriting the shared .5.
                return PouredApprovalColors.detailButtonBottom.opacity(0.6)
            case .ghost, .deny:
                return .clear
            }
        }

        @ViewBuilder
        private var background: some View {
            let shape = RoundedRectangle(
                cornerRadius: PouredFullSizeButtonKind.cornerRadius,
                style: .continuous
            )

            switch kind {
            case .event:
                shape.fill(
                    LinearGradient(
                        colors: [PouredApprovalColors.allowTop, PouredApprovalColors.allowBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            case .wayfinding:
                shape.fill(
                    LinearGradient(
                        colors: [PouredApprovalColors.codexButtonTop, PouredApprovalColors.codexBlue],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            case .detailPrimary:
                shape.fill(
                    LinearGradient(
                        colors: [PouredApprovalColors.detailButtonTop, PouredApprovalColors.detailButtonBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            case .ghost:
                shape.fill(
                    Color(red: 0xF2/255, green: 0xF5/255, blue: 0xFB/255)
                        .opacity(isHovering ? 0.14 : 0.08)
                )
            case .deny:
                shape.fill(PouredApprovalColors.denyFill)
            }
        }
    }
}

// MARK: - Outcome badge (mockup §H `.outcome`)

/// The completion outcome pill (`SPEC` §4H · mockup `.outcome.ok/.intr/.fail`):
/// a glyph + label at the `outcomeBadge` role (10.5/650), the status tint on its
/// matching tinted-pill fill. State is glyph + colour, never colour alone.
private struct PouredOutcomeBadge: View {
    let glyphName: String
    let label: String
    let tint: Color
    let fill: Color

    /// PI-X-001/H1: the §H completion hero draws the same pill one step up —
    /// `font-size:11px;padding:3px 10px` (`01-poured-island.html:1400`). The §C
    /// row's badge (R13/X5) keeps the base metrics.
    var isHero: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: glyphName)
                .font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)
            Text(label)
                .font(isHero ? PouredType.Role.outcomeBadgeHero.font : PouredType.Role.outcomeBadge.font)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, isHero ? 10 : 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(fill))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

// MARK: - Metadata flow layout (mockup §D `.meta-grid{flex-wrap:wrap}`)

/// A left-to-right wrapping row (`flex-wrap: wrap`) for the metadata cells: it
/// lays subviews at their ideal size, breaking to a new line when the next cell
/// would overrun the proposed width. Small and self-contained so the grid can
/// reflow at either panel width without a fixed column count.
private struct PouredFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let addedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, addedWidth > maxWidth {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = addedWidth
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
