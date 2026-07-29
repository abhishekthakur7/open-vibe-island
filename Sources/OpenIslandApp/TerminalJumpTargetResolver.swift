import Foundation
import OpenIslandCore

/// Precision metadata is now supplied by the signed local bridge helper.
/// The former resolver discovered terminal CLIs through PATH and sent dynamic
/// tmux/WezTerm commands; local-only mode deliberately does neither.
struct TerminalJumpTargetResolver {
    typealias ActiveProcessSnapshot = ActiveAgentProcessDiscovery.ProcessSnapshot

    func resolveJumpTargets(
        for sessions: [AgentSession],
        activeProcesses: [ActiveProcessSnapshot]
    ) -> [String: JumpTarget] {
        [:]
    }
}
