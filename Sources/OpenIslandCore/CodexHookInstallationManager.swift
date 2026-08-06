import Foundation

public struct CodexHookInstallationStatus: Equatable, Sendable {
    public var codexDirectory: URL
    public var configURL: URL
    public var hooksURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var featureFlagEnabled: Bool
    public var managedHooksPresent: Bool
    public var manifest: CodexHookInstallerManifest?
    /// Read-only ownership result.  Callers must use this rather than command
    /// text or a manifest filename to decide whether a repair is safe.
    public var managementOutcome: HookManagementOutcome

    public init(
        codexDirectory: URL,
        configURL: URL,
        hooksURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        featureFlagEnabled: Bool,
        managedHooksPresent: Bool,
        manifest: CodexHookInstallerManifest?,
        managementOutcome: HookManagementOutcome = .unowned
    ) {
        self.codexDirectory = codexDirectory
        self.configURL = configURL
        self.hooksURL = hooksURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.featureFlagEnabled = featureFlagEnabled
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
        self.managementOutcome = managementOutcome
    }
}

public final class CodexHookInstallationManager: @unchecked Sendable {
    private static let managerID = "codex-hooks"

    public let codexDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager
    private let featureKeyProvider: @Sendable () -> CodexHooksFeatureFlagKey
    private let credentialRevoker: () throws -> Void

    public init(
        codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default,
        featureKeyProvider: @escaping @Sendable () -> CodexHooksFeatureFlagKey = CodexHookInstaller.preferredCodexHooksFeatureKey,
        credentialRevoker: @escaping () throws -> Void = { try BridgeCredentialLifecycle.revokeManagedHookCredential() }
    ) {
        self.codexDirectory = codexDirectory.standardizedFileURL
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
        self.featureKeyProvider = featureKeyProvider
        self.credentialRevoker = credentialRevoker
    }

