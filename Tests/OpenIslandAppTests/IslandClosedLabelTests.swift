import AppKit
import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-322 (Part A) — the closed pill's label vocabulary.
///
/// The specs pin these exact sentences (SPEC-halo Slot 1 / §6.5,
/// SPEC-poured §3.1 A2/A2′/A5/A6, SPEC-flight-deck §3): the pill narrates
/// `Editing AppModel.swift`, `Refactoring · 3 agents`, `3 working`,
/// `Approve swift build?`, `Answer needed`, `Done · the-automator`,
/// `Interrupted · niche-radar`, `Failed · open-vibe-island` — never
/// `Claude · Edit`. Every assertion here is an exact string, and every one
/// injects `now`, so nothing depends on the wall clock.
struct IslandClosedLabelTests {

    // MARK: - Fixtures

    /// A `LanguageManager` pinned to a known language, with the user's own
    /// `appLanguage` default restored afterwards (same idiom as
    /// `NarratedActivityTests`).
    private func withLanguage<T>(
        _ language: LanguageManager.AppLanguage,
        _ body: (LanguageManager) -> T
    ) -> T {
        let original = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let manager = LanguageManager()
        manager.language = language
        return body(manager)
    }

    private func session(
        id: String = "spotlight",
        workspace: String = "open-vibe-island",
        phase: SessionPhase,
        outcome: SessionOutcome = .success,
        updatedAt: Date = Date(timeIntervalSince1970: 10_000),
        permissionRequest: PermissionRequest? = nil,
        currentTool: String? = nil,
        preview: String? = nil,
        subagents: Int = 0
    ) -> AgentSession {
        let metadata: ClaudeSessionMetadata? = {
            guard currentTool != nil || preview != nil || subagents > 0 else { return nil }
            return ClaudeSessionMetadata(
                currentTool: currentTool,
                currentToolInputPreview: preview,
                activeSubagents: (0..<subagents).map { ClaudeSubagentInfo(agentID: "agent-\($0)") }
            )
        }()

        return AgentSession(
            id: id,
            title: "Claude · \(workspace)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            outcome: outcome,
            summary: phase.displayName,
            updatedAt: updatedAt,
            permissionRequest: permissionRequest,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: workspace,
                paneTitle: "claude ~/\(workspace)",
                workingDirectory: "/tmp/\(workspace)",
                terminalSessionID: "ghostty-\(id)"
            ),
            claudeMetadata: metadata
        )
    }

    private func label(
        _ session: AgentSession?,
        runningCount: Int = 1,
        preference: IslandCenterLabel = .agentAction,
        now: Date = Date(timeIntervalSince1970: 10_000)
    ) -> String? {
        withLanguage(.en) { language in
            IslandClosedLabelResolver.label(
                spotlight: session,
                runningCount: runningCount,
                preference: preference,
                language: language,
                now: now
            )
        }
    }

    // MARK: - Attention · permission

    @Test
    func permissionLabelNarratesTheFirstTwoCommandWords() {
        let pending = session(
            phase: .waitingForApproval,
            permissionRequest: PermissionRequest(
                title: "Run command",
                summary: "Claude wants to run a shell command.",
                affectedPath: ""
            ),
            currentTool: "Bash",
            preview: "swift build -c release --product OpenIslandHooks"
        )

        #expect(label(pending) == "Approve swift build?")
    }

    @Test
    func permissionLabelFallsBackToApprovalNeededWithoutACommand() {
        // A file-edit approval carries a path, not a command — `Approve
        // /Users/a/AppModel.swift?` would be nonsense.
        let pending = session(
            phase: .waitingForApproval,
            permissionRequest: PermissionRequest(
                title: "Edit file",
                summary: "Claude wants to edit a file.",
                affectedPath: "/Users/a/Sources/AppModel.swift"
            )
        )

        #expect(label(pending) == "Approval needed")
    }

    // MARK: - Attention · question

    @Test
    func questionLabelIsAnswerNeeded() {
        #expect(label(session(phase: .waitingForAnswer)) == "Answer needed")
    }

    // MARK: - Running

    @Test
    func singleRunningSessionNarratesItsActivity() {
        let running = session(
            phase: .running,
            currentTool: "Edit",
            preview: "/Users/a/Developer/open-vibe-island/Sources/OpenIslandApp/AppModel.swift"
        )

        #expect(label(running) == "Editing AppModel.swift")
    }

    @Test
    func manyRunningSessionsCollapseToACount() {
        let running = session(
            phase: .running,
            currentTool: "Edit",
            preview: "AppModel.swift"
        )

        #expect(label(running, runningCount: 3) == "3 working")
    }

    @Test
    func runningSessionWithoutNarrationFallsBackToTheLegacyForm() {
        // Nothing to narrate → the pre-AB-322 `.agentAction` rendering, so the
        // pill never goes blank.
        #expect(label(session(phase: .running)) == "Claude Code")
    }

    // MARK: - Outcomes (settle window)

    @Test
    func outcomeLabelsNameTheWorkspace() {
        let finishedAt = Date(timeIntervalSince1970: 10_000)
        let justAfter = finishedAt.addingTimeInterval(1)

        #expect(
            label(
                session(workspace: "the-automator", phase: .completed, outcome: .success, updatedAt: finishedAt),
                runningCount: 0,
                now: justAfter
            ) == "Done · the-automator"
        )

        #expect(
            label(
                session(workspace: "niche-radar", phase: .completed, outcome: .interrupted, updatedAt: finishedAt),
                runningCount: 0,
                now: justAfter
            ) == "Interrupted · niche-radar"
        )

        #expect(
            label(
                session(workspace: "open-vibe-island", phase: .completed, outcome: .failed, updatedAt: finishedAt),
                runningCount: 0,
                now: justAfter
            ) == "Failed · open-vibe-island"
        )
    }

    @Test
    func outcomeLabelSurvivesToTheEdgeOfTheSettleWindowThenFallsBack() {
        let finishedAt = Date(timeIntervalSince1970: 10_000)
        let window = IslandClosedPillTiming.outcomeLabelWindow
        let done = session(
            workspace: "the-automator",
            phase: .completed,
            outcome: .success,
            updatedAt: finishedAt
        )

        // Just inside the window: still the verdict.
        #expect(
            label(done, runningCount: 0, now: finishedAt.addingTimeInterval(window - 0.1))
                == "Done · the-automator"
        )

        // At and past the window: back to the ordinary preference rendering.
        #expect(label(done, runningCount: 0, now: finishedAt.addingTimeInterval(window)) == "Claude Code")
        #expect(label(done, runningCount: 0, now: finishedAt.addingTimeInterval(600)) == "Claude Code")
    }

    // MARK: - Preference gating (unchanged behaviour)

    @Test
    func offPreferenceStillProducesNoLabel() {
        let running = session(phase: .running, currentTool: "Edit", preview: "AppModel.swift")
        #expect(label(running, preference: .off) == nil)
    }

    @Test
    func noSpotlightSessionProducesNoLabel() {
        #expect(label(nil) == nil)
        #expect(label(nil, preference: .sessionName) == nil)
    }

    // MARK: - Localization

    // MARK: - AppModel wiring

    @MainActor
    @Test
    func appModelLabelUsesTheInjectedReferenceDateForTheSettleWindow() {
        // Locale-agnostic on purpose: `LanguageManager.shared` follows the
        // host's `appLanguage`, so this asserts the *shape* (the raw workspace
        // name is present inside the window, gone after it) rather than the
        // localized word. Exact strings are pinned above on the resolver.
        let finishedAt = Date(timeIntervalSince1970: 10_000)
        let model = AppModel()
        model.overlayPlacementDiagnostics = OverlayPlacementDiagnostics(
            targetScreenID: "display-topbar",
            targetScreenName: "External Display",
            selectionSummary: "test",
            mode: .topBar,
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
            overlayFrame: NSRect(x: 400, y: 820, width: 700, height: 160)
        )
        #expect(model.islandCenterLabel == .agentAction)

        var done = session(workspace: "the-automator", phase: .completed, updatedAt: finishedAt)
        done.isProcessAlive = true
        model.state = SessionState(sessions: [done])
        #expect(model.islandClosedSpotlight?.id == done.id)

        let inside = model.islandClosedLabel(at: finishedAt.addingTimeInterval(1))
        #expect(inside?.contains("the-automator") == true)
        #expect(inside?.contains(" · ") == true)

        let outside = model.islandClosedLabel(at: finishedAt.addingTimeInterval(60))
        #expect(outside == "Claude Code")
    }
}
