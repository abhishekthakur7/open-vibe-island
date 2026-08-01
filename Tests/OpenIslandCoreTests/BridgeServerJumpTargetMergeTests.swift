import Foundation
import Testing
@testable import OpenIslandCore

/// Pins `BridgeServer.mergeJumpTargetPreservingExistingResolvedFields`
/// behavior on two "resolved" fields — `terminalSessionID` and
/// `warpPaneUUID`. Both fields are determined at hook time by
/// potentially-flaky runtime probes (AppleScript locators, SQLite
/// reads, process-tree walks), so when a later hook fails to re-resolve
/// them the merged jumpTarget must carry forward the previous value
/// instead of clearing it.
struct BridgeServerJumpTargetMergeTests {
    @Test
    func preservesWarpPaneUUIDWhenIncomingIsNilAndExistingHasValue() {
        // Regression for PR #266 Codex review [P2]:
        // When `warpPaneResolver` returns nil during a transient
        // state (pgrep race, SQLite lock, Warp startup), the incoming
        // jumpTarget has `warpPaneUUID = nil`. Without preservation
        // the session's good uuid would be overwritten, permanently
        // demoting precision jump to bare activation for the rest
        // of the session.
        let existing = JumpTarget(
            terminalApp: "Warp",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/tmp/demo",
            warpPaneUUID: "D1A5DF3027E44FC080FE2656FAF2BA2E"
        )
        let incoming = JumpTarget(
            terminalApp: "Warp",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/tmp/demo",
            warpPaneUUID: nil
        )

        let merged = BridgeServer.mergeJumpTargetPreservingExistingResolvedFields(
            incoming: incoming,
            existing: existing
        )

        #expect(merged.warpPaneUUID == "D1A5DF3027E44FC080FE2656FAF2BA2E")
    }

    @Test
    func overwritesWarpPaneUUIDWhenIncomingHasValue() {
        // When the incoming hook successfully re-resolves the uuid,
        // it MUST win — the shell or pane may have moved since the
        // last hook. Only nil-valued incoming fields are preserved.
        let existing = JumpTarget(
            terminalApp: "Warp",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/tmp/demo",
            warpPaneUUID: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        )
        let incoming = JumpTarget(
            terminalApp: "Warp",
            workspaceName: "demo",
            paneTitle: "Claude demo",
            workingDirectory: "/tmp/demo",
            warpPaneUUID: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
        )

        let merged = BridgeServer.mergeJumpTargetPreservingExistingResolvedFields(
            incoming: incoming,
            existing: existing
        )

        #expect(merged.warpPaneUUID == "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB")
    }
}
