import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct AgentsGridRightSlotTests {
    /// Per-session state derives from `SessionPhase`: waiting-for-approval /
    /// waiting-for-answer map to `.waiting`, running to `.running`, and
    /// everything else (completed, stale) to `.idle`.
    @Test
    func cellStateReflectsSessionPhase() {
        let model = AppModel()
        pinAgentsGridPreference(on: model)
        let now = Date(timeIntervalSince1970: 300_000)

        let running  = makeSession(id: "r", firstSeenAt: now,                         updatedAt: now, phase: .running)
        let waitingA = makeSession(
            id: "w",
            firstSeenAt: now.addingTimeInterval(1),
            updatedAt: now,
            phase: .waitingForApproval,
            permissionRequest: PermissionRequest(title: "edit", summary: "edit", affectedPath: "/tmp/x")
        )
        let completed = makeSession(id: "c", firstSeenAt: now.addingTimeInterval(2), updatedAt: now, phase: .completed)

        model.state = SessionState(sessions: [running, waitingA, completed])

        // AB-322: a waiting session now outranks the resting preference in
        // `islandClosedRightSlotContent()` (it returns `.attentionCount`), so
        // the grid's own phase→cell mapping is exercised through the preference
        // derivation. The mapping under test is unchanged.
        guard case let .agents(cells)? = model.islandPreferredRightSlotContent() else {
            Issue.record("Expected .agents right-slot content")
            return
        }
        #expect(cells.count == 3)

        guard cells.count == 3,
              case let .session(_, s0) = cells[0],
              case let .session(_, s1) = cells[1],
              case let .session(_, s2) = cells[2]
        else {
            Issue.record("Expected three session cells")
            return
        }
        #expect(s0 == .running)
        #expect(s1 == .waiting)
        #expect(s2 == .idle)
    }

    // MARK: - helpers

    /// Pin the agents-grid preference on *both* display profiles.
    ///
    /// `AppModel.islandRightSlot` reads and writes whichever profile
    /// `activeAppearanceProfile` resolves to, and that resolves from
    /// `overlayPlacementDiagnostics` — which the overlay fills in
    /// asynchronously. Assigning `islandRightSlot` once therefore lands in
    /// whichever bucket happened to be active at that instant, and a placement
    /// arriving mid-test flipped the getter to the other bucket's default
    /// `.count`. That race is why these tests failed in rotation; writing both
    /// buckets makes the preference profile-independent (AB-322).
    private func pinAgentsGridPreference(on model: AppModel) {
        model.updateAppearancePreferences(for: .notch) { $0.rightSlot = .agents }
        model.updateAppearancePreferences(for: .topBar) { $0.rightSlot = .agents }
    }

    private func makeSession(
        id: String,
        firstSeenAt: Date,
        updatedAt: Date,
        phase: SessionPhase = .running,
        permissionRequest: PermissionRequest? = nil
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · \(id)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "",
            updatedAt: updatedAt,
            firstSeenAt: firstSeenAt,
            permissionRequest: permissionRequest,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: id,
                paneTitle: "claude ~/\(id)",
                workingDirectory: "/tmp/\(id)",
                terminalSessionID: "ghostty-\(id)"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/\(id).jsonl",
                currentTool: "Task"
            )
        )
        session.isProcessAlive = true
        session.isHookManaged = true
        return session
    }
}
