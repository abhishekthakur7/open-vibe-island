import Foundation
import OpenIslandCore

/// Local jump is intentionally a focus-only capability.  Hook payloads may
/// describe a terminal, but they cannot cause command entry, shell execution,
/// deep-link opening, directory opening, multiplexer control, or arbitrary
/// application activation.
struct TerminalJumpService {
    typealias AutomationRunner = @Sendable (LocalAppleScriptTemplate, [String]) throws -> String
    typealias ActivationRunner = @Sendable (String) throws -> Void

    private let automationRunner: AutomationRunner
    private let activationRunner: ActivationRunner

    init(
        automationRunner: @escaping AutomationRunner = Self.runAppleScript,
        activationRunner: @escaping ActivationRunner = Self.activate
    ) {
        self.automationRunner = automationRunner
        self.activationRunner = activationRunner
    }

    func jump(to target: JumpTarget) throws -> String {
        let terminal = try terminal(for: target.terminalApp)
        switch terminal {
        case let .ghostty(bundleIdentifier):
            if let identifier = validatedSurfaceIdentifier(target.terminalSessionID),
               try automationRunner(.ghosttyFocus, [identifier]) == "matched" {
                return "Focused the matching Ghostty terminal."
            }
            try activationRunner(bundleIdentifier)
            return "Activated Ghostty."
        case let .terminal(bundleIdentifier):
            if let tty = validatedTTY(target.terminalTTY),
               try automationRunner(.terminalFocus, [tty]) == "matched" {
                return "Focused the matching Terminal tab."
            }
            try activationRunner(bundleIdentifier)
            return "Activated Terminal."
        case let .iTerm(bundleIdentifier):
            if let identifier = validatedSurfaceIdentifier(target.terminalSessionID) ?? validatedTTY(target.terminalTTY),
               try automationRunner(.iTermFocus, [identifier]) == "matched" {
                return "Focused the matching iTerm session."
            }
            try activationRunner(bundleIdentifier)
            return "Activated iTerm."
        case let .warp(bundleIdentifier):
            try activationRunner(bundleIdentifier)
            return "Activated Warp. Precise pane selection is unavailable in local-only mode."
        }
    }

    private enum SupportedTerminal {
        case ghostty(String)
        case terminal(String)
        case iTerm(String)
        case warp(String)
    }

    private func terminal(for value: String) throws -> SupportedTerminal {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ghostty": .ghostty("com.mitchellh.ghostty")
        case "terminal", "apple_terminal": .terminal("com.apple.Terminal")
        case "iterm", "iterm2": .iTerm("com.googlecode.iterm2")
        case "warp", "warpterminal": .warp("dev.warp.Warp-Stable")
        default: throw TerminalJumpError.unsupportedTerminal(value)
        }
    }

    private func validatedSurfaceIdentifier(_ value: String?) -> String? {
        guard let value, isSafeSurfaceValue(value) else { return nil }
        return value
    }

    private func validatedTTY(_ value: String?) -> String? {
        guard let value, value.hasPrefix("/dev/tty"), isSafeSurfaceValue(value) else { return nil }
        return value
    }

    private func isSafeSurfaceValue(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 256, !value.hasPrefix("-") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/-"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func runAppleScript(_ template: LocalAppleScriptTemplate, _ parameters: [String]) throws -> String {
        let result = try LocalProcessRunner.shared.runAppleScript(template, parameters: parameters, timeout: 1)
        return String(data: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func activate(_ bundleIdentifier: String) throws {
        _ = try LocalProcessRunner.shared.activateTerminal(bundleIdentifier)
    }
}

enum TerminalJumpError: Error, LocalizedError {
    case unsupportedTerminal(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedTerminal(name):
            "Unsupported local terminal: \(name)"
        }
    }
}
