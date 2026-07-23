import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-239: menu-bar count / Dock badge / system-notification wiring.
///
/// Deliberately never sets `model.systemNotificationsEnabled = true` on a
/// real `AppModel` — doing so calls `UserNotificationService.requestAuthorizationIfNeeded()`,
/// which touches `UNUserNotificationCenter.current()`. That API requires a
/// proper app bundle and hard-crashes the bare `swift test` executable (verified
/// directly: it throws `NSInternalInconsistencyException` — "bundleProxyForCurrentProcess
/// is nil"). `SystemNotificationPolicyTests` covers the posting decision instead,
/// entirely without touching the real notification center.
@MainActor
@Suite(.serialized)
struct AppModelAttentionSurfacesTests {
    init() {
        [
            "app.menuBarAttentionEnabled",
            "app.systemNotificationsEnabled",
            "app.dockBadgeEnabled",
        ].forEach(UserDefaults.standard.removeObject(forKey:))
    }

    private func liveSession(
        id: String,
        title: String,
        tool: AgentTool,
        phase: SessionPhase,
        summary: String,
        updatedAt: Date
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: title,
            tool: tool,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: summary,
            updatedAt: updatedAt,
            permissionRequest: phase == .waitingForApproval
                ? PermissionRequest(title: "T", summary: "S", affectedPath: "/tmp")
                : nil
        )
        session.isProcessAlive = true
        return session
    }

    @Test
    func attentionSessionsIncludeOnlyPermissionAndQuestionPhases() {
        let model = AppModel()
        let now = Date.now

        let approval = liveSession(id: "approval", title: "Codex · a", tool: .codex, phase: .waitingForApproval, summary: "Approve", updatedAt: now)
        let question = liveSession(id: "question", title: "Claude · b", tool: .claudeCode, phase: .waitingForAnswer, summary: "Answer", updatedAt: now)
        let running = liveSession(id: "running", title: "Codex · c", tool: .codex, phase: .running, summary: "Working", updatedAt: now)
        let completed = liveSession(id: "completed", title: "Codex · d", tool: .codex, phase: .completed, summary: "Done", updatedAt: now)

        model.state = SessionState(sessions: [approval, question, running, completed])

        #expect(Set(model.attentionSessions.map(\.id)) == Set(["approval", "question"]))
        #expect(model.liveAttentionCount == 2)
    }

    @Test
    func attentionSessionsIsEmptyWithNoWaitingSessions() {
        let model = AppModel()
        let now = Date.now
        let running = liveSession(id: "running", title: "Codex · c", tool: .codex, phase: .running, summary: "Working", updatedAt: now)

        model.state = SessionState(sessions: [running])

        #expect(model.attentionSessions.isEmpty)
        #expect(model.liveAttentionCount == 0)
    }

    @Test
    func presentOverlayFocusedSelectsSessionAndOpensItsCard() {
        let model = AppModel()
        let now = Date.now
        let session = liveSession(id: "target", title: "Codex · target", tool: .codex, phase: .waitingForApproval, summary: "Approve", updatedAt: now)
        model.state = SessionState(sessions: [session])

        model.presentOverlayFocused(onSessionID: "target")

        #expect(model.selectedSessionID == "target")
        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .click)
        #expect(model.islandSurface == .sessionList(actionableSessionID: "target"))
    }

    @Test
    func presentOverlayFocusedIsNoOpForAnUnknownSessionID() {
        let model = AppModel()

        model.presentOverlayFocused(onSessionID: "does-not-exist")

        #expect(model.notchStatus == .closed)
        #expect(model.selectedSessionID == nil)
    }

    @Test
    func attentionPreferencesDefaultToOff() {
        let model = AppModel()
        #expect(!model.menuBarAttentionEnabled)
        #expect(!model.systemNotificationsEnabled)
        #expect(!model.dockBadgeEnabled)
    }

    @Test
    func menuBarAttentionPreferencePersistsAcrossModelInstances() {
        let model = AppModel()
        model.menuBarAttentionEnabled = true
        #expect(UserDefaults.standard.bool(forKey: "app.menuBarAttentionEnabled"))

        let reloaded = AppModel()
        #expect(reloaded.menuBarAttentionEnabled)
        // Cleanup: avoid leaking a live NSStatusItem into later tests in this process.
        reloaded.menuBarAttentionEnabled = false
        model.menuBarAttentionEnabled = false
    }

    @Test
    func dockBadgePreferencePersistsAcrossModelInstances() {
        let model = AppModel()
        model.dockBadgeEnabled = true
        #expect(UserDefaults.standard.bool(forKey: "app.dockBadgeEnabled"))

        let reloaded = AppModel()
        #expect(reloaded.dockBadgeEnabled)
    }
}
