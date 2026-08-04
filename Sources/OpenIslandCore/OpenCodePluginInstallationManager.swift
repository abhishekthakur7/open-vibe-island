import Foundation

public struct OpenCodePluginInstallationStatus: Equatable, Sendable {
    public var openCodeConfigDirectory: URL
    public var pluginsDirectory: URL
    public var configURL: URL
    public var pluginFileURL: URL
    public var manifestURL: URL
    public var pluginFilePresent: Bool
    public var pluginRegistered: Bool
    /// Legacy per-user manifests are no longer installation authority.  This
    /// remains for display compatibility and is nil for new installations.
    public var manifest: OpenCodePluginInstallerManifest?
    public var managementOutcome: HookManagementOutcome

    public var isInstalled: Bool { managementOutcome == .exactManaged }

    public init(openCodeConfigDirectory: URL, pluginsDirectory: URL, configURL: URL, pluginFileURL: URL, manifestURL: URL, pluginFilePresent: Bool, pluginRegistered: Bool, manifest: OpenCodePluginInstallerManifest?, managementOutcome: HookManagementOutcome = .unowned) {
        self.openCodeConfigDirectory = openCodeConfigDirectory
        self.pluginsDirectory = pluginsDirectory
        self.configURL = configURL
        self.pluginFileURL = pluginFileURL
        self.manifestURL = manifestURL
        self.pluginFilePresent = pluginFilePresent
        self.pluginRegistered = pluginRegistered
        self.manifest = manifest
        self.managementOutcome = managementOutcome
    }
}

public struct OpenCodePluginInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-opencode-plugin-install.json"
    public var pluginPath: String
    public var installedAt: Date
    public init(pluginPath: String, installedAt: Date = .now) { self.pluginPath = pluginPath; self.installedAt = installedAt }
}

/// Installs only the bundled, manifest-verified OpenCode plugin.  A plugin
/// filename, config entry, legacy manifest, or sidecar by itself is never
/// ownership evidence: both mutated targets must independently prove their
/// exact bytes and provenance before they can be changed again.
public final class OpenCodePluginInstallationManager: @unchecked Sendable {
    private static let managerID = "opencode-plugin"
    public static let pluginFileName = "open-island.js"
    public static let bundledPluginDigest = "aec0e723e9826ba64ca6deb0647b9fa4cf06ea64e9796746b0273dbf7408dd3b"
    private static let bundledPluginArtifactID = "resource:Contents/Resources/open-island-opencode.js"
    private static let bundledPluginArtifactVersion = 1
    private static let bundledPluginTemplateVersion = "1"

    public let openCodeConfigDirectory: URL
    private let fileManager: FileManager
    private let credentialRevoker: () throws -> Void

    public init(
        openCodeConfigDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode", isDirectory: true),
        fileManager: FileManager = .default,
        credentialRevoker: @escaping () throws -> Void = { try BridgeCredentialLifecycle.revokeManagedHookCredential() }
    ) {
        self.openCodeConfigDirectory = openCodeConfigDirectory.standardizedFileURL
        self.fileManager = fileManager
        self.credentialRevoker = credentialRevoker
    }

    private var pluginsDirectory: URL { openCodeConfigDirectory.appendingPathComponent("plugins", isDirectory: true) }
    private var pluginFileURL: URL { pluginsDirectory.appendingPathComponent(Self.pluginFileName) }
    private var configURL: URL { openCodeConfigDirectory.appendingPathComponent("config.json") }
    private var manifestURL: URL { openCodeConfigDirectory.appendingPathComponent(OpenCodePluginInstallerManifest.fileName) }

    /// Status is deliberately read-only: no directories, backups, journals,
    /// configuration, or credentials are touched while inspecting ownership.
    public func status() throws -> OpenCodePluginInstallationStatus {
        do { return try inspect() }
        catch { return baseStatus(outcome: HookManagementOutcome.from(error: error)) }
    }

