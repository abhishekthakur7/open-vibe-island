import Foundation
import Testing
@testable import OpenIslandCore

struct CodexSessionTrackingTests {
    @Test
    func codexSessionStoreRoundTripsTrackedSessions() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-tracking-\(UUID().uuidString)", isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("session-terminals.json")
        let store = CodexSessionStore(fileURL: fileURL)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let records = [
            CodexTrackedSessionRecord(
                sessionID: "codex-session-1",
                title: "Codex · open-island",
                origin: .live,
                attachmentState: .attached,
                summary: "Inspecting rollout watcher.",
                phase: .running,
                updatedAt: .now,
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: "codex ~/Personal/open-island"
                ),
                codexMetadata: CodexSessionMetadata(
                    transcriptPath: "/tmp/rollout.jsonl",
                    initialUserPrompt: "Start by checking the rollout watcher.",
                    lastUserPrompt: "Check the rollout watcher state.",
                    lastAssistantMessage: "Inspecting rollout watcher.",
                    currentTool: "exec_command",
                    currentCommandPreview: "git status -sb",
                    // F20 (overlay remediation Phase 3): round-trips the new
                    // field through the same store this test already proves
                    // round-trips everything else.
                    model: "gpt-5-codex"
                )
            )
        ]

        try store.save(records)
        let reloaded = try store.load()

        #expect(reloaded.count == records.count)
        #expect(reloaded.first?.sessionID == records.first?.sessionID)
        #expect(reloaded.first?.codexMetadata == nil)
        #expect(reloaded.first?.jumpTarget == nil)
        #expect(reloaded.first?.session.codexMetadata == nil)
        #expect(reloaded.first?.session.origin == .live)
        #expect(reloaded.first?.session.attachmentState == .attached)
    }

    @Test
    func codexTrackedSessionRecordRejectsDemoAndLegacyMockSessions() {
        let liveRecord = CodexTrackedSessionRecord(
            sessionID: "codex-live-1",
            title: "Codex · live",
            origin: .live,
            attachmentState: .attached,
            summary: "Working",
            phase: .running,
            updatedAt: .now
        )
        let demoRecord = CodexTrackedSessionRecord(
            sessionID: "codex-demo-1",
            title: "Codex · demo",
            origin: .demo,
            attachmentState: .attached,
            summary: "Working",
            phase: .running,
            updatedAt: .now
        )
        let legacyMockRecord = CodexTrackedSessionRecord(
            sessionID: "codex-backend-server",
            title: "backend server",
            summary: "REST endpoints built. Tests are green.",
            phase: .completed,
            updatedAt: .now
        )
        let debugScenarioRecord = CodexTrackedSessionRecord(
            sessionID: "session-approval",
            title: "Codex · open-island",
            origin: .live,
            attachmentState: .attached,
            summary: "Approval needed",
            phase: .waitingForApproval,
            updatedAt: .now
        )

        #expect(liveRecord.shouldRestoreToLiveState)
        #expect(!demoRecord.shouldRestoreToLiveState)
        #expect(!legacyMockRecord.shouldRestoreToLiveState)
        #expect(!debugScenarioRecord.shouldRestoreToLiveState)
    }

    @Test
    func codexRolloutReducerTracksPromptCommandAndCompletion() {
        let initialLines = [
            rolloutLine(
                timestamp: "2026-04-02T04:03:44.500Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Check the rollout watcher status.",
                ]
            ),
            rolloutLine(
                timestamp: "2026-04-02T04:03:44.894Z",
                type: "response_item",
                payload: [
                    "type": "function_call",
                    "name": "exec_command",
                    "arguments": "{\"cmd\":\"git status -sb\"}",
                ]
            ),
        ]
        let initialSnapshot = CodexRolloutReducer.snapshot(for: initialLines)
        // F20 clobber fix (overlay remediation Phase 3C): `existingMetadata` stands
        // in for what the hook path already merged onto this session (mirroring
        // `BridgeServer.mergedCodexMetadata`'s output) before this rollout-sourced
        // update runs — see `codexRolloutReducerPreservesHookSourcedModelAcrossRolloutMetadataUpdate`
        // below for the dedicated clobber regression.
        let hookSourcedMetadata = CodexSessionMetadata(model: "gpt-5-codex")
        let initialEvents = CodexRolloutReducer.events(
            from: nil,
            to: initialSnapshot,
            sessionID: "codex-session-1",
            transcriptPath: "/tmp/rollout.jsonl",
            existingMetadata: hookSourcedMetadata
        )

        #expect(initialSnapshot.initialUserPrompt == "Check the rollout watcher status.")
        #expect(initialSnapshot.lastUserPrompt == "Check the rollout watcher status.")
        #expect(initialSnapshot.currentTool == "exec_command")
        #expect(initialSnapshot.currentCommandPreview == "git status -sb")
        #expect(initialEvents.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.initialUserPrompt == "Check the rollout watcher status." }))
        #expect(initialEvents.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.lastUserPrompt == "Check the rollout watcher status." }))
        #expect(initialEvents.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.currentCommandPreview == "git status -sb" }))
        #expect(initialEvents.contains(where: { $0.trackedActivityUpdate?.summary == "Running command." }))
        // F20 clobber fix (overlay remediation Phase 3C): this used to pin the bug
        // rather than leave it as a prose note — `CodexRolloutSnapshot` has no
        // model field, so a rollout-sourced metadata update built purely from the
        // snapshot always carried `model == nil`, clobbering whatever the hook path
        // had set the instant `SessionState.apply` applied it (blind overwrite, not
        // a merge — `SessionState.swift`'s `.sessionMetadataUpdated` case). Now
        // `events(...)` merges against `existingMetadata`, so the model set above
        // survives this rollout-sourced update instead.
        #expect(initialEvents.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.model == "gpt-5-codex" }))

        let finalSnapshot = CodexRolloutReducer.snapshot(
            for: initialLines + [
                rolloutLine(
                    timestamp: "2026-04-02T04:03:45.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "agent_message",
                        "message": "Inspecting README and current hooks config.",
                    ]
                ),
                rolloutLine(
                    timestamp: "2026-04-02T04:03:46.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "task_complete",
                        "last_agent_message": "Rollout watcher is wired and verified.",
                    ]
                ),
            ]
        )
        let finalEvents = CodexRolloutReducer.events(
            from: initialSnapshot,
            to: finalSnapshot,
            sessionID: "codex-session-1",
            transcriptPath: "/tmp/rollout.jsonl",
            existingMetadata: hookSourcedMetadata
        )

        #expect(finalSnapshot.phase == .completed)
        #expect(finalSnapshot.currentTool == nil)
        #expect(finalSnapshot.currentCommandPreview == nil)
        #expect(finalEvents.contains(where: { $0.trackedSessionCompletion?.summary == "Rollout watcher is wired and verified." }))
        #expect(finalEvents.contains(where: { $0.trackedSessionCompletion?.isInterrupt != true }))
        #expect(finalEvents.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.currentTool == nil }))
        #expect(finalEvents.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.currentCommandPreview == nil }))
        // The model survives all the way through completion too, not just the
        // first rollout-sourced update.
        #expect(finalEvents.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.model == "gpt-5-codex" }))
    }

    /// F20 clobber fix (overlay remediation Phase 3C) — regression test for the
    /// production bug documented in `docs/design/overlay-redesign/
    /// REMEDIATION-PLAN.md`'s Phase 3A outcome: a hook-reported `model` was being
    /// reset to `nil` by the very next rollout poll (~3s later,
    /// `SessionDiscoveryCoordinator.refreshCodexRolloutTracking` →
    /// `CodexRolloutWatcher`) because `CodexRolloutSnapshot` has no field for it
    /// and `events(...)` built `CodexSessionMetadata` purely from the snapshot.
    /// Confirmed failing before the fix (asserting `model == "gpt-5-codex"`
    /// against the unmerged construction produced `model == nil`) and passing
    /// after — see the Phase 3C report for both directions.
    @Test
    func codexRolloutReducerPreservesHookSourcedModelAcrossRolloutMetadataUpdate() {
        // Step 1: the hook path already resolved and merged a model onto this
        // session (mirrors what `BridgeServer.mergedCodexMetadata` produces from
        // `CodexHookPayload.model` — reconstructed directly here since that merge
        // lives outside this file). It also carries a `currentTool` the hook had
        // reported, to prove the fix below doesn't over-apply.
        let hookSourcedMetadata = CodexSessionMetadata(
            currentTool: "exec_command",
            currentCommandPreview: "git status -sb",
            model: "gpt-5-codex"
        )

        // Step 2: a rollout-sourced poll ~3s later — Codex finished the tool call
        // the hook had reported, so `currentTool`/`currentCommandPreview`
        // legitimately clear. `CodexRolloutSnapshot` never carries `model` at all.
        let oldSnapshot = CodexRolloutSnapshot(
            currentTool: "exec_command",
            currentCommandPreview: "git status -sb"
        )
        let newSnapshot = CodexRolloutSnapshot(
            summary: "Thinking.",
            currentTool: nil,
            currentCommandPreview: nil
        )

        let events = CodexRolloutReducer.events(
            from: oldSnapshot,
            to: newSnapshot,
            sessionID: "codex-session-1",
            transcriptPath: "/tmp/rollout.jsonl",
            existingMetadata: hookSourcedMetadata
        )

        // The clobber this regression test exists to catch: the model must
        // survive a rollout-sourced update, even though the rollout itself never
        // observes it.
        #expect(events.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.model == "gpt-5-codex" }))
        // The inverse error the fix must not introduce: a field the rollout DOES
        // legitimately clear must still be allowed to clear, despite
        // `existingMetadata` carrying a stale non-nil value for it — merging must
        // not freeze it.
        #expect(events.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.currentTool == nil }))
        #expect(events.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.currentCommandPreview == nil }))
    }

    @Test
    func codexRolloutReducerAlignsCodexResponseItemStatuses() {
        var snapshot = CodexRolloutSnapshot()

        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:44.500Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Check the Codex statuses.",
                ]
            ),
            to: &snapshot
        )
        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:45.000Z",
                type: "response_item",
                payload: [
                    "type": "reasoning",
                    "summary": [],
                ]
            ),
            to: &snapshot
        )

        #expect(snapshot.currentTool == nil)
        #expect(snapshot.currentCommandPreview == nil)
        #expect(snapshot.summary == "Thinking.")

        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:46.000Z",
                type: "response_item",
                payload: [
                    "type": "web_search_call",
                    "status": "completed",
                    "action": [
                        "type": "search",
                        "query": "Codex rollout ResponseItem",
                    ],
                ]
            ),
            to: &snapshot
        )

        #expect(snapshot.currentTool == "web_search")
        #expect(snapshot.currentCommandPreview == "Codex rollout ResponseItem")
        #expect(snapshot.summary == "Running web search.")

        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:47.000Z",
                type: "response_item",
                payload: [
                    "type": "function_call_output",
                    "call_id": "call-1",
                    "output": "done",
                ]
            ),
            to: &snapshot
        )

        #expect(snapshot.currentTool == nil)
        #expect(snapshot.currentCommandPreview == nil)
        #expect(snapshot.summary == "Thinking.")

        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:48.000Z",
                type: "response_item",
                payload: [
                    "type": "image_generation_call",
                    "id": "ig-1",
                    "status": "completed",
                    "revised_prompt": "A status diagram",
                    "result": "base64",
                ]
            ),
            to: &snapshot
        )

        #expect(snapshot.currentTool == "image_generation")
        #expect(snapshot.currentCommandPreview == "A status diagram")
        #expect(snapshot.summary == "Running image generation.")

        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:49.000Z",
                type: "response_item",
                payload: [
                    "type": "local_shell_call",
                    "status": "in_progress",
                    "action": [
                        "type": "exec",
                        "command": ["zsh", "-lc", "swift test --filter CodexSessionTrackingTests"],
                    ],
                ]
            ),
            to: &snapshot
        )

        #expect(snapshot.currentTool == "exec_command")
        #expect(snapshot.currentCommandPreview == "swift test --filter CodexSessionTrackingTests")
        #expect(snapshot.summary == "Running command.")

        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:50.000Z",
                type: "response_item",
                payload: [
                    "type": "tool_search_call",
                    "execution": "search docs",
                    "arguments": [
                        "query": "Codex EventMsg",
                    ],
                ]
            ),
            to: &snapshot
        )

        #expect(snapshot.currentTool == "tool_search")
        #expect(snapshot.currentCommandPreview == "search docs")
        #expect(snapshot.summary == "Running tool search.")
    }

    @Test
    func codexRolloutReducerAlignsCodexEventMessageStatuses() {
        var snapshot = CodexRolloutSnapshot()

        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:44.500Z",
                type: "event_msg",
                payload: [
                    "type": "exec_command_begin",
                    "command": ["zsh", "-lc", "git status -sb"],
                ]
            ),
            to: &snapshot
        )

        #expect(snapshot.currentTool == "exec_command")
        #expect(snapshot.currentCommandPreview == "git status -sb")
        #expect(snapshot.summary == "Running command.")

        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:45.000Z",
                type: "event_msg",
                payload: [
                    "type": "exec_command_end",
                    "command": ["zsh", "-lc", "git status -sb"],
                    "stdout": "",
                    "stderr": "",
                    "exit_code": 0,
                    "status": "completed",
                ]
            ),
            to: &snapshot
        )

        #expect(snapshot.currentTool == nil)
        #expect(snapshot.currentCommandPreview == nil)
        #expect(snapshot.summary == "Thinking.")

        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:46.000Z",
                type: "event_msg",
                payload: [
                    "type": "terminal_interaction",
                    "stdin": "y\n",
                ]
            ),
            to: &snapshot
        )

        #expect(snapshot.currentTool == "write_stdin")
        #expect(snapshot.currentCommandPreview == "y")
        #expect(snapshot.summary == "Running input.")

        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:47.000Z",
                type: "event_msg",
                payload: [
                    "type": "patch_apply_begin",
                    "changes": [
                        "Sources/OpenIslandCore/CodexSessionTracking.swift": [:],
                    ],
                ]
            ),
            to: &snapshot
        )

        #expect(snapshot.currentTool == "apply_patch")
        #expect(snapshot.currentCommandPreview == "CodexSessionTracking.swift")
        #expect(snapshot.summary == "Running patch.")

        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:48.000Z",
                type: "event_msg",
                payload: [
                    "type": "patch_apply_end",
                    "success": true,
                    "changes": [
                        "Sources/OpenIslandCore/CodexSessionTracking.swift": [:],
                    ],
                    "status": "completed",
                ]
            ),
            to: &snapshot
        )

        #expect(snapshot.currentTool == nil)
        #expect(snapshot.summary == "Thinking.")

        CodexRolloutReducer.apply(
            line: rolloutLine(
                timestamp: "2026-04-02T04:03:49.000Z",
                type: "event_msg",
                payload: [
                    "type": "web_search_end",
                    "query": "Codex statuses",
                    "action": [
                        "type": "find_in_page",
                        "pattern": "ResponseItem",
                        "url": "https://github.com/openai/codex",
                    ],
                ]
            ),
            to: &snapshot
        )

        #expect(snapshot.currentTool == "web_search")
        #expect(snapshot.currentCommandPreview == "'ResponseItem' in https://github.com/openai/codex")
        #expect(snapshot.summary == "Running web search.")
    }

    @Test
    func codexRolloutReducerMarksTurnAbortedAsInterruptedCompletion() {
        let initialSnapshot = CodexRolloutReducer.snapshot(for: [
            rolloutLine(
                timestamp: "2026-04-02T04:03:44.500Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Inspect the completion notification behavior.",
                ]
            ),
        ])
        let interruptedSnapshot = CodexRolloutReducer.snapshot(for: [
            rolloutLine(
                timestamp: "2026-04-02T04:03:44.500Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Inspect the completion notification behavior.",
                ]
            ),
            rolloutLine(
                timestamp: "2026-04-02T04:03:45.000Z",
                type: "event_msg",
                payload: [
                    "type": "turn_aborted",
                    "reason": "interrupted",
                ]
            ),
        ])
        let events = CodexRolloutReducer.events(
            from: initialSnapshot,
            to: interruptedSnapshot,
            sessionID: "codex-session-1",
            transcriptPath: "/tmp/rollout.jsonl"
        )

        #expect(interruptedSnapshot.phase == .completed)
        #expect(interruptedSnapshot.isInterrupted)
        #expect(events.contains(where: {
            $0.trackedSessionCompletion?.summary == "Codex turn was interrupted."
                && $0.trackedSessionCompletion?.isInterrupt == true
        }))
    }

    @Test
    func codexAppSessionReconcilerEndsArchivedSessions() {
        let events = CodexAppSessionReconciler.reconciliationEvents(
            for: [
                AgentSession(
                    id: "019ef332-b281-7292-874f-4cf8787fb4b8",
                    title: "Codex · hacking-activity",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .attached,
                    phase: .completed,
                    summary: "Turn stalled.",
                    updatedAt: .now,
                    jumpTarget: JumpTarget(
                        terminalApp: "Codex.app",
                        workspaceName: "hacking-activity",
                        paneTitle: "Codex",
                        workingDirectory: "/Users/admin/GoCode/hacking-activity",
                        codexThreadID: "019ef332-b281-7292-874f-4cf8787fb4b8"
                    )
                ),
            ],
            archivedSessionIDs: ["019ef332-b281-7292-874f-4cf8787fb4b8"]
        )

        #expect(events.count == 1)
        #expect(events.first?.trackedSessionCompletion?.isSessionEnd == true)
        #expect(events.first?.trackedSessionCompletion?.summary == "Codex thread archived.")
    }

    /// F20 clobber fix (overlay remediation Phase 3C) — the same clobber as
    /// `codexRolloutReducerPreservesHookSourcedModelAcrossRolloutMetadataUpdate`,
    /// exercised through the actual `CodexRolloutWatcher` timer/file-polling path
    /// (like `codexRolloutWatcherTracksAppendedLines` above) rather than the pure
    /// reducer, so the watcher-level wiring — `updateKnownMetadata(_:)` →
    /// `knownMetadataBySessionID` → `refresh(observation:)` — is proven connected
    /// end to end, not just correct in isolation.
    @Test
    func codexRolloutWatcherPreservesKnownMetadataAcrossPolls() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-rollout-metadata-\(UUID().uuidString)", isDirectory: true)
        let rolloutURL = rootURL.appendingPathComponent("rollout.jsonl")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data().write(to: rolloutURL)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let recorder = EventRecorder()
        let watcher = CodexRolloutWatcher(pollInterval: 0.05)
        watcher.eventHandler = { event in
            Task {
                await recorder.append(event)
            }
        }

        // Mirrors `SessionDiscoveryCoordinator.refreshCodexRolloutTracking`:
        // known metadata is refreshed before `sync(targets:)` on every applied
        // event, so it is already populated by the time the very first poll
        // runs — not just from the second poll onward.
        watcher.updateKnownMetadata([
            "codex-session-1": CodexSessionMetadata(model: "gpt-5-codex"),
        ])
        watcher.sync(targets: [
            CodexRolloutWatchTarget(
                sessionID: "codex-session-1",
                transcriptPath: rolloutURL.path
            )
        ])

        try appendRolloutLine(
            rolloutLine(
                timestamp: "2026-04-02T04:03:44.894Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Inspect the README.",
                ]
            ),
            to: rolloutURL
        )

        try await Task.sleep(for: .milliseconds(200))
        watcher.stop()

        let events = await recorder.snapshot()
        #expect(events.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.lastUserPrompt == "Inspect the README." }))
        // The clobber this test exists to catch: every real poll tick used to
        // rebuild `codexMetadata` purely from the rollout snapshot (no `model`
        // field exists on `CodexRolloutSnapshot`), so this assertion would have
        // failed with `model == nil` before the fix.
        #expect(events.contains(where: { $0.trackedMetadataUpdate?.codexMetadata.model == "gpt-5-codex" }))
    }

    @Test
    func codexRolloutDiscoveryFindsRecentSessionsFromLocalRollouts() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-discovery-\(UUID().uuidString)", isDirectory: true)
        let recentDirectoryURL = rootURL.appendingPathComponent("2026/04/02", isDirectory: true)
        let staleDirectoryURL = rootURL.appendingPathComponent("2026/03/30", isDirectory: true)
        let recentRolloutURL = recentDirectoryURL.appendingPathComponent("rollout-recent.jsonl")
        let staleRolloutURL = staleDirectoryURL.appendingPathComponent("rollout-stale.jsonl")
        let now = Date(timeIntervalSince1970: 1_743_555_200)

        try FileManager.default.createDirectory(at: recentDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staleDirectoryURL, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let recentLines = [
            sessionMetaLine(
                sessionID: "codex-session-1",
                timestamp: "2026-04-02T04:03:44.000Z",
                cwd: "/Users/wangruobing/Personal/open-island"
            ),
            rolloutLine(
                timestamp: "2026-04-02T04:03:45.000Z",
                type: "response_item",
                payload: [
                    "type": "function_call",
                    "name": "exec_command",
                    "arguments": "{\"cmd\":\"git status -sb\"}",
                ]
            ),
            rolloutLine(
                timestamp: "2026-04-02T04:03:45.500Z",
                type: "event_msg",
                payload: [
                    "type": "user_message",
                    "message": "Inspect the local rollout files.",
                ]
            ),
            rolloutLine(
                timestamp: "2026-04-02T04:03:46.000Z",
                type: "event_msg",
                payload: [
                    "type": "agent_message",
                    "message": "Inspecting the local rollout files.",
                ]
            ),
        ]
        let staleLines = [
            sessionMetaLine(
                sessionID: "codex-session-stale",
                timestamp: "2026-03-30T04:03:44.000Z",
                cwd: "/Users/wangruobing/Personal/old-repo"
            ),
        ]

        try recentLines.joined(separator: "\n").appending("\n").write(to: recentRolloutURL, atomically: true, encoding: .utf8)
        try staleLines.joined(separator: "\n").appending("\n").write(to: staleRolloutURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: recentRolloutURL.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-172_800)], ofItemAtPath: staleRolloutURL.path)

        let discovery = CodexRolloutDiscovery(
            rootURL: rootURL,
            fileManager: .default,
            maxAge: 86_400,
            maxFiles: 10
        )

        let records = discovery.discoverRecentSessions(now: now)

        #expect(records.count == 1)
        #expect(records.first?.sessionID == "codex-session-1")
        #expect(records.first?.title == "Codex · open-island")
        #expect(records.first?.summary == "Inspecting the local rollout files.")
        #expect(records.first?.phase == .running)
        #expect(
            records.first?.codexMetadata?.transcriptPath.map {
                URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
            } == recentRolloutURL.resolvingSymlinksInPath().path
        )
        #expect(records.first?.codexMetadata?.lastAssistantMessage == "Inspecting the local rollout files.")
        #expect(records.first?.codexMetadata?.lastUserPrompt == "Inspect the local rollout files.")
        #expect(records.first?.codexMetadata?.currentTool == nil)
        #expect(records.first?.codexMetadata?.currentCommandPreview == nil)
        #expect(records.first?.origin == .live)
        #expect(records.first?.attachmentState == .stale)
    }

    @Test
    func codexRolloutDiscoveryStreamsRolloutsLargerThanReadChunk() throws {
        // Pins streaming behavior across read-chunk boundaries. The
        // discovery path used to slurp the whole rollout via
        // `String(contentsOf:)`, which on multi-MB files allocated
        // 2–3× file size every 10s and pushed the app toward swap.
        // The streamed reader must reassemble lines correctly when
        // the meaningful events sit beyond the first 64 KB chunk.
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-discovery-stream-\(UUID().uuidString)", isDirectory: true)
        let rolloutDirectoryURL = rootURL.appendingPathComponent("2026/04/02", isDirectory: true)
        let rolloutURL = rolloutDirectoryURL.appendingPathComponent("rollout-large.jsonl")
        let now = Date(timeIntervalSince1970: 1_743_555_200)

        try FileManager.default.createDirectory(at: rolloutDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        var lines: [String] = [
            sessionMetaLine(
                sessionID: "codex-session-large",
                timestamp: "2026-04-02T04:03:44.000Z",
                cwd: "/Users/wangruobing/Personal/open-island"
            )
        ]
        // Pad with enough no-op `agent_message` lines to push the
        // meaningful events past the 64 KB read-chunk boundary so
        // the streaming loop must span at least two chunks.
        let padding = String(repeating: "x", count: 256)
        for index in 0..<800 {
            lines.append(rolloutLine(
                timestamp: "2026-04-02T04:03:45.000Z",
                type: "event_msg",
                payload: [
                    "type": "agent_message",
                    "message": "padding \(index) \(padding)",
                ]
            ))
        }
        lines.append(rolloutLine(
            timestamp: "2026-04-02T04:03:46.000Z",
            type: "event_msg",
            payload: [
                "type": "user_message",
                "message": "Inspect the large rollout.",
            ]
        ))
        lines.append(rolloutLine(
            timestamp: "2026-04-02T04:03:46.500Z",
            type: "event_msg",
            payload: [
                "type": "agent_message",
                "message": "Streamed the large rollout end-to-end.",
            ]
        ))

        let body = lines.joined(separator: "\n").appending("\n")
        try body.write(to: rolloutURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: rolloutURL.path)

        // Sanity-check the fixture genuinely exceeds the streaming
        // chunk size, otherwise this test wouldn't prove anything.
        let fileSize = (try FileManager.default.attributesOfItem(atPath: rolloutURL.path)[.size] as? Int) ?? 0
        #expect(fileSize > 64 * 1_024)

        let discovery = CodexRolloutDiscovery(
            rootURL: rootURL,
            fileManager: .default,
            maxAge: 86_400,
            maxFiles: 10
        )

        let records = discovery.discoverRecentSessions(now: now)

        #expect(records.count == 1)
        #expect(records.first?.sessionID == "codex-session-large")
        #expect(records.first?.summary == "Streamed the large rollout end-to-end.")
        #expect(records.first?.codexMetadata?.lastUserPrompt == "Inspect the large rollout.")
        #expect(records.first?.codexMetadata?.lastAssistantMessage == "Streamed the large rollout end-to-end.")
    }

}

