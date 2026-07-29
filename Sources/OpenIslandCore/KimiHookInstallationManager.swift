import Foundation

public struct KimiHookInstallationStatus: Equatable, Sendable, Codable {
    public var kimiDirectory: URL
    public var configURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: KimiHookInstallerManifest?
    /// A read-only ownership result. A TOML marker, command text, or manifest
    /// name alone is collision evidence, never authority to mutate Kimi.
    public var managementOutcome: HookManagementOutcome

    public init(kimiDirectory: URL, configURL: URL, manifestURL: URL, hooksBinaryURL: URL?, managedHooksPresent: Bool, manifest: KimiHookInstallerManifest?, managementOutcome: HookManagementOutcome = .unowned) {
        self.kimiDirectory = kimiDirectory
        self.configURL = configURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
        self.managementOutcome = managementOutcome
    }

    private enum CodingKeys: String, CodingKey { case kimiDirectory, configURL, manifestURL, hooksBinaryURL, managedHooksPresent, manifest }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kimiDirectory = try values.decode(URL.self, forKey: .kimiDirectory)
        configURL = try values.decode(URL.self, forKey: .configURL)
        manifestURL = try values.decode(URL.self, forKey: .manifestURL)
        hooksBinaryURL = try values.decodeIfPresent(URL.self, forKey: .hooksBinaryURL)
        managedHooksPresent = try values.decode(Bool.self, forKey: .managedHooksPresent)
        manifest = try values.decodeIfPresent(KimiHookInstallerManifest.self, forKey: .manifest)
        managementOutcome = managedHooksPresent ? .exactManaged : .unowned
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kimiDirectory, forKey: .kimiDirectory)
        try values.encode(configURL, forKey: .configURL)
        try values.encode(manifestURL, forKey: .manifestURL)
        try values.encodeIfPresent(hooksBinaryURL, forKey: .hooksBinaryURL)
        try values.encode(managedHooksPresent, forKey: .managedHooksPresent)
        try values.encodeIfPresent(manifest, forKey: .manifest)
    }
}

public final class KimiHookInstallationManager: @unchecked Sendable {
    private static let managerID = "kimi-hooks"
    private static let formatVersion = "2"

    public let kimiDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager
    private let credentialRevoker: () throws -> Void

    public init(
        kimiDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default,
        credentialRevoker: @escaping () throws -> Void = { try BridgeCredentialLifecycle.revokeManagedHookCredential() }
    ) {
        self.kimiDirectory = kimiDirectory.standardizedFileURL
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
        self.credentialRevoker = credentialRevoker
    }

