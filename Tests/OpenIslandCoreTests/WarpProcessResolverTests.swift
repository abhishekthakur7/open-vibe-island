import Foundation
import Testing
@testable import OpenIslandCore

struct WarpProcessResolverTests {
    @Test
    func resolveReturnsShellAndServerWhenParentChainReachesTerminalServer() {
        // Simulates the real chain: hook CLI (1000) → claude (900) →
        // zsh (500) → Warp terminal-server (200).
        // The walker climbs from its `startingFrom` argument, so we
        // start at 900 (mimicking what getppid() would return if the
        // hook CLI's own pid were 1000). The expected shellPID is the
        // LAST pid whose parent IS terminal-server — that's 500.
        let parents: [pid_t: pid_t] = [
            900: 500,
            500: 200,
            200: 1,
        ]
        let commands: [pid_t: String] = [
            900: "claude --dangerously-skip-permissions",
            500: "-zsh",
            200: "/Applications/Warp.app/Contents/MacOS/stable terminal-server --parent-pid=199",
            1: "launchd",
        ]

        let ctx = WarpProcessResolver.resolvePaneContext(
            startingFrom: 900,
            parentPIDProvider: { parents[$0] },
            commandProvider: { commands[$0] }
        )

        #expect(ctx == WarpProcessResolver.PaneContext(shellPID: 500, terminalServerPID: 200))
    }

    @Test
    func resolveReturnsNilWhenRunningOutsideWarp() {
        // Simulates a Ghostty-hosted claude: parent chain never reaches
        // a Warp terminal-server, just terminates at launchd.
        let parents: [pid_t: pid_t] = [
            900: 500,
            500: 150,
            150: 1,
        ]
        let commands: [pid_t: String] = [
            900: "claude --dangerously-skip-permissions",
            500: "-zsh",
            150: "/Applications/Ghostty.app/Contents/MacOS/ghostty",
            1: "launchd",
        ]

        let ctx = WarpProcessResolver.resolvePaneContext(
            startingFrom: 900,
            parentPIDProvider: { parents[$0] },
            commandProvider: { commands[$0] }
        )

        #expect(ctx == nil)
    }

    @Test
    func isWarpTerminalServerRejectsMainWarpProcess() {
        // Warp's main GUI process runs the same binary but without the
        // `terminal-server` subcommand. The walker must not treat it as
        // the pane-spawning terminal-server, otherwise the shellPID
        // would point one level too high in the tree.
        #expect(!WarpProcessResolver.isWarpTerminalServer(
            command: "/Applications/Warp.app/Contents/MacOS/stable"
        ))
    }

}
