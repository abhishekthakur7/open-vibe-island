import Foundation
import OpenIslandCore

/// Deterministic `AgentSession` (and usage) fixtures shared by the appearance
/// previews (AB-305) and the debug scenario harness (AB-326).
///
/// AB-326 promoted this from a `private enum` inside `AppearanceSettingsPane`
/// to a module-internal namespace so `IslandDebugScenario` can reuse the exact
/// same payloads instead of hand-rolling parallel copies. Two rules keep the
/// set honest and reproducible:
///
/// 1. **Injected clock.** Every date is an offset from a caller-supplied `now`.
///    Nothing here reads `Date()`/`.now`, so a given `now` produces a byte-for-byte
///    identical fixture — the property the snapshot harness (T09) leans on.
/// 2. **Stable identities.** Every `UUID` (`PermissionRequest`, `QuestionPrompt`,
///    `QuestionOption`) is derived from a seed string via ``stableID(_:)`` rather
///    than `UUID()`, so `AgentSession` equality holds across calls and the
///    fixtures never carry invented data shapes — only real model fields.
///
/// Every fixture is `origin: .demo`.
enum AppearancePreviewFixtures {
    // MARK: - Deterministic identity

    /// A reproducible `UUID` seeded from a string. Two independent 64-bit
    /// FNV-1a passes over the seed's full UTF-8 byte sequence produce the
    /// id's two 8-byte halves, so the same seed always yields the same id —
    /// which is what lets whole `AgentSession`s (with their nested
    /// `PermissionRequest` / `QuestionPrompt` UUIDs) compare equal across two
    /// fixture builds.
    ///
    /// Phase 1 remediation item 1.4: the previous implementation copied only
    /// the seed's first 16 UTF-8 bytes verbatim into the UUID — no hashing,
    /// no mixing — so any two seeds sharing a 16-character prefix collided
    /// outright. `conformanceQuestions()` below seeds three Auth options as
    /// `"conformance-auth-oauth"` / `"-apikey"` / `"-mtls"` and four Scope
    /// options as `"conformance-scope-…"`; every seed in each group shared
    /// its group's 16-character prefix, so every option in both groups
    /// rendered as option[0]. Hashing the *whole* seed instead of truncating
    /// it fixes this (verified collision-free for every seed in this file).
    /// Not a cryptographic hash: `CryptoKit` has no existing import anywhere
    /// in this target and isn't worth adding for a preview/test fixture with
    /// no security requirement — determinism plus a reasonable spread across
    /// a handful of short, distinct fixture strings is the only real
    /// contract `stableID` has to keep.
    static func stableID(_ seed: String) -> UUID {
        let seedBytes = Array(seed.utf8)
        let high = fnv1a64(seedBytes, offsetBasis: 0xcbf2_9ce4_8422_2325) // FNV-1a 64-bit offset basis
        let low = fnv1a64(seedBytes, offsetBasis: 0x9e37_79b9_7f4a_7c15) // distinct basis (64-bit golden ratio)

        var bytes = [UInt8](repeating: 0, count: 16)
        for shift in 0..<8 {
            bytes[shift] = UInt8((high >> (8 * (7 - shift))) & 0xff)
            bytes[8 + shift] = UInt8((low >> (8 * (7 - shift))) & 0xff)
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// One 64-bit FNV-1a pass.
    /// over `bytes`, seeded with a caller-chosen offset basis so two passes
    /// over the same input with different bases produce independent-looking
    /// 64-bit halves for ``stableID(_:)``.
    private static func fnv1a64(_ bytes: [UInt8], offsetBasis: UInt64) -> UInt64 {
        let prime: UInt64 = 0x0000_0100_0000_01b3
        var hash = offsetBasis
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }

    // MARK: - Baseline session set (AB-305)

    /// The original five-state baseline the appearance previews render. One per
    /// live state — running, needs-approval, needs-answer, recently-completed
    /// (`done`) and stale-completed (`idle`) — spread across agents and projects
    /// so agent/project grouping forms multiple sections, and time-stamped so the
    /// recent vs. stale completed rows land on opposite sides of the staleness cut.
    ///
    /// AB-326: the running row now carries `cursorMetadata` so the narration
    /// layer (AB-321) resolves it to "Editing AppModel.swift", and the approval /
    /// question payloads carry stable ids so the whole set is deterministic.
    ///
    /// **60s age-badge margin (Phase 1 remediation item 1.6).**
    /// `spotlightAgeBadge` reads a *fresh* `Date()` at render time, not this
    /// function's `now` (`Tests/OpenIslandAppTests/Support/ThemeSnapshotting.swift:25-32`
    /// documents that the harness cannot inject that clock), so any latency
    /// between building this fixture and the snapshot being rasterized adds
    /// straight onto every offset below. Each of the four attention-order
    /// rows' offsets is pinned to the middle of its intended minute bucket —
    /// ≥25s clear of the next 60s rollover in both directions — so ordinary
    /// render latency can't flip `"<1m"`/`"1m"`/`"2m"` to the next bucket's
    /// text, per the harness's own rule that a fixture must never sit within
    /// ~30s of a 60s boundary (`ThemeSnapshotHarnessTests.swift:87-88`). A
    /// pre-fix `preview-done` offset of `-45` (only 15s of margin) is what
    /// made `testPouredSessionListBaselineNotch`/`TopBar` consistently red.
    static func sessions(now: Date, lang: LanguageManager) -> [AgentSession] {
        // Attention order first (needs-approval, needs-answer, running, done,
        // idle) — `IslandSessionSectioning` leaves `.attention` untouched, so
        // this array *is* the attention ordering.
        [
            AgentSession(
                id: "preview-approval",
                title: "Codex · open-island",
                tool: .codex,
                origin: .demo,
                attachmentState: .attached,
                phase: .waitingForApproval,
                summary: lang.t("settings.appearance.preview.approveShellCommand"),
                updatedAt: now.addingTimeInterval(-90), // mid "1m" bucket, 30s clear of the 60s/120s rollovers
                permissionRequest: PermissionRequest(
                    id: stableID("preview-approval-permission"),
                    title: lang.t("approval.toolPermissionRequested"),
                    summary: lang.t("settings.appearance.preview.approveShellCommand"),
                    affectedPath: "Sources/OpenIslandApp/Views/SettingsView.swift",
                    primaryActionTitle: "Allow",
                    secondaryActionTitle: "Deny"
                ),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: "codex ~/open-island",
                    terminalSessionID: "preview-approval"
                )
            ),
            AgentSession(
                id: "preview-answer",
                title: "Claude · open-island",
                tool: .claudeCode,
                origin: .demo,
                attachmentState: .attached,
                phase: .waitingForAnswer,
                summary: lang.t("settings.appearance.preview.waitingForAnswer"),
                updatedAt: now.addingTimeInterval(-150), // mid "2m" bucket, 30s clear of the 120s/180s rollovers
                questionPrompt: QuestionPrompt(
                    id: stableID("preview-answer-prompt"),
                    title: lang.t("settings.appearance.preview.waitingForAnswer"),
                    questions: [
                        QuestionPromptItem(
                            question: lang.t("settings.appearance.preview.waitingForAnswer"),
                            header: "",
                            options: [
                                QuestionOption(id: stableID("preview-answer-ship"), label: "Ship it"),
                                QuestionOption(id: stableID("preview-answer-revise"), label: "Revise"),
                            ]
                        )
                    ]
                ),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: "claude ~/open-island",
                    terminalSessionID: "preview-answer"
                )
            ),
            AgentSession(
                id: "preview-running",
                title: "Cursor · website",
                tool: .cursor,
                origin: .demo,
                attachmentState: .attached,
                phase: .running,
                summary: lang.t("settings.appearance.preview.editingSessionListPreview"),
                updatedAt: now.addingTimeInterval(-30), // mid "<1m" bucket, 30s clear of the 0s/60s rollovers
                jumpTarget: JumpTarget(
                    terminalApp: "Cursor",
                    workspaceName: "website",
                    paneTitle: "cursor ~/website",
                    terminalSessionID: "preview-running"
                ),
                // AB-326 item 11: currentTool + preview drive the narration layer
                // (`AgentSession.narratedActivity`) to render "Editing AppModel.swift".
                cursorMetadata: CursorSessionMetadata(
                    currentTool: "Edit",
                    currentToolInputPreview: "Sources/OpenIslandApp/AppModel.swift"
                )
            ),
            AgentSession(
                id: "preview-done",
                title: "Gemini · docs",
                tool: .geminiCLI,
                origin: .demo,
                attachmentState: .attached,
                phase: .completed,
                summary: lang.t("settings.appearance.preview.replyAvailable"),
                // mid "<1m" bucket, ≥25s clear both ways. Was -45 (only 15s of
                // margin to the 60s rollover) — the boundary flip that made
                // testPouredSessionListBaselineNotch/TopBar consistently red.
                updatedAt: now.addingTimeInterval(-32),
                jumpTarget: JumpTarget(
                    terminalApp: "WezTerm",
                    workspaceName: "docs",
                    paneTitle: "gemini ~/docs",
                    terminalSessionID: "preview-done"
                )
            ),
            AgentSession(
                id: "preview-idle",
                title: "Codex · open-island",
                tool: .codex,
                origin: .demo,
                attachmentState: .attached,
                phase: .completed,
                summary: lang.t("settings.appearance.preview.completedEarlier"),
                updatedAt: now.addingTimeInterval(-25 * 60),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: "codex ~/open-island",
                    terminalSessionID: "preview-idle"
                )
            ),
        ]
    }

    // MARK: - Empty state (AB-326 item 10)

    /// Explicit zero-session state, so the empty scaffold can be exercised
    /// without smuggling in a "happens to be empty right now" list.
    static let empty: [AgentSession] = []

    // MARK: - Completion outcomes (AB-326 items 1–2)

    /// Claude turn that ended via Ctrl-C — `outcome: .interrupted` refines the
    /// `.completed` phase so tint/glyph/label can tell it apart from a clean
    /// success. Workspace `niche-radar`, finished 4m ago.
    static func completedInterrupted(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-completed-interrupted",
            title: "Claude · niche-radar",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            outcome: .interrupted,
            summary: "Stopped mid-refactor before the extraction finished.",
            updatedAt: now.addingTimeInterval(-4 * 60),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "niche-radar",
                paneTitle: "claude ~/niche-radar",
                terminalSessionID: "fixture-completed-interrupted"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                // Phase 1 remediation item 1.5: without a transcriptPath the
                // Transcript affordance's gate (`AgentSession.trackingTranscriptPath`,
                // a pure non-empty-string check — no FileManager/on-disk
                // requirement) never opens, so no fixture exercised it.
                transcriptPath: "~/.claude/projects/niche-radar/fixture-completed-interrupted.jsonl",
                initialUserPrompt: "Extract the ranking heuristics into their own module.",
                lastUserPrompt: "^C",
                lastAssistantMessage: "Interrupted while moving the scorer — no files were left half-written."
            )
        )
    }

    /// Codex turn that ended in failure — `outcome: .failed`. Workspace
    /// `open-vibe-island`, finished 3m30s ago — inside the 5-minute
    /// `staleCompletedDisplayThreshold` (`AgentSession+Presentation.swift:20`)
    /// so `isStaleCompletedForIsland` stays false and the row renders through
    /// the failed-outcome template instead of falling back to idle. Phase 1
    /// remediation item 1.3: a prior `-9 * 60` offset exceeded that
    /// threshold, so every theme forced `presence = .inactive` and the
    /// failed-outcome template never rendered.
    static func completedFailed(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-completed-failed",
            title: "Codex · open-vibe-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            outcome: .failed,
            summary: "Build failed: 2 errors in BridgeServer.swift.",
            // 210s (3m30s): under the 300s stale-completed threshold, off a
            // 60s age-badge boundary (see `sessions(now:lang:)` above), and
            // distinct from `completedInterrupted`'s -4*60 (-240s).
            updatedAt: now.addingTimeInterval(-3 * 60 - 30),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-vibe-island",
                paneTitle: "codex ~/open-vibe-island",
                terminalSessionID: "fixture-completed-failed"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Wire the new usage envelope through the bridge.",
                lastUserPrompt: "Wire the new usage envelope through the bridge.",
                lastAssistantMessage: "swift build exited non-zero — BridgeServer.swift has two type errors I could not resolve."
            )
        )
    }

    /// A clean success completion — `outcome: .success` — mirroring the mockup
    /// §H card: `the-automator` on `docs/agents-md`, a rich `<strong>` + inline
    /// `code` result and a `43m` run length (`firstSeenAt` sits 43 minutes before
    /// `updatedAt`). Finished 2 minutes ago so it stays inside the 5-minute
    /// non-stale window and the completion card expands (the mockup's "12m" is
    /// illustrative; the acceptance criterion is a *tabular* finished-ago). Pins
    /// the Poured §4H Success badge + tabular duration that `completedInterrupted`
    /// / `completedFailed` can't.
    static func completedSuccess(now: Date) -> AgentSession {
        // -150s: 2 minutes ago, mid "2m" age bucket (safely off a 60s boundary
        // per the snapshot harness's determinism contract) and inside the 5-minute
        // non-stale window so the card expands.
        let finishedAt = now.addingTimeInterval(-150)
        return AgentSession(
            id: "fixture-completed-success",
            title: "Claude · the-automator",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            outcome: .success,
            summary: "Documented the new bridge-auth flow.",
            updatedAt: finishedAt,
            firstSeenAt: finishedAt.addingTimeInterval(-43 * 60),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "the-automator",
                paneTitle: "claude ~/the-automator",
                terminalSessionID: "fixture-completed-success"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                // Phase 1 remediation item 1.5: also needed here (not just on
                // completedInterrupted) so F13's Flight Deck completion-card
                // Transcript branch has a fixture that actually exercises it.
                transcriptPath: "~/.claude/projects/the-automator/fixture-completed-success.jsonl",
                initialUserPrompt: "Document the bridge-auth flow in AGENTS.md and CLAUDE.md.",
                lastUserPrompt: "Document the bridge-auth flow in AGENTS.md and CLAUDE.md.",
                lastAssistantMessage: """
                Updated **AGENTS.md** and **CLAUDE.md** to document the new bridge-auth flow. \
                Added a "Working agreement" note about fail-open hooks and refreshed the support \
                matrix to include `OpenCode` and `Kimi`.

                - 2 files changed
                - Support matrix now matches README
                """,
                worktreeBranch: "docs/agents-md"
            )
        )
    }

    // MARK: - Duplicate-workspace trio (AB-326 item 3)

    /// Three sessions that all collide on workspace `the-automator`, exercising
    /// AB-323's list-level disambiguation:
    ///
    /// - `[0]` Claude on `feat/bridge-auth` (running) → unique branch suffix.
    /// - `[1]` Claude on `main` (running, three subagents) → unique branch suffix.
    /// - `[2]` Codex, no branch, updated 12m ago → recency fallback (branch is
    ///   Claude-only ground truth, so a Codex row can never claim one).
    static func duplicateWorkspaceTrio(now: Date) -> [AgentSession] {
        [
            AgentSession(
                id: "fixture-trio-claude-bridge-auth",
                title: "Claude · the-automator",
                tool: .claudeCode,
                origin: .demo,
                attachmentState: .attached,
                phase: .running,
                summary: "Adding the bridge auth handshake.",
                updatedAt: now.addingTimeInterval(-30),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "the-automator",
                    paneTitle: "claude ~/the-automator",
                    terminalSessionID: "fixture-trio-bridge-auth"
                ),
                claudeMetadata: ClaudeSessionMetadata(
                    lastUserPrompt: "Add token rotation to the bridge auth path.",
                    currentTool: "Edit",
                    currentToolInputPreview: "Sources/OpenIslandCore/BridgeServer.swift",
                    worktreeBranch: "feat/bridge-auth"
                )
            ),
            AgentSession(
                id: "fixture-trio-claude-main",
                title: "Claude · the-automator",
                tool: .claudeCode,
                origin: .demo,
                attachmentState: .attached,
                phase: .running,
                summary: "Running the release checklist.",
                updatedAt: now.addingTimeInterval(-52),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "the-automator",
                    paneTitle: "claude ~/the-automator",
                    terminalSessionID: "fixture-trio-main"
                ),
                claudeMetadata: ClaudeSessionMetadata(
                    lastUserPrompt: "Kick off the release checklist across the sub-tasks.",
                    currentTool: "Task",
                    worktreeBranch: "main",
                    activeSubagents: [
                        ClaudeSubagentInfo(
                            agentID: "trio-sub-1",
                            agentType: "Explore",
                            taskDescription: "Audit the changelog since the last tag",
                            startedAt: now.addingTimeInterval(-40)
                        ),
                        ClaudeSubagentInfo(
                            agentID: "trio-sub-2",
                            agentType: "general-purpose",
                            taskDescription: "Verify the notarization credentials",
                            startedAt: now.addingTimeInterval(-64)
                        ),
                        ClaudeSubagentInfo(
                            agentID: "trio-sub-3",
                            agentType: "Plan",
                            taskDescription: "Draft the bilingual release notes",
                            startedAt: now.addingTimeInterval(-12)
                        ),
                    ]
                )
            ),
            AgentSession(
                id: "fixture-trio-codex",
                title: "Codex · the-automator",
                tool: .codex,
                origin: .demo,
                attachmentState: .attached,
                phase: .completed,
                summary: "Regenerated the fixtures earlier.",
                updatedAt: now.addingTimeInterval(-12 * 60),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "the-automator",
                    paneTitle: "codex ~/the-automator",
                    terminalSessionID: "fixture-trio-codex"
                ),
                codexMetadata: CodexSessionMetadata(
                    initialUserPrompt: "Regenerate the preview fixtures.",
                    lastUserPrompt: "Regenerate the preview fixtures.",
                    lastAssistantMessage: "Fixtures regenerated and committed."
                )
            ),
        ]
    }

    // MARK: - Permission: shell command (AB-326 item 4)

    /// Claude asking to run a shell command. The command text rides in
    /// `claudeMetadata.currentToolInputPreview` (which `currentCommandPreviewText`
    /// surfaces as the hero's `$ …` line); the request carries a summary line, an
    /// `affectedPath`, and two real `addRules` suggestions whose `displayLabel`s
    /// read as scoped "allow running swift build …" buttons.
    static func permissionCommand(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-permission-command",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Claude wants to run a release build of the hooks binary.",
            updatedAt: now.addingTimeInterval(-14),
            permissionRequest: PermissionRequest(
                id: stableID("fixture-permission-command"),
                title: "Run shell command",
                summary: "Claude wants to run a release build of the hooks binary.",
                affectedPath: "~/Developer/open-vibe-island",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny",
                toolName: "Bash",
                suggestedUpdates: [
                    .addRules(
                        destination: .projectSettings,
                        rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "swift build")],
                        behavior: .allow
                    ),
                    .addRules(
                        destination: .userSettings,
                        rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "swift build")],
                        behavior: .allow
                    ),
                ]
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-vibe-island",
                paneTitle: "claude ~/open-vibe-island",
                terminalSessionID: "fixture-permission-command"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Build the hooks binary in release mode.",
                currentTool: "Bash",
                currentToolInputPreview: "swift build -c release --product OpenIslandHooks",
                // Overlay remediation Phase 4 (F2.4 coverage): mirrors the mockup's
                // measured "claude · Opus 4.8 · feat/auth-bridge" run
                // (`shots/mockup/flightDeck-E1.png`) — the exact fixture this
                // mockup depicts. Before this, no `.waitingForApproval` fixture set
                // `model`/`worktreeBranch`, so `FlightDeckAnnunciatorHeader`'s
                // compact context run (and Halo's who-line, which reads the same
                // `displayModelName`) never rendered anywhere.
                model: "claude-opus-4-8-20260101",
                worktreeBranch: "feat/auth-bridge"
            )
        )
    }

    // MARK: - Permission: inline diff (AB-326 item 5)

    /// Claude asking to edit `AGENTS.md`, carrying a `fileDiffSource` whose
    /// old/new text differ on several lines so `PermissionDiff.compute` yields a
    /// real (>3-line) inline diff in the approval hero.
    ///
    /// Phase 1 remediation item 1.2: written as prose, not a bulleted list —
    /// every line here is prose precisely so none starts with `"-"`/`"+"`.
    /// A leading dash in the *content* made the rendered diff marker's F4/F12
    /// acceptance criteria unfalsifiable: a marker glyph would appear to be
    /// present whether or not the UI actually renders a dedicated marker
    /// column, because the text itself already started with `-`. See
    /// `docs/design/overlay-redesign/REMEDIATION-PLAN.md` §3a.
    static func permissionDiff(now: Date) -> AgentSession {
        let oldText = """
        ## Verification

        After making changes, run swift build and confirm it succeeds before moving on.
        Summarize what changed once the round is done.
        Commit the round on the feature branch before stopping.
        """
        let newText = """
        ## Verification

        After making changes, run swift build and swift test and confirm both succeed before moving on.
        Capture a harness smoke run whenever the change affects rendered UI.
        Summarize what changed once the round is done, calling out any verification gaps.
        Commit the round on the feature branch before stopping.
        """

        return AgentSession(
            id: "fixture-permission-diff",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Claude wants to edit AGENTS.md.",
            updatedAt: now.addingTimeInterval(-11),
            permissionRequest: PermissionRequest(
                id: stableID("fixture-permission-diff"),
                title: "Edit file",
                summary: "Claude wants to edit AGENTS.md.",
                affectedPath: "AGENTS.md",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny",
                toolName: "Edit",
                suggestedUpdates: [
                    .addRules(
                        destination: .projectSettings,
                        rules: [ClaudePermissionRuleValue(toolName: "Edit", ruleContent: "AGENTS.md")],
                        behavior: .allow
                    ),
                ],
                fileDiffSource: PermissionFileDiffSource(oldText: oldText, newText: newText)
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-vibe-island",
                paneTitle: "claude ~/open-vibe-island",
                terminalSessionID: "fixture-permission-diff"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Tighten the verification section of AGENTS.md.",
                currentTool: "Edit",
                // Overlay remediation Phase 4 (F2.4 coverage): mirrors the mockup's
                // measured "claude · Opus 4.8 · main" run for this exact edit
                // (`shots/mockup/flightDeck-E2.png`) — see `permissionCommand`'s
                // comment above for why this was previously unset everywhere.
                model: "claude-opus-4-8-20260101",
                worktreeBranch: "main"
            )
        )
    }

    // MARK: - Permission: terminal-only (AB-326 item 6)

    /// Codex permission that can only be answered in the terminal. `Codex`
    /// requests set `requiresTerminalApproval: true`, so the hero swaps its
    /// Deny/Allow buttons for a "respond in terminal" CTA.
    static func codexTerminalApproval(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-codex-terminal-approval",
            title: "Codex · open-vibe-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Codex wants to run: git push origin main",
            updatedAt: now.addingTimeInterval(-16),
            permissionRequest: PermissionRequest(
                id: stableID("fixture-codex-terminal-approval"),
                title: "Approve command",
                summary: "Codex wants to run: git push origin main",
                affectedPath: "~/Developer/open-vibe-island",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny",
                toolName: "shell",
                requiresTerminalApproval: true
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Codex.app",
                workspaceName: "open-vibe-island",
                paneTitle: "codex ~/open-vibe-island",
                terminalSessionID: "fixture-codex-terminal-approval",
                codexThreadID: "fixture-codex-thread"
            ),
            codexMetadata: CodexSessionMetadata(
                lastUserPrompt: "Push the release commit.",
                currentTool: "shell",
                currentCommandPreview: "git push origin main"
            )
        )
    }

    // MARK: - Question: multi-question conformance set (AB-326 item 7)

    /// The shared conformance question set — headers `Auth` / `Scope` and the
    /// `Auth` question text are copied verbatim across every conformance fixture,
    /// so the same prompt exercises single-select (with per-option descriptions)
    /// and multi-select (with a freeform "Other") in one card.
    static func conformanceQuestions() -> [QuestionPromptItem] {
        [
            QuestionPromptItem(
                question: "Which auth method should the bridge use?",
                header: "Auth",
                options: [
                    QuestionOption(
                        id: stableID("conformance-auth-oauth"),
                        label: "OAuth 2.0",
                        description: "Delegated tokens that rotate automatically."
                    ),
                    QuestionOption(
                        id: stableID("conformance-auth-apikey"),
                        label: "API key",
                        description: "A single shared secret stored in the keychain."
                    ),
                    QuestionOption(
                        id: stableID("conformance-auth-mtls"),
                        label: "mTLS",
                        description: "A client certificate per machine."
                    ),
                ],
                multiSelect: false
            ),
            QuestionPromptItem(
                question: "Which surfaces should the bridge expose?",
                header: "Scope",
                options: [
                    QuestionOption(id: stableID("conformance-scope-socket"), label: "Local socket"),
                    QuestionOption(id: stableID("conformance-scope-loopback"), label: "Loopback HTTP"),
                    QuestionOption(id: stableID("conformance-scope-ssh"), label: "SSH tunnel"),
                    QuestionOption(
                        id: stableID("conformance-scope-other"),
                        label: "Other",
                        allowsFreeform: true
                    ),
                ],
                multiSelect: true
            ),
        ]
    }

    /// Claude waiting on the two-question conformance prompt.
    static func questionMulti(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-question-multi",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForAnswer,
            summary: "Claude needs two decisions before wiring the bridge.",
            updatedAt: now.addingTimeInterval(-19),
            questionPrompt: QuestionPrompt(
                id: stableID("fixture-question-multi"),
                title: "Bridge configuration",
                questions: conformanceQuestions()
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-vibe-island",
                paneTitle: "claude ~/open-vibe-island",
                terminalSessionID: "fixture-question-multi"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Design the local bridge transport.",
                currentTool: "AskUserQuestion",
                // Overlay remediation Phase 4 (F2.4 coverage): model style matches
                // the question-hero mockup (`shots/mockup/flightDeck-F1.png`, "claude
                // · Sonnet 5 · …"); branch reuses the bridge-auth theme the
                // duplicate-workspace trio already carries (`feat/bridge-auth`,
                // `AppearancePreviewFixtures.duplicateWorkspaceTrio`) — same feature,
                // consistent with this question being about the same bridge design.
                model: "claude-sonnet-5-20260101",
                worktreeBranch: "feat/bridge-auth"
            )
        )
    }

    // MARK: - Subagents + tasks (AB-326 item 8)

    /// Running Claude session fanned out across three subagents (Explore /
    /// general-purpose / Plan) with a five-item task list (two completed, one
    /// in progress, two pending) so the row's orchestration detail is fully
    /// exercised.
    static func subagentsAndTasks(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-subagents-tasks",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .running,
            summary: "Coordinating the overlay redesign rollout.",
            updatedAt: now.addingTimeInterval(-6),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-vibe-island",
                paneTitle: "claude ~/open-vibe-island",
                terminalSessionID: "fixture-subagents-tasks"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Drive the redesign tickets in parallel.",
                currentTool: "Task",
                activeSubagents: [
                    ClaudeSubagentInfo(
                        agentID: "subagent-explore",
                        agentType: "Explore",
                        taskDescription: "Map the theme token surface",
                        startedAt: now.addingTimeInterval(-42)
                    ),
                    ClaudeSubagentInfo(
                        agentID: "subagent-general",
                        agentType: "general-purpose",
                        taskDescription: "Port the session rows to Poured 2.0",
                        startedAt: now.addingTimeInterval(-75)
                    ),
                    ClaudeSubagentInfo(
                        agentID: "subagent-plan",
                        agentType: "Plan",
                        taskDescription: "Sequence the Flight Deck follow-ups",
                        startedAt: now.addingTimeInterval(-8)
                    ),
                ],
                activeTasks: [
                    ClaudeTaskInfo(id: "task-1", title: "Palette + material tokens", status: .completed),
                    ClaudeTaskInfo(id: "task-2", title: "Closed-pill ambient states", status: .completed),
                    ClaudeTaskInfo(id: "task-3", title: "Header + meters + scaffold", status: .inProgress),
                    ClaudeTaskInfo(id: "task-4", title: "Session rows", status: .pending),
                    ClaudeTaskInfo(id: "task-5", title: "Permission hero + conformance", status: .pending),
                ]
            )
        )
    }

    // MARK: - Poured §C grouped-six (PI-V-001)

    /// The exact six sessions the Poured board draws in §C
    /// (`01-poured-island.html:809-918`), in the board's own top-to-bottom
    /// order, so `C1-grouped-six` finally has a deterministic native fixture
    /// instead of "exact deterministic fixture missing".
    ///
    /// The board's six, and where each one comes from:
    ///
    /// | # | group     | workspace         | disambiguator          | agent  | age |
    /// |---|-----------|-------------------|------------------------|--------|-----|
    /// | 1 | Needs you | `the-automator`   | `feat/bridge-auth`     | claude | 1m  |
    /// | 2 | Needs you | `niche-radar`     | —                      | codex  | 3m  |
    /// | 3 | Working   | `open-vibe-island`| `feat/theme-poured`    | claude | now |
    /// | 4 | Working   | `the-automator`   | `main · 3 subagents`   | claude | 8m  |
    /// | 5 | Done      | `the-automator`   | `docs/agents-md`       | claude | 12m |
    /// | 6 | Done      | `open-vibe-island`| `fix/socket-leak`      | cursor | 22m |
    ///
    /// Rows 4 and 5 are **reused** from the fixtures that already depict them —
    /// `duplicateWorkspaceTrio(now:)[1]` is the board's `the-automator` / `main`
    /// / three-subagents runner, and `completedSuccess(now:)` is its
    /// `docs/agents-md` / `Success` / `43m` completion. The *identity* matches;
    /// the copy does not (see the divergence table below). They are rebuilt
    /// against a **shifted `now`** rather than copied: passing
    /// `now - 428s` to the trio lands its `-52s` row on the board's `8m`, and
    /// `now - 570s` lands `completedSuccess`'s `-150s` row on the board's `12m`.
    /// Every nested offset (subagent `startedAt`, the 43-minute `firstSeenAt`)
    /// shifts with it, so the reused payloads stay internally consistent and no
    /// second copy of them can drift.
    ///
    /// Rows 1, 2, 3 and 6 have no existing equivalent (the board's permission is
    /// on `the-automator`/`feat/bridge-auth`, not `permissionCommand`'s
    /// `open-vibe-island`/`feat/auth-bridge`; its question is a bare Codex row,
    /// not `questionMulti`'s two-question Claude card; its interrupt is a Cursor
    /// row on `open-vibe-island`, not `completedInterrupted`'s Claude row on
    /// `niche-radar`) and are built here.
    ///
    /// ### C1 native/reference divergences (all of them, in one place)
    ///
    /// | # | divergence | why |
    /// |---|------------|-----|
    /// | 4 | activity string is the trio's own copy, not the board's row-4 text | reused payload kept internally consistent rather than re-worded |
    /// | 4 | the board's `2/5 tasks` progress chip is **absent** | no native session field carries a task ratio; fabricating one would invent data |
    /// | 5 | activity string is `completedSuccess`'s own copy, not the board's row-5 text | same reuse rule as row 4 |
    /// | 6 | the board's `fix/socket-leak` branch tag is **not carried** | branch is Claude-only ground truth (AB-323); see `pouredGroupedSixInterrupted` |
    /// | 5, 6 | ages 12m / 22m vs the board's `0 idle` footer | see the threshold note below |
    ///
    /// Rows 5 and 6 finished 12 and 22 minutes ago, so under the default
    /// 5-minute `staleCompletedDisplayThreshold` the shared state sectioning
    /// files them under `state-idle`, not `state-done`. The board draws them as
    /// `Done` **and** reads `0 idle` in the same footer, which is only
    /// self-consistent at a ≥22-minute (or `never`) threshold. The fixture
    /// reproduces the board's recency; the threshold is the caller's choice —
    /// and `IslandDebugScenario.pouredGroupedSix` scopes it to `.never` so the
    /// mapped C1 scenario renders §C's three groups (PI-C-001).
    static func pouredGroupedSix(now: Date) -> [AgentSession] {
        [
            pouredGroupedSixPermission(now: now),
            pouredGroupedSixQuestion(now: now),
            pouredGroupedSixRunning(now: now),
            duplicateWorkspaceTrio(now: now.addingTimeInterval(-8 * 60 + 52))[1],
            completedSuccess(now: now.addingTimeInterval(-12 * 60 + 150)),
            pouredGroupedSixInterrupted(now: now),
        ]
    }

    /// Board row 1 (`:812-826`): Claude on `the-automator` / `feat/bridge-auth`
    /// asking to run `swift build`, 1 minute old. The command text rides in
    /// `currentToolInputPreview`, exactly like `permissionCommand`.
    private static func pouredGroupedSixPermission(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-poured-c1-permission",
            title: "Claude · the-automator",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Claude wants to run swift build.",
            updatedAt: now.addingTimeInterval(-60),
            permissionRequest: PermissionRequest(
                id: stableID("fixture-poured-c1-permission"),
                title: "Run shell command",
                summary: "Claude wants to run swift build.",
                affectedPath: "~/Developer/the-automator",
                primaryActionTitle: "Approve",
                secondaryActionTitle: "Deny",
                toolName: "Bash",
                suggestedUpdates: [
                    .addRules(
                        destination: .projectSettings,
                        rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "swift build")],
                        behavior: .allow
                    ),
                ]
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "the-automator",
                paneTitle: "claude ~/the-automator",
                terminalSessionID: "fixture-poured-c1-permission"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Build the bridge auth changes.",
                currentTool: "Bash",
                currentToolInputPreview: "swift build",
                model: "claude-opus-4-8-20260101",
                worktreeBranch: "feat/bridge-auth"
            )
        )
    }

    /// Board row 2 (`:828-841`): Codex on `niche-radar` asking the auth
    /// question, 3 minutes old, with **no** disambiguator — the workspace is
    /// unique in the six, so `SessionDisambiguation` must leave it bare. The
    /// question text is the board's verbatim, which is also the first
    /// `conformanceQuestions()` prompt; the three options are that prompt's.
    private static func pouredGroupedSixQuestion(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-poured-c1-question",
            title: "Codex · niche-radar",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForAnswer,
            summary: "Which auth method should the bridge use?",
            updatedAt: now.addingTimeInterval(-3 * 60),
            questionPrompt: QuestionPrompt(
                id: stableID("fixture-poured-c1-question"),
                title: "Bridge auth",
                questions: [
                    QuestionPromptItem(
                        question: "Which auth method should the bridge use?",
                        header: "Auth",
                        options: [
                            QuestionOption(id: stableID("poured-c1-auth-oauth"), label: "OAuth 2.0"),
                            QuestionOption(id: stableID("poured-c1-auth-apikey"), label: "API key"),
                            QuestionOption(id: stableID("poured-c1-auth-mtls"), label: "mTLS"),
                        ],
                        multiSelect: false
                    ),
                ]
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "niche-radar",
                paneTitle: "codex ~/niche-radar",
                terminalSessionID: "fixture-poured-c1-question"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Wire the ranking bridge.",
                lastUserPrompt: "Wire the ranking bridge.",
                lastAssistantMessage: "Which auth method should the bridge use?",
                currentTool: "ask_user"
            )
        )
    }

    /// Board row 3 (`:846-861`): Claude editing `AppModel.swift` on
    /// `open-vibe-island` / `feat/theme-poured`, `now` (age reads `now`, so the
    /// offset must stay under one minute — `-2s`, off any 60s badge boundary).
    private static func pouredGroupedSixRunning(now: Date) -> AgentSession {
        AgentSession(
            id: "fixture-poured-c1-running",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .running,
            summary: "Editing AppModel.swift.",
            updatedAt: now.addingTimeInterval(-2),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-vibe-island",
                paneTitle: "claude ~/open-vibe-island",
                terminalSessionID: "fixture-poured-c1-running"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                lastUserPrompt: "Bring the opened list to Poured parity.",
                currentTool: "Edit",
                currentToolInputPreview: "Sources/OpenIslandApp/AppModel.swift",
                model: "claude-opus-4-8-20260101",
                worktreeBranch: "feat/theme-poured"
            )
        )
    }

    /// Board row 6 (`:900-913`): a **Cursor** turn on `open-vibe-island` /
    /// `fix/socket-leak` stopped mid-edit, 22 minutes old with an 18-minute run
    /// length (`firstSeenAt` sits 18 minutes before `updatedAt`). The only
    /// non-Claude, non-Codex row in the set, and the only `.interrupted` one.
    ///
    /// The board's `fix/socket-leak` tag is **deliberately not carried**: branch
    /// is Claude-only ground truth (AB-323 — `SessionDisambiguation.branch(for:)`
    /// reads `claudeMetadata.worktreeBranch` and nothing else), so a Cursor row
    /// fabricating one would be inventing data the session never has. This row
    /// does collide on `open-vibe-island` with row 3, so it still disambiguates
    /// — via the recency fallback, not a branch. A reference/native divergence
    /// recorded here, not papered over.
    private static func pouredGroupedSixInterrupted(now: Date) -> AgentSession {
        let finishedAt = now.addingTimeInterval(-22 * 60)
        return AgentSession(
            id: "fixture-poured-c1-interrupted",
            title: "Cursor · open-vibe-island",
            tool: .cursor,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            outcome: .interrupted,
            summary: "Stopped while editing BridgeServer.swift",
            updatedAt: finishedAt,
            firstSeenAt: finishedAt.addingTimeInterval(-18 * 60),
            jumpTarget: JumpTarget(
                terminalApp: "Cursor",
                workspaceName: "open-vibe-island",
                paneTitle: "cursor ~/open-vibe-island",
                terminalSessionID: "fixture-poured-c1-interrupted"
            )
        )
    }

    // MARK: - Usage meters (AB-326 item 9)

    /// Fixture usage providers exposed for the header meter path. Claude carries
    /// two windows (`5h` 34%, `7d` 78%); Codex carries one (`7d` 92%). Reset
    /// times are offsets from `now` so the "resets in …" readouts stay stable.
    /// Stage 2 injects these into the settings preview header; the debug
    /// `usageMeters` scenario feeds them to the live overlay header.
    static func usageProviders(now: Date) -> [UsageProviderPresentation] {
        [
            UsageProviderPresentation(
                id: "claude",
                title: "Claude",
                windows: [
                    UsageWindowPresentation(
                        id: "claude-5h",
                        label: "5h",
                        usedPercentage: 34,
                        resetsAt: now.addingTimeInterval(2 * 3_600 + 10 * 60)
                    ),
                    UsageWindowPresentation(
                        id: "claude-7d",
                        label: "7d",
                        usedPercentage: 78,
                        resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3_600)
                    ),
                ]
            ),
            UsageProviderPresentation(
                id: "codex",
                title: "Codex",
                windows: [
                    UsageWindowPresentation(
                        id: "codex-7d",
                        label: "7d",
                        usedPercentage: 92,
                        resetsAt: now.addingTimeInterval(19 * 3_600)
                    ),
                ]
            ),
        ]
    }
}