    /// Status deliberately has no recovery or cleanup side effects.
    public func status(hooksBinaryURL: URL? = nil) throws -> KimiHookInstallationStatus {
        let urls = targetURLs()
        do { return try inspect(urls: urls, hooksBinaryURL: hooksBinaryURL) }
        catch { return baseStatus(urls: urls, hooksBinaryURL: hooksBinaryURL, manifest: nil, outcome: HookManagementOutcome.from(error: error)) }
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> KimiHookInstallationStatus {
        // Verify the immutable source and classify every target no-follow
        // before creating ~/.kimi or replacing the shared helper.
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
        case .unowned: break
        default: throw error(for: current.managementOutcome, path: urls.config.path)
        }

        let configData = try checkedData(at: urls.config)
        guard try checkedData(at: urls.manifest) == nil,
              !(try pathExists(sidecar(for: urls.config))),
              !(try pathExists(sidecar(for: urls.manifest))),
              !(try backupExists(for: urls.config)) else { throw ManagedHookFileSystemError.ambiguous(urls.config.path) }
        let command = KimiHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        let existing = configData.flatMap { String(data: $0, encoding: .utf8) }
        guard configData == nil || existing != nil,
              case .none = KimiHookInstaller.managedConfigState(existingContents: existing, hookCommand: command) else {
            throw ManagedHookFileSystemError.ambiguous(urls.config.path)
        }
        let mutation = KimiHookInstaller.installConfigTOML(existingContents: existing, hookCommand: command)
        guard let outputString = mutation.contents,
              case let .exact(entryDigest: entryDigest) = KimiHookInstaller.managedConfigState(existingContents: outputString, hookCommand: command) else {
            throw ManagedHookFileSystemError.ambiguous(urls.config.path)
        }
        let configOutput = Data(outputString.utf8)
        let manifestData = try encodedManifest(KimiHookInstallerManifest(hookCommand: command))

        try ManagedHookFileSystem.createDirectory(kimiDirectory, fileManager: fileManager)
        _ = try ManagedHooksBinary.install(from: artifact, to: managedHooksBinaryURL, fileManager: fileManager)
        if configData != nil { try ManagedHookBackupLifecycle.createBackup(of: urls.config, fileManager: fileManager) }
        try replace(configOutput, at: urls.config)
        try recordProvenance(target: urls.config, entryDigest: entryDigest, preDigest: configData.map(ManagedHookFileSystem.digest), postData: configOutput, artifact: artifact)
        try replace(manifestData, at: urls.manifest)
        try recordProvenance(target: urls.manifest, entryDigest: ManagedHookFileSystem.digest(of: manifestData), preDigest: nil, postData: manifestData, artifact: artifact)
        return try status(hooksBinaryURL: managedHooksBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> KimiHookInstallationStatus {
        let urls = targetURLs()
        let current = try status()
        switch current.managementOutcome {
        case .unowned: return current
        case .exactManaged: break
        default: throw error(for: current.managementOutcome, path: urls.config.path)
        }
        try preflightForMutation(urls: urls)
        let configData = try requireData(at: urls.config)
        guard let config = String(data: configData, encoding: .utf8) else { throw ManagedHookFileSystemError.ambiguous(urls.config.path) }
        let manifestData = try requireData(at: urls.manifest)
        let manifest = try requireManifest(at: urls.manifest)
        let configRecord = try requireVerifiedProvenance(for: urls.config)
        _ = try requireVerifiedProvenance(for: urls.manifest)
        let command = KimiHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        guard manifest.hookCommand == command,
              case let .exact(entryDigest: entryDigest) = KimiHookInstaller.managedConfigState(existingContents: config, hookCommand: command),
              configRecord.managedEntryDigest == entryDigest else { throw ManagedHookFileSystemError.ambiguous(urls.config.path) }
        let mutation = KimiHookInstaller.uninstallExactConfigTOML(existingContents: config, hookCommand: command)
        guard mutation.managedHooksPresent else { throw ManagedHookFileSystemError.ambiguous(urls.config.path) }
        let configSidecarDigest = try ManagedHookFileSystem.digest(ofFile: sidecar(for: urls.config))
        let manifestSidecarDigest = try ManagedHookFileSystem.digest(ofFile: sidecar(for: urls.manifest))

        try ManagedHookBackupLifecycle.snapshotForMutation(of: urls.config, fileManager: fileManager)
        if let contents = mutation.contents { try replace(Data(contents.utf8), at: urls.config) }
        else { try ManagedHookFileSystem.remove(urls.config, expectedDigest: ManagedHookFileSystem.digest(of: configData)) }
        try ManagedHookFileSystem.remove(urls.manifest, expectedDigest: ManagedHookFileSystem.digest(of: manifestData))
        try ManagedHookFileSystem.remove(sidecar(for: urls.config), expectedDigest: configSidecarDigest)
        try ManagedHookFileSystem.remove(sidecar(for: urls.manifest), expectedDigest: manifestSidecarDigest)
        try ManagedHookBackupLifecycle.removeBackup(for: urls.config, fileManager: fileManager)
        try credentialRevoker()
        return try status()
    }

    private struct TargetURLs { let config: URL; let manifest: URL }
    private func targetURLs() -> TargetURLs { TargetURLs(config: kimiDirectory.appendingPathComponent("config.toml"), manifest: kimiDirectory.appendingPathComponent(KimiHookInstallerManifest.fileName)) }

    private func inspect(urls: TargetURLs, hooksBinaryURL: URL?) throws -> KimiHookInstallationStatus {
        try preflightRead(urls: urls)
        try ensureNoRecoveryJournals(urls: urls)
        let configData = try checkedData(at: urls.config)
        let config = configData.flatMap { String(data: $0, encoding: .utf8) }
        guard configData == nil || config != nil else { throw ManagedHookFileSystemError.ambiguous(urls.config.path) }
        let manifestData = try checkedData(at: urls.manifest)
        let command = KimiHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        let state = KimiHookInstaller.managedConfigState(existingContents: config, hookCommand: command)
        let anyEvidence = try pathExists(sidecar(for: urls.config)) || pathExists(sidecar(for: urls.manifest)) || backupExists(for: urls.config)
        if manifestData == nil, !anyEvidence, case .none = state { return baseStatus(urls: urls, hooksBinaryURL: hooksBinaryURL, manifest: nil, outcome: .unowned) }
        guard let manifestData,
              let manifest = decodeManifest(manifestData), manifest.hookCommand == command,
              case let .exact(entryDigest: entryDigest) = state,
              let configRecord = try ManagedHookProvenance.loadVerified(for: urls.config, managerID: Self.managerID, fileManager: fileManager),
              let manifestRecord = try ManagedHookProvenance.loadVerified(for: urls.manifest, managerID: Self.managerID, fileManager: fileManager),
              configRecord.formatVersion == Self.formatVersion, manifestRecord.formatVersion == Self.formatVersion,
              configRecord.managedEntryDigest == entryDigest,
              manifestRecord.managedEntryDigest == ManagedHookFileSystem.digest(of: manifestData),
              try backupIdentityMatches(configRecord, target: urls.config), try backupIdentityMatches(manifestRecord, target: urls.manifest),
              try artifactIdentityMatches(configRecord), try artifactIdentityMatches(manifestRecord) else { throw ManagedHookFileSystemError.ambiguous(urls.config.path) }
        return baseStatus(urls: urls, hooksBinaryURL: hooksBinaryURL, manifest: manifest, outcome: .exactManaged)
    }

    private func baseStatus(urls: TargetURLs, hooksBinaryURL: URL?, manifest: KimiHookInstallerManifest?, outcome: HookManagementOutcome) -> KimiHookInstallationStatus {
        KimiHookInstallationStatus(kimiDirectory: kimiDirectory, configURL: urls.config, manifestURL: urls.manifest, hooksBinaryURL: resolvedHooksBinaryURL(explicitURL: hooksBinaryURL), managedHooksPresent: outcome == .exactManaged, manifest: manifest, managementOutcome: outcome)
    }

    private func preflightForMutation(urls: TargetURLs) throws { try preflightRead(urls: urls); try ensureNoRecoveryJournals(urls: urls) }
    private func preflightRead(urls: TargetURLs) throws {
        try validateDirectoryForRead(kimiDirectory)
        let targets = [urls.config, urls.manifest, sidecar(for: urls.config), sidecar(for: urls.manifest), ManagedHookBackupLifecycle.backupURL(for: urls.config), ManagedHookBackupLifecycle.metadataURL(for: urls.config), ManagedHookFileSystem.journalURL(for: urls.config), ManagedHookFileSystem.journalURL(for: urls.manifest), ManagedHookFileSystem.journalURL(for: sidecar(for: urls.config)), ManagedHookFileSystem.journalURL(for: sidecar(for: urls.manifest))]
        for target in targets where try pathExists(target) { try ManagedHookFileSystem.validateTarget(target, allowMissing: false) }
    }
    private func validateDirectoryForRead(_ directory: URL) throws {
        if try pathExists(directory) { return try ManagedHookFileSystem.validateDirectoryPath(directory) }
        var parent = directory.deletingLastPathComponent()
        while !(try pathExists(parent)) { parent = parent.deletingLastPathComponent() }
        try ManagedHookFileSystem.validateDirectoryPath(parent)
    }
    private func ensureNoRecoveryJournals(urls: TargetURLs) throws {
        for target in [urls.config, urls.manifest, sidecar(for: urls.config), sidecar(for: urls.manifest)] where try pathExists(ManagedHookFileSystem.journalURL(for: target)) { throw ManagedHookFileSystemError.recoveryRequired(ManagedHookFileSystem.journalURL(for: target).path) }
    }
    private func checkedData(at url: URL) throws -> Data? { guard try pathExists(url) else { return nil }; try ManagedHookFileSystem.validateTarget(url, allowMissing: false); return try Data(contentsOf: url, options: [.mappedIfSafe]) }
    private func requireData(at url: URL) throws -> Data { guard let data = try checkedData(at: url) else { throw ManagedHookFileSystemError.ambiguous(url.path) }; return data }
    private func requireManifest(at url: URL) throws -> KimiHookInstallerManifest { guard let manifest = decodeManifest(try requireData(at: url)) else { throw ManagedHookFileSystemError.ambiguous(url.path) }; return manifest }
    private func decodeManifest(_ data: Data) -> KimiHookInstallerManifest? { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try? decoder.decode(KimiHookInstallerManifest.self, from: data) }
    private func encodedManifest(_ manifest: KimiHookInstallerManifest) throws -> Data { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return try encoder.encode(manifest) }
    private func sidecar(for target: URL) -> URL { ManagedHookProvenance.sidecarURL(for: target) }
    private func pathExists(_ url: URL) throws -> Bool { try ManagedHookFileSystem.existsNoFollow(url) }
    private func backupExists(for target: URL) throws -> Bool { try pathExists(ManagedHookBackupLifecycle.backupURL(for: target)) || pathExists(ManagedHookBackupLifecycle.metadataURL(for: target)) }
    private func requireVerifiedProvenance(for target: URL) throws -> ManagedHookProvenance {
        guard let record = try ManagedHookProvenance.loadVerified(for: target, managerID: Self.managerID, fileManager: fileManager), record.formatVersion == Self.formatVersion, try backupIdentityMatches(record, target: target), try artifactIdentityMatches(record) else { throw ManagedHookFileSystemError.ambiguous(target.path) }; return record
    }
    private func backupIdentityMatches(_ record: ManagedHookProvenance, target: URL) throws -> Bool {
        let backup = ManagedHookBackupLifecycle.backupURL(for: target), metadata = ManagedHookBackupLifecycle.metadataURL(for: target)
        if let expected = record.backupDigest { guard try pathExists(backup), try pathExists(metadata), try ManagedHookBackupLifecycle.isVerifiedBackup(for: target, fileManager: fileManager) else { return false }; return try ManagedHookFileSystem.digest(ofFile: backup) == expected }
        let hasBackup = try pathExists(backup)
        let hasMetadata = try pathExists(metadata)
        return !hasBackup && !hasMetadata
    }
    private func artifactIdentityMatches(_ record: ManagedHookProvenance) throws -> Bool {
        guard ManagedHooksBinary.managementOutcome(at: managedHooksBinaryURL, fileManager: fileManager) == .exactManaged, record.artifactID == VerifiedBundledHookArtifact.helperID, record.artifactVersion != nil, record.artifactTemplateVersion?.isEmpty == false, record.artifactExpectedMode != nil, record.artifactManagedMarker == "OpenIslandHooks", let digest = record.artifactSHA256 else { return false }
        return try ManagedHookFileSystem.digest(ofFile: managedHooksBinaryURL) == digest
    }
    private func recordProvenance(target: URL, entryDigest: String, preDigest: String?, postData: Data, artifact: VerifiedBundledHookArtifact) throws {
        let backup = ManagedHookBackupLifecycle.backupURL(for: target)
        let backupDigest = try pathExists(backup) ? ManagedHookFileSystem.digest(ofFile: backup) : nil
        try ManagedHookProvenance.record(ManagedHookProvenance(targetURL: target, managerID: Self.managerID, formatVersion: Self.formatVersion, managedEntryDigest: entryDigest, preMutationDigest: preDigest, postMutationDigest: ManagedHookFileSystem.digest(of: postData), backupDigest: backupDigest, artifact: artifact.entry), for: target, fileManager: fileManager)
    }
    private func provenanceNeedsArtifactRefresh(urls: TargetURLs, artifact: VerifiedBundledHookArtifact) throws -> Bool { try [urls.config, urls.manifest].contains { target in let record = try requireVerifiedProvenance(for: target); return record.artifactID != artifact.entry.artifactID || record.artifactVersion != artifact.entry.version || record.artifactSHA256 != artifact.entry.sha256 || record.artifactTemplateVersion != artifact.entry.templateVersion } }
    private func refreshArtifactProvenance(urls: TargetURLs, artifact: VerifiedBundledHookArtifact) throws {
        for target in [urls.config, urls.manifest] {
            guard let record = try ManagedHookProvenance.loadVerified(for: target, managerID: Self.managerID, fileManager: fileManager), record.formatVersion == Self.formatVersion, try backupIdentityMatches(record, target: target) else { throw ManagedHookFileSystemError.ambiguous(target.path) }
            try recordProvenance(target: target, entryDigest: record.managedEntryDigest, preDigest: record.preMutationDigest, postData: try requireData(at: target), artifact: artifact)
        }
    }
    private func replace(_ data: Data, at target: URL) throws { try ManagedHookFileSystem.replace(data, at: target, expectedDigest: ManagedHookFileSystem.digest(of: data), fileManager: fileManager) }
    private func resolvedHooksBinaryURL(explicitURL: URL?) -> URL? { if let explicitURL { return explicitURL.standardizedFileURL }; return fileManager.isExecutableFile(atPath: managedHooksBinaryURL.path) ? managedHooksBinaryURL : nil }
    private func error(for outcome: HookManagementOutcome, path: String) -> Error { switch outcome { case .unsafePath: return ManagedHookFileSystemError.unsafePath(path, "is unsafe"); case .unresolvedRecovery: return ManagedHookFileSystemError.recoveryRequired(path); default: return ManagedHookFileSystemError.ambiguous(path) } }
}
