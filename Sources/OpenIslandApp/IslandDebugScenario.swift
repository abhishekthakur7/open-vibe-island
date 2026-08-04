import CoreGraphics
import Foundation
import OpenIslandCore

struct IslandDebugSnapshot {
    let title: String
    let summary: String
    let previewHeight: CGFloat
    let notchStatus: NotchStatus
    let notchOpenReason: NotchOpenReason?
    let islandSurface: IslandSurface
    let sessions: [AgentSession]
    let selectedSessionID: String?
    /// AB-326: usage meters to force into the header for the `usageMeters`
    /// scenario. `nil` (the default) leaves the real usage path untouched, so
    /// every pre-existing scenario renders exactly as before.
    var usageProviders: [UsageProviderPresentation]? = nil
    /// Slice 6 · J1 (PI-X-001): the installed-agent display names to pin for the
    /// §J reassurance pill. The live list is derived from whichever agents the
    /// running machine has hooks for, so the board's
    /// `Hooks installed for Claude, Codex, Gemini` was not reproducible in a
    /// capture. `nil` (the default) leaves `AppModel.installedAgentDisplayNames`
    /// deriving from real hook status, exactly as before.
    var installedAgentNames: [String]? = nil
    /// Overlay remediation Phase 1 item 1.7 (P1.a): forces the lead row's
    /// expanded detail open via `\.islandRowExpandedByDefault`, so the
    /// `subagentsExpanded` scenario can capture Flight Deck's/Halo's §D/§G
    /// expanded body without a real tap gesture (Poured's expansion is
    /// presence-derived and already reachable — see F6). `false` (the
    /// default) leaves every pre-existing scenario — including
    /// `subagentsCard`, which deliberately keeps documenting the collapsed
    /// row — rendering exactly as before.
    var forcesRowExpansion: Bool = false
    /// Slice 5 · F4: which option indices a question scenario opens with
    /// selected, driving `\.islandQuestionPromptPreselection`. The board's §F
    /// frames are all drawn in a selected state (F2 option 1, F′ options 1+2,
    /// F″ option 1) and `selections` is interaction-driven `@State`, so without
    /// this the three frames could only ever be captured empty — and F′'s
    /// `Submit 2 selected` label was unreachable entirely. `nil` (the default)
    /// leaves every pre-existing scenario rendering exactly as before.
    var questionPreselection: IslandQuestionPromptPreselection? = nil
    /// Slice 5 · §E: drops the `Auto-collapses in Ns · hover pauses` footer from
    /// the Poured permission hero.
    ///
    /// The board carries that line on **E4 only** (`01-poured-island.html:1140-1143`)
    /// — E1, E2 and E3 are standalone hero frames with no countdown at all. Native
    /// prints it on every notification-presentation hero, so the three scenarios
    /// that exist to reproduce E1/E2/E3 grew a line their board frames do not
    /// have, and the root's own E-still capture had no way to turn it off. `false`
    /// (the default) leaves `notificationCard` — the E4 scenario — and every other
    /// path exactly as before.
    var suppressesNotificationCountdown: Bool = false
}

