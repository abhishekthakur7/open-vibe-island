import Foundation

public struct CursorHookInstallationStatus: Equatable, Sendable {
    public var cursorDirectory: URL
    public var hooksURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: CursorHookInstallerManifest?
    /// Read-only ownership result. Command text and a manifest filename are
    /// collision evidence only; callers must use this value for mutations.
    public var managementOutcome: HookManagementOutcome

    public init(
        cursorDirectory: URL,
        hooksURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        manifest: CursorHookInstallerManifest?,
        managementOutcome: HookManagementOutcome = .unowned
    ) {
        self.cursorDirectory = cursorDirectory
        self.hooksURL = hooksURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
        self.managementOutcome = managementOutcome
    }
}

public final class CursorHookInstallationManager: @unchecked Sendable {
    private static let managerID = "cursor-hooks"
    private static let formatVersion = "2"

    public let cursorDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager
    private let credentialRevoker: () throws -> Void

    public init(
        cursorDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default,
        credentialRevoker: @escaping () throws -> Void = { try BridgeCredentialLifecycle.revokeManagedHookCredential() }
    ) {
        self.cursorDirectory = cursorDirectory.standardizedFileURL
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
        self.credentialRevoker = credentialRevoker
    }

    /// Status is deliberately read-only. It never creates ~/.cursor, installs
    /// a helper, prunes recovery evidence, or resolves a journal.
    public func status(hooksBinaryURL: URL? = nil) throws -> CursorHookInstallationStatus {
        let urls = targetURLs()
        do { return try inspect(urls: urls, hooksBinaryURL: hooksBinaryURL) }
        catch { return baseStatus(urls: urls, hooksBinaryURL: hooksBinaryURL, manifest: nil, outcome: HookManagementOutcome.from(error: error)) }
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> CursorHookInstallationStatus {
        // Do not create a configuration directory or helper destination until
        // immutable app artifact verification and nofollow classification pass.
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
            throw error(for: current.managementOutcome, path: urls.hooks.path)
        }

        let hooksData = try checkedData(at: urls.hooks)
        guard try checkedData(at: urls.manifest) == nil,
              !(try pathExists(sidecar(for: urls.hooks))),
              !(try pathExists(sidecar(for: urls.manifest))),
              !(try backupExists(for: urls.hooks)) else {
            throw ManagedHookFileSystemError.ambiguous(urls.hooks.path)
        }
        let command = CursorHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        guard case .none = try CursorHookInstaller.managedHookState(existingData: hooksData, hookCommand: command) else {
            throw ManagedHookFileSystemError.ambiguous(urls.hooks.path)
        }
        let mutation = try CursorHookInstaller.installHooksJSON(existingData: hooksData, hookCommand: command)
        guard let hooksOutput = mutation.contents,
              case let .exact(entryDigest: entryDigest) = try CursorHookInstaller.managedHookState(existingData: hooksOutput, hookCommand: command) else {
            throw ManagedHookFileSystemError.ambiguous(urls.hooks.path)
        }
        let manifestData = try encodedManifest(CursorHookInstallerManifest(hookCommand: command))

        // No user target has changed before all targets, sidecars, backups,
        // and recovery journals were classified above.
        try ManagedHookFileSystem.createDirectory(cursorDirectory, fileManager: fileManager)
        _ = try ManagedHooksBinary.install(from: artifact, to: managedHooksBinaryURL, fileManager: fileManager)
        if hooksData != nil { try ManagedHookBackupLifecycle.createBackup(of: urls.hooks, fileManager: fileManager) }
        try replace(hooksOutput, at: urls.hooks)
        try recordProvenance(target: urls.hooks, entryDigest: entryDigest, preDigest: hooksData.map(ManagedHookFileSystem.digest), postData: hooksOutput, artifact: artifact)
        try replace(manifestData, at: urls.manifest)
        try recordProvenance(target: urls.manifest, entryDigest: ManagedHookFileSystem.digest(of: manifestData), preDigest: nil, postData: manifestData, artifact: artifact)
        return try status(hooksBinaryURL: managedHooksBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> CursorHookInstallationStatus {
        let urls = targetURLs()
        let current = try status()
        switch current.managementOutcome {
        case .unowned: return current
        case .exactManaged: break
        default: throw error(for: current.managementOutcome, path: urls.hooks.path)
        }
        try preflightForMutation(urls: urls)
        let hooksData = try requireData(at: urls.hooks)
        let manifestData = try requireData(at: urls.manifest)
        let manifest = try requireManifest(at: urls.manifest)
        let hooksProvenance = try requireVerifiedProvenance(for: urls.hooks)
        _ = try requireVerifiedProvenance(for: urls.manifest)
        let command = CursorHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        guard manifest.hookCommand == command,
              case let .exact(entryDigest: entryDigest) = try CursorHookInstaller.managedHookState(existingData: hooksData, hookCommand: command),
              hooksProvenance.managedEntryDigest == entryDigest else {
            throw ManagedHookFileSystemError.ambiguous(urls.hooks.path)
        }
        let mutation = try CursorHookInstaller.uninstallHooksJSON(existingData: hooksData, managedCommand: command)
        guard mutation.managedHooksPresent else { throw ManagedHookFileSystemError.ambiguous(urls.hooks.path) }
        let hooksSidecarDigest = try ManagedHookFileSystem.digest(ofFile: sidecar(for: urls.hooks))
        let manifestSidecarDigest = try ManagedHookFileSystem.digest(ofFile: sidecar(for: urls.manifest))

        try ManagedHookBackupLifecycle.snapshotForMutation(of: urls.hooks, fileManager: fileManager)
        if let contents = mutation.contents { try replace(contents, at: urls.hooks) }
        else { try ManagedHookFileSystem.remove(urls.hooks, expectedDigest: ManagedHookFileSystem.digest(of: hooksData)) }
        try ManagedHookFileSystem.remove(urls.manifest, expectedDigest: ManagedHookFileSystem.digest(of: manifestData))
        try ManagedHookFileSystem.remove(sidecar(for: urls.hooks), expectedDigest: hooksSidecarDigest)
        try ManagedHookFileSystem.remove(sidecar(for: urls.manifest), expectedDigest: manifestSidecarDigest)
        try ManagedHookBackupLifecycle.removeBackup(for: urls.hooks, fileManager: fileManager)
        try credentialRevoker()
        return try status()
    }

    private struct TargetURLs {
        let hooks: URL
        let manifest: URL
    }

    private func targetURLs() -> TargetURLs {
        TargetURLs(hooks: cursorDirectory.appendingPathComponent("hooks.json"), manifest: cursorDirectory.appendingPathComponent(CursorHookInstallerManifest.fileName))
    }

    private func inspect(urls: TargetURLs, hooksBinaryURL: URL?) throws -> CursorHookInstallationStatus {
        try preflightRead(urls: urls)
        try ensureNoRecoveryJournals(urls: urls)
        let hooksData = try checkedData(at: urls.hooks)
        let manifestData = try checkedData(at: urls.manifest)
        let command = CursorHookInstaller.hookCommand(for: managedHooksBinaryURL.path)
        let state = try CursorHookInstaller.managedHookState(existingData: hooksData, hookCommand: command)
        let anyEvidence = try pathExists(sidecar(for: urls.hooks)) || pathExists(sidecar(for: urls.manifest)) || backupExists(for: urls.hooks)
        if manifestData == nil, !anyEvidence, case .none = state {
            return baseStatus(urls: urls, hooksBinaryURL: hooksBinaryURL, manifest: nil, outcome: .unowned)
        }
        guard let manifestData,
              let manifest = decodeManifest(manifestData), manifest.hookCommand == command,
              case let .exact(entryDigest: hooksEntryDigest) = state,
              let hooksRecord = try ManagedHookProvenance.loadVerified(for: urls.hooks, managerID: Self.managerID, fileManager: fileManager),
              let manifestRecord = try ManagedHookProvenance.loadVerified(for: urls.manifest, managerID: Self.managerID, fileManager: fileManager),
              hooksRecord.formatVersion == Self.formatVersion, manifestRecord.formatVersion == Self.formatVersion,
              hooksRecord.managedEntryDigest == hooksEntryDigest,
              manifestRecord.managedEntryDigest == ManagedHookFileSystem.digest(of: manifestData),
              try backupIdentityMatches(hooksRecord, target: urls.hooks),
              try backupIdentityMatches(manifestRecord, target: urls.manifest),
              try artifactIdentityMatches(hooksRecord), try artifactIdentityMatches(manifestRecord)
        else { throw ManagedHookFileSystemError.ambiguous(urls.hooks.path) }
        return baseStatus(urls: urls, hooksBinaryURL: hooksBinaryURL, manifest: manifest, outcome: .exactManaged)
    }

    private func baseStatus(urls: TargetURLs, hooksBinaryURL: URL?, manifest: CursorHookInstallerManifest?, outcome: HookManagementOutcome) -> CursorHookInstallationStatus {
        CursorHookInstallationStatus(cursorDirectory: cursorDirectory, hooksURL: urls.hooks, manifestURL: urls.manifest, hooksBinaryURL: resolvedHooksBinaryURL(explicitURL: hooksBinaryURL), managedHooksPresent: outcome == .exactManaged, manifest: manifest, managementOutcome: outcome)
    }

    private func preflightForMutation(urls: TargetURLs) throws {
        try preflightRead(urls: urls)
        try ensureNoRecoveryJournals(urls: urls)
    }

    private func preflightRead(urls: TargetURLs) throws {
        try validateDirectoryForRead(cursorDirectory)
        let targets = [urls.hooks, urls.manifest, sidecar(for: urls.hooks), sidecar(for: urls.manifest), ManagedHookBackupLifecycle.backupURL(for: urls.hooks), ManagedHookBackupLifecycle.metadataURL(for: urls.hooks), ManagedHookFileSystem.journalURL(for: urls.hooks), ManagedHookFileSystem.journalURL(for: urls.manifest), ManagedHookFileSystem.journalURL(for: sidecar(for: urls.hooks)), ManagedHookFileSystem.journalURL(for: sidecar(for: urls.manifest))]
        for target in targets where try pathExists(target) { try ManagedHookFileSystem.validateTarget(target, allowMissing: false) }
    }

    private func validateDirectoryForRead(_ directory: URL) throws {
        if try pathExists(directory) { return try ManagedHookFileSystem.validateDirectoryPath(directory) }
        var parent = directory.deletingLastPathComponent()
        while !(try pathExists(parent)) { parent = parent.deletingLastPathComponent() }
        try ManagedHookFileSystem.validateDirectoryPath(parent)
    }

    private func ensureNoRecoveryJournals(urls: TargetURLs) throws {
        for target in [urls.hooks, urls.manifest, sidecar(for: urls.hooks), sidecar(for: urls.manifest)] {
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

    private func requireManifest(at url: URL) throws -> CursorHookInstallerManifest {
        guard let manifest = decodeManifest(try requireData(at: url)) else { throw ManagedHookFileSystemError.ambiguous(url.path) }
        return manifest
    }

    private func decodeManifest(_ data: Data) -> CursorHookInstallerManifest? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CursorHookInstallerManifest.self, from: data)
    }

    private func encodedManifest(_ manifest: CursorHookInstallerManifest) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    private func sidecar(for target: URL) -> URL { ManagedHookProvenance.sidecarURL(for: target) }
    private func pathExists(_ url: URL) throws -> Bool { try ManagedHookFileSystem.existsNoFollow(url) }
    private func backupExists(for target: URL) throws -> Bool { try pathExists(ManagedHookBackupLifecycle.backupURL(for: target)) || pathExists(ManagedHookBackupLifecycle.metadataURL(for: target)) }

    private func requireVerifiedProvenance(for target: URL) throws -> ManagedHookProvenance {
        guard let record = try ManagedHookProvenance.loadVerified(for: target, managerID: Self.managerID, fileManager: fileManager), record.formatVersion == Self.formatVersion,
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
        try [urls.hooks, urls.manifest].contains { target in
            let record = try requireVerifiedProvenance(for: target)
            return record.artifactID != artifact.entry.artifactID || record.artifactVersion != artifact.entry.version || record.artifactSHA256 != artifact.entry.sha256 || record.artifactTemplateVersion != artifact.entry.templateVersion
        }
    }

    private func refreshArtifactProvenance(urls: TargetURLs, artifact: VerifiedBundledHookArtifact) throws {
        for target in [urls.hooks, urls.manifest] {
            // The helper has just been replaced, so the old record's artifact
            // digest intentionally no longer matches. Its target, sidecar,
            // format, and backup identity must still verify before metadata
            // can be refreshed.
            guard let record = try ManagedHookProvenance.loadVerified(for: target, managerID: Self.managerID, fileManager: fileManager),
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