private actor EventRecorder {
    private var events: [AgentEvent] = []

    func append(_ event: AgentEvent) {
        events.append(event)
    }

    func snapshot() -> [AgentEvent] {
        events
    }
}

private func appendRolloutLine(_ line: String, to fileURL: URL) throws {
    guard let data = "\(line)\n".data(using: .utf8) else {
        return
    }

    let handle = try FileHandle(forWritingTo: fileURL)
    defer {
        try? handle.close()
    }

    try handle.seekToEnd()
    try handle.write(contentsOf: data)
}

private func rolloutLine(
    timestamp: String,
    type: String,
    payload: [String: Any]
) -> String {
    let object: [String: Any] = [
        "timestamp": timestamp,
        "type": type,
        "payload": payload,
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func sessionMetaLine(
    sessionID: String,
    timestamp: String,
    cwd: String
) -> String {
    rolloutLine(
        timestamp: timestamp,
        type: "session_meta",
        payload: [
            "id": sessionID,
            "timestamp": timestamp,
            "cwd": cwd,
            "originator": "codex-tui",
            "source": "cli",
        ]
    )
}

private extension AgentEvent {
    var trackedActivityUpdate: SessionActivityUpdated? {
        if case let .activityUpdated(payload) = self {
            payload
        } else {
            nil
        }
    }

    var trackedSessionCompletion: SessionCompleted? {
        if case let .sessionCompleted(payload) = self {
            payload
        } else {
            nil
        }
    }

    var trackedMetadataUpdate: SessionMetadataUpdated? {
        if case let .sessionMetadataUpdated(payload) = self {
            payload
        } else {
            nil
        }
    }
}