enum IslandDebugScenario: String, CaseIterable, Identifiable {
    case closed
    case closedAttention
    case closedCritical
    // Halo parity V2 · G-45: the sanctioned multi-running enabler. Every other
    // closed fixture has exactly one running session, so Halo's agents-grid
    // right slot (its `.count` default above 1 running — `AppModel
    // .islandPreferredRightSlotContent()`) was never reachable and the pill
    // correctly kept showing `×N`.
    case closedMultiRunning
    // Halo parity V2 · G-62/M-27: the §B peek's `+N more` chip only exists when
    // more than one session is waiting on the user, and `closedAttention` (the
    // A3 fixture, deliberately left alone) has exactly one.
    case closedAttentionQueue
    case sessionList
    case approvalCard
    case questionCard
    case completionCard
    case longCompletionCard
    // AB-326: conformance scenarios backed by `AppearancePreviewFixtures`.
    case diffApprovalCard
    case codexApprovalCard
    case multiQuestionCard
    case subagentsCard
    // Overlay remediation Phase 1 item 1.7 (P1.a): same fixture and surface
    // config as `subagentsCard`, with `forcesRowExpansion` set — keeps
    // `subagentsCard` itself documenting the collapsed row (its own
    // worthwhile regression target) instead of redefining it in place.
    case subagentsExpanded
    case completedInterrupted
    case completedFailed
    case usageMeters
    // Poured parity PI-V-001: the §C board's exact six sessions, so
    // `C1-grouped-six` has a deterministic native fixture. `sessionList` is the
    // generic opened list (nine rows, one runner, seven idle) and can't stand in
    // for a six-row two-per-group board.
    case pouredGroupedSix
    // Poured parity Slice 5 (PI-X-001): the board's §D / §F′ / §F″ frames.
    // `pouredSessionDetail` is the second scenario to set `forcesRowExpansion`
    // — see its snapshot arm for why the §D board frame cannot be reached
    // without it.
    case pouredSessionDetail
    case pouredMultiSelectQuestion
    case pouredCompactQuestion
    // Poured parity Slice 6 (PI-X-001): the board's §H hero and §G″ pill.
    // `completionCard`'s fixture is a Codex session with a 15-second run (no
    // duration) and none of the board's copy, and no pre-existing closed
    // scenario has a Claude running spotlight, so neither frame was reachable.
    case completedSuccess
    case closedTaskCounter
    case emptyState

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closed:
            "Closed Notch"
        case .closedAttention:
            "Closed Notch — Permission"
        case .closedCritical:
            "Closed Notch — Critical Usage"
        case .closedMultiRunning:
            "Closed Notch — Several Running"
        case .closedAttentionQueue:
            "Closed Notch — Permission Queue"
        case .sessionList:
            "Session List"
        case .approvalCard:
            "Approval Card"
        case .questionCard:
            "Question Card"
        case .completionCard:
            "Completion Card"
        case .longCompletionCard:
            "Long Completion Card"
        case .diffApprovalCard:
            "Diff Approval Card"
        case .codexApprovalCard:
            "Codex Terminal Approval"
        case .multiQuestionCard:
            "Multi-Question Card"
        case .subagentsCard:
            "Subagents & Tasks"
        case .subagentsExpanded:
            "Subagents & Tasks — Expanded"
        case .completedInterrupted:
            "Completed — Interrupted"
        case .completedFailed:
            "Completed — Failed"
        case .usageMeters:
            "Usage Meters"
        case .pouredGroupedSix:
            "Poured §C — Grouped Six"
        case .pouredSessionDetail:
            "Poured §D — Session Detail"
        case .pouredMultiSelectQuestion:
            "Poured §F′ — Multi-Select"
        case .pouredCompactQuestion:
            "Poured §F″ — Compact Question"
        case .completedSuccess:
            "Poured §H — Completed Success"
        case .closedTaskCounter:
            "Poured §G″ — Task Counter Pill"
        case .emptyState:
            "Empty State"
        }
    }

    var summary: String {
        switch self {
        case .closed:
            "Collapsed idle/running notch with live count and attention affordance."
        case .closedAttention:
            "Collapsed notch spotlighting a permission request — the A3 amber attention glow bleeding outside the pill."
        case .closedCritical:
            "Collapsed notch with no running/waiting sessions and one usage window past 90% — the only state that surfaces the I′ usage filament in the pill."
        case .closedMultiRunning:
            "Collapsed notch with three sessions running at once — the only state that surfaces Halo's §A2′ agents grid in the right wing (and the aggregate \"N working\" label)."
        case .closedAttentionQueue:
            "Collapsed notch with two sessions blocked on the user at once — the only state that surfaces the §B hover peek's \"+N more waiting\" chip."
        case .sessionList:
            "Manual expanded list with running, active, and inactive session rows."
        case .approvalCard:
            "Auto-expanded permission surface with approve and deny actions."
        case .questionCard:
            "Auto-expanded question surface with selectable answer buttons."
        case .completionCard:
            "Auto-expanded finished-task reminder surface after a turn completes."
        case .longCompletionCard:
            "Long finished-task reply stays inside the card and scrolls internally."
        case .diffApprovalCard:
            "Edit permission with an inline old/new diff preview inside the hero."
        case .codexApprovalCard:
            "Codex permission that can only be answered in the terminal (respond-in-terminal CTA)."
        case .multiQuestionCard:
            "Two-question prompt: single-select with descriptions, then multi-select with a freeform option."
        case .subagentsCard:
            "Running session fanned out across three subagents with a five-item task list."
        case .subagentsExpanded:
            "Same subagents/tasks fixture, row pinned open via the harness expansion seam — makes the §D/§G expanded body capturable for Flight Deck and Halo."
        case .completedInterrupted:
            "Finished-task reminder for a turn that was interrupted mid-run."
        case .completedFailed:
            "Finished-task reminder for a turn that ended in failure."
        case .usageMeters:
            "Expanded list with the header usage meters populated from fixture providers."
        case .pouredGroupedSix:
            "The Poured board's §C six: two waiting, two running, two done — the exact deterministic fixture behind the C1-grouped-six parity scenario."
        case .pouredSessionDetail:
            "The Poured board's §D: one running row expanded in place — metadata grid, the last assistant message as rich prose, jump/transcript rail."
        case .pouredMultiSelectQuestion:
            "The Poured board's §F′: a single multi-select question — square checks, running count in the submit label, no descriptions and no freeform Other."
        case .pouredCompactQuestion:
            "The Poured board's §F″: the compact single question — a two-option Yes/Hold with no descriptions, no submit CTA and no keyboard hint."
        case .completedSuccess:
            "The Poured board's §H: one clean success expanded into the completion hero — outcome tile, model sub-line, the result as prose, duration/agent footer and the jump/reply/transcript/dismiss rail."
        case .closedTaskCounter:
            "The Poured board's §G″: a collapsed pill whose spotlight is a Claude session fanned out across subagents — left wing \"Refactoring · 3 agents\", right slot the ⏲ 2/5 task counter."
        case .emptyState:
            "Expanded surface with zero sessions — the empty scaffold."
        }
    }

    func snapshot(at now: Date = .now) -> IslandDebugSnapshot {
        switch self {
        case .closed:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .closedAttention:
            // A collapsed notch whose spotlight session is blocked on a
            // permission approval, so the Poured pill wears its A3 amber
            // attention state (`SPEC-poured-island` §4A A3) — the glow bleeds
            // outside the silhouette and the right slot is the amber count badge.
            // The `attnpulse` never drops to zero opacity, so this frame is
            // judgeable regardless of the capture's animation phase (unlike the
            // `closed` A2 working glow, which breathes through 0).
            let approval = DebugSessionFactory.approvalSession(now: now)
            let sessions = DebugSessionFactory.notificationSessions(lead: approval, now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: approval.id
            )

        case .closedCritical:
            // I′ usage compression (mockup §I′): a collapsed notch whose right
            // slot is the critical-usage filament. That slot only wins the
            // resolver ladder when nothing outranks usage — no waiting sessions
            // and no *running* spotlight — so the fixture is the completed rows
            // only, paired with the ≥90% usage providers (Codex 7d = 92%).
            let sessions = DebugSessionFactory.listSessions(now: now)
                .filter { $0.phase == .completed }
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id,
                usageProviders: AppearancePreviewFixtures.usageProviders(now: now)
            )

        case .closedMultiRunning:
            // Halo parity V2 · G-45 (mockup §A2′): the agents grid is Halo's
            // right wing whenever MORE than one session is running — a state
            // `closed` cannot reach (`listSessions` runs exactly one). Same
            // shape as `closed` otherwise: collapsed notch, the real list, the
            // running spotlight selected. The two extra runners are ordinary
            // demo sessions, not a special payload — the grid reads
            // `phase == .running` off the surfaced list like it does live.
            let sessions = DebugSessionFactory.multiRunningSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .closedAttentionQueue:
            // Halo parity V2 · G-62/M-27: `closedAttention` plus a *second*
            // blocked session (a question behind the permission), so the §B
            // peek has something to compress into `+1 more waiting`. Both are
            // the existing `approvalSession`/`questionSession` fixtures — no new
            // payload shapes, only a second one in the same list.
            let approval = DebugSessionFactory.approvalSession(now: now)
            let question = DebugSessionFactory.questionSession(now: now)
            var sessions = DebugSessionFactory.notificationSessions(lead: approval, now: now)
            if sessions.count > 1 { sessions[1] = question }
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: approval.id
            )

        case .sessionList:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 430,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .approvalCard:
            let session = DebugSessionFactory.approvalSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 330,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id,
                // Slice 5 · §E: this scenario reproduces a board E-frame that
                // carries no `Auto-collapses in Ns` footer (E4 is the only frame
                // that does), so the countdown is suppressed here.
                suppressesNotificationCountdown: true
            )

        case .questionCard:
            let session = DebugSessionFactory.questionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 270,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .completionCard:
            let session = DebugSessionFactory.completionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 250,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .longCompletionCard:
            let session = DebugSessionFactory.longCompletionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 290,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .diffApprovalCard:
            let session = AppearancePreviewFixtures.permissionDiff(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 380,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id,
                // Slice 5 · §E: this scenario reproduces a board E-frame that
                // carries no `Auto-collapses in Ns` footer (E4 is the only frame
                // that does), so the countdown is suppressed here.
                suppressesNotificationCountdown: true
            )

        case .codexApprovalCard:
            let session = AppearancePreviewFixtures.codexTerminalApproval(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 300,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id,
                // Slice 5 · §E: this scenario reproduces a board E-frame that
                // carries no `Auto-collapses in Ns` footer (E4 is the only frame
                // that does), so the countdown is suppressed here.
                suppressesNotificationCountdown: true
            )

        case .multiQuestionCard:
            let session = AppearancePreviewFixtures.questionMulti(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 380,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id,
                // Slice 5 · F4: the board's F frame draws option 1 selected —
                // gold `.num`, 1.5px ring, `.ck` tick (`01-poured-island.html:1178-1182`).
                questionPreselection: .firstOption
            )

        case .subagentsCard:
            let session = AppearancePreviewFixtures.subagentsAndTasks(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 460,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .subagentsExpanded:
            // Same fixture and surface config as `subagentsCard` — only
            // `forcesRowExpansion` differs, so the two scenarios are directly
            // comparable (collapsed vs. expanded) for the same underlying row.
            let session = AppearancePreviewFixtures.subagentsAndTasks(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 460,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id,
                forcesRowExpansion: true
            )

        case .completedInterrupted:
            let session = AppearancePreviewFixtures.completedInterrupted(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 250,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .completedFailed:
            let session = AppearancePreviewFixtures.completedFailed(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 250,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .usageMeters:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 430,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id,
                usageProviders: AppearancePreviewFixtures.usageProviders(now: now)
            )

        case .pouredGroupedSix:
            // Poured parity PI-V-001 (C1-grouped-six). Opened, click-opened (the
            // board draws the *user-opened* list, not a notification surface),
            // no actionable session id — §C shows the row-level Approve/Deny
            // affordances inside the list, not an expanded permission hero.
            // Session order is the board's own top-to-bottom order; the list's
            // own sectioning re-derives the three groups from it.
            let sessions = AppearancePreviewFixtures.pouredGroupedSix(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 430,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: sessions,
                // PI-C-001 / owner ruling R1: the board's `Done` rows are 12m /
                // 22m old and its footer reads `0 idle` in the same frame. No
                // scenario-scoped stale window is needed for that any more —
                // the Poured list itself never stales `Done`
                // (`PouredSessionListScaffold.taxonomyStaleThreshold`).
                //
                // PI-C-006: the board's §C frame shows no expanded / selected
                // row — with actionable rows no longer auto-expanding, nothing
                // in the list is open, so the frame must not pre-select one
                // either.
                selectedSessionID: nil,
                // PI-I-001 / PI-C-004: the §C header renders two usage rings,
                // one per wing.
                usageProviders: AppearancePreviewFixtures.pouredGroupedSixUsageProviders(now: now)
            )

        case .pouredSessionDetail:
            // Poured parity Slice 5 (D1-detail). The board's §D frame draws the
            // expanded row as the panel's **sole child** — no header group, no
            // sibling rows, no footer — so the fixture is a one-session list,
            // not `notificationSessions(lead:)`.
            //
            // `forcesRowExpansion` is required, and this is the second scenario
            // to set it (`IslandDebugScenarioTests` pins the set). Poured's
            // expansion gate (`PouredSessionRow.PouredRowExpansion.resolved`)
            // opens a detail body only for `expandedByDefault`, an explicit
            // chevron/`Answer` tap, or an actionable row in *notification*
            // presentation — a quiet `.running` row in the list is collapsed by
            // construction (PI-C-006), which is exactly the state §D expands
            // *from*. Without the seam there is no non-interactive way to reach
            // §D at all.
            //
            // Click-opened, not `.notification`: the board's §D is a
            // user-opened list, and the row carries no attention affordance.
            let session = AppearancePreviewFixtures.pouredSessionDetail(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 430,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: [session],
                selectedSessionID: session.id,
                forcesRowExpansion: true
            )

        case .pouredMultiSelectQuestion:
            // Poured parity Slice 5 (F3-multi-select). The board draws F′ as a
            // standalone 440px panel holding one `.q-hero` — one session, and
            // it is the actionable one so the question hero renders.
            let session = AppearancePreviewFixtures.pouredMultiSelectQuestion(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 300,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: [session],
                selectedSessionID: session.id,
                // Slice 5 · F4: F′ draws options **1 and 2** selected — `✓` in
                // both `.num` chips, both `.ck` ticks lit, and the submit reading
                // `Submit 2 selected` (`01-poured-island.html:1222-1234`). That
                // two-selection state is the whole point of the frame and was
                // unreachable through the old first-option-only seam.
                questionPreselection: IslandQuestionPromptPreselection(optionIndices: [0, 1])
            )

        case .pouredCompactQuestion:
            // Poured parity Slice 5 (F4-compact-question). Same single-session
            // shape as F′. The board's compact one-row layout is built — the
            // fixture's own shape selects it, via the pure
            // `PouredCompactQuestionLayout.applies(to:)` predicate
            // (`IslandPanelView.swift:2930`), so nothing here opts in.
            let session = AppearancePreviewFixtures.pouredCompactQuestion(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 260,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: [session],
                selectedSessionID: session.id,
                // Slice 5 · F4: F″ draws `1 Yes, deploy` as `.opt.sel`
                // (`01-poured-island.html:1255`) — solid gold chip + 1.5px ring,
                // and deliberately no tick (Y2, honoured as rendered).
                questionPreselection: .firstOption
            )

        case .completedSuccess:
            // Poured parity Slice 6 (H1-completed). The board draws §H as a
            // standalone 440px panel holding one completion card, so the fixture
            // is a one-session list like §D's.
            //
            // Two seams are both required and neither is optional: the row must
            // be the surface's *actionable* one (`shouldShowEmbeddedDetailBody`
            // gates a completed row's hero on `isActionable`), and
            // `forcesRowExpansion` must be set (a completed row in a
            // click-opened list is collapsed by construction — PI-C-006). The
            // pairing is what makes the §H hero reachable without a tap.
            let session = AppearancePreviewFixtures.completedSuccess(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 360,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: [session],
                selectedSessionID: session.id,
                forcesRowExpansion: true
            )

        case .closedTaskCounter:
            // Poured parity Slice 6 (G3-task-pill). The right-slot resolver only
            // reaches `.taskCounter` when the spotlight is a *running* session
            // carrying `claudeMetadata.activeTasks` / `activeSubagents`
            // (`IslandRightSlotResolver.taskReading(for:)`) — every other closed
            // scenario spotlights a Codex fixture with no Claude metadata, so
            // the slot was unreachable. `subagentsAndTasks` is that session, and
            // it is the only one here so nothing outranks it.
            let session = AppearancePreviewFixtures.subagentsAndTasks(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: [session],
                selectedSessionID: session.id
            )

        case .emptyState:
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 300,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: AppearancePreviewFixtures.empty,
                selectedSessionID: nil,
                // J1: the board's own three (`01-poured-island.html:1535`).
                installedAgentNames: ["Claude", "Codex", "Gemini"]
            )
        }
    }
}

