import Foundation
import OpenIslandCore

@main
struct OpenIslandSetupCLI {
    static func main() {
        do {
            let command = try SetupCommand(arguments: Array(CommandLine.arguments.dropFirst()))
            if let status = try command.run() {
                writeStatus(status)
                exit(status.exitCode)
            }
        } catch let error as SetupError {
            if error == .consentRequired {
                let outcome = HookManagementOutcome.consentRequired
                writeStatus(outcome.status(for: .sharedHelper), to: stderr)
                exit(outcome.exitStatus)
            }
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        } catch {
            let outcome = HookManagementOutcome.from(error: error)
            writeStatus(outcome.status(for: .sharedHelper), to: stderr)
            exit(outcome.exitStatus)
        }
    }

    private static func writeStatus(_ status: HookManagementStatus, to stream: UnsafeMutablePointer<FILE> = stdout) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(status) else { return }
        data.withUnsafeBytes { bytes in
            _ = fwrite(bytes.baseAddress, 1, bytes.count, stream)
        }
        _ = fputc(10, stream)
    }
}

private struct SetupCommand {
    enum Action: String {
        case install
        case uninstall
        case status
        case installClaude
        case uninstallClaude
        case statusClaude
        case installKimi
        case uninstallKimi
        case statusKimi
    }

    let action: Action
    let codexDirectory: URL
    let claudeDirectory: URL
    let kimiDirectory: URL
    let hooksBinary: URL?
    let statusFamily: HookIntegrationFamily

    init(arguments: [String]) throws {
        guard let rawAction = arguments.first,
              let action = Action(rawValue: rawAction) else {
            throw SetupError.usage
        }

        self.action = action

        var hooksBinary: URL?
        var codexDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        var claudeDirectory = ClaudeConfigDirectory.resolved()
        var kimiDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi", isDirectory: true)
        var statusFamily: HookIntegrationFamily = switch action {
        case .statusClaude: .claude
        case .statusKimi: .kimi
        default: .codexCLI
        }

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--hooks-binary":
                index += 1
                guard index < arguments.count else {
                    throw SetupError.missingValue("--hooks-binary")
                }
                hooksBinary = URL(fileURLWithPath: arguments[index]).standardizedFileURL

            case "--codex-dir":
                index += 1
                guard index < arguments.count else {
                    throw SetupError.missingValue("--codex-dir")
                }
                codexDirectory = URL(fileURLWithPath: arguments[index]).standardizedFileURL

            case "--claude-dir":
                index += 1
                guard index < arguments.count else {
                    throw SetupError.missingValue("--claude-dir")
                }
                claudeDirectory = URL(fileURLWithPath: arguments[index]).standardizedFileURL

            case "--kimi-dir":
                index += 1
                guard index < arguments.count else {
                    throw SetupError.missingValue("--kimi-dir")
                }
                kimiDirectory = URL(fileURLWithPath: arguments[index]).standardizedFileURL

            case "--family":
                index += 1
                guard index < arguments.count, let family = HookIntegrationFamily(rawValue: arguments[index]) else {
                    throw SetupError.missingValue("--family <known family>")
                }
                statusFamily = family

            default:
                throw SetupError.unexpectedArgument(arguments[index])
            }

