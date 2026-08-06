import Foundation

public struct GeminiHookInstallationStatus: Equatable, Sendable {
    public var geminiDirectory: URL
    public var settingsURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: GeminiHookInstallerManifest?
    /// Read-only ownership outcome. Command text, a hook name, or a manifest
    /// filename is never sufficient authority to mutate Gemini settings.
    public var managementOutcome: HookManagementOutcome

    public init(
        geminiDirectory: URL,
        settingsURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        manifest: GeminiHookInstallerManifest?,
        managementOutcome: HookManagementOutcome = .unowned
    ) {
        self.geminiDirectory = geminiDirectory
        self.settingsURL = settingsURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
        self.managementOutcome = managementOutcome
    }
}

public final class GeminiHookInstallationManager: @unchecked Sendable {
    private static let managerID = "gemini-hooks"
    private static let formatVersion = "2"

    public let geminiDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager
    private let credentialRevoker: () throws -> Void

    public init(
        geminiDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default,
        credentialRevoker: @escaping () throws -> Void = { try BridgeCredentialLifecycle.revokeManagedHookCredential() }
    ) {
        self.geminiDirectory = geminiDirectory.standardizedFileURL
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
        self.credentialRevoker = credentialRevoker
    }

    /// Status is deliberately non-mutating: it never creates ~/.gemini,
    /// installs the helper, prunes backups, or resolves interrupted writes.
    public func status(hooksBinaryURL: URL? = nil) throws -> GeminiHookInstallationStatus {
        let urls = targetURLs()
        do { return try inspect(urls: urls, hooksBinaryURL: hooksBinaryURL) }
        catch { return baseStatus(urls: urls, hooksBinaryURL: hooksBinaryURL, manifest: nil, outcome: HookManagementOutcome.from(error: error)) }
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> GeminiHookInstallationStatus {
        // Artifact verification and all no-follow reads happen before creating
        // a directory or installing/replacing the shared helper.
        let artifact = try VerifiedBundledHookArtifact.verify(helperURL: hooksBinaryURL, fileManager: fileManager)
        let urls = targetURLs()
        try preflightForMutation(urls: urls)
        let current = try status(hooksBinaryURL: managedHooksBinaryURL)
        switch current.managementOutcome {
        case .exactManaged:
            if try provenanceNeedsArtifactRefresh(urls: urls, artifact: artifact) {
                _ = try ManagedHooksBinary.install(from: artifact, to: managedHooksBinaryURL, fileManager: fileManager)
                try refreshArtifactProvenance(urls: urls, artifact: artifact)
            }
            return try status(hooksBinaryURL: managedHooksBinaryURL)
        case .unowned:
            break
        default:
            throw error(for: current.managementOutcome, path: urls.settings.path)
        }

        let settingsData = try checkedData(at: urls.settings)
        guard try checkedData(at: urls.manifest) == nil,
              !(try pathExists(sidecar(for: urls.settings))),
              !(try pathExists(sidecar(for: urls.manifest))),
              !(try backupExists(for: urls.settings)) else {
            throw ManagedHookFileSystemError.ambiguous(urls.settings.path)
        }
        let command = GeminiHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        guard case .none = try GeminiHookInstaller.managedSettingsState(existingData: settingsData, hookCommand: command) else {
            throw ManagedHookFileSystemError.ambiguous(urls.settings.path)
        }
        let mutation = try GeminiHookInstaller.installSettingsJSON(existingData: settingsData, hookCommand: command)
        guard let settingsOutput = mutation.contents,
              case let .exact(entryDigest: entryDigest) = try GeminiHookInstaller.managedSettingsState(existingData: settingsOutput, hookCommand: command) else {
            throw ManagedHookFileSystemError.ambiguous(urls.settings.path)
        }
        let manifestData = try encodedManifest(GeminiHookInstallerManifest(hookCommand: command))

        // Do not touch user targets before all sibling state has been
        // classified. This preserves unrelated settings and ambiguity evidence.
        try ManagedHookFileSystem.createDirectory(geminiDirectory, fileManager: fileManager)
        _ = try ManagedHooksBinary.install(from: artifact, to: managedHooksBinaryURL, fileManager: fileManager)
        if settingsData != nil { try ManagedHookBackupLifecycle.createBackup(of: urls.settings, fileManager: fileManager) }
        try replace(settingsOutput, at: urls.settings)
        try recordProvenance(target: urls.settings, entryDigest: entryDigest, preDigest: settingsData.map(ManagedHookFileSystem.digest), postData: settingsOutput, artifact: artifact)
        try replace(manifestData, at: urls.manifest)
        try recordProvenance(target: urls.manifest, entryDigest: ManagedHookFileSystem.digest(of: manifestData), preDigest: nil, postData: manifestData, artifact: artifact)
        return try status(hooksBinaryURL: managedHooksBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> GeminiHookInstallationStatus {
        let urls = targetURLs()
        let current = try status()
        switch current.managementOutcome {
        case .unowned: return current
        case .exactManaged: break
        default: throw error(for: current.managementOutcome, path: urls.settings.path)
        }
        try preflightForMutation(urls: urls)
        let settingsData = try requireData(at: urls.settings)
        let manifestData = try requireData(at: urls.manifest)
        let manifest = try requireManifest(at: urls.manifest)
        let settingsRecord = try requireVerifiedProvenance(for: urls.settings)
        _ = try requireVerifiedProvenance(for: urls.manifest)
        let command = GeminiHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        guard manifest.hookCommand == command,
              case let .exact(entryDigest: entryDigest) = try GeminiHookInstaller.managedSettingsState(existingData: settingsData, hookCommand: command),
              settingsRecord.identifiesManagedEntries(entryDigest) else {
            throw ManagedHookFileSystemError.ambiguous(urls.settings.path)
        }
        let mutation = try GeminiHookInstaller.uninstallSettingsJSON(existingData: settingsData, managedCommand: command)
        guard mutation.managedHooksPresent else { throw ManagedHookFileSystemError.ambiguous(urls.settings.path) }
        let settingsSidecarDigest = try ManagedHookFileSystem.digest(ofFile: sidecar(for: urls.settings))
        let manifestSidecarDigest = try ManagedHookFileSystem.digest(ofFile: sidecar(for: urls.manifest))

        try ManagedHookBackupLifecycle.snapshotForMutation(of: urls.settings, fileManager: fileManager)
        if let contents = mutation.contents { try replace(contents, at: urls.settings) }
        else { try ManagedHookFileSystem.remove(urls.settings, expectedDigest: ManagedHookFileSystem.digest(of: settingsData)) }
        try ManagedHookFileSystem.remove(urls.manifest, expectedDigest: ManagedHookFileSystem.digest(of: manifestData))
        try ManagedHookFileSystem.remove(sidecar(for: urls.settings), expectedDigest: settingsSidecarDigest)
        try ManagedHookFileSystem.remove(sidecar(for: urls.manifest), expectedDigest: manifestSidecarDigest)
        try ManagedHookBackupLifecycle.removeBackup(for: urls.settings, fileManager: fileManager)
        try credentialRevoker()
        return try status()
    }

    private struct TargetURLs { let settings: URL; let manifest: URL }

    private func targetURLs() -> TargetURLs {
        TargetURLs(settings: geminiDirectory.appendingPathComponent("settings.json"), manifest: geminiDirectory.appendingPathComponent(GeminiHookInstallerManifest.fileName))
    }

    private func inspect(urls: TargetURLs, hooksBinaryURL: URL?) throws -> GeminiHookInstallationStatus {
        try preflightRead(urls: urls)
        try ensureNoRecoveryJournals(urls: urls)
        let settingsData = try checkedData(at: urls.settings)
        let manifestData = try checkedData(at: urls.manifest)
        let command = GeminiHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        let state = try GeminiHookInstaller.managedSettingsState(existingData: settingsData, hookCommand: command)
        let anyEvidence = try pathExists(sidecar(for: urls.settings)) || pathExists(sidecar(for: urls.manifest)) || backupExists(for: urls.settings)
        if manifestData == nil, !anyEvidence, case .none = state {
            return baseStatus(urls: urls, hooksBinaryURL: hooksBinaryURL, manifest: nil, outcome: .unowned)
        }
        guard let manifestData,
              let manifest = decodeManifest(manifestData), manifest.hookCommand == command,
              case let .exact(entryDigest: settingsEntryDigest) = state,
              let settingsRecord = try ManagedHookProvenance.loadVerified(for: urls.settings, managerID: Self.managerID, ownership: .shared, fileManager: fileManager),
              let manifestRecord = try ManagedHookProvenance.loadVerified(for: urls.manifest, managerID: Self.managerID, ownership: .exclusive, fileManager: fileManager),
              settingsRecord.formatVersion == Self.formatVersion, manifestRecord.formatVersion == Self.formatVersion,
              settingsRecord.identifiesManagedEntries(settingsEntryDigest),
              manifestRecord.managedEntryDigest == ManagedHookFileSystem.digest(of: manifestData),
              try backupIdentityMatches(settingsRecord, target: urls.settings),
              try backupIdentityMatches(manifestRecord, target: urls.manifest),
              try artifactIdentityMatches(settingsRecord), try artifactIdentityMatches(manifestRecord)
        else { throw ManagedHookFileSystemError.ambiguous(urls.settings.path) }
        return baseStatus(urls: urls, hooksBinaryURL: hooksBinaryURL, manifest: manifest, outcome: .exactManaged)
    }

    private func baseStatus(urls: TargetURLs, hooksBinaryURL: URL?, manifest: GeminiHookInstallerManifest?, outcome: HookManagementOutcome) -> GeminiHookInstallationStatus {
        GeminiHookInstallationStatus(geminiDirectory: geminiDirectory, settingsURL: urls.settings, manifestURL: urls.manifest, hooksBinaryURL: resolvedHooksBinaryURL(explicitURL: hooksBinaryURL), managedHooksPresent: outcome == .exactManaged, manifest: manifest, managementOutcome: outcome)
    }

    private func preflightForMutation(urls: TargetURLs) throws {
        try preflightRead(urls: urls)
        try ensureNoRecoveryJournals(urls: urls)
    }

    private func preflightRead(urls: TargetURLs) throws {
        try validateDirectoryForRead(geminiDirectory)
        let targets = [urls.settings, urls.manifest, sidecar(for: urls.settings), sidecar(for: urls.manifest), ManagedHookBackupLifecycle.backupURL(for: urls.settings), ManagedHookBackupLifecycle.metadataURL(for: urls.settings), ManagedHookFileSystem.journalURL(for: urls.settings), ManagedHookFileSystem.journalURL(for: urls.manifest), ManagedHookFileSystem.journalURL(for: sidecar(for: urls.settings)), ManagedHookFileSystem.journalURL(for: sidecar(for: urls.manifest))]
        for target in targets where try pathExists(target) { try ManagedHookFileSystem.validateTarget(target, allowMissing: false) }
    }

    private func validateDirectoryForRead(_ directory: URL) throws {
        if try pathExists(directory) { return try ManagedHookFileSystem.validateDirectoryPath(directory) }
        var parent = directory.deletingLastPathComponent()
        while !(try pathExists(parent)) { parent = parent.deletingLastPathComponent() }
        try ManagedHookFileSystem.validateDirectoryPath(parent)
    }

    private func ensureNoRecoveryJournals(urls: TargetURLs) throws {
        for target in [urls.settings, urls.manifest, sidecar(for: urls.settings), sidecar(for: urls.manifest)] {
            let journal = ManagedHookFileSystem.journalURL(for: target)
            if try pathExists(journal) { throw ManagedHookFileSystemError.recoveryRequired(journal.path) }
        }
    }

    private func checkedData(at url: URL) throws -> Data? {
        guard try pathExists(url) else { return nil }
        try ManagedHookFileSystem.validateTarget(url, allowMissing: false)
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func requireData(at url: URL) throws -> Data {
        guard let data = try checkedData(at: url) else { throw ManagedHookFileSystemError.ambiguous(url.path) }
        return data
    }

    private func requireManifest(at url: URL) throws -> GeminiHookInstallerManifest {
        guard let manifest = decodeManifest(try requireData(at: url)) else { throw ManagedHookFileSystemError.ambiguous(url.path) }
        return manifest
    }

    private func decodeManifest(_ data: Data) -> GeminiHookInstallerManifest? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GeminiHookInstallerManifest.self, from: data)
    }

    private func encodedManifest(_ manifest: GeminiHookInstallerManifest) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    private func sidecar(for target: URL) -> URL { ManagedHookProvenance.sidecarURL(for: target) }
    private func pathExists(_ url: URL) throws -> Bool { try ManagedHookFileSystem.existsNoFollow(url) }
    private func backupExists(for target: URL) throws -> Bool { try pathExists(ManagedHookBackupLifecycle.backupURL(for: target)) || pathExists(ManagedHookBackupLifecycle.metadataURL(for: target)) }

    /// `settings.json` belongs to Gemini; the manifest is ours.
    private func ownership(of target: URL) -> ManagedHookProvenance.TargetOwnership {
        target == targetURLs().manifest ? .exclusive : .shared
    }

    private func requireVerifiedProvenance(for target: URL) throws -> ManagedHookProvenance {
        guard let record = try ManagedHookProvenance.loadVerified(for: target, managerID: Self.managerID, ownership: ownership(of: target), fileManager: fileManager), record.formatVersion == Self.formatVersion,
              try backupIdentityMatches(record, target: target), try artifactIdentityMatches(record) else {
            throw ManagedHookFileSystemError.ambiguous(target.path)
        }
        return record
    }

    private func backupIdentityMatches(_ record: ManagedHookProvenance, target: URL) throws -> Bool {
        let backup = ManagedHookBackupLifecycle.backupURL(for: target)
        let metadata = ManagedHookBackupLifecycle.metadataURL(for: target)
        if let expected = record.backupDigest {
            guard try pathExists(backup), try pathExists(metadata), try ManagedHookBackupLifecycle.isVerifiedBackup(for: target, fileManager: fileManager) else { return false }
            return try ManagedHookFileSystem.digest(ofFile: backup) == expected
        }
        let hasBackup = try pathExists(backup)
        let hasMetadata = try pathExists(metadata)
        return !hasBackup && !hasMetadata
    }

    private func artifactIdentityMatches(_ record: ManagedHookProvenance) throws -> Bool {
        guard ManagedHooksBinary.managementOutcome(at: managedHooksBinaryURL, fileManager: fileManager) == .exactManaged,
              record.artifactID == VerifiedBundledHookArtifact.helperID,
              record.artifactVersion != nil, record.artifactTemplateVersion?.isEmpty == false,
              record.artifactExpectedMode != nil, record.artifactManagedMarker == "OpenIslandHooks",
              let digest = record.artifactSHA256 else { return false }
        return try ManagedHookFileSystem.digest(ofFile: managedHooksBinaryURL) == digest
    }

    private func recordProvenance(target: URL, entryDigest: String, preDigest: String?, postData: Data, artifact: VerifiedBundledHookArtifact) throws {
        let backup = ManagedHookBackupLifecycle.backupURL(for: target)
        let backupDigest = try pathExists(backup) ? ManagedHookFileSystem.digest(ofFile: backup) : nil
        let record = ManagedHookProvenance(targetURL: target, managerID: Self.managerID, formatVersion: Self.formatVersion, managedEntryDigest: entryDigest, preMutationDigest: preDigest, postMutationDigest: ManagedHookFileSystem.digest(of: postData), backupDigest: backupDigest, artifact: artifact.entry)
        try ManagedHookProvenance.record(record, for: target, fileManager: fileManager)
    }

    private func provenanceNeedsArtifactRefresh(urls: TargetURLs, artifact: VerifiedBundledHookArtifact) throws -> Bool {
        try [urls.settings, urls.manifest].contains { target in
            let record = try requireVerifiedProvenance(for: target)
            return record.artifactID != artifact.entry.artifactID || record.artifactVersion != artifact.entry.version || record.artifactSHA256 != artifact.entry.sha256 || record.artifactTemplateVersion != artifact.entry.templateVersion
        }
    }

    private func refreshArtifactProvenance(urls: TargetURLs, artifact: VerifiedBundledHookArtifact) throws {
        for target in [urls.settings, urls.manifest] {
            // The helper was replaced just above: the old sidecar's helper
            // digest is intentionally stale, while all target evidence must
            // remain exact before its artifact identity may be refreshed.
            guard let record = try ManagedHookProvenance.loadVerified(for: target, managerID: Self.managerID, ownership: ownership(of: target), fileManager: fileManager),
                  record.formatVersion == Self.formatVersion,
                  try backupIdentityMatches(record, target: target) else {
                throw ManagedHookFileSystemError.ambiguous(target.path)
            }
            try recordProvenance(target: target, entryDigest: record.managedEntryDigest, preDigest: record.preMutationDigest, postData: try requireData(at: target), artifact: artifact)
        }
    }

    private func replace(_ data: Data, at target: URL) throws {
        try ManagedHookFileSystem.replace(data, at: target, expectedDigest: ManagedHookFileSystem.digest(of: data), fileManager: fileManager)
    }

    private func resolvedHooksBinaryURL(explicitURL: URL?) -> URL? {
        if let explicitURL { return explicitURL.standardizedFileURL }
        return fileManager.isExecutableFile(atPath: managedHooksBinaryURL.path) ? managedHooksBinaryURL : nil
    }

    private func error(for outcome: HookManagementOutcome, path: String) -> Error {
        switch outcome {
        case .unsafePath: return ManagedHookFileSystemError.unsafePath(path, "is unsafe")
        case .unresolvedRecovery: return ManagedHookFileSystemError.recoveryRequired(path)
        default: return ManagedHookFileSystemError.ambiguous(path)
        }
    }
}