private enum DebugSessionFactory {
    static func listSessions(now: Date) -> [AgentSession] {
        [
            runningSession(now: now),
            recentCompletedSession(now: now),
            inactiveSession(
                id: "session-claude-research",
                workspace: "claude-research",
                initialPrompt: "I'm mainly interested in the data-fetching part — I want to show my usage in real time inside another app.",
                latestPrompt: "Why are we even looking at Cursor's official docs? What does this have to do with Cursor?",
                assistant: "I wouldn't pick based on 'oldest'. Oldest doesn't mean lightest or best suited for this task.",
                age: 27 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-personal",
                workspace: "Personal",
                initialPrompt: "[Image #1]I took 3 screenshots for you — these are the models currently available in Cursor.",
                latestPrompt: "[Image #1]I took 3 screenshots for you — these are the models currently available in Cursor.",
                assistant: "Strictly speaking, the model in this screenshot isn't the one the `voice-input` app should…",
                age: 32 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-open-agent-sdk",
                workspace: "open-agent-sdk",
                initialPrompt: "OK, so do you need to open a PR now?",
                latestPrompt: "Just go ahead and open a PR then.",
                assistant: "PR is open:",
                age: 60 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-voice-input",
                workspace: "voice-input",
                initialPrompt: "Take a look at the voice-input repo, focus on the model selection.",
                latestPrompt: "Strictly speaking, which model should it use?",
                assistant: "If the goal is lightweight and real-time, I wouldn't map it directly onto one of Cursor's off-the-shelf plans.",
                age: 78 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-agents",
                workspace: "agents",
                initialPrompt: "Give me your branch and worktree.",
                latestPrompt: "So you need to restart first?",
                assistant: "Already restarted. It's running the new dev process now.",
                age: 92 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-claude",
                workspace: "claude-code",
                initialPrompt: "Let's first change the whole notch background to pure black.",
                latestPrompt: "That blank space at the bottom needs to go.",
                assistant: "Expanded-state height now sizes to content.",
                age: 118 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-hooks",
                workspace: "hooks",
                initialPrompt: "If I wanted to monitor Claude Code usage in real time, how would I do it?",
                latestPrompt: "What if I want to show it in another app?",
                assistant: "There are already a few more direct paths in the code.",
                age: 130 * 60,
                now: now
            ),
        ]
    }