    /// Status never recovers journals, prunes backups, creates directories, or
    /// rewrites a config.  Every non-exact state is intentionally observable.
    public func status(hooksBinaryURL: URL? = nil) throws -> CodexHookInstallationStatus {
        let urls = targetURLs()
        do {
            return try inspect(urls: urls, hooksBinaryURL: hooksBinaryURL)
        } catch {
            return baseStatus(
                urls: urls,
                hooksBinaryURL: hooksBinaryURL,
                configContents: "",
                manifest: nil,
                outcome: HookManagementOutcome.from(error: error)
            )
        }
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> CodexHookInstallationStatus {
        // Verification happens before even creating ~/.codex.  The caller's
        // consent boundary is outside this manager; this is its final source
        // integrity boundary.
        let artifact = try VerifiedBundledHookArtifact.verify(helperURL: hooksBinaryURL, fileManager: fileManager)
        let urls = targetURLs()
        try preflightRead(urls: urls)
        try ensureNoRecoveryJournals(urls: urls)

        let current = try status(hooksBinaryURL: managedHooksBinaryURL)
        switch current.managementOutcome {
        case .exactManaged:
            // A verified managed installation may be updated, but no target
            // is changed unless all current sidecars first verify exactly.
            if try provenanceNeedsArtifactRefresh(urls: urls, artifact: artifact) {
                _ = try ManagedHooksBinary.install(from: artifact, to: managedHooksBinaryURL, fileManager: fileManager)
                try refreshArtifactProvenance(urls: urls, artifact: artifact)
            }
            return current
        case .unowned:
            break
        default:
            throw error(for: current.managementOutcome, path: urls.hooks.path)
        }

        let existingConfig = try checkedData(at: urls.config)
        let existingHooks = try checkedData(at: urls.hooks)
        let existingManifest = try checkedData(at: urls.manifest)
        guard existingManifest == nil,
              !(try pathExists(sidecar(for: urls.config))),
              !(try pathExists(sidecar(for: urls.hooks))),
              !(try pathExists(sidecar(for: urls.manifest))),
              !(try pathExists(urls.legacyManifest)),
              !(try backupExists(for: urls.config)), !(try backupExists(for: urls.hooks)) else {
            throw ManagedHookFileSystemError.ambiguous(urls.manifest.path)
        }

        let command = CodexHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        guard case .none = try CodexHookInstaller.managedHookState(existingData: existingHooks, hookCommand: command) else {
            throw ManagedHookFileSystemError.ambiguous(urls.hooks.path)
        }
        let configContents = existingConfig.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        guard existingConfig == nil || String(data: existingConfig!, encoding: .utf8) != nil else {
            throw ManagedHookFileSystemError.ambiguous(urls.config.path)
        }
        let featureMutation = CodexHookInstaller.enableCodexHooksFeature(
            in: configContents,
            preferredKey: featureKeyProvider()
        )
        let hooksMutation = try CodexHookInstaller.appendExactManagedHooksJSON(existingData: existingHooks, hookCommand: command)
        guard let hooksData = hooksMutation.contents,
              case let .exact(entryDigest: hooksEntryDigest) = try CodexHookInstaller.managedHookState(existingData: hooksData, hookCommand: command) else {
            throw ManagedHookFileSystemError.ambiguous(urls.hooks.path)
        }

        let manifest = CodexHookInstallerManifest(
            hookCommand: command,
            enabledCodexHooksFeature: featureMutation.featureEnabledByInstaller
        )
        let manifestData = try encodedManifest(manifest)
        let configData = Data(featureMutation.contents.utf8)

        // The helper is installed only after all user-owned targets have been
        // classified.  A managed-looking/partial entry cannot trigger writes.
        try ManagedHookFileSystem.createDirectory(codexDirectory, fileManager: fileManager)
        _ = try ManagedHooksBinary.install(from: artifact, to: managedHooksBinaryURL, fileManager: fileManager)
        if featureMutation.changed, existingConfig != nil { try backupFile(at: urls.config) }
        if existingHooks != nil { try backupFile(at: urls.hooks) }

        if featureMutation.changed {
            try replace(configData, at: urls.config)
            guard let featureDigest = CodexHookInstaller.managedFeatureEntryDigest(in: featureMutation.contents) else {
                throw ManagedHookFileSystemError.ambiguous(urls.config.path)
            }
            try recordProvenance(
                target: urls.config, entryDigest: featureDigest, preDigest: existingConfig.map(ManagedHookFileSystem.digest),
                postData: configData, artifact: artifact
            )
        }
        try replace(hooksData, at: urls.hooks)
        try recordProvenance(
            target: urls.hooks, entryDigest: hooksEntryDigest, preDigest: existingHooks.map(ManagedHookFileSystem.digest),
            postData: hooksData, artifact: artifact
        )
        try replace(manifestData, at: urls.manifest)
        try recordProvenance(
            target: urls.manifest, entryDigest: ManagedHookFileSystem.digest(of: manifestData), preDigest: nil,
            postData: manifestData, artifact: artifact
        )
        return try status(hooksBinaryURL: managedHooksBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> CodexHookInstallationStatus {
        let urls = targetURLs()
        let current = try status()
        switch current.managementOutcome {
        case .unowned: return current
        case .exactManaged: break
        default: throw error(for: current.managementOutcome, path: urls.hooks.path)
        }

        let manifest = try requireManifest(at: urls.manifest)
        let hooksData = try requireData(at: urls.hooks)
        let hooksProvenance = try requireVerifiedProvenance(for: urls.hooks)
        _ = try requireVerifiedProvenance(for: urls.manifest)
        let hooksSidecarDigest = try ManagedHookFileSystem.digest(ofFile: ManagedHookProvenance.sidecarURL(for: urls.hooks))
        let manifestSidecarDigest = try ManagedHookFileSystem.digest(ofFile: ManagedHookProvenance.sidecarURL(for: urls.manifest))
        let command = CodexHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        guard manifest.hookCommand == command,
              case let .exact(entryDigest: digest) = try CodexHookInstaller.managedHookState(existingData: hooksData, hookCommand: command),
              hooksProvenance.managedEntryDigest == digest else {
            throw ManagedHookFileSystemError.ambiguous(urls.hooks.path)
        }
        let hooksMutation = try CodexHookInstaller.removeExactManagedHooksJSON(existingData: hooksData, hookCommand: command)

        var configMutation: (data: Data, sidecarDigest: String)?
        if manifest.enabledCodexHooksFeature {
            let configData = try requireData(at: urls.config)
            let configProvenance = try requireVerifiedProvenance(for: urls.config)
            guard configProvenance.managedEntryDigest == CodexHookInstaller.managedFeatureEntryDigest(in: String(decoding: configData, as: UTF8.self)),
                  let mutation = CodexHookInstaller.disableCodexHooksFeature(
                    in: String(decoding: configData, as: UTF8.self), matchingEntryDigest: configProvenance.managedEntryDigest
                  ) else { throw ManagedHookFileSystemError.ambiguous(urls.config.path) }
            configMutation = (Data(mutation.contents.utf8), try ManagedHookFileSystem.digest(ofFile: ManagedHookProvenance.sidecarURL(for: urls.config)))
        }

        try backupFile(at: urls.hooks)
        if configMutation != nil { try backupFile(at: urls.config) }
        if let hooksData = hooksMutation.contents { try replace(hooksData, at: urls.hooks) }
        else { try ManagedHookFileSystem.remove(urls.hooks, expectedDigest: ManagedHookFileSystem.digest(of: hooksData)) }
        if let configMutation { try replace(configMutation.data, at: urls.config) }
        try ManagedHookFileSystem.remove(urls.manifest, expectedDigest: ManagedHookFileSystem.digest(ofFile: urls.manifest))

        if let configMutation {
            try ManagedHookFileSystem.remove(ManagedHookProvenance.sidecarURL(for: urls.config), expectedDigest: configMutation.sidecarDigest)
        }
        try ManagedHookFileSystem.remove(ManagedHookProvenance.sidecarURL(for: urls.hooks), expectedDigest: hooksSidecarDigest)
        try ManagedHookFileSystem.remove(ManagedHookProvenance.sidecarURL(for: urls.manifest), expectedDigest: manifestSidecarDigest)
        try ManagedHookBackupLifecycle.removeBackup(for: urls.hooks, fileManager: fileManager)
        if configMutation != nil { try ManagedHookBackupLifecycle.removeBackup(for: urls.config, fileManager: fileManager) }
        try credentialRevoker()
        return try status()
    }

    // MARK: - Read-only ownership inspection

    private struct TargetURLs {
        let config: URL
        let hooks: URL
        let manifest: URL
        let legacyManifest: URL
    }

    private func targetURLs() -> TargetURLs {
        TargetURLs(
            config: codexDirectory.appendingPathComponent("config.toml"),
            hooks: codexDirectory.appendingPathComponent("hooks.json"),
            manifest: codexDirectory.appendingPathComponent(CodexHookInstallerManifest.fileName),
            legacyManifest: codexDirectory.appendingPathComponent(CodexHookInstallerManifest.legacyFileName)
        )
    }

    private func inspect(urls: TargetURLs, hooksBinaryURL: URL?) throws -> CodexHookInstallationStatus {
        try preflightRead(urls: urls)
        try ensureNoRecoveryJournals(urls: urls)
        let configData = try checkedData(at: urls.config)
        let hooksData = try checkedData(at: urls.hooks)
        let manifestData = try checkedData(at: urls.manifest)
        guard !(try pathExists(urls.legacyManifest)) else { throw ManagedHookFileSystemError.ambiguous(urls.legacyManifest.path) }
        let configContents = configData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        guard configData == nil || String(data: configData!, encoding: .utf8) != nil else { throw ManagedHookFileSystemError.ambiguous(urls.config.path) }
        let anySidecar = try [urls.config, urls.hooks, urls.manifest].contains { try pathExists(sidecar(for: $0)) }
        let anyBackup = try [urls.config, urls.hooks].contains { try backupExists(for: $0) }
        let command = CodexHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        let state = try CodexHookInstaller.managedHookState(existingData: hooksData, hookCommand: command)

        if manifestData == nil, !anySidecar, !anyBackup, case .none = state {
            return baseStatus(urls: urls, hooksBinaryURL: hooksBinaryURL, configContents: configContents, manifest: nil, outcome: .unowned)
        }
        guard let manifestData,
              let manifest = decodeManifest(manifestData),
              manifest.hookCommand == command,
              case let .exact(entryDigest: hooksEntryDigest) = state,
              let hooksProvenance = try ManagedHookProvenance.loadVerified(for: urls.hooks, managerID: Self.managerID, ownership: .shared, fileManager: fileManager),
              let manifestProvenance = try ManagedHookProvenance.loadVerified(for: urls.manifest, managerID: Self.managerID, ownership: .exclusive, fileManager: fileManager),
              hooksProvenance.managedEntryDigest == hooksEntryDigest,
              manifestProvenance.managedEntryDigest == ManagedHookFileSystem.digest(of: manifestData),
              try backupIdentityMatches(hooksProvenance, target: urls.hooks),
              try backupIdentityMatches(manifestProvenance, target: urls.manifest),
              try artifactIdentityMatches(hooksProvenance),
              try artifactIdentityMatches(manifestProvenance)
        else { throw ManagedHookFileSystemError.ambiguous(urls.hooks.path) }

        if manifest.enabledCodexHooksFeature {
            guard let configData,
                  let configProvenance = try ManagedHookProvenance.loadVerified(for: urls.config, managerID: Self.managerID, ownership: .shared, fileManager: fileManager),
                  configProvenance.managedEntryDigest == CodexHookInstaller.managedFeatureEntryDigest(in: String(decoding: configData, as: UTF8.self)),
                  try backupIdentityMatches(configProvenance, target: urls.config),
                  try artifactIdentityMatches(configProvenance)
            else { throw ManagedHookFileSystemError.ambiguous(urls.config.path) }
        } else if try pathExists(sidecar(for: urls.config)) {
            throw ManagedHookFileSystemError.ambiguous(urls.config.path)
        }
        return baseStatus(urls: urls, hooksBinaryURL: hooksBinaryURL, configContents: configContents, manifest: manifest, outcome: .exactManaged)
    }

    private func baseStatus(urls: TargetURLs, hooksBinaryURL: URL?, configContents: String, manifest: CodexHookInstallerManifest?, outcome: HookManagementOutcome) -> CodexHookInstallationStatus {
        let resolved = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)
        return CodexHookInstallationStatus(
            codexDirectory: codexDirectory, configURL: urls.config, hooksURL: urls.hooks, manifestURL: urls.manifest,
            hooksBinaryURL: resolved, featureFlagEnabled: CodexHookInstaller.isCodexHooksFeatureEnabled(in: configContents),
            managedHooksPresent: outcome == .exactManaged, manifest: manifest, managementOutcome: outcome
        )
    }

    // MARK: - Exact evidence helpers

    private func checkedData(at url: URL) throws -> Data? {
        guard try pathExists(url) else { return nil }
        try ManagedHookFileSystem.validateTarget(url, allowMissing: false)
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func requireData(at url: URL) throws -> Data {
        guard let data = try checkedData(at: url) else { throw ManagedHookFileSystemError.ambiguous(url.path) }
        return data
    }

    private func requireManifest(at url: URL) throws -> CodexHookInstallerManifest {
        guard let manifest = decodeManifest(try requireData(at: url)) else { throw ManagedHookFileSystemError.ambiguous(url.path) }
        return manifest
    }

    private func decodeManifest(_ data: Data) -> CodexHookInstallerManifest? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CodexHookInstallerManifest.self, from: data)
    }

    private func encodedManifest(_ manifest: CodexHookInstallerManifest) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    private func sidecar(for target: URL) -> URL { ManagedHookProvenance.sidecarURL(for: target) }
    private func pathExists(_ url: URL) throws -> Bool { try ManagedHookFileSystem.existsNoFollow(url) }
    private func backupExists(for target: URL) throws -> Bool {
        try pathExists(ManagedHookBackupLifecycle.backupURL(for: target)) ||
            pathExists(ManagedHookBackupLifecycle.metadataURL(for: target))
    }

    /// `config.toml` and `hooks.json` belong to Codex; the manifest is ours.
    private func ownership(of target: URL) -> ManagedHookProvenance.TargetOwnership {
        target == targetURLs().manifest ? .exclusive : .shared
    }

    private func requireVerifiedProvenance(for target: URL) throws -> ManagedHookProvenance {
        guard let provenance = try ManagedHookProvenance.loadVerified(for: target, managerID: Self.managerID, ownership: ownership(of: target), fileManager: fileManager) else {
            throw ManagedHookFileSystemError.ambiguous(target.path)
        }
        guard try backupIdentityMatches(provenance, target: target), try artifactIdentityMatches(provenance) else {
            throw ManagedHookFileSystemError.ambiguous(target.path)
        }
        return provenance
    }

    private func backupIdentityMatches(_ provenance: ManagedHookProvenance, target: URL) throws -> Bool {
        let backup = ManagedHookBackupLifecycle.backupURL(for: target)
        let metadata = ManagedHookBackupLifecycle.metadataURL(for: target)
        if let expected = provenance.backupDigest {
            guard try pathExists(backup), try pathExists(metadata),
                  try ManagedHookBackupLifecycle.isVerifiedBackup(for: target, fileManager: fileManager) else { return false }
            return try ManagedHookFileSystem.digest(ofFile: backup) == expected
        }
        let hasBackup = try pathExists(backup)
        let hasMetadata = try pathExists(metadata)
        return !hasBackup && !hasMetadata
    }

    private func artifactIdentityMatches(_ provenance: ManagedHookProvenance) throws -> Bool {
        guard ManagedHooksBinary.managementOutcome(at: managedHooksBinaryURL, fileManager: fileManager) == .exactManaged,
              provenance.artifactID == VerifiedBundledHookArtifact.helperID,
              provenance.artifactVersion != nil, provenance.artifactTemplateVersion?.isEmpty == false,
              provenance.artifactExpectedMode != nil, provenance.artifactManagedMarker == "OpenIslandHooks",
              let digest = provenance.artifactSHA256 else { return false }
        return try ManagedHookFileSystem.digest(ofFile: managedHooksBinaryURL) == digest
    }

    private func recordProvenance(target: URL, entryDigest: String, preDigest: String?, postData: Data, artifact: VerifiedBundledHookArtifact) throws {
        let backup = ManagedHookBackupLifecycle.backupURL(for: target)
        let backupDigest = try pathExists(backup) ? ManagedHookFileSystem.digest(ofFile: backup) : nil
        let provenance = ManagedHookProvenance(
            targetURL: target, managerID: Self.managerID, formatVersion: artifact.entry.templateVersion,
            managedEntryDigest: entryDigest, preMutationDigest: preDigest,
            postMutationDigest: ManagedHookFileSystem.digest(of: postData), backupDigest: backupDigest, artifact: artifact.entry
        )
        try ManagedHookProvenance.record(provenance, for: target, fileManager: fileManager)
    }

    private func provenanceNeedsArtifactRefresh(urls: TargetURLs, artifact: VerifiedBundledHookArtifact) throws -> Bool {
        let hasConfigSidecar = try pathExists(sidecar(for: urls.config))
        let targets = [urls.hooks, urls.manifest] + (hasConfigSidecar ? [urls.config] : [])
        return try targets.contains { target in
            let record = try requireVerifiedProvenance(for: target)
            return record.artifactID != artifact.entry.artifactID ||
                record.artifactVersion != artifact.entry.version ||
                record.artifactSHA256 != artifact.entry.sha256 ||
                record.artifactTemplateVersion != artifact.entry.templateVersion
        }
    }

    private func refreshArtifactProvenance(urls: TargetURLs, artifact: VerifiedBundledHookArtifact) throws {
        let hasConfigSidecar = try pathExists(sidecar(for: urls.config))
        let targets = [urls.hooks, urls.manifest] + (hasConfigSidecar ? [urls.config] : [])
        for target in targets {
            let record = try requireVerifiedProvenance(for: target)
            let data = try requireData(at: target)
            try recordProvenance(
                target: target, entryDigest: record.managedEntryDigest,
                preDigest: record.preMutationDigest, postData: data, artifact: artifact
            )
        }
    }

    private func replace(_ data: Data, at target: URL) throws {
        try ManagedHookFileSystem.replace(data, at: target, expectedDigest: ManagedHookFileSystem.digest(of: data), fileManager: fileManager)
    }

    private func backupFile(at url: URL) throws {
        try ManagedHookBackupLifecycle.createBackup(of: url, fileManager: fileManager)
    }

    private func ensureNoRecoveryJournals(urls: TargetURLs) throws {
        for target in [urls.config, urls.hooks, urls.manifest] {
            let journal = ManagedHookFileSystem.journalURL(for: target)
            if try pathExists(journal) { throw ManagedHookFileSystemError.recoveryRequired(journal.path) }
        }
    }

    private func preflightRead(urls: TargetURLs) throws {
        try validateDirectoryForRead(codexDirectory)
        let targets = [
            urls.config, urls.hooks, urls.manifest, urls.legacyManifest,
            sidecar(for: urls.config), sidecar(for: urls.hooks), sidecar(for: urls.manifest),
            ManagedHookBackupLifecycle.backupURL(for: urls.config), ManagedHookBackupLifecycle.metadataURL(for: urls.config),
            ManagedHookBackupLifecycle.backupURL(for: urls.hooks), ManagedHookBackupLifecycle.metadataURL(for: urls.hooks),
        ] + [urls.config, urls.hooks, urls.manifest].flatMap {
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