    @discardableResult
    public func install(pluginSourceURL: URL) throws -> OpenCodePluginInstallationStatus {
        // This must precede even creating ~/.config/opencode.
        let resource = try VerifiedBundledHookArtifact.verifiedResource(at: pluginSourceURL, fileManager: fileManager)
        try validatePluginResource(resource)
        // Classify every existing target and recovery sibling before creating
        // either directory or changing a user-owned configuration file.
        try preflightRead()
        try ensureNoRecoveryJournals()

        let current = try status()
        switch current.managementOutcome {
        case .exactManaged: return current
        case .unowned: break
        default: throw error(for: current.managementOutcome, path: pluginFileURL.path)
        }

        let configData = try checkedData(at: configURL)
        let pluginData = try checkedData(at: pluginFileURL)
        guard pluginData == nil,
              !(try pathExists(sidecar(for: configURL))),
              !(try pathExists(sidecar(for: pluginFileURL))),
              !(try pathExists(manifestURL)),
              !(try backupExists(for: configURL)) else {
            throw ManagedHookFileSystemError.ambiguous(pluginFileURL.path)
        }
        let mutation = try configMutationAddingReference(to: configData)
        guard let configOutput = mutation.data else { throw ManagedHookFileSystemError.ambiguous(configURL.path) }

        try ManagedHookFileSystem.createDirectory(openCodeConfigDirectory, fileManager: fileManager)
        try ManagedHookFileSystem.createDirectory(pluginsDirectory, fileManager: fileManager)
        if configData != nil { try ManagedHookBackupLifecycle.snapshotForMutation(of: configURL, fileManager: fileManager) }
        try replace(resource.data, at: pluginFileURL)
        try recordProvenance(target: pluginFileURL, entryDigest: resource.entry.sha256, preDigest: nil, postData: resource.data, artifact: resource.entry)
        try replace(configOutput, at: configURL)
        try recordProvenance(target: configURL, entryDigest: mutation.entryDigest, preDigest: configData.map(ManagedHookFileSystem.digest), postData: configOutput, artifact: resource.entry)
        return try status()
    }

    /// Raw bytes do not establish bundle provenance and are intentionally not
    /// an alternate installation authority.
    @available(*, deprecated, message: "Install from a manifest-verified bundled resource URL.")
    public func install(pluginSourceData: Data) throws -> OpenCodePluginInstallationStatus {
        throw ManagedHookFileSystemError.digestMismatch(pluginFileURL.path)
    }

    @discardableResult
    public func uninstall() throws -> OpenCodePluginInstallationStatus {
        let current = try status()
        switch current.managementOutcome {
        case .unowned: return current
        case .exactManaged: break
        default: throw error(for: current.managementOutcome, path: pluginFileURL.path)
        }
        try ensureNoRecoveryJournals()
        let configData = try requireData(at: configURL)
        let pluginData = try requireData(at: pluginFileURL)
        let configProvenance = try requireVerifiedProvenance(for: configURL)
        let pluginProvenance = try requireVerifiedProvenance(for: pluginFileURL)
        let configSidecarDigest = try ManagedHookFileSystem.digest(ofFile: ManagedHookProvenance.sidecarURL(for: configURL))
        let pluginSidecarDigest = try ManagedHookFileSystem.digest(ofFile: ManagedHookProvenance.sidecarURL(for: pluginFileURL))
        guard pluginProvenance.managedEntryDigest == ManagedHookFileSystem.digest(of: pluginData),
              let mutation = try configMutationRemovingReference(from: configData, expectedEntryDigest: configProvenance.managedEntryDigest) else {
            throw ManagedHookFileSystemError.ambiguous(pluginFileURL.path)
        }

        try ManagedHookBackupLifecycle.snapshotForMutation(of: configURL, fileManager: fileManager)
        if let data = mutation.data { try replace(data, at: configURL) }
        else { try ManagedHookFileSystem.remove(configURL, expectedDigest: ManagedHookFileSystem.digest(of: configData)) }
        try ManagedHookFileSystem.remove(pluginFileURL, expectedDigest: ManagedHookFileSystem.digest(of: pluginData))
        try ManagedHookFileSystem.remove(ManagedHookProvenance.sidecarURL(for: configURL), expectedDigest: configSidecarDigest)
        try ManagedHookFileSystem.remove(ManagedHookProvenance.sidecarURL(for: pluginFileURL), expectedDigest: pluginSidecarDigest)
        try ManagedHookBackupLifecycle.removeBackup(for: configURL, fileManager: fileManager)
        try credentialRevoker()
        return try status()
    }

    // MARK: - Read-only inspection

