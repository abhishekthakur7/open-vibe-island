import Foundation
import OpenIslandCore

/// Reply injection was an arbitrary terminal-command/AppleScript surface.
/// Local-only mode intentionally does not send text to another application.
/// Focusing a known local surface remains available through TerminalJumpService.
struct TerminalTextSender {
    static func canReply(to session: AgentSession, enabled: Bool) -> Bool { false }

    @discardableResult
    static func send(_ text: String, to session: AgentSession) -> Bool {
        false
    }
}
