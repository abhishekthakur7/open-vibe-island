import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeHooksTests {
    @Test
    func claudeHookOutputEncoderEncodesPermissionDecision() throws {
        let output = try ClaudeHookOutputEncoder.standardOutput(
            for: .claudeHookDirective(
                .permissionRequest(
                    .deny(message: "Permission denied in Open Island.", interrupt: true)
                )
            )
        )

        let payload = try #require(output)
        let object = try jsonObject(from: payload)
        let hookSpecificOutput = object["hookSpecificOutput"] as? [String: Any]
        let decision = hookSpecificOutput?["decision"] as? [String: Any]

        #expect(hookSpecificOutput?["hookEventName"] as? String == "PermissionRequest")
        #expect(decision?["behavior"] as? String == "deny")
        #expect(decision?["message"] as? String == "Permission denied in Open Island.")
        #expect(decision?["interrupt"] as? Bool == true)
    }

    // MARK: - AB-235: scoped always-allow (ClaudePermissionUpdate serialization)

    /// Confirms that choosing a scoped always-allow option round-trips onto
    /// the wire exactly as Claude Code's PermissionRequest hook contract
    /// expects: an "allow" decision whose `updatedPermissions` carries the
    /// selected `ClaudePermissionUpdate`, not just a bare allow.
    @Test
    func claudeHookOutputEncoderEncodesAllowDecisionWithScopedPermissionUpdate() throws {
        let rule = ClaudePermissionRuleValue(toolName: "Edit", ruleContent: "Sources/**")
        let update = ClaudePermissionUpdate.addRules(
            destination: .projectSettings,
            rules: [rule],
            behavior: .allow
        )

        let output = try ClaudeHookOutputEncoder.standardOutput(
            for: .claudeHookDirective(
                .permissionRequest(.allow(updatedInput: nil, updatedPermissions: [update]))
            )
        )

        let payload = try #require(output)
        let object = try jsonObject(from: payload)
        let hookSpecificOutput = object["hookSpecificOutput"] as? [String: Any]
        let decision = hookSpecificOutput?["decision"] as? [String: Any]
        let updatedPermissions = decision?["updatedPermissions"] as? [[String: Any]]

        #expect(decision?["behavior"] as? String == "allow")
        #expect(updatedPermissions?.count == 1)
        #expect(updatedPermissions?.first?["type"] as? String == "addRules")
        #expect(updatedPermissions?.first?["destination"] as? String == "projectSettings")
        #expect(updatedPermissions?.first?["behavior"] as? String == "allow")

        let rules = updatedPermissions?.first?["rules"] as? [[String: Any]]
        #expect(rules?.first?["toolName"] as? String == "Edit")
        #expect(rules?.first?["ruleContent"] as? String == "Sources/**")
    }

    /// Every `ClaudePermissionUpdate` case must survive an encode/decode
    /// round trip unchanged — this is the exact value carried from the
    /// approval card's chosen button, through `ApprovalAction.allowWithUpdates`,
    /// over the bridge, to the hook's stdout.
    @Test
    func claudePermissionUpdateRoundTripsThroughCodableForEveryCase() throws {
        let updates: [ClaudePermissionUpdate] = [
            .addRules(
                destination: .session,
                rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "npm run *")],
                behavior: .allow
            ),
            .replaceRules(
                destination: .localSettings,
                rules: [ClaudePermissionRuleValue(toolName: "Read")],
                behavior: .ask
            ),
            .removeRules(
                destination: .userSettings,
                rules: [ClaudePermissionRuleValue(toolName: "Write")],
                behavior: .deny
            ),
            .setMode(destination: .cliArg, mode: .acceptEdits),
            .addDirectories(destination: .projectSettings, directories: ["/tmp/a", "/tmp/b"]),
            .removeDirectories(destination: .projectSettings, directories: ["/tmp/a"]),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for update in updates {
            let data = try encoder.encode(update)
            let decoded = try decoder.decode(ClaudePermissionUpdate.self, from: data)
            #expect(decoded == update)
        }
    }

    /// The scoped-grant sentence is copy the overlay renders verbatim, and the
    /// mockup writes it exactly twice: a command is allowed "running `rtk grep`
    /// **from** this project" (`docs/design/overlay-redesign/06-halo.html:993`) and
    /// an edit is "**edits to** `*.md` **in** this project" (`:1031`). The label
    /// used to say "writing to … from this project" — four characters longer for
    /// no extra meaning, and on a 520pt panel those characters came out of the
    /// trailing scope phrase, which tail-truncated (parity G-21).
    @Test
    func editGrantLabelsUseTheMockupsShorterPhrasing() {
        let editScoped = ClaudePermissionUpdate.addRules(
            destination: .projectSettings,
            rules: [ClaudePermissionRuleValue(toolName: "Edit", ruleContent: "AGENTS.md")],
            behavior: .allow
        )
        #expect(editScoped.displayLabel == "Yes, allow edits to AGENTS.md/ in this project")

        // `Write` shares the verb; the preposition follows it.
        let writeScoped = ClaudePermissionUpdate.addRules(
            destination: .projectSettings,
            rules: [ClaudePermissionRuleValue(toolName: "Write", ruleContent: "docs")],
            behavior: .allow
        )
        #expect(writeScoped.displayLabel == "Yes, allow edits to docs/ in this project")

        // Every other verb keeps the board's "from this project" — the change is
        // scoped to the grammar the edit phrasing needs, not a blanket reword.
        let commandScoped = ClaudePermissionUpdate.addRules(
            destination: .projectSettings,
            rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "swift build")],
            behavior: .allow
        )
        #expect(commandScoped.displayLabel == "Yes, allow running swift build/ from this project")

        // Non-project destinations are preposition-free and unmoved.
        let editGlobal = ClaudePermissionUpdate.addRules(
            destination: .userSettings,
            rules: [ClaudePermissionRuleValue(toolName: "Edit", ruleContent: "AGENTS.md")],
            behavior: .allow
        )
        #expect(editGlobal.displayLabel == "Yes, allow edits to AGENTS.md/ globally")
    }

    @Test
    func claudeTranscriptDiscoveryRecoversRecentSessions() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-discovery-\(UUID().uuidString)", isDirectory: true)
        let workspaceDirectory = rootURL
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("-tmp-demo-repo", isDirectory: true)
        let transcriptURL = workspaceDirectory
            .appendingPathComponent("session-123.jsonl")
        let discovery = ClaudeTranscriptDiscovery(rootURL: rootURL.appendingPathComponent("projects", isDirectory: true))

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        let transcript = """
        {"cwd":"/tmp/demo-repo","sessionId":"session-123","type":"user","message":{"role":"user","content":"Fix the flaky auth tests."},"timestamp":"2026-04-03T03:20:00Z"}
        {"cwd":"/tmp/demo-repo","sessionId":"session-123","type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"I’m checking the auth test setup now."},{"type":"tool_use","id":"toolu_1","name":"Glob","input":{"pattern":"**/*auth*.test.ts"}}]},"timestamp":"2026-04-03T03:20:02Z"}
        {"cwd":"/tmp/demo-repo","sessionId":"session-123","type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"auth.test.ts"}]},"timestamp":"2026-04-03T03:20:04Z"}
        {"cwd":"/tmp/demo-repo","sessionId":"session-123","type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"Found the failing auth test file."}]},"timestamp":"2026-04-03T03:20:06Z"}
        """
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let sessions = discovery.discoverRecentSessions(
            now: ISO8601DateFormatter().date(from: "2026-04-03T03:20:10Z")!
        )

        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.id == "session-123")
        #expect(session.tool == .claudeCode)
        #expect(session.title == "Claude · demo-repo")
        #expect(session.summary == "Found the failing auth test file.")
        #expect(session.claudeMetadata?.initialUserPrompt == "Fix the flaky auth tests.")
        #expect(session.claudeMetadata?.lastAssistantMessage == "Found the failing auth test file.")
        #expect(session.claudeMetadata?.currentTool == nil)
        #expect(
            URL(fileURLWithPath: session.claudeMetadata?.transcriptPath ?? "").standardizedFileURL.path
                == transcriptURL.standardizedFileURL.path
        )
    }

    @Test
    func claudeTranscriptDiscoveryStreamsTranscriptsLargerThanReadChunk() throws {
        // Pins streaming behavior across read-chunk boundaries. The
        // pre-fix `parseSession` used `String(contentsOf:)` which on
        // heavy Claude users (multi-hundred-MB transcripts) produced
        // multi-GB startup peaks. The streamed reader must still
        // recover the same final state when meaningful events sit
        // beyond the first 64 KB chunk.
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-discovery-stream-\(UUID().uuidString)", isDirectory: true)
        let workspaceDirectory = rootURL
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("-tmp-demo-repo", isDirectory: true)
        let transcriptURL = workspaceDirectory.appendingPathComponent("session-large.jsonl")

        defer { try? FileManager.default.removeItem(at: rootURL) }

        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)

        let header = """
        {"cwd":"/tmp/demo-repo","sessionId":"session-large","type":"user","message":{"role":"user","content":"Initial prompt for the streamed transcript."},"timestamp":"2026-04-03T03:20:00Z"}
        """

        // Build a padded assistant message that, repeated many times,
        // overshoots the 64 KB chunk boundary. The final assistant
        // message must be recovered as the session summary.
        let padding = String(repeating: "x", count: 256)
        var lines: [String] = [header]
        for index in 0..<400 {
            lines.append("""
            {"cwd":"/tmp/demo-repo","sessionId":"session-large","type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"padding \(index) \(padding)"}]},"timestamp":"2026-04-03T03:20:01Z"}
            """)
        }
        lines.append("""
        {"cwd":"/tmp/demo-repo","sessionId":"session-large","type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"Streamed the large transcript end-to-end."}]},"timestamp":"2026-04-03T03:20:99Z"}
        """)

        let body = lines.joined(separator: "\n").appending("\n")
        try body.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let fileSize = (try FileManager.default.attributesOfItem(atPath: transcriptURL.path)[.size] as? Int) ?? 0
        #expect(fileSize > 64 * 1_024)

        let discovery = ClaudeTranscriptDiscovery(rootURL: rootURL.appendingPathComponent("projects", isDirectory: true))
        let sessions = discovery.discoverRecentSessions(
            now: ISO8601DateFormatter().date(from: "2026-04-03T03:21:00Z")!
        )

        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.id == "session-large")
        #expect(session.summary == "Streamed the large transcript end-to-end.")
        #expect(session.claudeMetadata?.initialUserPrompt == "Initial prompt for the streamed transcript.")
        #expect(session.claudeMetadata?.lastAssistantMessage == "Streamed the large transcript end-to-end.")
    }

    @Test
    func claudeInferTerminalAppPrefersWarpOverLeakedGhosttyEnvVars() {
        // Regression: launching Warp from a Ghostty tab leaks
        // GHOSTTY_RESOURCES_DIR (and friends) into every Warp shell via
        // macOS GUI app environment inheritance. The previous env-var-first
        // ordering tagged those Warp shells as Ghostty, causing
        // terminalLocator to query Ghostty's focused tab and stamp a
        // foreign Ghostty pane onto the Warp session's jumpTarget.
        // TERM_PROGRAM is the only signal that doesn't leak this way and
        // must dominate per-app env vars.
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo", hookEventName: .sessionStart, sessionID: "s1"
        ).withRuntimeContext(
            environment: [
                "TERM_PROGRAM": "WarpTerminal",
                "WARP_IS_LOCAL_SHELL_SESSION": "1",
                "GHOSTTY_RESOURCES_DIR": "/Applications/Ghostty.app/Contents/Resources/ghostty",
                "GHOSTTY_BIN_DIR": "/Applications/Ghostty.app/Contents/MacOS",
            ],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) }
        )

        #expect(payload.terminalApp == "Warp")
    }

    /// Verifies a Claude Desktop session is tagged `Claude.app` via the
    /// authoritative `CLAUDE_CODE_ENTRYPOINT=claude-desktop` signal. The
    /// desktop subprocess is TTY-less and invisible to process discovery, so
    /// this tag is what lets liveness follow the desktop app instead of a
    /// non-existent terminal process.
    @Test
    func claudeInferTerminalAppRecognizesClaudeDesktopViaEntrypoint() {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo", hookEventName: .sessionStart, sessionID: "s1"
        ).withRuntimeContext(
            environment: ["CLAUDE_CODE_ENTRYPOINT": "claude-desktop"],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) }
        )

        #expect(payload.terminalApp == "Claude.app")
        #expect(payload.defaultJumpTarget.terminalApp == "Claude.app")
    }

    /// Verifies the desktop entrypoint signal wins over a leaked
    /// `TERM_PROGRAM`. Launching Claude.app from a terminal (e.g.
    /// `open -a Claude` from Ghostty) leaks the parent shell's `TERM_PROGRAM`
    /// into the subprocess env; the session must still classify as
    /// `Claude.app`, not the launching terminal.
    @Test
    func claudeInferTerminalAppPrefersClaudeDesktopOverLeakedTermProgram() {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo", hookEventName: .sessionStart, sessionID: "s1"
        ).withRuntimeContext(
            environment: [
                "CLAUDE_CODE_ENTRYPOINT": "claude-desktop",
                "TERM_PROGRAM": "ghostty",
            ],
            currentTTYProvider: { nil },
            terminalLocatorProvider: { _ in (sessionID: nil, tty: nil, title: nil) }
        )

        #expect(payload.terminalApp == "Claude.app")
    }

}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}
