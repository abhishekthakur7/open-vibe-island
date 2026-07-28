import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// F20 clobber fix (overlay remediation Phase 3C): `SessionDiscoveryCoordinator
/// .mergeCodexMetadata` (private, exercised here through the internal
/// `mergeDiscoveredSessions(_:)`) has the same field-omission shape as the
/// rollout-watcher clobber covered by `CodexSessionTrackingTests` — it never
/// mentioned `model` at all, so the memberwise initializer silently defaulted
/// it to `nil` on every discovery/rediscovery merge
/// (`applyStartupDiscoveryPayload`, `applyCodexAppRediscovery`). Lower
/// frequency than the ~3s rollout poll (startup, or the 10s Codex.app
/// rediscovery throttle), but the same class of bug, in the same file.
@MainActor
struct SessionDiscoveryCoordinatorTests {
    @Test
    func mergeDiscoveredCodexSessionsPreservesModelFromExistingMetadata() {
        let coordinator = SessionDiscoveryCoordinator()
        let state = SessionState(sessions: [
            AgentSession(
                id: "codex-session-1",
                title: "Codex · open-island",
                tool: .codex,
                origin: .live,
                attachmentState: .attached,
                phase: .running,
                summary: "Thinking",
                updatedAt: .now,
                codexMetadata: CodexSessionMetadata(
                    transcriptPath: "/tmp/rollout.jsonl",
                    model: "gpt-5-codex"
                )
            ),
        ])
        coordinator.stateAccessor = { state }

        // A "discovered" session re-scanned from disk (startup, or periodic
        // Codex.app rediscovery) never carries a model today — neither
        // `CodexRolloutDiscovery.discoverRecord` nor
        // `CodexAppServerCoordinator.emitSessionStarted` populate one — but
        // does carry fresher activity metadata that should still win.
        let discovered = AgentSession(
            id: "codex-session-1",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .stale,
            phase: .running,
            summary: "Running command.",
            updatedAt: .now.addingTimeInterval(5),
            codexMetadata: CodexSessionMetadata(
                transcriptPath: "/tmp/rollout.jsonl",
                currentTool: "exec_command"
            )
        )

        let merged = coordinator.mergeDiscoveredSessions([discovered])
        let mergedMetadata = merged.first(where: { $0.id == "codex-session-1" })?.codexMetadata

        // The fix: model survives the merge instead of being dropped to nil.
        #expect(mergedMetadata?.model == "gpt-5-codex")
        // Pre-existing, unchanged behavior: the discovered session's fresher
        // activity still wins — confirms the fix is additive, not a
        // regression of the merge's existing field policy.
        #expect(mergedMetadata?.currentTool == "exec_command")
    }
}