            index += 1
        }

        if (action == .install || action == .installClaude || action == .installKimi), hooksBinary == nil {
            hooksBinary = HooksBinaryLocator.locate()
        }

        self.codexDirectory = codexDirectory
        self.claudeDirectory = claudeDirectory
        self.kimiDirectory = kimiDirectory
        self.hooksBinary = hooksBinary
        self.statusFamily = statusFamily
    }

    func run() throws -> HookManagementStatus? {
        switch action {
        case .install:
            try install()
        case .uninstall:
            try uninstall()
        case .status:
            return try status(for: statusFamily)
        case .installClaude:
            try installClaude()
        case .uninstallClaude:
            try uninstallClaude()
        case .statusClaude:
            return try statusClaude()
        case .installKimi:
            try installKimi()
        case .uninstallKimi:
            try uninstallKimi()
        case .statusKimi:
            return try statusKimi()
        }
        return nil
    }

    private func install() throws {
        throw SetupError.consentRequired
    }

    private func uninstall() throws {
        throw SetupError.consentRequired
    }

    private func status() throws -> HookManagementStatus {
        try status(for: .codexCLI)
    }

    /// This is intentionally a read-only dispatch. Each branch delegates to
    /// the same manager that Settings uses; none may create a helper, sidecar,
    /// backup, journal, or recovery state.
    private func status(for family: HookIntegrationFamily) throws -> HookManagementStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let outcome: HookManagementOutcome = switch family {
        case .claude:
            try ClaudeHookInstallationManager(claudeDirectory: claudeDirectory).status(hooksBinaryURL: hooksBinary).managementOutcome
        case .qoder:
            try ClaudeHookInstallationManager(claudeDirectory: home.appendingPathComponent(".qoder"), hookSource: "qoder").status(hooksBinaryURL: hooksBinary).managementOutcome
        case .qwenCode:
            try ClaudeHookInstallationManager(claudeDirectory: home.appendingPathComponent(".qwen"), hookSource: "qwen").status(hooksBinaryURL: hooksBinary).managementOutcome
        case .factoryDroid:
            try ClaudeHookInstallationManager(claudeDirectory: home.appendingPathComponent(".factory"), hookSource: "factory").status(hooksBinaryURL: hooksBinary).managementOutcome
        case .codebuddy:
            try ClaudeHookInstallationManager(claudeDirectory: home.appendingPathComponent(".codebuddy"), hookSource: "codebuddy").status(hooksBinaryURL: hooksBinary).managementOutcome
        case .codexCLI:
            try CodexHookInstallationManager(codexDirectory: codexDirectory).status(hooksBinaryURL: hooksBinary).managementOutcome
        case .cursor:
            try CursorHookInstallationManager().status(hooksBinaryURL: hooksBinary).managementOutcome
        case .gemini:
            try GeminiHookInstallationManager().status(hooksBinaryURL: hooksBinary).managementOutcome
        case .kimi:
            try KimiHookInstallationManager(kimiDirectory: kimiDirectory).status(hooksBinaryURL: hooksBinary).managementOutcome
        case .openCodeConfig, .openCodePlugin:
            try OpenCodePluginInstallationManager().status().managementOutcome
        case .claudeStatusLine:
            try ClaudeStatusLineInstallationManager(claudeDirectory: claudeDirectory).status().managementOutcome
        case .sharedHelper:
            ManagedHooksBinary.managementOutcome(at: hooksBinary ?? ManagedHooksBinary.defaultURL())
        }
        return outcome.status(for: family)
    }

    private func installClaude() throws {
        throw SetupError.consentRequired
    }

    private func uninstallClaude() throws {
        throw SetupError.consentRequired
    }

    private func statusClaude() throws -> HookManagementStatus {
        try status(for: .claude)
    }

    private func installKimi() throws {
        throw SetupError.consentRequired
    }

    private func uninstallKimi() throws {
        throw SetupError.consentRequired
    }

    private func statusKimi() throws -> HookManagementStatus {
        try status(for: .kimi)
    }
}

private enum SetupError: Error, LocalizedError, Equatable {
    case usage
    case consentRequired
    case missingValue(String)
    case unexpectedArgument(String)

    var errorDescription: String? {
        switch self {
        case .consentRequired:
            "OpenIslandSetup does not mutate hook configuration noninteractively."
        case .usage:
            """
            Usage:
              swift run OpenIslandSetup install [--hooks-binary /abs/path/to/OpenIslandHooks] [--codex-dir /abs/path/to/.codex]
              swift run OpenIslandSetup uninstall [--codex-dir /abs/path/to/.codex]
              swift run OpenIslandSetup status [--family codex-cli] [--hooks-binary /abs/path/to/OpenIslandHooks] [--codex-dir /abs/path/to/.codex]
              swift run OpenIslandSetup installClaude [--hooks-binary /abs/path/to/OpenIslandHooks] [--claude-dir /abs/path/to/.claude]
              swift run OpenIslandSetup uninstallClaude [--claude-dir /abs/path/to/.claude]
              swift run OpenIslandSetup statusClaude [--hooks-binary /abs/path/to/OpenIslandHooks] [--claude-dir /abs/path/to/.claude]
              swift run OpenIslandSetup installKimi [--hooks-binary /abs/path/to/OpenIslandHooks] [--kimi-dir /abs/path/to/.kimi]
              swift run OpenIslandSetup uninstallKimi [--kimi-dir /abs/path/to/.kimi]
              swift run OpenIslandSetup statusKimi [--hooks-binary /abs/path/to/OpenIslandHooks] [--kimi-dir /abs/path/to/.kimi]
            """
        case let .missingValue(flag):
            "Missing value for \(flag)"
        case let .unexpectedArgument(argument):
            "Unexpected argument: \(argument)"
        }
    }
}
