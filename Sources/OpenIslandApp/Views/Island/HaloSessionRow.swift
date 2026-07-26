import AppKit
import SwiftUI
@preconcurrency import MarkdownUI
import OpenIslandCore

/// Halo's session row — the collapsed **void row** (AB-344 · T25 · SPEC §5C/§5D ·
/// mockup §C/§D).
///
/// This is the Halo idiom taken to the row (SPEC §0): there is **no fill, no card,
/// no capsule** — the row floats in the pure-black void and all structure comes
/// from typography, a single achromatic monogram, the bloomed status dot, and (on
/// the live/actionable rows only) a 2pt edge-lit rail in the left margin. The
/// list-level chrome — the 8%-white inter-row hairlines and the white@.026 hover
/// wash — is drawn by `HaloSessionListScaffold`, so the row never re-draws them; it
/// owns only its own content and its own luminous bleed (the dot bloom + the rail
/// glow), which is exactly why Halo pins `rowIsDrawingGroupSafe = false` — a
/// `.drawingGroup()` would flatten/clip both to row bounds.
///
/// **Anatomy** (mockup `.row`): a `lead` column (status dot 8pt + achromatic
/// monogram), a `body` column (workspace title + T05 branch disambiguator; the T03
/// narrated activity with a "live" cyan verb for a running turn; meta chips + a
/// Jump chip on a completed row), the right-aligned tabular `age`, and a
/// hover-revealed dismiss. A fresh row plays a single ~0.7s light sweep on insert
/// (never looping; suppressed under Reduce Motion).
///
/// **The AB-344 Part-2 seam.** This part ships the *collapsed* row for **every**
/// phase (so the rail lights the live/permission/question rows in the list). The
/// expanded per-row detail and the actionable **heroes** — the permission command /
/// diff surface, the question options, the completion body, the subagent nests —
/// are Part 2 / AB-345. They mount **below** `HaloRowContent`'s summary: a later
/// agent adds an `isExpanded` slot and an actionable-body branch here, or forks the
/// notification presentation, with no change to the summary this file draws.
struct HaloSessionRow: View {
    let session: AgentSession
    var stateIndicator: IslandSessionStateIndicator = .animatedDot
    var completedStaleThreshold: TimeInterval = AgentSession.staleCompletedDisplayThreshold
    var isActionable: Bool = false
    /// Threaded to match the theme factory; Halo rows are never `.drawingGroup()`d
    /// (they carry glow), so this is deliberately unused (SPEC §1d / §3c).
    var useDrawingGroup: Bool = false
    var isInteractive: Bool = true
    /// Hover highlight, owned by the enclosing `SessionRowContainer` (AB-297) and
    /// the scaffold's hover wash. The row reads it only to reveal the dismiss glyph.
    let isHighlighted: Bool
    var presentation: IslandSessionRowPresentation = .list
    var sideInset: CGFloat = 16
    var lang: LanguageManager = .shared
    let actions: RowActions
    /// Reserved for the Part-2 question hero; the collapsed summary never uses it.
    var keyboardCoordinator: OverlayUICoordinator?
    /// Shared 15fps clock — threaded for the Part-2 heroes; the collapsed dot is a
    /// static bloomed light (the pulse lives on the perimeter edge, not the row).
    var pulseClock: PulseClock?

    var body: some View {
        HaloRowContent(
            session: session,
            completedStaleThreshold: completedStaleThreshold,
            isActionable: isActionable,
            isInteractive: isInteractive,
            isHighlighted: isHighlighted,
            presentation: presentation,
            sideInset: sideInset,
            lang: lang,
            actions: actions
        )
    }
}

// MARK: - Row content

/// The collapsed void body for every Halo row. Renders the shared summary (lead /
/// body / age / dismiss) drawn in the void idiom, plus the edge-lit rail and the
/// one-shot entrance sweep. The tap-to-jump and dismiss behaviours are preserved
/// verbatim from Classic so the row stays interchangeable inside one list.
private struct HaloRowContent: View {
    let session: AgentSession
    let completedStaleThreshold: TimeInterval
    let isActionable: Bool
    let isInteractive: Bool
    let isHighlighted: Bool
    let presentation: IslandSessionRowPresentation
    let sideInset: CGFloat
    let lang: LanguageManager
    let actions: RowActions

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// AB-323 · T05: list-level duplicate-workspace disambiguators, injected by
    /// `IslandPanelView`. Empty (the default) means "no collisions" and the title
    /// line renders the workspace name alone.
    @Environment(\.islandSessionDisambiguators) private var sessionDisambiguators

    /// Tap-toggled expansion (mockup §D "tap a row to expand it in place"). `nil`
    /// = follow the phase default; a tap latches an explicit open/closed. Reset
    /// when the list goes non-interactive so a settings preview never sticks open.
    @State private var detailOverride: Bool?

    /// The completion reply draft (§5H) — bound to the reply input on a finished,
    /// reply-capable row; cleared on submit.
    @State private var replyText: String = ""

    /// Harness / preview seam (AB-345 snapshots): when set, an expandable row is
    /// born expanded so a golden can pin the §5D grid / §5G nests / §5H body that
    /// otherwise only open on a tap. Defaults to `false` — production list rows
    /// open collapsed, and only the actionable row auto-expands (see below).
    @Environment(\.islandRowExpandedByDefault) private var expandedByDefault

    /// Each row owns its own age refresh so a tick invalidates only this row.
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
        let presence: IslandSessionPresence = isStaleCompleted ? .inactive : rawPresence
        let edgeState = HaloSessionRowFormat.edgeState(
            phase: session.phase,
            presence: presence,
            outcome: session.outcome
        )
        let rail = HaloSessionRowFormat.rail(for: edgeState)
        let isExpanded = resolvedIsExpanded(presence: presence)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                leadColumn(edgeState: edgeState, presence: presence)

                bodyColumn(
                    edgeState: edgeState,
                    presence: presence,
                    isExpanded: isExpanded,
                    referenceDate: referenceDate
                )

                Spacer(minLength: 8)