    private func inspect() throws -> OpenCodePluginInstallationStatus {
        try preflightRead()
        try ensureNoRecoveryJournals()
        let configData = try checkedData(at: configURL)
        let pluginData = try checkedData(at: pluginFileURL)
        let hasSidecar = try pathExists(sidecar(for: configURL)) || pathExists(sidecar(for: pluginFileURL))
        guard !(try pathExists(manifestURL)) else { throw ManagedHookFileSystemError.ambiguous(manifestURL.path) }
        let parsed = try parsedConfig(configData)
        let references = parsed?.plugins ?? []
        let expected = pluginFileReference()

        if pluginData == nil, !hasSidecar, !references.contains(expected), !references.contains(where: isManagedLookingReference) {
            return baseStatus(pluginPresent: false, registered: false, outcome: .unowned)
        }
        guard let configData, let pluginData,
              references.filter({ $0 == expected }).count == 1,
              !references.contains(where: { $0 != expected && isManagedLookingReference($0) }),
              let configProvenance = try ManagedHookProvenance.loadVerified(for: configURL, managerID: Self.managerID, fileManager: fileManager),
              let pluginProvenance = try ManagedHookProvenance.loadVerified(for: pluginFileURL, managerID: Self.managerID, fileManager: fileManager),
              configProvenance.managedEntryDigest == referenceDigest(expected),
              pluginProvenance.managedEntryDigest == ManagedHookFileSystem.digest(of: pluginData),
              pluginProvenance.managedEntryDigest == Self.bundledPluginDigest,
              try backupIdentityMatches(configProvenance, target: configURL),
              try backupIdentityMatches(pluginProvenance, target: pluginFileURL),
              artifactIdentityMatches(configProvenance), artifactIdentityMatches(pluginProvenance),
              ManagedHookFileSystem.digest(of: configData) == configProvenance.postMutationDigest
        else { throw ManagedHookFileSystemError.ambiguous(pluginFileURL.path) }
        return baseStatus(pluginPresent: true, registered: true, outcome: .exactManaged)
    }

    private func baseStatus(pluginPresent: Bool? = nil, registered: Bool? = nil, outcome: HookManagementOutcome) -> OpenCodePluginInstallationStatus {
        OpenCodePluginInstallationStatus(
            openCodeConfigDirectory: openCodeConfigDirectory, pluginsDirectory: pluginsDirectory, configURL: configURL,
            pluginFileURL: pluginFileURL, manifestURL: manifestURL,
            pluginFilePresent: pluginPresent ?? fileManager.fileExists(atPath: pluginFileURL.path),
            pluginRegistered: registered ?? false, manifest: nil, managementOutcome: outcome
        )
    }

    // MARK: - Exact config and provenance evidence

    private struct ParsedConfig { let object: [String: Any]; let plugins: [String] }
    private struct ConfigMutation { let data: Data?; let entryDigest: String }