// MARK: - Appearance preview scenarios (AB-326 stage 2)

/// The scenarios the Settings appearance session-list preview can render. Each
/// case maps — through the pure ``AppearancePreviewFixtures/scenarioContent(_:now:lang:)``
/// resolver — to a fixture session set, an optional actionable session id (so a
/// permission / question / completion *card* renders rather than a collapsed
/// row), and optional usage providers (only the ``meters`` case populates the
/// header meters).
enum AppearancePreviewScenario: String, CaseIterable, Identifiable, Sendable {
    case list
    case permissionCommand
    case permissionDiff
    case codexApproval
    case questionMulti
    case subagents
    case completedSuccess
    case completedVariants
    case duplicates
    case meters
    case empty

    var id: String { rawValue }

    /// Localization key for the picker label (en / zh-Hans / zh-Hant).
    var labelKey: String {
        "settings.appearance.previewScenario.\(rawValue)"
    }
}

/// The resolved inputs a scenario feeds into the session-list preview stage.
struct AppearancePreviewScenarioContent {
    /// The fixture sessions the preview lists.
    let sessions: [AgentSession]

    /// The session whose actionable (approval / question / completion) card the
    /// preview should expand. `nil` for the plain list / duplicates / meters /
    /// empty scenarios, where no single row is the hero.
    let actionableSessionID: String?

