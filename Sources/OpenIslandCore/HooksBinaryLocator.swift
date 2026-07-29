import Foundation

public enum ManagedHooksBinary {
    public static let binaryName = "OpenIslandHooks"
    public static let legacyBinaryName = "VibeIslandHooks"
    private static let provenanceManagerID = "open-island-hooks-binary"
    private static let provenanceFormatVersion = "1"

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        installDirectory(fileManager: fileManager)
            .appendingPathComponent(binaryName)
            .standardizedFileURL
    }

    public static func candidateURLs(fileManager: FileManager = .default) -> [URL] {
        [
            defaultURL(fileManager: fileManager),
            legacyInstallDirectory(fileManager: fileManager)
                .appendingPathComponent(legacyBinaryName)
                .standardizedFileURL,
        ]
    }

    @discardableResult
    public static func install(
        from artifact: VerifiedBundledHookArtifact,
        to destinationURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        // Re-verify here: callers cannot turn a previously checked, mutable
        // URL or a caller-computed digest into installation authority.
        let verifiedArtifact = try VerifiedBundledHookArtifact.verify(bundleURL: artifact.bundleURL, fileManager: fileManager)
        guard verifiedArtifact == artifact else {
            throw ManagedHookFileSystemError.digestMismatch(artifact.helperURL.path)
        }
        let resolvedSourceURL = verifiedArtifact.helperURL
        let resolvedDestinationURL = (destinationURL ?? defaultURL(fileManager: fileManager)).standardizedFileURL
        let sourceData = try Data(contentsOf: resolvedSourceURL, options: [.mappedIfSafe])
        let digest = ManagedHookFileSystem.digest(of: sourceData)
        guard verifiedArtifact.entry.sha256 == digest else {
            throw ManagedHookFileSystemError.digestMismatch(resolvedSourceURL.path)
        }

        // Source verification is complete before creating any destination
        // directory. A recovery journal is evidence of an interrupted write,
        // not authorization to repair or replace a helper during install.
        try ManagedHookFileSystem.createDirectory(resolvedDestinationURL.deletingLastPathComponent(), fileManager: fileManager)
        let journal = ManagedHookFileSystem.journalURL(for: resolvedDestinationURL)
        guard !(try ManagedHookFileSystem.existsNoFollow(journal)) else {
            throw ManagedHookFileSystemError.recoveryRequired(journal.path)
        }

        let targetExists = try ManagedHookFileSystem.existsNoFollow(resolvedDestinationURL)
        let sidecar = ManagedHookProvenance.sidecarURL(for: resolvedDestinationURL)
        let sidecarExists = try ManagedHookFileSystem.existsNoFollow(sidecar)
        let priorRecord: ManagedHookProvenance?
        if !targetExists {
            guard !sidecarExists else { throw ManagedHookFileSystemError.ambiguous(sidecar.path) }
            priorRecord = nil
        } else {
            guard sidecarExists,
                  let existing = try ManagedHookProvenance.loadVerified(
                    for: resolvedDestinationURL,
                    managerID: provenanceManagerID,
                    fileManager: fileManager
                  ),
                  isExactHelperProvenance(existing, destinationURL: resolvedDestinationURL, fileManager: fileManager)
            else { throw ManagedHookFileSystemError.ambiguous(resolvedDestinationURL.path) }

            let installedMode = try mode(of: resolvedDestinationURL, fileManager: fileManager)
            if existing.postMutationDigest == digest,
               installedMode == verifiedArtifact.entry.expectedMode,
               provenance(existing, matches: verifiedArtifact.entry, digest: digest) {
                return resolvedDestinationURL
            }
            priorRecord = existing
        }

        try ManagedHookFileSystem.replace(
            sourceData,
            at: resolvedDestinationURL,
            mode: mode_t(verifiedArtifact.entry.expectedMode),
            expectedDigest: digest,
            fileManager: fileManager
        )
        let record = ManagedHookProvenance(
            targetURL: resolvedDestinationURL,
            managerID: provenanceManagerID,
            formatVersion: provenanceFormatVersion,
            managedEntryDigest: digest,
            preMutationDigest: priorRecord?.postMutationDigest,
            postMutationDigest: digest,
            backupDigest: nil,
            artifact: verifiedArtifact.entry
        )
        try ManagedHookProvenance.record(record, for: resolvedDestinationURL, fileManager: fileManager)
        try ManagedHookFileSystem.validateTarget(resolvedDestinationURL, allowMissing: false)
        return resolvedDestinationURL
    }

    /// Read-only provenance classification for health and status surfaces.
    public static func managementOutcome(
        at destinationURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> HookManagementOutcome {
        let destination = (destinationURL ?? defaultURL(fileManager: fileManager)).standardizedFileURL
        do {
            let targetExists = try ManagedHookFileSystem.existsNoFollow(destination)
            let sidecar = ManagedHookProvenance.sidecarURL(for: destination)
            let sidecarExists = try ManagedHookFileSystem.existsNoFollow(sidecar)
            guard targetExists || sidecarExists else { return .unowned }
            if targetExists { try ManagedHookFileSystem.validateTarget(destination, allowMissing: false) }
            if sidecarExists { try ManagedHookFileSystem.validateTarget(sidecar, allowMissing: false) }
            guard targetExists, sidecarExists,
                  let record = try ManagedHookProvenance.loadVerified(for: destination, managerID: provenanceManagerID, fileManager: fileManager),
                  isExactHelperProvenance(record, destinationURL: destination, fileManager: fileManager)
            else { return .ambiguousUnmanaged }
            return .exactManaged
        } catch {
            return HookManagementOutcome.from(error: error)
        }
    }

    /// The shared helper is retained while individual integrations are
    /// removed. Reset Integrations calls this only after every manager has
    /// uninstalled and bridge credentials have been revoked.
    @discardableResult
    public static func removeVerified(
        at destinationURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let destination = (destinationURL ?? defaultURL(fileManager: fileManager)).standardizedFileURL
        let targetExists = try ManagedHookFileSystem.existsNoFollow(destination)
        let sidecar = ManagedHookProvenance.sidecarURL(for: destination)
        let sidecarExists = try ManagedHookFileSystem.existsNoFollow(sidecar)
        guard targetExists || sidecarExists else { return false }
        guard targetExists, sidecarExists,
              let record = try ManagedHookProvenance.loadVerified(for: destination, managerID: provenanceManagerID, fileManager: fileManager),
              isExactHelperProvenance(record, destinationURL: destination, fileManager: fileManager)
        else { throw ManagedHookFileSystemError.ambiguous(destination.path) }
        let sidecarDigest = try ManagedHookFileSystem.digest(ofFile: sidecar)
        try ManagedHookFileSystem.remove(destination, expectedDigest: record.postMutationDigest)
        try ManagedHookFileSystem.remove(sidecar, expectedDigest: sidecarDigest)
        return true
    }

    private static func mode(of url: URL, fileManager: FileManager) throws -> UInt16 {
        guard let permissions = try fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber else {
            throw ManagedHookFileSystemError.ambiguous(url.path)
        }
        return permissions.uint16Value
    }

    private static func isExactHelperProvenance(
        _ record: ManagedHookProvenance,
        destinationURL: URL,
        fileManager: FileManager
    ) -> Bool {
        record.formatVersion == provenanceFormatVersion &&
        record.targetPath == destinationURL.standardizedFileURL.path &&
        record.managedEntryDigest == record.postMutationDigest &&
        record.artifactID == VerifiedBundledHookArtifact.helperID &&
        record.artifactVersion != nil &&
        record.artifactSHA256 == record.postMutationDigest &&
        record.artifactExpectedMode != nil &&
        record.artifactManagedMarker == "OpenIslandHooks" &&
        !(record.artifactTemplateVersion ?? "").isEmpty &&
        (try? mode(of: destinationURL, fileManager: fileManager)) == record.artifactExpectedMode
    }

    private static func provenance(_ record: ManagedHookProvenance, matches entry: BundledArtifactManifest.Entry, digest: String) -> Bool {
        record.artifactID == entry.artifactID &&
        record.artifactVersion == entry.version &&
        record.artifactSHA256 == entry.sha256 &&
        record.artifactExpectedMode == entry.expectedMode &&
        record.artifactManagedMarker == entry.managedMarker &&
        record.artifactTemplateVersion == entry.templateVersion &&
        record.managedEntryDigest == digest && record.postMutationDigest == digest
    }

    private static func installDirectory(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("OpenIsland", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    private static func legacyInstallDirectory(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("VibeIsland", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }
}

public enum HooksBinaryLocator {
    public static func locateArtifact(
        fileManager: FileManager = .default,
        executableDirectory: URL? = nil
    ) -> VerifiedBundledHookArtifact? {
        guard let executableDirectory else { return nil }
        let bundleURL = executableDirectory.deletingLastPathComponent().deletingLastPathComponent()
        return try? VerifiedBundledHookArtifact.verify(bundleURL: bundleURL, fileManager: fileManager)
    }

    public static func locate(
        fileManager: FileManager = .default,
        currentDirectory: URL? = nil,
        executableDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        _ = currentDirectory
        _ = environment
        return locateArtifact(fileManager: fileManager, executableDirectory: executableDirectory)?.helperURL
    }
}