    static func notificationSessions(lead: AgentSession, now: Date) -> [AgentSession] {
        var sessions = listSessions(now: now)
        if sessions.isEmpty {
            return [lead]
        }
        sessions[0] = lead
        return sessions
    }

    /// `listSessions` with two of its idle rows replaced by live runners, so the
    /// island surfaces three `.running` sessions at once (Halo parity V2 · G-45).
    /// Substituting rather than appending keeps the list's own length, ordering
    /// and workspace vocabulary identical to `closed`'s, so the only difference
    /// the pill can see is the running count.
    static func multiRunningSessions(now: Date) -> [AgentSession] {
        var sessions = listSessions(now: now)
        let extras = [
            secondaryRunningSession(
                id: "session-running-hooks",
                workspace: "hooks",
                initialPrompt: "Consolidate the hook install flow into a single command.",
                lastPrompt: "Also take a look at the uninstall branch.",
                assistant: "Checking the hooks already registered in settings.json.",
                currentCommandPreview: "rg -n \"hooks\" Sources/OpenIslandCore",
                startedSecondsAgo: 12,
                now: now
            ),
            secondaryRunningSession(
                id: "session-running-voice",
                workspace: "voice-input",
                initialPrompt: "Take a look at the voice-input repo, focus on the model selection.",
                lastPrompt: "Get the real-time pipeline working first.",
                assistant: "Reading the sample-rate config for the audio pipeline.",
                currentCommandPreview: "swift build -c debug",
                startedSecondsAgo: 96,
                now: now
            ),
        ]

        for (offset, extra) in extras.enumerated() {
            // Slots 2 and 3 are the first two completed rows after the running
            // spotlight and the fresh completion — replacing them keeps the
            // spotlight ordering (`attention → running → first`) intact.
            let index = 2 + offset
            guard sessions.indices.contains(index) else { continue }
            sessions[index] = extra
        }
        return sessions
    }