    /// Usage providers injected into the preview header. Non-`nil` only for the
    /// `meters` scenario; every other scenario keeps the header's default
    /// (headerless) behaviour.
    let usageProviders: [UsageProviderPresentation]?
}

extension AppearancePreviewFixtures {
    /// Pure scenario → preview-content mapping. Deterministic for a given `now`
    /// (it only composes the `now`-injected fixtures above), so the picker and
    /// its unit test resolve identical content.
    static func scenarioContent(
        _ scenario: AppearancePreviewScenario,
        now: Date,
        lang: LanguageManager
    ) -> AppearancePreviewScenarioContent {
        switch scenario {
        case .list:
            return AppearancePreviewScenarioContent(
                sessions: sessions(now: now, lang: lang),
                actionableSessionID: nil,
                usageProviders: nil
            )
        case .permissionCommand:
            let session = permissionCommand(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [session],
                actionableSessionID: session.id,
                usageProviders: nil
            )
        case .permissionDiff:
            let session = permissionDiff(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [session],
                actionableSessionID: session.id,
                usageProviders: nil
            )
        case .codexApproval:
            let session = codexTerminalApproval(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [session],
                actionableSessionID: session.id,
                usageProviders: nil
            )
        case .questionMulti:
            let session = questionMulti(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [session],
                actionableSessionID: session.id,
                usageProviders: nil
            )
        case .subagents:
            let session = subagentsAndTasks(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [session],
                actionableSessionID: session.id,
                usageProviders: nil
            )
        case .completedSuccess:
            let session = completedSuccess(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [session],
                actionableSessionID: session.id,
                usageProviders: nil
            )
        case .completedVariants:
            // Both outcomes in one list. `actionableSessionID` can only expand
            // one row (the scaffold keys a single hero), so the interrupted card
            // opens fully while the failed row stays outcome-differentiated but
            // collapsed — the two treatments are visible side by side.
            let interrupted = completedInterrupted(now: now)
            let failed = completedFailed(now: now)
            return AppearancePreviewScenarioContent(
                sessions: [interrupted, failed],
                actionableSessionID: interrupted.id,
                usageProviders: nil
            )
        case .duplicates:
            return AppearancePreviewScenarioContent(
                sessions: duplicateWorkspaceTrio(now: now),
                actionableSessionID: nil,
                usageProviders: nil
            )
        case .meters:
            return AppearancePreviewScenarioContent(
                sessions: sessions(now: now, lang: lang),
                actionableSessionID: nil,
                usageProviders: usageProviders(now: now)
            )
        case .empty:
            return AppearancePreviewScenarioContent(
                sessions: empty,
                actionableSessionID: nil,
                usageProviders: nil
            )
        }
    }
}