    private func parsedConfig(_ data: Data?) throws -> ParsedConfig? {
        guard let data else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ManagedHookFileSystemError.ambiguous(configURL.path) }
        guard let value = object["plugin"] else { return ParsedConfig(object: object, plugins: []) }
        guard let plugins = value as? [String] else { throw ManagedHookFileSystemError.ambiguous(configURL.path) }
        return ParsedConfig(object: object, plugins: plugins)
    }

    private func configMutationAddingReference(to data: Data?) throws -> ConfigMutation {
        var object = try parsedConfig(data)?.object ?? [:]
        let plugins = try parsedConfig(data)?.plugins ?? []
        guard !plugins.contains(where: isManagedLookingReference) else { throw ManagedHookFileSystemError.ambiguous(configURL.path) }
        let expected = pluginFileReference()
        object["plugin"] = plugins + [expected]
        let output = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return ConfigMutation(data: output, entryDigest: referenceDigest(expected))
    }

    private func configMutationRemovingReference(from data: Data, expectedEntryDigest: String) throws -> ConfigMutation? {
        var object = try parsedConfig(data)?.object ?? [:]
        let plugins = try parsedConfig(data)?.plugins ?? []
        let expected = pluginFileReference()
        guard expectedEntryDigest == referenceDigest(expected), plugins.filter({ $0 == expected }).count == 1,
              !plugins.contains(where: { $0 != expected && isManagedLookingReference($0) }) else { return nil }
        let remaining = plugins.filter { $0 != expected }
        if remaining.isEmpty { object.removeValue(forKey: "plugin") } else { object["plugin"] = remaining }
        let output = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return ConfigMutation(data: output, entryDigest: expectedEntryDigest)
    }

    private func pluginFileReference() -> String { "file://\(pluginFileURL.standardizedFileURL.path)" }
    private func referenceDigest(_ reference: String) -> String { ManagedHookFileSystem.digest(of: Data(reference.utf8)) }
    private func isManagedLookingReference(_ reference: String) -> Bool { reference.localizedCaseInsensitiveContains("open-island") }

    private func checkedData(at url: URL) throws -> Data? {
        guard try pathExists(url) else { return nil }
        try ManagedHookFileSystem.validateTarget(url, allowMissing: false)
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func requireData(at url: URL) throws -> Data {
        guard let data = try checkedData(at: url) else { throw ManagedHookFileSystemError.ambiguous(url.path) }
        return data
    }

    private func replace(_ data: Data, at target: URL) throws {
        try ManagedHookFileSystem.replace(data, at: target, expectedDigest: ManagedHookFileSystem.digest(of: data), fileManager: fileManager)
    }

    private func sidecar(for target: URL) -> URL { ManagedHookProvenance.sidecarURL(for: target) }
    private func pathExists(_ url: URL) throws -> Bool { try ManagedHookFileSystem.existsNoFollow(url) }
    private func backupExists(for target: URL) throws -> Bool {
        try pathExists(ManagedHookBackupLifecycle.backupURL(for: target)) ||
            pathExists(ManagedHookBackupLifecycle.metadataURL(for: target))
    }

    private func preflightRead() throws {
        try validateDirectoryForRead(openCodeConfigDirectory)
        try validateDirectoryForRead(pluginsDirectory)
        let targets = [
            configURL, pluginFileURL, manifestURL,
            sidecar(for: configURL), sidecar(for: pluginFileURL),
            ManagedHookBackupLifecycle.backupURL(for: configURL),
            ManagedHookBackupLifecycle.metadataURL(for: configURL),
            ManagedHookFileSystem.journalURL(for: configURL),
            ManagedHookFileSystem.journalURL(for: pluginFileURL),
            ManagedHookFileSystem.journalURL(for: sidecar(for: configURL)),
            ManagedHookFileSystem.journalURL(for: sidecar(for: pluginFileURL)),
        ]
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

    private func ensureNoRecoveryJournals() throws {
        for target in [configURL, pluginFileURL] {
            let journal = ManagedHookFileSystem.journalURL(for: target)
            if try pathExists(journal) { throw ManagedHookFileSystemError.recoveryRequired(journal.path) }
        }
    }

    private func validatePluginResource(_ resource: VerifiedBundledResource) throws {
        guard resource.entry.artifactID == Self.bundledPluginArtifactID,
              resource.entry.version == Self.bundledPluginArtifactVersion,
              resource.entry.relativePath == "Contents/Resources/open-island-opencode.js",
              resource.entry.sha256 == Self.bundledPluginDigest,
              resource.entry.managedMarker == "static-resource",
              resource.entry.templateVersion == Self.bundledPluginTemplateVersion else {
            throw BundledHookArtifactError.invalidManifest(resource.resourceURL.path)
        }
    }

    private func artifactIdentityMatches(_ provenance: ManagedHookProvenance) -> Bool {
        provenance.artifactID == Self.bundledPluginArtifactID &&
        provenance.artifactVersion == Self.bundledPluginArtifactVersion &&
        provenance.artifactSHA256 == Self.bundledPluginDigest &&
        provenance.artifactTemplateVersion == Self.bundledPluginTemplateVersion
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

    private func requireVerifiedProvenance(for target: URL) throws -> ManagedHookProvenance {
        guard let provenance = try ManagedHookProvenance.loadVerified(for: target, managerID: Self.managerID, fileManager: fileManager),
              artifactIdentityMatches(provenance), try backupIdentityMatches(provenance, target: target) else {
            throw ManagedHookFileSystemError.ambiguous(target.path)
        }
        return provenance
    }

    private func recordProvenance(target: URL, entryDigest: String, preDigest: String?, postData: Data, artifact: BundledArtifactManifest.Entry) throws {
        let backup = ManagedHookBackupLifecycle.backupURL(for: target)
        let backupDigest = try pathExists(backup) ? ManagedHookFileSystem.digest(ofFile: backup) : nil
        let provenance = ManagedHookProvenance(targetURL: target, managerID: Self.managerID, formatVersion: artifact.templateVersion,
                                               managedEntryDigest: entryDigest, preMutationDigest: preDigest,
                                               postMutationDigest: ManagedHookFileSystem.digest(of: postData), backupDigest: backupDigest, artifact: artifact)
        try ManagedHookProvenance.record(provenance, for: target, fileManager: fileManager)
    }

    private func error(for outcome: HookManagementOutcome, path: String) -> Error {
        switch outcome {
        case .unsafePath: return ManagedHookFileSystemError.unsafePath(path, "has unsafe ownership, type, or permissions")
        case .unverifiedArtifact: return ManagedHookFileSystemError.digestMismatch(path)
        case .unresolvedRecovery: return ManagedHookFileSystemError.recoveryRequired(path)
        default: return ManagedHookFileSystemError.ambiguous(path)
        }
    }
}
