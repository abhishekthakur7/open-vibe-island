import AppKit
import Foundation
import OpenIslandCore

struct ForegroundTerminalSessionProbe {
    typealias FrontmostBundleIdentifierProvider = @Sendable () -> String?
    typealias AppleScriptRunner = @Sendable (LocalAppleScriptTemplate, [String]) async throws -> String

    private static let fieldSeparator = "\u{1f}"
    private static let appleScriptTimeout: DispatchTimeInterval = .seconds(1)

    private final class ContinuationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var hasResumed = false

        func resumeOnce(_ action: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !hasResumed else {
                return
            }

            hasResumed = true
            action()
        }
    }

    private final class PipeBox: @unchecked Sendable {
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        func outputString() -> String {
            String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        func errorString() -> String {
            String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        func closePipes() {
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }
    }

    private let frontmostBundleIdentifierProvider: FrontmostBundleIdentifierProvider
    private let appleScriptRunner: AppleScriptRunner

    /// Returns `true` when the provided session already owns the focused
    /// surface of the current frontmost terminal app.
    init(
        frontmostBundleIdentifierProvider: @escaping FrontmostBundleIdentifierProvider = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        appleScriptRunner: @escaping AppleScriptRunner = Self.runAppleScript
    ) {
        self.frontmostBundleIdentifierProvider = frontmostBundleIdentifierProvider
        self.appleScriptRunner = appleScriptRunner
    }

    func matches(session: AgentSession) async -> Bool {
        await matches(jumpTarget: session.jumpTarget)
    }

    func matches(jumpTarget: JumpTarget?) async -> Bool {
        guard let jumpTarget,
              let frontmostBundleIdentifier = frontmostBundleIdentifierProvider() else {
            return false
        }

        switch frontmostBundleIdentifier {
        case "com.mitchellh.ghostty":
            guard let focusedTerminalID = await ghosttyFocusedTerminalID(),
                  let sessionTerminalID = nonEmptyValue(jumpTarget.terminalSessionID) else {
                return false
            }
            return focusedTerminalID == sessionTerminalID

        case "com.apple.Terminal":
            guard let focusedTTY = normalizedTTY(await terminalFocusedTTY()),
                  let sessionTTY = normalizedTTY(jumpTarget.terminalTTY) else {
                return false
            }
            return focusedTTY == sessionTTY

        case "com.googlecode.iterm2":
            let focusedSession = await itermFocusedSession()

            if let focusedSessionID = focusedSession?.sessionID,
               let sessionTerminalID = nonEmptyValue(jumpTarget.terminalSessionID),
               focusedSessionID == sessionTerminalID {
                return true
            }

            if let focusedTTY = normalizedTTY(focusedSession?.tty),
               let sessionTTY = normalizedTTY(jumpTarget.terminalTTY),
               focusedTTY == sessionTTY {
                return true
            }

            return false

        default:
            return false
        }
    }

    private func ghosttyFocusedTerminalID() async -> String? {
        return nonEmptyValue(try? await appleScriptRunner(.ghosttyFocusedTerminalProbe, []))
    }

    private func terminalFocusedTTY() async -> String? {
        return nonEmptyValue(try? await appleScriptRunner(.terminalFocusedTTYProbe, []))
    }

    private func itermFocusedSession() async -> (sessionID: String?, tty: String?)? {
        guard let output = nonEmptyValue(try? await appleScriptRunner(.iTermFocusedSessionProbe, [])) else {
            return nil
        }

        let values = output.components(separatedBy: Self.fieldSeparator)
        if values.isEmpty {
            return nil
        }

        return (
            sessionID: values.indices.contains(0) ? nonEmptyValue(values[0]) : nil,
            tty: values.indices.contains(1) ? nonEmptyValue(values[1]) : nil
        )
    }

    private func nonEmptyValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func normalizedTTY(_ value: String?) -> String? {
        guard let trimmed = nonEmptyValue(value) else {
            return nil
        }

        return trimmed.hasPrefix("/dev/") ? trimmed : "/dev/\(trimmed)"
    }

    private static func runAppleScript(_ template: LocalAppleScriptTemplate, _ parameters: [String]) async throws -> String {
        let result = try await Task.detached(priority: .utility) {
            try LocalProcessRunner.shared.runAppleScript(template, parameters: parameters, timeout: 1)
        }.value
        return String(data: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