    static func secondaryRunningSession(
        id: String,
        workspace: String,
        initialPrompt: String,
        lastPrompt: String,
        assistant: String,
        currentCommandPreview: String,
        startedSecondsAgo: TimeInterval,
        now: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(workspace)",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .running,
            summary: assistant,
            updatedAt: now.addingTimeInterval(-startedSecondsAgo),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: workspace,
                paneTitle: "codex ~/Personal/\(workspace)",
                workingDirectory: "/Users/wangruobing/Personal/\(workspace)",
                terminalSessionID: "ghostty-\(id)"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: initialPrompt,
                lastUserPrompt: lastPrompt,
                lastAssistantMessage: assistant,
                currentTool: "exec_command",
                currentCommandPreview: currentCommandPreview
            )
        )
    }

    static func runningSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-running",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .running,
            summary: "Reading IslandPanelView.swift and AppModel.swift",
            updatedAt: now.addingTimeInterval(-45),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-running"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Fully refactor DEV into a debug page — I need to reliably review these cards' UI.",
                lastUserPrompt: "There were some wrong changes before too, right? You should redo them.",
                lastAssistantMessage: "Reading the existing notch state and event routing, preparing to split the reminder state out of the session list.",
                currentTool: "exec_command",
                currentCommandPreview: "sed -n '1,260p' Sources/OpenIslandApp/Views/SettingsView.swift"
            )
        )
    }

    static func recentCompletedSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-recent",
            title: "Codex · open-agent-sdk",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "The session list now matches the original island more closely.",
            updatedAt: now.addingTimeInterval(-3 * 60),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-agent-sdk",
                paneTitle: "codex ~/Personal/open-agent-sdk",
                workingDirectory: "/Users/wangruobing/Personal/open-agent-sdk",
                terminalSessionID: "ghostty-recent"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Read the local research notes and see how they relate to the agent we're building.",
                lastUserPrompt: "The ideas in the local notes feel a lot like what we're building for the agent.",
                lastAssistantMessage: "Done organizing — pulled out a few key differences relevant to autoresearch."
            )
        )
    }

    static func inactiveSession(
        id: String,
        workspace: String,
        initialPrompt: String,
        latestPrompt: String,
        assistant: String,
        age: TimeInterval,
        now: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(workspace)",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: assistant,
            updatedAt: now.addingTimeInterval(-age),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: workspace,
                paneTitle: "codex ~/Personal/\(workspace)",
                workingDirectory: "/Users/wangruobing/Personal/\(workspace)",
                terminalSessionID: "ghostty-\(id)"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: initialPrompt,
                lastUserPrompt: latestPrompt,
                lastAssistantMessage: assistant
            )
        )
    }

    static func approvalSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-approval",
            title: "Claude Code · open-island",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            // Slice 5 · E3: the §E1 hero prints this as its *effect* line, so it
            // has to say what running the command DOES — a declarative sentence
            // plus its side effect, the way the board's E1 reads ("Compiles the
            // OpenIsland package. No files are modified.", `01-poured-island.html:1010`).
            // Never a question-form restatement of the ask, and never a raw tool
            // name: "Allow exec_command to rewrite SettingsView.swift?" cleared
            // `PouredApprovalHeroCopy.effect`'s echo heuristic and shipped both
            // faults straight into the card.
            summary: "Renames AppearanceSection to AppearanceSettingsSection in SettingsView.swift. One file is modified.",
            updatedAt: now.addingTimeInterval(-20),
            permissionRequest: PermissionRequest(
                title: "Approve file rewrite",
                summary: "Renames AppearanceSection to AppearanceSettingsSection in SettingsView.swift. One file is modified.",
                affectedPath: "Sources/OpenIslandApp/Views/SettingsView.swift",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny",
                // The tool this request is actually for — `claudeMetadata.currentTool`
                // below already says `exec_command`. Without it the always-allow
                // scope row has no rule to name and never renders (G-21).
                toolName: "exec_command",
                // X7 (D's F-04 · C's M-9/M-10): the board's E1 renders **two**
                // `.scope` rows — a command-prefix grant scoped to the project
                // (`Always allow ` `swift build` ` from this project`, carrying
                // the `⌘⇧Y` cap) and the whole-tool grant under it
                // (`Always allow all ` `swift` ` commands`, **no** cap;
                // `01-poured-island.html:1018-1026`, verified against
                // `mapper-reference.md` §5.2). The fixture carried none, so E1
                // fell through to the single generic row and the frame could
                // not be compared with the board at all.
                //
                // Both are real `addRules` updates the row sends verbatim on
                // tap, so the rendered sentence and the action can never
                // disagree: the first is `.projectSettings` (→ "from this
                // project"), the second names the executable with no rule
                // content (→ "all `sed` commands"). Order matters — the first
                // row is the one that gets the keycap.
                suggestedUpdates: [
                    .addRules(
                        destination: .projectSettings,
                        rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "sed -i ''")],
                        behavior: .allow
                    ),
                    .addRules(
                        destination: .session,
                        rules: [ClaudePermissionRuleValue(toolName: "sed")],
                        behavior: .allow
                    ),
                ]
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "claude ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-approval"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                initialUserPrompt: "Next I want to keep filling in some more capabilities.",
                lastUserPrompt: "askUserquestion and permission approval — I want to build those into our island too.",
                lastAssistantMessage: "Ready to rewrite the DEV page — needs approval for the file change.",
                currentTool: "exec_command",
                // The command has to *be* the rewrite the summary / title /
                // affectedPath all describe — a `head -5000 …` read here made the
                // demo card contradict itself. Still long enough to exercise the
                // hero command block's middle truncation (G-27).
                currentToolInputPreview: "sed -i '' -e 's/AppearanceSection/AppearanceSettingsSection/g' /Users/wangruobing/Personal/open-island/Sources/OpenIslandApp/Views/SettingsView.swift",
                model: "claude-opus-4-8-20260101",
                worktreeBranch: "feat/approval-flow"
            )
        )
    }

    static func questionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-question",
            title: "Claude Code · open-island",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForAnswer,
            summary: "Should this reminder auto-collapse?",
            updatedAt: now.addingTimeInterval(-18),
            questionPrompt: QuestionPrompt(
                title: "Which authentication method should we use?",
                questions: [
                    QuestionPromptItem(
                        question: "Which authentication method should we use?",
                        header: "Auth",
                        options: [
                            // Deliberately a full two-line description (G-04): the
                            // option body wraps at panel width, which is the only
                            // way the `lineLimit(2)` behaviour is ever exercised.
                            QuestionOption(
                                label: "JWT tokens",
                                description: "Stateless and scalable — no session store to keep, though revoking one early needs a deny list."
                            ),
                            QuestionOption(label: "Session cookies", description: "Traditional approach"),
                            QuestionOption(label: "OAuth 2.0", description: "Third-party auth"),
                            QuestionOption(label: "Other", description: "", allowsFreeform: true),
                        ]
                    )
                ]
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "claude ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-question"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                initialUserPrompt: "The original product looks like a single notch surface with multiple content surfaces.",
                lastUserPrompt: "What should we do?",
                lastAssistantMessage: "Suggest splitting approvalCard, questionCard, and completionCard into separate surfaces first.",
                currentTool: "AskUserQuestion",
                model: "claude-sonnet-5-20260101",
                worktreeBranch: "feat/question-flow"
            )
        )
    }

    static func completionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-completion",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "The DEV page is now switched to mock-driven card debug mode.",
            updatedAt: now.addingTimeInterval(-15),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-completion"
            ),
            codexMetadata: CodexSessionMetadata(
                transcriptPath: "/tmp/open-island-debug-completion.jsonl",
                initialUserPrompt: "This time I probably do need some mocking to let me review these cards' UI.",
                lastUserPrompt: "Go ahead and fully refactor DEV into a debug page.",
                lastAssistantMessage: "Plan file written. How are your hooks firing?"
            )
        )
    }

    static func longCompletionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-completion-long",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "The README commit is done — long replies should now scroll inside the card.",
            updatedAt: now.addingTimeInterval(-45),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-completion-long"
            ),
            codexMetadata: CodexSessionMetadata(
                transcriptPath: "/tmp/open-island-debug-completion-long.jsonl",
                initialUserPrompt: "Please commit this README too, then paste the result back to me.",
                lastUserPrompt: "Also confirm the current worktree and verification status.",
                lastAssistantMessage: """
The existing changes to [README.md](/Users/wangruobing/Personal/open-island/README.md) have already been committed separately — commit `f196316`, message `docs: update readme tagline`.

No tests were run this round since it's just a copy change. The current worktree is clean; `main` is now `ahead 6` relative to `origin/main`.

If you want me to continue with the next round, I'd suggest switching the work to a dedicated worktree so it doesn't collide with parallel changes on the shared `main`.

Next I'll check the current repo state, then create a new worktree and branch off `origin/main`, and continue working on this styling issue in the new workspace through to verification.
""",
                // F20 (overlay remediation Phase 3): this is the completion
                // fixture that exercises the completion grid's Model cell
                // (mockup §H) for a Codex session — `"gpt-5-codex"` also
                // exercises `shortModelDisplayName`'s GPT-family path
                // (→ "GPT-5"), the same worked example its doc comment cites.
                // Before F20 this cell structurally could never draw for any
                // codex-tool session, this fixture included.
                model: "gpt-5-codex"
            )
        )
    }
}