                trailingColumn(presence: presence, isExpanded: isExpanded, referenceDate: referenceDate)
            }
            .padding(.horizontal, sideInset)
            .padding(.top, 12)
            .padding(.bottom, isExpanded ? 6 : 12)

            // The Part-2 expanded slot (§5D/§5G/§5H): the metadata grid, the
            // subagent / todo nests, the rich last-message / result, and the
            // follow-up rail. Mounts below the summary; the summary above is
            // untouched. The permission / question interiors are AB-345's — they
            // replace the `sessionDetailBody` branch with their command / options
            // heroes without touching the collapsed row.
            if isExpanded {
                expandedDetail(edgeState: edgeState, presence: presence, referenceDate: referenceDate)
            }
        }
        // The 2pt edge-lit rail sits at the row's left edge, inset vertically — a
        // colored glow bleeds off it into the void (mockup `.rail` box-shadow). Only
        // the live / actionable states draw it; a settled or idle row is rail-free.
        .overlay(alignment: .leading) {
            if presentation == .list, let rail {
                HaloEdgeLitRail(rail: rail, tokens: tokens)
            }
        }
        // Row entrance: a single ~0.7s light sweep on insert (never loops; none
        // under Reduce Motion — the row just appears). Clipped to the row bounds so
        // the sweep stays inside while the dot bloom / rail glow bleed freely.
        .modifier(HaloRowEntranceSweep(enabled: presentation == .list && !reduceMotion))
        // Idle / stale rows recede into the void.
        .opacity(presence == .inactive ? 0.7 : 1)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.14), value: isHighlighted)
        .animation(.easeInOut(duration: 0.18), value: session.phase)
        .animation(.easeInOut(duration: 0.18), value: session.outcome)
        .animation(.easeInOut(duration: 0.18), value: presence)
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
        .onTapGesture(perform: handlePrimaryTap)
        .onChange(of: isInteractive) { _, interactive in
            if !interactive { detailOverride = nil }
        }
        // One grouped VoiceOver summary — identical wording to every theme so rows
        // read the same however they're skinned. The expand/collapse toggle and the
        // dismiss stay reachable as named rotor actions even though their glyphs are
        // only hover- / chevron-revealed.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityRowSummaryText(referenceDate: referenceDate))
        .accessibilityAddTraits(isInteractive ? .isButton : [])
        .accessibilityAction {
            guard isInteractive else { return }
            actions.jump()
        }
        .accessibilityAction(named: Text(lang.t(isExpanded ? "a11y.session.collapseDetail" : "a11y.session.expandDetail"))) {
            toggleDetail(currentlyOpen: isExpanded)
        }
        .modifier(HaloOptionalNamedAccessibilityAction(
            name: actions.dismiss != nil ? lang.t("a11y.session.dismiss") : nil,
            action: { actions.dismiss?() }
        ))
    }

    // MARK: - Expansion

    /// Whether the row shows its expanded detail. Production list rows open
    /// **collapsed** (the calm void list, mockup §C) and expand on a tap; the one
    /// **actionable** row (the session that needs you, or a completion card) auto-
    /// expands so its body is never a tap away; a harness / preview forces it open
    /// via `expandedByDefault`. A non-interactive list never expands.
    private func resolvedIsExpanded(presence: IslandSessionPresence) -> Bool {
        guard isInteractive else { return false }
        let defaultExpanded = expandedByDefault || isActionable
        return detailOverride ?? defaultExpanded
    }

    private func toggleDetail(currentlyOpen: Bool) {
        guard isInteractive else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            detailOverride = !currentlyOpen
        }
    }

    // MARK: - Lead column (status dot + monogram)

    private func leadColumn(edgeState: HaloSessionRowFormat.EdgeState, presence: IslandSessionPresence) -> some View {
        VStack(spacing: 7) {
            HaloStatusDot(
                tint: dotTint(edgeState),
                bloomOpacity: dotBloomOpacity(edgeState)
            )
            HaloAgentMonogram(
                text: HaloSessionRowFormat.monogram(agentShortName: session.tool.shortName),
                tokens: tokens,
                increasesContrast: increasesContrast
            )
        }
        .padding(.top, 3)
        .accessibilityHidden(true)
    }

    // MARK: - Body column (title · activity · meta)

    private func bodyColumn(
        edgeState: HaloSessionRowFormat.EdgeState,
        presence: IslandSessionPresence,
        isExpanded: Bool,
        referenceDate: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titleLine(edgeState: edgeState, presence: presence)

            if let activity = activityText(edgeState: edgeState) {
                activity
                    .font(.system(size: HaloTypography.activitySize, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 4)
            }

            // The collapsed meta chip line is the summary affordance; expanded, the
            // §5D grid + action rail below replace it, so it is suppressed to avoid
            // showing the model / jump twice.
            if !isExpanded {
                metaLine(edgeState: edgeState, presence: presence, referenceDate: referenceDate)
            }
        }
    }

    /// The mockup `.tl` line: the workspace name at the `workspaceTitle` role, and —
    /// only when a duplicate workspace name in the list demands it — the T05
    /// branch/recency disambiguator as a mono span at tertiary (SPEC §5C). The name
    /// yields (tail-truncates) before the disambiguator, which pins its width, so a
    /// long name never squeezes the branch out of view.
    private func titleLine(edgeState: HaloSessionRowFormat.EdgeState, presence: IslandSessionPresence) -> some View {
        HStack(spacing: 8) {
            Text(session.spotlightDisplayName)
                .font(.system(size: HaloTypography.workspaceTitleSize, weight: .semibold))
                .tracking(HaloTypography.workspaceTitleSize * -0.01)
                .foregroundStyle(titleColor(presence: presence))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(session.spotlightWorkspaceName)

            if let disambiguator = disambiguatorSuffix {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9, weight: .regular))
                        .accessibilityHidden(true)
                    Text(disambiguator)
                        .font(.system(size: HaloTypography.branchDisambSize, weight: .regular, design: .monospaced))
                }
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }

            // A live completed row carries its outcome badge on the right of the
            // title line (mockup §C/§H `.outc` at `margin-left:auto`) — glyph + word
            // + hue, in both the collapsed row and the expanded body, so a finish's
            // verdict reads without opening it. Idle / receded rows drop it (calm).
            if let outcome = completedOutcome(edgeState) {
                Spacer(minLength: 6)
                outcomeBadge(outcome)
            }
        }
    }

    /// The completed row's outcome (or `nil` for a live / idle row), driving the
    /// title-line badge and the §5H `Outcome` cell from one source.
    private func completedOutcome(_ edgeState: HaloSessionRowFormat.EdgeState) -> HaloSessionRowFormat.Outcome? {
        switch edgeState {
        case .success: return .success
        case .interrupted: return .interrupted
        case .failed: return .failed
        case .running, .permission, .question, .idle: return nil
        }
    }

    /// The outcome badge (mockup `.outc ok/intr/fail`): a tinted-pill glyph + word.
    /// Success is a green ✓ on `green@.12`; interrupted a warn ⊘ / failed a red ✕ on
    /// their own status tints — distinct glyph **and** hue, never colour alone.
    private func outcomeBadge(_ outcome: HaloSessionRowFormat.Outcome) -> some View {
        let tint = outcomeTint(outcome)
        return HStack(spacing: 4) {
            Image(systemName: outcome.glyphName)
                .font(.system(size: 9.5, weight: .bold))
                .accessibilityHidden(true)
            Text(outcomeLabel(outcome))
                .font(.system(size: HaloTypography.outcomeBadgeSize, weight: .bold))
        }
        .foregroundStyle(tint.opacity(0.96))
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(tint.opacity(0.12), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }

    private func outcomeTint(_ outcome: HaloSessionRowFormat.Outcome) -> Color {
        switch outcome {
        case .success: return tokens.colors.statusCompleted
        case .interrupted: return tokens.colors.statusInterrupted
        case .failed: return tokens.colors.statusFailed
        }
    }

    private func outcomeLabel(_ outcome: HaloSessionRowFormat.Outcome) -> String {
        switch outcome {
        case .success: return lang.t("island.halo.outcome.success")
        case .interrupted: return lang.t("island.halo.outcome.interrupted")
        case .failed: return lang.t("island.halo.outcome.failed")
        }
    }

    /// The mockup `.act` line (SPEC §5C / §5D): the T03 narrated activity. A running
    /// turn narrates verb+object with a **"live" cyan verb** (mockup `.act .live`);
    /// every other row speaks a plain human phrase wholly at secondary — never a raw
    /// tool id or a `$ …` command echo. Returns `nil` when there is nothing to say.
    private func activityText(edgeState: HaloSessionRowFormat.EdgeState) -> Text? {
        let primary = tokens.colors.paper.opacity(contrastText(0.96))
        let secondary = tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity))

        if edgeState == .running, let narrated = session.narratedActivity {
            let live = Text(narrated.localizedVerb(lang))
                .font(.system(size: HaloTypography.activitySize, weight: .medium))
                .foregroundStyle(tokens.colors.statusRunning)
            if let object = narrated.object, !object.isEmpty {
                return live + Text(verbatim: " " + object).foregroundStyle(primary)
            }
            return live
        }

        guard let phrase = humanActivityText else { return nil }
        return Text(phrase).foregroundStyle(secondary)
    }

    /// The meta chip line (mockup `.meta`): model / permission-mode / terminal
    /// chips, a running-turn live timer pin, and — on a completed row — the primary
    /// Jump chip. Suppressed on the permission / question rows, which reserve that
    /// space for the Part-2 hero body (the Approve/Deny · options surfaces).
    @ViewBuilder
    private func metaLine(
        edgeState: HaloSessionRowFormat.EdgeState,
        presence: IslandSessionPresence,
        referenceDate: Date
    ) -> some View {
        switch edgeState {
        case .permission, .question:
            // Part-2 hero seam: no meta line — the actionable body lands here.
            EmptyView()
        case .running:
            HaloMetaFlow {
                if let model = session.displayModelName {
                    chip(model, mono: true)
                }
                if let mode = permissionModeChipText {
                    chip(mode)
                }
                // The §G′ subagent roll-up (mockup §C running row `3 active`): the
                // only fan-out count the collapsed row surfaces — the full nest
                // opens with the row (§5G). Present only with real subagents.
                if let subagents = activeSubagents {
                    pin("point.3.connected.trianglepath.dotted", lang.t("island.halo.subagents.active", subagents.count))
                }
                pin("clock", session.elapsedRunningLabel(at: referenceDate))
            }
            .padding(.top, 7)
        case .success, .interrupted, .failed:
            HaloMetaFlow {
                jumpChip
                if session.isRemote {
                    chip("SSH")
                } else if let terminal = session.spotlightTerminalBadge {
                    chip(terminal)
                }
            }
            .padding(.top, 7)
        case .idle:
            if let model = session.displayModelName {
                HaloMetaFlow { chip(model, mono: true) }
                    .padding(.top, 7)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Trailing column (age + hover-reveal dismiss)

    private func trailingColumn(presence: IslandSessionPresence, isExpanded: Bool, referenceDate: Date) -> some View {
        HStack(spacing: 6) {
            Text(ageBadgeText(at: referenceDate))
                .font(.system(size: HaloTypography.ageSize, weight: .regular).monospacedDigit())
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
                .lineLimit(1)
                .frame(minWidth: 30, alignment: .trailing)

            // The quiet expand / collapse chevron (mockup §D "tap to expand"): the
            // one affordance the void row keeps for opening the detail in place. Tap
            // still jumps; this toggles. Hidden on non-interactive lists.
            if isInteractive && presentation == .list {
                HaloDetailToggle(isOpen: isExpanded, action: { toggleDetail(currentlyOpen: isExpanded) }, lang: lang)
                    .accessibilityHidden(true)
            }

            if let dismiss = actions.dismiss {
                // Hover-reveal (mockup `.dismiss`): opacity 0→1 + scale .82→1 on the
                // row's hover. Hidden at rest; still reachable via the row's named
                // VoiceOver dismiss action above, so it is a11y-hidden here.
                HaloDismissButton(action: dismiss, lang: lang)
                    .opacity(isHighlighted ? 1 : 0)
                    .scaleEffect(isHighlighted ? 1 : 0.82)
                    .accessibilityHidden(true)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Meta chips

    private func chip(_ text: String, mono: Bool = false) -> some View {
        Text(text)
            .font(.system(
                size: mono ? HaloTypography.metaChipValueSize : HaloTypography.metaChipSize,
                weight: .medium,
                design: mono ? .monospaced : .default
            ))
            .monospacedDigit()
            .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(HaloEdge.hair2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func pin(_ systemName: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .regular))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: HaloTypography.metaChipSize, weight: .regular).monospacedDigit())
        }
        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
    }

    /// The primary Jump chip on a completed row (mockup `.jump`) — a hairline
    /// achromatic chip that fires `actions.jump()`. The whole row already jumps on
    /// tap; this is the explicit affordance the mockup surfaces in the meta line.
    private var jumpChip: some View {
        Button(action: actions.jump) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
                Text(lang.t("island.halo.row.jump"))
                    .font(.system(size: HaloTypography.jumpChipSize, weight: .semibold))
            }
            .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(HaloEdge.hair2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t("island.halo.row.jump"))
    }

    // MARK: - Expanded detail (§5D/§5G/§5H)

    /// The detail column indents past the lead column (dot + monogram) so it aligns
    /// under the body text — `sideInset` + the 16pt monogram + the 13pt summary gap.
    private var detailLeadingInset: CGFloat { sideInset + 16 + 13 }

    /// The whole expanded slot. The §5G subagent / todo nests ride at the top of
    /// the detail whenever there is nested work (a fan-out is worth seeing on any
    /// live row); then the body forks — a completed row draws the §5H completion
    /// body, every other row the §5D session detail. The permission / question
    /// branch is the AB-345 seam: today they fall through to `sessionDetailBody`
    /// (a real metadata grid + last message), replaced there by the command / diff
    /// / options heroes without touching this file's summary or nests.
    @ViewBuilder
    private func expandedDetail(
        edgeState: HaloSessionRowFormat.EdgeState,
        presence: IslandSessionPresence,
        referenceDate: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if activeSubagents != nil || activeTasks != nil {
                nestSlab(referenceDate: referenceDate)
                    .padding(.top, 11)
            }

            switch edgeState {
            case .success, .interrupted, .failed:
                completionBody(edgeState: edgeState, referenceDate: referenceDate)
                    .padding(.top, 11)
            case .running, .permission, .question, .idle:
                sessionDetailBody(presence: presence, referenceDate: referenceDate)
            }
        }
        .padding(.leading, detailLeadingInset)
        .padding(.trailing, sideInset)
        .padding(.bottom, 14)
    }

    private var activeSubagents: [ClaudeSubagentInfo]? {
        guard let subs = session.claudeMetadata?.activeSubagents, !subs.isEmpty else { return nil }
        return subs
    }

    private var activeTasks: [ClaudeTaskInfo]? {
        guard let tasks = session.claudeMetadata?.activeTasks, !tasks.isEmpty else { return nil }
        return tasks
    }

    // MARK: Subagents & todo nest (§5G · mockup §G `.nest`)

    /// The single nest slab (mockup `.nest`): a faint-hairline inset card grouping
    /// the subagent fan-out and the todo list into one surface rather than loose
    /// rows in the void.
    private func nestSlab(referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let subagents = activeSubagents {
                subagentSection(subagents, referenceDate: referenceDate)
            }
            if let tasks = activeTasks {
                todoSection(tasks)
            }
        }
        .padding(.vertical, 7)
        .background(nestBackground)
    }

    private var nestBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.025))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func subagentSection(_ subagents: [ClaudeSubagentInfo], referenceDate: Date) -> some View {
        // Nest header (mockup `.nest-h`): nodes glyph + "Subagents" + "N active".
        HStack(spacing: 6) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 11, weight: .regular))
                .accessibilityHidden(true)
            Text(lang.t("island.halo.subagents.header").uppercased())
                .font(.system(size: HaloTypography.nestHeaderSize, weight: .bold))
                .tracking(HaloTypography.nestHeaderSize * 0.09)
            Text(lang.t("island.halo.subagents.active", subagents.count))
                .font(.system(size: HaloTypography.nestHeaderSize, weight: .semibold).monospacedDigit())
            Spacer(minLength: 0)
        }
        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
        .padding(.horizontal, 11)
        .padding(.top, 4)
        .padding(.bottom, 4)

        ForEach(subagents, id: \.agentID) { sub in
            subagentRow(sub, referenceDate: referenceDate)
        }
    }

    /// A single subagent (mockup `.suba`): a running-light glyph + the type (12/600)
    /// over the task (11/400), and the **live elapsed** tabular on the right. A
    /// completed subagent (one that has reported a `summary`) settles to a green
    /// dot + "Completed"; a running one counts up `now − startedAt`.
    private func subagentRow(_ sub: ClaudeSubagentInfo, referenceDate: Date) -> some View {
        let isRunning = sub.summary == nil
        let tint = isRunning ? tokens.colors.statusRunning : tokens.colors.statusCompleted
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.5), radius: 3)
                .padding(.top, 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(subagentTypeText(sub))
                    .font(.system(size: HaloTypography.subagentTypeSize, weight: .semibold))
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.96)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let task = sub.taskDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !task.isEmpty {
                    Text(task)
                        .font(.system(size: HaloTypography.subagentTaskSize, weight: .regular))
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 6)

            subagentElapsed(sub, isRunning: isRunning)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lang.t(isRunning ? "a11y.subagent.running" : "subagents.completed"))
    }

    private func subagentTypeText(_ sub: ClaudeSubagentInfo) -> String {
        let type = sub.agentType?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (type?.isEmpty == false ? type! : sub.agentID)
    }

    @ViewBuilder
    private func subagentElapsed(_ sub: ClaudeSubagentInfo, isRunning: Bool) -> some View {
        let color = tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
        if isRunning, let started = sub.startedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(HaloSessionRowFormat.subagentElapsedLabel(
                    seconds: Int(context.date.timeIntervalSince(started))
                ))
                .font(.system(size: HaloTypography.subagentElapsedSize, weight: .regular).monospacedDigit())
                .foregroundStyle(color)
            }
        } else if !isRunning {
            Text(lang.t("subagents.completed"))
                .font(.system(size: HaloTypography.subagentElapsedSize, weight: .regular))
                .foregroundStyle(color)
        }
    }

    // MARK: Todo list (§5G · mockup `.todos`)

    @ViewBuilder
    private func todoSection(_ tasks: [ClaudeTaskInfo]) -> some View {
        let rollup = PouredTaskRollup(statuses: tasks.map(\.status))
        // If subagents already drew a header above, keep a faint divider so the two
        // lists read as one grouped nest but stay legibly separate.
        if activeSubagents != nil {
            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 1)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
        }

        // Todo progress (`2 of 5`, tabular) — the AC's roll-up over the list.
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(lang.t("island.halo.tasks.progress", rollup.done, rollup.total))
                .font(.system(size: HaloTypography.nestHeaderSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 2)

        VStack(alignment: .leading, spacing: 3) {
            ForEach(tasks) { task in
                todoRow(task)
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 2)
        .padding(.bottom, 3)
    }

    /// A single todo (mockup `.todo`): the state carried by **icon** — a check for
    /// done (green + strikethrough), a clock for doing (cyan + "in progress"), a
    /// hollow ring for pending — never colour alone.
    private func todoRow(_ task: ClaudeTaskInfo) -> some View {
        HStack(spacing: 8) {
            todoIcon(task.status)
                .frame(width: 14, height: 14)

            Text(task.title)
                .font(.system(size: HaloTypography.todoSize, weight: .regular))
                .foregroundStyle(todoTitleColor(task.status))
                .strikethrough(task.status == .completed)
                .lineLimit(1)
                .truncationMode(.tail)

            if task.status == .inProgress {
                Spacer(minLength: 6)
                Text(lang.t("island.halo.tasks.doing"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.colors.statusRunning)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func todoIcon(_ status: ClaudeTaskInfo.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tokens.colors.statusCompleted)
        case .inProgress:
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tokens.colors.statusRunning)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
        }
    }

    private func todoTitleColor(_ status: ClaudeTaskInfo.Status) -> Color {
        switch status {
        case .completed:
            return tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity))
        case .inProgress:
            return tokens.colors.paper.opacity(contrastText(0.96))
        case .pending:
            return tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity))
        }
    }

    // MARK: Session detail (§5D · mockup §D)

    /// The quiet expanded detail for a live / idle (non-completed) row: the §5D
    /// metadata grid, the last assistant message as rich text, and the action rail
    /// (Jump primary + Transcript + working directory dimmed).
    private func sessionDetailBody(presence: IslandSessionPresence, referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            metadataGrid {
                detailMetadataCells(referenceDate: referenceDate)
            }
            .padding(.top, 11)

            if let message = lastAssistantMessageForDetail {
                assistantCard(
                    label: lang.t("island.halo.detail.lastMessage", session.tool.displayName),
                    message: message
                )
                .padding(.top, 10)
            }

            detailActionRail
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func detailMetadataCells(referenceDate: Date) -> some View {
        // Agent — the monogram + full name (identity, a whisper in the row, a plain
        // statement once open).
        metadataCell(key: lang.t("island.halo.detail.meta.agent")) {
            HStack(spacing: 6) {
                HaloAgentMonogram(
                    text: HaloSessionRowFormat.monogram(agentShortName: session.tool.shortName),
                    tokens: tokens,
                    increasesContrast: increasesContrast
                )
                Text(session.tool.displayName)
                    .font(metadataValueFont)
                    .foregroundStyle(metadataValueColor)
                    .lineLimit(1)
            }
        }

        if let model = session.displayModelName {
            metadataTextCell(key: lang.t("island.halo.detail.meta.model"), value: model)
        }

        if let permission = permissionModeValueText {
            metadataTextCell(key: lang.t("island.halo.detail.meta.permission"), value: permission)
        }

        if let branch = SessionDisambiguation.branch(for: session) {
            metadataTextCell(
                key: lang.t("island.halo.detail.meta.branch"),
                value: SessionDisambiguation.displayBranch(branch),
                mono: true
            )
        }

        if session.phase == .running {
            metadataTextCell(
                key: lang.t("island.halo.detail.meta.duration"),
                value: session.elapsedRunningLabel(at: referenceDate),
                tabular: true
            )
        }

        if let terminal = terminalAttachmentText {
            metadataTextCell(key: lang.t("island.halo.detail.meta.terminal"), value: terminal)
        }
    }

    /// The §5D action rail: Jump is the primary blue-lit chip, Transcript a ghost,
    /// and the working directory a mono dimmed span pushed to the trailing edge.
    private var detailActionRail: some View {
        HStack(spacing: 10) {
            jumpPrimaryChip

            if let transcriptPath = trimmedTranscriptPath {
                TranscriptAffordance(
                    path: transcriptPath,
                    workspace: session.spotlightWorkspaceName,
                    lang: lang
                )
            }

            Spacer(minLength: 8)

            if let directory = directoryDisplayText {
                Text(directory)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(directory)
            }
        }
    }

    // MARK: Completion body (§5H · mockup §H)

    /// The completed-session body: the rich result, the §5H metadata grid
    /// (Outcome / Duration / Model / Finished), the reply input where the agent
    /// supports a follow-up, and the follow-up rail (Jump primary + Transcript +
    /// Dismiss). The outcome badge itself already rides the title line above.
    private func completionBody(edgeState: HaloSessionRowFormat.EdgeState, referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = completionMessageForDetail {
                assistantCard(label: lang.t("island.halo.detail.result"), message: message)
            }

            metadataGrid {
                completionMetadataCells(edgeState: edgeState, referenceDate: referenceDate)
            }
            .padding(.top, completionMessageForDetail != nil ? 11 : 0)

            if actions.reply != nil {
                replyInput
                    .padding(.top, 11)
            }

            completionActionRail
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func completionMetadataCells(edgeState: HaloSessionRowFormat.EdgeState, referenceDate: Date) -> some View {
        if let outcome = completedOutcome(edgeState) {
            metadataCell(key: lang.t("island.halo.done.outcome")) {
                HStack(spacing: 4) {
                    Image(systemName: outcome.glyphName)
                        .font(.system(size: 10, weight: .bold))
                        .accessibilityHidden(true)
                    Text(outcomeLabel(outcome))
                        .font(metadataValueFont)
                        .lineLimit(1)
                }
                .foregroundStyle(outcomeTint(outcome).opacity(0.96))
            }
        }

        metadataTextCell(
            key: lang.t("island.halo.done.duration"),
            value: HaloSessionRowFormat.durationLabel(seconds: completionDurationSeconds),
            tabular: true
        )

        if let model = session.displayModelName {
            metadataTextCell(key: lang.t("island.halo.done.model"), value: model, mono: true)
        }

        metadataTextCell(
            key: lang.t("island.halo.done.finished"),
            value: lang.t("island.halo.done.finishedAgo", session.spotlightAgeBadge),
            tabular: true
        )
    }

    /// The completion run length in whole seconds — `updatedAt − firstSeenAt`,
    /// frozen at completion so it never drifts with wall-clock time.
    private var completionDurationSeconds: Int {
        Int(session.updatedAt.timeIntervalSince(session.firstSeenAt))
    }

    /// The §5H follow-up rail: Jump primary + Transcript ghost + a trailing Dismiss
    /// chip (the honest verb — hides the row, there is no kill). Reply is its own
    /// input above (rendered only where the agent supports a follow-up turn).
    private var completionActionRail: some View {
        HStack(spacing: 10) {
            jumpPrimaryChip

            if let transcriptPath = trimmedTranscriptPath {
                TranscriptAffordance(
                    path: transcriptPath,
                    workspace: session.spotlightWorkspaceName,
                    lang: lang
                )
            }

            Spacer(minLength: 8)

            if let dismiss = actions.dismiss {
                Button(action: dismiss) {
                    Text(lang.t("island.halo.row.dismiss"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.secondaryTextOpacity)))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lang.t("a11y.session.dismiss"))
            }
        }
    }

    @ViewBuilder
    private var replyInput: some View {
        HStack(spacing: 8) {
            ReplyTextField(
                placeholder: lang.t("completion.replyPlaceholder", session.completionReplyRecipientName),
                text: $replyText,
                onSubmit: { submitReply() }
            )
            .frame(height: 32)

            Button {
                submitReply()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? Color.white.opacity(0.2) : Color.white.opacity(0.9))
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

    // MARK: Metadata grid (§5D/§5H · mockup `.mgrid` / `.mcell`)

    private func metadataGrid<Cells: View>(@ViewBuilder cells: () -> Cells) -> some View {
        HaloMetaGridLayout(spacing: 9) {
            cells()
        }
    }

    private func metadataTextCell(key: String, value: String, mono: Bool = false, tabular: Bool = false) -> some View {
        metadataCell(key: key) {
            Text(value)
                .font(mono ? metadataValueMonoFont : (tabular ? metadataValueFont.monospacedDigit() : metadataValueFont))
                .foregroundStyle(metadataValueColor)
                .lineLimit(1)
                .truncationMode(mono ? .middle : .tail)
        }
    }

    /// A grid cell (mockup `.mcell`): a 10pt uppercase tertiary key (lifted to the
    /// Halo floor) over a 12.5pt value. Absent fields never reach here — the cell
    /// builders emit nothing rather than an em-dash (SPEC §0 honesty).
    private func metadataCell<Content: View>(key: String, @ViewBuilder value: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key.uppercased())
                .font(.system(size: HaloTypography.metadataKeySize, weight: .semibold))
                .tracking(HaloTypography.metadataKeySize * 0.08)
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))
            value()
        }
        .frame(minWidth: 118, alignment: .leading)
    }

    private var metadataValueFont: Font {
        // Weight 560 in the SPEC — approximated at `.medium` (SwiftUI has no 560).
        .system(size: HaloTypography.metadataValueSize, weight: .medium)
    }

    private var metadataValueMonoFont: Font {
        .system(size: HaloTypography.metadataValueSize, weight: .medium, design: .monospaced).monospacedDigit()
    }

    private var metadataValueColor: Color {
        tokens.colors.paper.opacity(contrastText(0.96))
    }

    // MARK: Rich last-message / result card (mockup `.assistant`)

    /// The last assistant message / completion result as rich text (Markdown, the
    /// shared `.completionCard` theme so inline `code` reads mono ~11pt and emphasis
    /// resolves on the void) — never a raw single-line dump. Capped in an
    /// `AutoHeightScrollView` so a long message can't run the row off the panel.
    private func assistantCard(label: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: HaloTypography.nestHeaderSize, weight: .semibold))
                .tracking(HaloTypography.nestHeaderSize * 0.09)
                .foregroundStyle(tokens.colors.paper.opacity(contrastText(tokens.colors.tertiaryTextOpacity)))

            AutoHeightScrollView(maxHeight: 150) {
                Markdown(message)
                    .markdownTheme(.completionCard(tokens.colors))
                    .markdownImageProvider(.noNetwork)
                    .markdownInlineImageProvider(.noNetwork)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(nestBackground)
    }

    // MARK: Detail data helpers

    private var lastAssistantMessageForDetail: String? {
        guard let text = session.lastAssistantMessageText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    private var completionMessageForDetail: String? {
        if let text = session.completionAssistantMessageText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return (summary.isEmpty || summary == SessionPhase.completed.displayName) ? nil : summary
    }

    /// Claude-only permission mode, surfaced verbatim (`acceptEdits`, `plan`,
    /// `bypassPermissions`). The implicit `.default` carries no information, so it
    /// renders nothing rather than a noisy cell.
    private var permissionModeValueText: String? {
        guard session.tool == .claudeCode,
              let mode = session.claudeMetadata?.permissionMode,
              mode != .default else {
            return nil
        }
        return mode.rawValue
    }

    /// `Ghostty · attached` (mockup §D): the terminal app + its pane attachment
    /// state. `nil` when there is no resolved terminal.
    private var terminalAttachmentText: String? {
        guard let terminal = session.spotlightTerminalBadge else { return nil }
        return terminal + " · " + lang.t(attachmentStateKey)
    }

    private var attachmentStateKey: String {
        switch session.attachmentState {
        case .attached: return "island.halo.attachment.attached"
        case .stale: return "island.halo.attachment.stale"
        case .detached: return "island.halo.attachment.detached"
        }
    }

    /// Home-abbreviated, middle-truncated working directory (mockup
    /// `~/Developer/open-vibe-island`). `nil` when the session carries none.
    private var directoryDisplayText: String? {
        guard let raw = session.jumpTarget?.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if raw == home {
            return "~"
        } else if raw.hasPrefix(home + "/") {
            return "~" + raw.dropFirst(home.count)
        }
        return raw
    }

    private var trimmedTranscriptPath: String? {
        guard let path = session.trackingTranscriptPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return path
    }

    /// The primary Jump chip on an expanded row (mockup §D/§H `.jump` blue-lit): a
    /// `blue@.16` well carrying the jump verb, the row's primary CTA.
    private var jumpPrimaryChip: some View {
        Button(action: actions.jump) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10.5, weight: .semibold))
                    .accessibilityHidden(true)
                Text(jumpLabel)
                    .font(.system(size: HaloTypography.jumpChipSize, weight: .semibold))
            }
            .foregroundStyle(tokens.colors.paper.opacity(contrastText(0.96)))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Color(red: 80 / 255.0, green: 170 / 255.0, blue: 255 / 255.0).opacity(0.16),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(jumpLabel)
    }

    private var jumpLabel: String {
        if let terminal = session.spotlightTerminalBadge {
            return lang.t("island.halo.row.jump") + " · " + terminal
        }
        return lang.t("island.halo.row.jump")
    }

    // MARK: - Behaviour

    private func handlePrimaryTap() {
        guard isInteractive else { return }
        actions.jump()
    }

    // MARK: - Colour helpers

    private func contrastText(_ base: Double) -> Double {
        tokens.colors.text(base, increaseContrast: increasesContrast)
    }

    /// The status-dot hue per edge state — each state's *primary* tint (SPEC §1a).
    /// Never brand-colored: identity is the achromatic monogram, colour is state.
    private func dotTint(_ state: HaloSessionRowFormat.EdgeState) -> Color {
        switch state {
        case .running: return tokens.colors.statusRunning
        case .permission: return tokens.colors.statusWaitingForApproval
        case .question: return tokens.colors.statusWaitingForAnswer
        case .success: return tokens.colors.statusCompleted
        case .interrupted: return tokens.colors.statusInterrupted
        case .failed: return tokens.colors.statusFailed
        case .idle: return tokens.colors.statusIdle
        }
    }

    /// The dot bloom opacity per state (mockup `.dot::after`): the standard .55
    /// bloom, a dimmed .35 for a failure (a static, quieter light), and **no** bloom
    /// for idle (a flat dim dot — the calmest mark).
    private func dotBloomOpacity(_ state: HaloSessionRowFormat.EdgeState) -> Double {
        switch state {
        case .idle: return 0
        case .failed: return 0.35
        default: return 0.55
        }
    }

    private func titleColor(presence: IslandSessionPresence) -> Color {
        if isHighlighted { return tokens.colors.paper }
        return presence == .inactive
            ? tokens.colors.paper.opacity(0.78)
            : tokens.colors.paper.opacity(contrastText(0.95))
    }

    // MARK: - Text helpers

    private var disambiguatorSuffix: String? {
        guard let raw = sessionDisambiguators[session.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }

    private var humanActivityText: String? {
        if let activity = session.spotlightActivityLineText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !activity.isEmpty {
            return activity
        }
        let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    private var permissionModeChipText: String? {
        switch session.claudeMetadata?.permissionMode {
        case .plan: return lang.t("badge.planMode")
        case .bypassPermissions: return lang.t("badge.bypassPermissions")
        default: return nil
        }
    }

    private func ageBadgeText(at referenceDate: Date) -> String {
        if session.phase == .running {
            return session.elapsedRunningLabel(at: referenceDate)
        }
        return session.spotlightAgeBadge
    }

    // MARK: - Accessibility (identical wording to Classic / the sibling themes)

    private func accessibilityRowSummaryText(referenceDate: Date) -> String {
        lang.t(
            "a11y.session.summary",
            session.tool.displayName,
            session.spotlightWorkspaceName,
            accessibilityPhaseText,
            accessibilityElapsedText(at: referenceDate)
        )
    }

    private var accessibilityPhaseText: String {
        switch session.phase {
        case .running:
            return lang.t("a11y.phase.running")
        case .waitingForApproval:
            return lang.t("a11y.phase.waitingForApproval")
        case .waitingForAnswer:
            return lang.t("a11y.phase.waitingForAnswer")
        case .completed:
            switch session.outcome {
            case .success: return lang.t("a11y.phase.completed")
            case .interrupted: return lang.t("a11y.phase.interrupted")
            case .failed: return lang.t("a11y.phase.failed")
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
}

// MARK: - Leaf views

/// The bloomed status dot (mockup `.dot`): an 8pt light source with a soft
/// same-hue bloom behind it (inset −3 → a 14pt circle, blur 2). Never a flat
/// circle — the void's only in-row light besides the rail. Isolated so the blur
/// stays cheap and the row's `.drawingGroup = false` reasoning is local here.
private struct HaloStatusDot: View {
    let tint: Color
    let bloomOpacity: Double

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: HaloMetrics.dot, height: HaloMetrics.dot)
            .background(bloom)
    }

    @ViewBuilder
    private var bloom: some View {
        if bloomOpacity > 0 {
            Circle()
                .fill(tint.opacity(bloomOpacity))
                // inset −3 on all sides of the 8pt dot → a 14pt bloom, blurred 2pt.
                .frame(width: HaloMetrics.dot + 6, height: HaloMetrics.dot + 6)
                .blur(radius: 2)
        }
    }
}

/// The achromatic agent monogram (mockup `.mono-tag`): a 16pt rounded chip carrying
/// the agent's identity initial in mono at t2, on a whisper-faint white@.07 fill.
/// Identity is a grey whisper — **never** brand-colored (brief §7).
private struct HaloAgentMonogram: View {
    let text: String
    let tokens: IslandThemeTokens
    let increasesContrast: Bool

    var body: some View {
        Text(text)
            .font(.system(size: HaloTypography.monogramSize, weight: .bold, design: .monospaced))
            .tracking(HaloTypography.monogramSize * -0.02)
            .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            .frame(width: 16, height: 16)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// The 2pt edge-lit rail (mockup `.rail`): a vertical gradient in the left margin,
/// inset 8pt top/bottom, casting a colored glow off into the void. Only the live /
/// actionable states draw it. A `Rail` value carries the state; the gradient stops
/// and glow are resolved from the shared status tokens + the Halo-local partner
/// hues (violet / magenta) so the rail can never disagree with the perimeter edge.
private struct HaloEdgeLitRail: View {
    let rail: HaloSessionRowFormat.Rail
    let tokens: IslandThemeTokens

    var body: some View {
        RoundedRectangle(cornerRadius: HaloMetrics.railWidth / 2, style: .continuous)
            .fill(gradient)
            .frame(width: HaloMetrics.railWidth)
            .padding(.vertical, HaloMetrics.railInsetY)
            .shadow(color: glow, radius: glowRadius)
            .accessibilityHidden(true)
    }

    private var gradient: LinearGradient {
        switch rail {
        case .running:
            return LinearGradient(
                colors: [tokens.colors.statusRunning, HaloEdge.violet],
                startPoint: .top,
                endPoint: .bottom
            )
        case .permission:
            return LinearGradient(
                colors: [tokens.colors.statusWaitingForApproval, HaloEdge.magenta],
                startPoint: .top,
                endPoint: .bottom
            )
        case .question:
            // Flat qgold — a question is softer than a permission (SPEC §5C).
            return LinearGradient(
                colors: [tokens.colors.statusWaitingForAnswer, tokens.colors.statusWaitingForAnswer],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// The rail's colored glow (mockup `.rail` box-shadow) — a soft same-family
    /// bleed so the rail reads as travelling light, not a hard chip.
    private var glow: Color {
        switch rail {
        case .running: return Color(red: 80 / 255.0, green: 150 / 255.0, blue: 255 / 255.0).opacity(0.6)
        case .permission: return HaloEdge.permissionBloom.opacity(0.7)
        case .question: return HaloEdge.questionBloom.opacity(0.6)
        }
    }

    private var glowRadius: CGFloat {
        // mockup box-shadow blur 8 / 10 / 8 → SwiftUI Gaussian σ ≈ blur / 2.
        rail == .permission ? 5 : 4
    }
}

/// The dismiss control (mockup `.dismiss`): a quiet ✕ in a faint circular well that
/// warms to red on its own hover, carrying a ≥20pt hit target. Its reveal (opacity
/// + scale off the row's hover) is applied by the caller; a local copy so Halo owns
/// the void styling rather than the shared `DismissButton`'s look.
private struct HaloDismissButton: View {
    let action: () -> Void
    var lang: LanguageManager = .shared
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isHovered ? Color.white : Color.white.opacity(0.5))
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(isHovered ? Color(red: 224 / 255.0, green: 89 / 255.0, blue: 108 / 255.0).opacity(0.6) : Color.white.opacity(0.06))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(lang.t("a11y.session.dismiss"))
    }
}

// MARK: - Layout + motion helpers

/// A wrapping horizontal flow for the meta chips (mockup `.meta{flex-wrap:wrap}`)
/// so a dense row (model · mode · timer) never overflows the body column — it wraps
/// to a second line instead. Thin wrapper around `HStack` with the mockup's 12pt
/// gap; kept as its own type so the gap is declared once.
private struct HaloMetaFlow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        // A single-line flow is faithful to the collapsed row (the mockup wraps only
        // under extreme narrowing); `lineLimit(1)` keeps chips on one row and lets
        // the body column truncate, matching the title/activity lines above.
        HStack(spacing: 12) {
            content
        }
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The quiet expand / collapse chevron (mockup §D "tap a row to expand it"): a
/// faint chevron in the trailing column that rotates between the collapsed and
/// expanded states. It is the one affordance the void row keeps for opening the
/// detail in place; the row's primary tap still jumps, and the same toggle is a
/// named VoiceOver rotor action, so this stays a11y-hidden.
private struct HaloDetailToggle: View {
    let isOpen: Bool
    let action: () -> Void
    var lang: LanguageManager = .shared
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .foregroundStyle(Color.white.opacity(isHovered ? 0.7 : 0.4))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A wrapping flow (mockup `.mgrid` `repeat(auto-fill, minmax(…))`) for the
/// metadata cells so the grid fills as many cells per row as fit, then wraps —
/// two-up on the narrow panel, more on a wider one, with no fixed column count
/// baked in. A thin `Layout` mirroring the sibling themes' flow layouts, kept
/// local so Halo owns its own grid geometry.
private struct HaloMetaGridLayout: Layout {
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

/// The row entrance sweep (mockup `.sweep`, SPEC §5K): a single ~0.7s ease-out
/// diagonal light pass on insert, **never** looping (the mockup's 3.4s loop is
/// illustration only). Suppressed entirely under Reduce Motion — the row just
/// appears. The sweep overlay is clipped to the row bounds so it stays inside while
/// the dot bloom / rail glow bleed freely (clipping only the overlay, never the
/// row, keeps `drawingGroup = false` intact).
private struct HaloRowEntranceSweep: ViewModifier {
    let enabled: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay {
            if enabled {
                GeometryReader { proxy in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.34),
                            .init(color: Color(red: 120 / 255.0, green: 180 / 255.0, blue: 255 / 255.0).opacity(0.14), location: 0.5),
                            .init(color: .clear, location: 0.66),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: proxy.size.width)
                    .offset(x: phase * proxy.size.width)
                    .allowsHitTesting(false)
                }
                .clipped()
                .onAppear {
                    // Latch from off-left to off-right exactly once.
                    withAnimation(.easeOut(duration: HaloMotion.sweep)) {
                        phase = 1
                    }
                }
            }
        }
    }
}

/// Attaches a named VoiceOver action only when `name` is non-nil — the row's
/// "Dismiss" rotor action, present only for dismissible rows. A local copy of the
/// same modifier the sibling themes' rows use.
private struct HaloOptionalNamedAccessibilityAction: ViewModifier {
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
