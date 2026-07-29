import Foundation

public struct ClaudeStatusLineInstallationStatus: Equatable, Sendable {
    public var claudeDirectory: URL
    public var settingsURL: URL
    public var scriptDirectoryURL: URL
    public var scriptURL: URL
    public var cacheURL: URL
    public var statusLineCommand: String?
    public var hasStatusLine: Bool
    public var managedStatusLineConfigured: Bool
    public var managedStatusLineInstalled: Bool
    public var managedStatusLineNeedsRepair: Bool
    public var hasConflictingStatusLine: Bool
    public var managedStatusLineIsWrapper: Bool
    /// Read-only ownership classification. Marker text and a canonical command
    /// path are intentionally not sufficient to produce `.exactManaged`.
    public var managementOutcome: HookManagementOutcome

    public init(claudeDirectory: URL, settingsURL: URL, scriptDirectoryURL: URL, scriptURL: URL, cacheURL: URL, statusLineCommand: String?, hasStatusLine: Bool, managedStatusLineConfigured: Bool, managedStatusLineInstalled: Bool, managedStatusLineNeedsRepair: Bool, hasConflictingStatusLine: Bool, managedStatusLineIsWrapper: Bool = false, managementOutcome: HookManagementOutcome = .unowned) {
        self.claudeDirectory = claudeDirectory; self.settingsURL = settingsURL
        self.scriptDirectoryURL = scriptDirectoryURL; self.scriptURL = scriptURL; self.cacheURL = cacheURL
        self.statusLineCommand = statusLineCommand; self.hasStatusLine = hasStatusLine
        self.managedStatusLineConfigured = managedStatusLineConfigured
        self.managedStatusLineInstalled = managedStatusLineInstalled
        self.managedStatusLineNeedsRepair = managedStatusLineNeedsRepair
        self.hasConflictingStatusLine = hasConflictingStatusLine
        self.managedStatusLineIsWrapper = managedStatusLineIsWrapper
        self.managementOutcome = managementOutcome
    }
}

public enum ClaudeStatusLineInstallationError: LocalizedError, Sendable {
    case existingStatusLineConflict(command: String?)
    case invalidSettingsRoot
    case wrappableCommandMissing
    case unverifiedTemplate

    public var errorDescription: String? {
        switch self {
        case let .existingStatusLineConflict(command):
            return command.flatMap { $0.isEmpty ? nil : "Claude Code already has a custom status line: \($0)" } ?? "Claude Code already has a custom status line."
        case .invalidSettingsRoot: return "Claude Code settings.json must contain a top-level object."
        case .wrappableCommandMissing: return "No existing statusLine command was found to wrap."
        case .unverifiedTemplate: return "Open Island will not install an unverified Claude status-line template. Refresh Open Island Dev and retry."
        }
    }
}

public let openIslandOriginalStatusLineKey = "_openIslandOriginalStatusLine"

/// The only template authority accepted by the status-line installer. Production
/// resolves these paths from the signed app bundle; tests may inject resources
/// that have already passed the same manifest verification.
public struct ClaudeStatusLineTemplateResources: Sendable, Equatable {
    public let normal: VerifiedBundledResource
    public let wrapper: VerifiedBundledResource
    public let delegate: VerifiedBundledResource

    public init(normal: VerifiedBundledResource, wrapper: VerifiedBundledResource, delegate: VerifiedBundledResource) {
        self.normal = normal
        self.wrapper = wrapper
        self.delegate = delegate
    }
}

/// Installs the Claude usage bridge only when every byte that it owns can be
/// proven by an adjacent 0600 provenance record.  It deliberately does not
/// migrate the old Vibe Island path: a copied marker or a stale command must be
/// reviewed by the user, not silently rewritten.
public final class ClaudeStatusLineInstallationManager: @unchecked Sendable {
    public static let managerID = "claude-status-line"
    public static let managedScriptName = "open-island-statusline"
    public static let wrappedDelegateScriptName = "open-island-statusline-delegate"
    public static let legacyManagedScriptName = "vibe-island-statusline"
    public static let managedCacheURL = ClaudeUsageLoader.defaultCacheURL
    public static let managedTemplateMarker = "Open Island status-line template"
    public static let managedTemplateVersion = "1"

