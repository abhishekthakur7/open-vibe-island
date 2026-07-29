import Foundation

/// The runtime surface that owns a hook target.  This deliberately keeps
/// Claude-family variants distinct even though they share an implementation.
public enum HookIntegrationFamily: String, CaseIterable, Codable, Sendable {
    case claude
    case qoder
    case qwenCode = "qwen-code"
    case factoryDroid = "factory-droid"
    case codebuddy
    case codexCLI = "codex-cli"
    case cursor
    case gemini
    case kimi
    case openCodeConfig = "opencode-config"
    case openCodePlugin = "opencode-plugin"
    case claudeStatusLine = "claude-status-line"
    case sharedHelper = "shared-helper"
}

/// The lossless status contract shared by managers, health, Settings, and the
/// noninteractive setup CLI.  Its fields are intentionally stable for scripts
/// and should not be reconstructed from display text.
public struct HookManagementStatus: Codable, Equatable, Sendable {
    public let family: HookIntegrationFamily
    public let outcomeCode: String
    public let exitCode: Int32
    public let remediation: String

    public init(family: HookIntegrationFamily, outcome: HookManagementOutcome) {
        self.family = family
        self.outcomeCode = outcome.rawValue
        self.exitCode = outcome.exitStatus
        self.remediation = outcome.remediation
    }
}

/// Stable result vocabulary shared by Settings and `OpenIslandSetup`.  A
/// caller must never infer ownership from a generic filesystem error.
public enum HookManagementOutcome: String, CaseIterable, Sendable, Equatable {
    /// Status-only outcome: every managed target and its provenance agree.
    case exactManaged
    /// Status-only outcome: no Open Island ownership evidence was found.
    case unowned
    case success
    case noChange
    case consentRequired
    case unsafePath
    case unverifiedArtifact
    case ambiguousUnmanaged
    case unresolvedRecovery
    /// A filesystem read or inspection failed. No ownership decision can be
    /// inferred and status leaves every target and recovery artifact intact.
    case ioFailure

    /// Stable noninteractive process statuses.  `0` is reserved for a
    /// completed request (including idempotence); the remaining values are
    /// intentionally small and documented for scripts.
    public var exitStatus: Int32 {
        switch self {
        case .success, .noChange, .exactManaged, .unowned: return 0
        case .consentRequired: return 20
        case .unsafePath: return 21
        case .unverifiedArtifact: return 22
        case .ambiguousUnmanaged: return 23
        case .unresolvedRecovery: return 24
        case .ioFailure: return 25
        }
    }

    public var remediation: String {
        switch self {
        case .success, .noChange, .exactManaged, .unowned:
            return "No remediation is required."
        case .consentRequired:
            return "Review the target, source version, digest, permissions, and managed changes in Settings, then explicitly confirm installation."
        case .unsafePath:
            return "Repair the target path so every component is a current-user or root-owned non-symlink directory that is not group- or world-writable, then retry."
        case .unverifiedArtifact:
            return "Refresh Open Island Dev with zsh scripts/launch-dev-app.sh and retry using the bundled, manifest-verified artifact."
        case .ambiguousUnmanaged:
            return "Open Island left the existing content untouched. Inspect or remove the ambiguous managed-looking entries and retry; do not rely on automatic cleanup."
        case .unresolvedRecovery:
            return "Open Island left the target and recovery files untouched. Inspect the journal and verified backup, resolve them manually, then retry."
        case .ioFailure:
            return "Open Island could not read the target safely. Check local filesystem availability and permissions, then retry; no target, backup, journal, provenance record, or helper was changed."
        }
    }

    /// Stable UI/CLI wording keeps an unsafe or unresolved state distinct from
    /// an ordinary installation failure.
    public func displayMessage(operation: String) -> String {
        "\(operation) [\(rawValue)]: \(remediation)"
    }

    public func status(for family: HookIntegrationFamily) -> HookManagementStatus {
        HookManagementStatus(family: family, outcome: self)
    }

    public static func from(error: Error) -> HookManagementOutcome {
        if error is BundledHookArtifactError { return .unverifiedArtifact }
        if let error = error as? ClaudeStatusLineInstallationError, case .unverifiedTemplate = error { return .unverifiedArtifact }
        if error is CodexHookInstallerError || error is ClaudeHookInstallerError || error is CursorHookInstallerError || error is GeminiHookInstallerError { return .ambiguousUnmanaged }
        if let error = error as? ManagedHookFileSystemError {
            switch error {
            case .unsafePath: return .unsafePath
            case .digestMismatch: return .unverifiedArtifact
            case .ambiguous: return .ambiguousUnmanaged
            case .io: return .ioFailure
            case .recoveryRequired: return .unresolvedRecovery
            }
        }
        if error is ManagedHookBackupError { return .unresolvedRecovery }
        return .unresolvedRecovery
    }
}
