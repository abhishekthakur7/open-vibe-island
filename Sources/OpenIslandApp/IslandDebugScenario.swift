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
    /// Overlay remediation Phase 1 item 1.7 (P1.a): forces the lead row's
    /// expanded detail open via `\.islandRowExpandedByDefault`, so the
    /// `subagentsExpanded` scenario can capture Flight Deck's/Halo's §D/§G
    /// expanded body without a real tap gesture (Poured's expansion is
    /// presence-derived and already reachable — see F6). `false` (the
    /// default) leaves every pre-existing scenario — including
    /// `subagentsCard`, which deliberately keeps documenting the collapsed
    /// row — rendering exactly as before.
    var forcesRowExpansion: Bool = false
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
                selectedSessionID: session.id
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
                selectedSessionID: session.id
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
                selectedSessionID: session.id
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
                selectedSessionID: session.id
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

        case .emptyState:
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 300,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: AppearancePreviewFixtures.empty,
                selectedSessionID: nil
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
                initialPrompt: "我更关注获取的部分 我想在其他 app 里实时展示我的 usage。",
                latestPrompt: "为什么要查 Cursor 官方呢？这个事跟 Cursor 有什么关系？",
                assistant: "不建议按“最古老”来选。最古老不等于最轻量且最适合这个任务。",
                age: 27 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-personal",
                workspace: "Personal",
                initialPrompt: "[Image #1]我给你截了 3 张图，这个是我现在 Cursor 里面可用的模型。",
                latestPrompt: "[Image #1]我给你截了 3 张图，这个是我现在 Cursor 里面可用的模型。",
                assistant: "这张图里的模型，严格说不是这个 `voice-input` App 应该选的模…",
                age: 32 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-open-agent-sdk",
                workspace: "open-agent-sdk",
                initialPrompt: "OK，那现在你是不是需要提一个 PR？",
                latestPrompt: "那你直接提个 PR 吧",
                assistant: "PR 已经提好了：",
                age: 60 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-voice-input",
                workspace: "voice-input",
                initialPrompt: "看看 voice-input 这个仓库，重点关注模型选型。",
                latestPrompt: "严格来说它应该选哪个模型？",
                assistant: "如果目标是轻量实时，不建议直接按 Cursor 现成套餐来映射。",
                age: 78 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-agents",
                workspace: "agents",
                initialPrompt: "把你的分支和 worktree 都给我。",
                latestPrompt: "所以你是要先重启吗？",
                assistant: "已经重启了。现在跑的是新的 dev 进程。",
                age: 92 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-claude",
                workspace: "claude-code",
                initialPrompt: "我们先把整个 notch 的背景换成纯黑。",
                latestPrompt: "下面那块空白要去掉。",
                assistant: "展开态高度已经改成按内容自适应。",
                age: 118 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-hooks",
                workspace: "hooks",
                initialPrompt: "假如我想实时监控 Claude Code 的 usage 应该怎么做？",
                latestPrompt: "如果是在别的 app 里展示呢？",
                assistant: "代码里已经有几条更直接的路可以走。",
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
                initialPrompt: "把 hook 的安装流程整理成一条命令。",
                lastPrompt: "顺便看看 uninstall 的分支。",
                assistant: "正在核对 settings.json 里已注册的 hook。",
                currentCommandPreview: "rg -n \"hooks\" Sources/OpenIslandCore",
                startedSecondsAgo: 12,
                now: now
            ),
            secondaryRunningSession(
                id: "session-running-voice",
                workspace: "voice-input",
                initialPrompt: "看看 voice-input 这个仓库，重点关注模型选型。",
                lastPrompt: "先把实时链路跑通。",
                assistant: "正在读取音频管线的采样率配置。",
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
                initialUserPrompt: "把 DEV 完全重构成一个 debug 页面，我需要稳定验收这些 card 的 UI。",
                lastUserPrompt: "之前也有错误的改动吧 你应该重新改",
                lastAssistantMessage: "读取现有 notch 状态与事件路由，准备把提醒态从 session list 里拆出来。",
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
                initialUserPrompt: "读一下本地的研究笔记，看看和我们在做的 agent 有什么关联。",
                lastUserPrompt: "本地笔记里的思路感觉和我们在做的 agent 很像。",
                lastAssistantMessage: "整理完了，已经提炼出和 autoreserach 相关的几段关键差异。"
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
            summary: "Allow exec_command to rewrite SettingsView.swift?",
            updatedAt: now.addingTimeInterval(-20),
            permissionRequest: PermissionRequest(
                title: "Approve file rewrite",
                summary: "Allow exec_command to rewrite SettingsView.swift?",
                affectedPath: "Sources/OpenIslandApp/Views/SettingsView.swift",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny",
                // The tool this request is actually for — `claudeMetadata.currentTool`
                // below already says `exec_command`. Without it the always-allow
                // scope row has no rule to name and never renders (G-21).
                toolName: "exec_command"
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "claude ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-approval"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                initialUserPrompt: "接下来我打算继续补齐一些能力。",
                lastUserPrompt: "askUserquestion 和权限审批，我想把他们也做到我们的 island 里。",
                lastAssistantMessage: "已经准备好重写 DEV 页面，需要批准文件改动。",
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
            summary: "这个提醒态需要自动收起吗？",
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
                initialUserPrompt: "原产品看起来像是单 notch surface + 多 content surface。",
                lastUserPrompt: "我们应该怎么做？",
                lastAssistantMessage: "建议先把 approvalCard、questionCard、completionCard 拆成独立 surface。",
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
            summary: "DEV 页面已经切到 mock-driven card 调试模式。",
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
                initialUserPrompt: "这次我可能确实需要一些 mock 手段，让我能验收这些 Card 的 UI。",
                lastUserPrompt: "可以把 DEV 完全重构成一个 debug 页面。",
                lastAssistantMessage: "Plan 文件已写好。你的 hooks 触发情况如何？"
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
            summary: "README 提交已经完成，长回复现在应该在卡片内部滚动。",
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
                initialUserPrompt: "帮我把这个 README 也提交了，然后把结果贴给我。",
                lastUserPrompt: "顺便确认一下当前工作树和验证情况。",
                lastAssistantMessage: """
[README.md](/Users/wangruobing/Personal/open-island/README.md) 的现有改动已经单独提交了，commit 是 `f196316`，message 是 `docs: update readme tagline`。

这轮没有跑测试，因为只是文案改动。当前工作树是干净的，`main` 相对 `origin/main` 现在是 `ahead 6`。

如果你要我继续做下一轮，我建议把工作切到独立 worktree 里，这样不会和共享 `main` 上的并行改动互相打架。

下一步我会先检查当前仓库状态，然后从 `origin/main` 新建一个 worktree 和分支，在新工作区里继续处理这个样式问题并做完验证。
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