    public let claudeDirectory: URL
    public let scriptDirectoryURL: URL
    public let legacyScriptDirectoryURL: URL
    private let fileManager: FileManager
    private let templateResources: ClaudeStatusLineTemplateResources?

    public init(claudeDirectory: URL = ClaudeConfigDirectory.resolved(), scriptDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".open-island", isDirectory: true).appendingPathComponent("bin", isDirectory: true), legacyScriptDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vibe-island", isDirectory: true).appendingPathComponent("bin", isDirectory: true), templateResources: ClaudeStatusLineTemplateResources? = nil, fileManager: FileManager = .default) {
        self.claudeDirectory = claudeDirectory
        self.scriptDirectoryURL = scriptDirectoryURL
        self.legacyScriptDirectoryURL = legacyScriptDirectoryURL
        self.templateResources = templateResources
        self.fileManager = fileManager
    }

    /// Returns a descriptor only after the exact built-in template bytes have
    /// been checked.  It gives Settings a source identity for consent without
    /// making templates public mutation authority.
    public func verifiedTemplateDescriptor(wrapping: Bool) throws -> VerifiedHookTemplateDescriptor {
        let templates = try verifiedTemplates()
        return VerifiedHookTemplateDescriptor(entry: (wrapping ? templates.wrapper : templates.normal).entry)
    }

    /// This method never repairs journals, prunes backups, creates a directory,
    /// or writes a sidecar. It is safe for UI refresh and polling.
    public func status() throws -> ClaudeStatusLineInstallationStatus {
        let urls = targetURLs
        try preflightRead(urls)
        let settings = try loadSettings(at: urls.settings)
        let statusLine = settings["statusLine"] as? [String: Any]
        let command = statusLine?["command"] as? String
        let expectedCommand = command == urls.script.path
        let wrapper = settings[openIslandOriginalStatusLineKey] as? [String: Any]
        let hasJournal = try journalExists(for: urls)
        // A settings file by itself is ordinary Claude state. It becomes
        // ownership evidence only when it points at one of our canonical paths
        // or has a provenance sibling; otherwise an explicit wrapper remains
        // available for a user's custom command.
        let evidence = try ownershipEvidenceExists(for: urls, command: command) || command == urls.legacyScript.path

        var outcome: HookManagementOutcome = .unowned
        var exact = false
        if hasJournal {
            outcome = .unresolvedRecovery
        } else if evidence {
            do {
                if expectedCommand, let statusLine, let exactWrapper = try exactInstallation(settings: settings, statusLine: statusLine, wrapper: wrapper, urls: urls) {
                    exact = true
                    outcome = .exactManaged
                    // A normal installation must not leave a delegate behind.
                    let hasDelegate = try pathExists(urls.delegate)
                    let hasDelegateSidecar = try pathExists(sidecar(for: urls.delegate))
                    let hasDelegateEvidence = hasDelegate || hasDelegateSidecar
                    if !exactWrapper && hasDelegateEvidence {
                        exact = false; outcome = .ambiguousUnmanaged
                    }
                } else {
                    outcome = .ambiguousUnmanaged
                }
            } catch {
                // Evidence that is malformed, stale, copied, or changed while
                // being inspected is still useful status information, but it
                // never becomes permission to mutate it.
                outcome = .ambiguousUnmanaged
            }
        }

        return ClaudeStatusLineInstallationStatus(
            claudeDirectory: claudeDirectory, settingsURL: urls.settings, scriptDirectoryURL: scriptDirectoryURL,
            scriptURL: urls.script, cacheURL: Self.managedCacheURL, statusLineCommand: command,
            hasStatusLine: statusLine != nil, managedStatusLineConfigured: expectedCommand,
            managedStatusLineInstalled: exact, managedStatusLineNeedsRepair: expectedCommand && !exact,
            hasConflictingStatusLine: statusLine != nil && !expectedCommand,
            managedStatusLineIsWrapper: exact && wrapper != nil, managementOutcome: outcome
        )
    }

    @discardableResult
    public func install() throws -> ClaudeStatusLineInstallationStatus {
        let templates = try verifiedTemplates()
        let current = try status()
        switch current.managementOutcome {
        case .exactManaged: return current
        case .unresolvedRecovery: throw ManagedHookFileSystemError.recoveryRequired(current.settingsURL.path)
        case .ambiguousUnmanaged: throw ManagedHookFileSystemError.ambiguous(current.settingsURL.path)
        case .unowned: break
        default: throw ManagedHookFileSystemError.ambiguous(current.settingsURL.path)
        }
        if current.hasConflictingStatusLine { throw ClaudeStatusLineInstallationError.existingStatusLineConflict(command: current.statusLineCommand) }
        return try install(mode: .normal, originalStatusLine: nil, originalCommand: nil, templates: templates)
    }

    @discardableResult
    public func installAsWrapper() throws -> ClaudeStatusLineInstallationStatus {
        let templates = try verifiedTemplates()
        let current = try status()
        if current.managementOutcome == .exactManaged { return current }
        guard current.managementOutcome == .unowned,
              current.hasConflictingStatusLine,
              let settings = try? loadSettings(at: current.settingsURL),
              let original = settings["statusLine"] as? [String: Any],
              let command = original["command"] as? String, !command.isEmpty
        else { throw ClaudeStatusLineInstallationError.wrappableCommandMissing }
        return try install(mode: .wrapper, originalStatusLine: original, originalCommand: command, templates: templates)
    }

    @discardableResult
    public func uninstall() throws -> ClaudeStatusLineInstallationStatus {
        _ = try verifiedTemplates()
        let current = try status()
        guard current.managementOutcome == .exactManaged else {
            switch current.managementOutcome {
            case .unowned: return current
            case .unresolvedRecovery: throw ManagedHookFileSystemError.recoveryRequired(current.settingsURL.path)
            default: throw ManagedHookFileSystemError.ambiguous(current.settingsURL.path)
            }
        }
        let urls = targetURLs
        let settingsProvenance = try requireProvenance(for: urls.settings)
        let scriptProvenance = try requireProvenance(for: urls.script)
        let settingsSidecarDigest = try ManagedHookFileSystem.digest(ofFile: ManagedHookProvenance.sidecarURL(for: urls.settings))
        let scriptSidecarDigest = try ManagedHookFileSystem.digest(ofFile: ManagedHookProvenance.sidecarURL(for: urls.script))
        let wrapper = try loadSettings(at: urls.settings)[openIslandOriginalStatusLineKey] as? [String: Any]
        var delegateSidecarDigest: String?
        if wrapper != nil { _ = try requireProvenance(for: urls.delegate); delegateSidecarDigest = try ManagedHookFileSystem.digest(ofFile: ManagedHookProvenance.sidecarURL(for: urls.delegate)) }

        // The original settings bytes, not a reconstruction, are the only
        // permitted uninstall restore source.
        if let preDigest = settingsProvenance.preMutationDigest {
            guard settingsProvenance.backupDigest == preDigest,
                  try backupMatches(settingsProvenance, target: urls.settings) else { throw ManagedHookFileSystemError.ambiguous(urls.settings.path) }
            let backup = ManagedHookBackupLifecycle.backupURL(for: urls.settings)
            let data = try Data(contentsOf: backup, options: [.mappedIfSafe])
            try ManagedHookFileSystem.replace(data, at: urls.settings, expectedDigest: preDigest, fileManager: fileManager)
        } else {
            let hasBackup = try pathExists(ManagedHookBackupLifecycle.backupURL(for: urls.settings))
            guard settingsProvenance.backupDigest == nil,
                  !hasBackup else { throw ManagedHookFileSystemError.ambiguous(urls.settings.path) }
            try ManagedHookFileSystem.remove(urls.settings, expectedDigest: settingsProvenance.postMutationDigest)
        }
        try ManagedHookFileSystem.remove(urls.script, expectedDigest: scriptProvenance.postMutationDigest)
        if wrapper != nil { try ManagedHookFileSystem.remove(urls.delegate, expectedDigest: try requireProvenance(for: urls.delegate).postMutationDigest) }
        try ManagedHookFileSystem.remove(ManagedHookProvenance.sidecarURL(for: urls.settings), expectedDigest: settingsSidecarDigest)
        try ManagedHookFileSystem.remove(ManagedHookProvenance.sidecarURL(for: urls.script), expectedDigest: scriptSidecarDigest)
        if let delegateSidecarDigest { try ManagedHookFileSystem.remove(ManagedHookProvenance.sidecarURL(for: urls.delegate), expectedDigest: delegateSidecarDigest) }
        try ManagedHookBackupLifecycle.removeBackup(for: urls.settings, fileManager: fileManager)
        return try status()
    }

    private enum Mode { case normal, wrapper }
    private struct TargetURLs { let settings: URL; let script: URL; let delegate: URL; let legacyScript: URL }
    private var targetURLs: TargetURLs {
        TargetURLs(settings: claudeDirectory.appendingPathComponent("settings.json"), script: scriptDirectoryURL.appendingPathComponent(Self.managedScriptName), delegate: scriptDirectoryURL.appendingPathComponent(Self.wrappedDelegateScriptName), legacyScript: legacyScriptDirectoryURL.appendingPathComponent(Self.legacyManagedScriptName))
    }

    private func install(mode: Mode, originalStatusLine: [String: Any]?, originalCommand: String?, templates: ClaudeStatusLineTemplateResources) throws -> ClaudeStatusLineInstallationStatus {
        let urls = targetURLs
        // Reclassify every mutation input after the caller's status/consent
        // check and before creating a directory or writing a script.
        try preflightRead(urls)
        let existing = try loadSettings(at: urls.settings)
        let preDigest = try pathExists(urls.settings) ? ManagedHookFileSystem.digest(ofFile: urls.settings) : nil
        var mutated = existing
        mutated["statusLine"] = managedStatusLine(for: urls.script)
        if mode == .wrapper { mutated[openIslandOriginalStatusLineKey] = originalStatusLine }
        let settingsData = try serializeSettings(mutated)
        let scriptResource = mode == .wrapper ? templates.wrapper : templates.normal
        let scriptData = try renderedScript(resource: scriptResource, cacheURL: Self.managedCacheURL, delegateScriptURL: mode == .wrapper ? urls.delegate : nil)
        let delegateData = try originalCommand.map { try renderedDelegate(resource: templates.delegate, originalCommand: $0) }

        try ManagedHookFileSystem.createDirectory(claudeDirectory, fileManager: fileManager)
        try ManagedHookFileSystem.createDirectory(scriptDirectoryURL, fileManager: fileManager)
        if preDigest != nil { try ManagedHookBackupLifecycle.snapshotForMutation(of: urls.settings, fileManager: fileManager) }
        try ManagedHookFileSystem.replace(scriptData, at: urls.script, mode: 0o755, expectedDigest: ManagedHookFileSystem.digest(of: scriptData), fileManager: fileManager)
        try record(target: urls.script, entryDigest: ManagedHookFileSystem.digest(of: scriptData), preDigest: nil, postData: scriptData, template: scriptResource.entry)
        if let delegateData {
            try ManagedHookFileSystem.replace(delegateData, at: urls.delegate, mode: 0o755, expectedDigest: ManagedHookFileSystem.digest(of: delegateData), fileManager: fileManager)
            try record(target: urls.delegate, entryDigest: ManagedHookFileSystem.digest(of: delegateData), preDigest: nil, postData: delegateData, template: templates.delegate.entry)
        }
        try ManagedHookFileSystem.replace(settingsData, at: urls.settings, expectedDigest: ManagedHookFileSystem.digest(of: settingsData), fileManager: fileManager)
        let statusLineData = try serializeSettings(managedStatusLine(for: urls.script))
        try record(target: urls.settings, entryDigest: ManagedHookFileSystem.digest(of: statusLineData), preDigest: preDigest, postData: settingsData, template: scriptResource.entry)
        return try status()
    }

    private func exactInstallation(settings: [String: Any], statusLine: [String: Any], wrapper: [String: Any]?, urls: TargetURLs) throws -> Bool? {
        let isWrapper = wrapper != nil
        guard statusLine as NSDictionary == managedStatusLine(for: urls.script) as NSDictionary else { return nil }
        let templates = try verifiedTemplates()
        let scriptResource = isWrapper ? templates.wrapper : templates.normal
        let settingsData = try serializeSettings(settings)
        let entryData = try serializeSettings(managedStatusLine(for: urls.script))
        guard try provenanceMatches(target: urls.settings, entryDigest: ManagedHookFileSystem.digest(of: entryData), postData: settingsData, template: scriptResource.entry),
              try provenanceMatches(target: urls.script, entryDigest: ManagedHookFileSystem.digest(of: try renderedScript(resource: scriptResource, cacheURL: Self.managedCacheURL, delegateScriptURL: isWrapper ? urls.delegate : nil)), postData: try renderedScript(resource: scriptResource, cacheURL: Self.managedCacheURL, delegateScriptURL: isWrapper ? urls.delegate : nil), template: scriptResource.entry)
        else { return nil }
        if let wrapper {
            guard let original = wrapper["command"] as? String, !original.isEmpty else { return nil }
            let delegateData = try renderedDelegate(resource: templates.delegate, originalCommand: original)
            guard try provenanceMatches(target: urls.delegate, entryDigest: ManagedHookFileSystem.digest(of: delegateData), postData: delegateData, template: templates.delegate.entry) else { return nil }
        }
        guard let settingsProvenance = try? requireProvenance(for: urls.settings), try backupMatches(settingsProvenance, target: urls.settings) else { return nil }
        return isWrapper
    }

    private func provenanceMatches(target: URL, entryDigest: String, postData: Data, template: BundledArtifactManifest.Entry) throws -> Bool {
        guard let provenance = try ManagedHookProvenance.loadVerified(for: target, managerID: Self.managerID, fileManager: fileManager) else { return false }
        return provenance.formatVersion == Self.managedTemplateVersion
            && provenance.managedEntryDigest == entryDigest
            && provenance.postMutationDigest == ManagedHookFileSystem.digest(of: postData)
            && provenance.artifactID == template.artifactID
            && provenance.artifactVersion == template.version
            && provenance.artifactSHA256 == template.sha256
            && provenance.artifactTemplateVersion == template.templateVersion
    }

    private func record(target: URL, entryDigest: String, preDigest: String?, postData: Data, template: BundledArtifactManifest.Entry) throws {
        let backupDigest = preDigest == nil ? nil : try ManagedHookFileSystem.digest(ofFile: ManagedHookBackupLifecycle.backupURL(for: target))
        let provenance = ManagedHookProvenance(targetURL: target, managerID: Self.managerID, formatVersion: Self.managedTemplateVersion, managedEntryDigest: entryDigest, preMutationDigest: preDigest, postMutationDigest: ManagedHookFileSystem.digest(of: postData), backupDigest: backupDigest, artifact: template)
        try ManagedHookProvenance.record(provenance, for: target, fileManager: fileManager)
    }

    private func requireProvenance(for target: URL) throws -> ManagedHookProvenance {
        guard let provenance = try ManagedHookProvenance.loadVerified(for: target, managerID: Self.managerID, fileManager: fileManager) else { throw ManagedHookFileSystemError.ambiguous(target.path) }
        return provenance
    }

    private func backupMatches(_ provenance: ManagedHookProvenance, target: URL) throws -> Bool {
        if provenance.preMutationDigest == nil {
            let hasBackup = try pathExists(ManagedHookBackupLifecycle.backupURL(for: target))
            let hasMetadata = try pathExists(ManagedHookBackupLifecycle.metadataURL(for: target))
            return provenance.backupDigest == nil && !hasBackup && !hasMetadata
        }
        guard let expected = provenance.backupDigest, expected == provenance.preMutationDigest,
              try ManagedHookBackupLifecycle.isVerifiedBackup(for: target, fileManager: fileManager) else { return false }
        return try ManagedHookFileSystem.digest(ofFile: ManagedHookBackupLifecycle.backupURL(for: target)) == expected
    }

    private func ownershipEvidenceExists(for urls: TargetURLs, command: String?) throws -> Bool {
        let hasSettingsSidecar = try pathExists(sidecar(for: urls.settings))
        if command == urls.script.path || hasSettingsSidecar { return true }
        for target in [urls.script, urls.delegate, urls.legacyScript] {
            let targetExists = try pathExists(target)
            let sidecarExists = try pathExists(sidecar(for: target))
            if targetExists || sidecarExists { return true }
        }
        let hasBackup = try pathExists(ManagedHookBackupLifecycle.backupURL(for: urls.settings))
        let hasMetadata = try pathExists(ManagedHookBackupLifecycle.metadataURL(for: urls.settings))
        return hasBackup || hasMetadata
    }

    private func journalExists(for urls: TargetURLs) throws -> Bool {
        for target in [urls.settings, urls.script, urls.delegate, urls.legacyScript] {
            if try pathExists(ManagedHookFileSystem.journalURL(for: target)) ||
                pathExists(ManagedHookFileSystem.journalURL(for: sidecar(for: target))) { return true }
        }
        return false
    }

    private func loadSettings(at url: URL) throws -> [String: Any] {
        guard try pathExists(url) else { return [:] }
        try ManagedHookFileSystem.validateTarget(url, allowMissing: false)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url, options: [.mappedIfSafe]))
        guard let settings = object as? [String: Any] else { throw ClaudeStatusLineInstallationError.invalidSettingsRoot }
        return settings
    }

    private func sidecar(for target: URL) -> URL { ManagedHookProvenance.sidecarURL(for: target) }
    private func pathExists(_ url: URL) throws -> Bool { try ManagedHookFileSystem.existsNoFollow(url) }

    private func preflightRead(_ urls: TargetURLs) throws {
        for directory in [claudeDirectory, scriptDirectoryURL, legacyScriptDirectoryURL] {
            try validateDirectoryForRead(directory)
        }
        let targets = [
            urls.settings, urls.script, urls.delegate, urls.legacyScript,
            sidecar(for: urls.settings), sidecar(for: urls.script), sidecar(for: urls.delegate), sidecar(for: urls.legacyScript),
            ManagedHookBackupLifecycle.backupURL(for: urls.settings), ManagedHookBackupLifecycle.metadataURL(for: urls.settings),
        ] + [urls.settings, urls.script, urls.delegate, urls.legacyScript].flatMap {
            [ManagedHookFileSystem.journalURL(for: $0), ManagedHookFileSystem.journalURL(for: sidecar(for: $0))]
        }
        for target in targets where try pathExists(target) {
            try ManagedHookFileSystem.validateTarget(target, allowMissing: false)
        }
    }

    private func validateDirectoryForRead(_ directory: URL) throws {
        if try pathExists(directory) { return try ManagedHookFileSystem.validateDirectoryPath(directory) }
        var parent = directory.deletingLastPathComponent()
        while !(try pathExists(parent)) { parent = parent.deletingLastPathComponent() }
        try ManagedHookFileSystem.validateDirectoryPath(parent)
    }
    private func serializeSettings(_ settings: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) }
    private func managedStatusLine(for scriptURL: URL) -> [String: Any] { ["type": "command", "command": scriptURL.path, "padding": 2] }

    private enum TemplateKind: CaseIterable {
        case normal, wrapper, delegate

        var artifactID: String {
            switch self {
            case .normal: "claude-statusline-script-template"
            case .wrapper: "claude-statusline-wrapper-template"
            case .delegate: "claude-statusline-delegate-template"
            }
        }

        var relativePath: String {
            switch self {
            case .normal: "Contents/Resources/ClaudeStatusLineTemplates/status-line-v1.sh.template"
            case .wrapper: "Contents/Resources/ClaudeStatusLineTemplates/status-line-wrapper-v1.sh.template"
            case .delegate: "Contents/Resources/ClaudeStatusLineTemplates/status-line-delegate-v1.sh.template"
            }
        }

        var placeholders: Set<String> {
            switch self {
            case .normal: ["OPEN_ISLAND_CACHE_PATH_SHELL_QUOTED"]
            case .wrapper: ["OPEN_ISLAND_CACHE_PATH_SHELL_QUOTED", "OPEN_ISLAND_DELEGATE_PATH_SHELL_QUOTED"]
            case .delegate: ["OPEN_ISLAND_ORIGINAL_COMMAND_SHELL_QUOTED"]
            }
        }
    }

    private func verifiedTemplates() throws -> ClaudeStatusLineTemplateResources {
        let resources = try templateResources ?? bundledTemplateResources()
        try validateTemplate(resources.normal, kind: .normal)
        try validateTemplate(resources.wrapper, kind: .wrapper)
        try validateTemplate(resources.delegate, kind: .delegate)
        return resources
    }

    private func bundledTemplateResources() throws -> ClaudeStatusLineTemplateResources {
        let bundleURL = Bundle.main.bundleURL
        func resource(_ kind: TemplateKind) throws -> VerifiedBundledResource {
            try VerifiedBundledHookArtifact.verifiedResource(at: bundleURL.appendingPathComponent(kind.relativePath), fileManager: fileManager)
        }
        return try ClaudeStatusLineTemplateResources(normal: resource(.normal), wrapper: resource(.wrapper), delegate: resource(.delegate))
    }

    private func validateTemplate(_ resource: VerifiedBundledResource, kind: TemplateKind) throws {
        let entry = resource.entry
        guard (try? ManagedHookFileSystem.validateTarget(resource.resourceURL, allowMissing: false)) != nil,
              let onDiskData = try? Data(contentsOf: resource.resourceURL, options: [.mappedIfSafe]),
              onDiskData == resource.data,
              entry.artifactID == kind.artifactID,
              entry.version >= 1,
              entry.relativePath == kind.relativePath,
              entry.managedMarker == Self.managedTemplateMarker,
              entry.templateVersion == Self.managedTemplateVersion,
              entry.sha256 == ManagedHookFileSystem.digest(of: resource.data),
              let text = String(data: resource.data, encoding: .utf8),
              text.contains("# \(Self.managedTemplateMarker) version: \(entry.templateVersion)"),
              Set(placeholderNames(in: text)) == kind.placeholders,
              placeholderNames(in: text).count == kind.placeholders.count
        else { throw ClaudeStatusLineInstallationError.unverifiedTemplate }
    }

    private func renderedScript(resource: VerifiedBundledResource, cacheURL: URL, delegateScriptURL: URL?) throws -> Data {
        let kind: TemplateKind = delegateScriptURL == nil ? .normal : .wrapper
        var values = ["OPEN_ISLAND_CACHE_PATH_SHELL_QUOTED": Self.shellQuote(cacheURL.path)]
        if let delegateScriptURL { values["OPEN_ISLAND_DELEGATE_PATH_SHELL_QUOTED"] = Self.shellQuote(delegateScriptURL.path) }
        return try render(resource: resource, kind: kind, values: values)
    }

    private func renderedDelegate(resource: VerifiedBundledResource, originalCommand: String) throws -> Data {
        try render(resource: resource, kind: .delegate, values: [
            "OPEN_ISLAND_ORIGINAL_COMMAND_SHELL_QUOTED": Self.shellQuote(originalCommand),
        ])
    }

    private func render(resource: VerifiedBundledResource, kind: TemplateKind, values: [String: String]) throws -> Data {
        try validateTemplate(resource, kind: kind)
        guard Set(values.keys) == kind.placeholders,
              var text = String(data: resource.data, encoding: .utf8)
        else { throw ClaudeStatusLineInstallationError.unverifiedTemplate }
        for name in kind.placeholders {
            guard let value = values[name] else { throw ClaudeStatusLineInstallationError.unverifiedTemplate }
            text = text.replacingOccurrences(of: "{{\(name)}}", with: value)
        }
        guard placeholderNames(in: text).isEmpty else { throw ClaudeStatusLineInstallationError.unverifiedTemplate }
        return Data(text.utf8)
    }

    private func placeholderNames(in text: String) -> [String] {
        let expression = try? NSRegularExpression(pattern: "\\{\\{([A-Z_]+)\\}\\}")
        let range = NSRange(text.startIndex..., in: text)
        return expression?.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        } ?? []
    }

    private static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
}
