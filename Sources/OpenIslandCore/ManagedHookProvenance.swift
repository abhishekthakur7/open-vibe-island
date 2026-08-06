import Foundation

/// Immutable, adjacent evidence that a target was written by this build.
///
/// A config marker, command substring, manifest filename, or plugin suffix is
/// deliberately insufficient for ownership.  This record is private and is
/// checked before any destructive operation.  It contains only identities and
/// digests; it never copies user configuration content.
public struct ManagedHookProvenance: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let marker = "open-island-managed-provenance"

    public var schemaVersion: Int
    public var marker: String
    public var targetPath: String
    public var managerID: String
    public var formatVersion: String
    public var managedEntryDigest: String
    public var preMutationDigest: String?
    public var postMutationDigest: String
    public var backupDigest: String?
    public var artifactID: String?
    public var artifactVersion: Int?
    public var artifactSHA256: String?
    public var artifactTemplateVersion: String?
    /// Required for the shared executable helper. Optional to preserve
    /// compatibility with existing configuration provenance records.
    public var artifactExpectedMode: UInt16?
    public var artifactManagedMarker: String?
    public var backupPath: String
    public var generation: String

    public init(
        targetURL: URL,
        managerID: String,
        formatVersion: String,
        managedEntryDigest: String,
        preMutationDigest: String?,
        postMutationDigest: String,
        backupDigest: String?,
        artifact: BundledArtifactManifest.Entry? = nil,
        generation: String = UUID().uuidString
    ) {
        self.schemaVersion = Self.schemaVersion
        self.marker = Self.marker
        self.targetPath = targetURL.standardizedFileURL.path
        self.managerID = managerID
        self.formatVersion = formatVersion
        self.managedEntryDigest = managedEntryDigest
        self.preMutationDigest = preMutationDigest
        self.postMutationDigest = postMutationDigest
        self.backupDigest = backupDigest
        self.artifactID = artifact?.artifactID
        self.artifactVersion = artifact?.version
        self.artifactSHA256 = artifact?.sha256
        self.artifactTemplateVersion = artifact?.templateVersion
        self.artifactExpectedMode = artifact?.expectedMode
        self.artifactManagedMarker = artifact?.managedMarker
        self.backupPath = ManagedHookBackupLifecycle.backupURL(for: targetURL).standardizedFileURL.path
        self.generation = generation
    }

    /// How exclusively Open Island owns the bytes of a target file.
    ///
    /// This selects the correct whole-file invariant.  It is not a relaxation
    /// knob: a `.shared` caller must still prove ownership with
    /// `managedEntryDigest` recomputed from the target's current content.
    public enum TargetOwnership: Sendable, Equatable {
        /// Open Island created the file and is its only writer — manifests, the
        /// bundled helper, generated plugin and script files.  Every byte is
        /// ours, so `postMutationDigest` equality is a valid tamper check.
        case exclusive
        /// A host-tool configuration Open Island appends entries to and shares
        /// with its owner and other integrations — `hooks.json`,
        /// `settings.json`, `config.toml`, `opencode.json`.  Co-tenants
        /// legitimately add their own entries and re-serialize the whole file
        /// with a different key order or escaping, so whole-file equality
        /// measures co-tenancy rather than ownership and must not be used.
        case shared
    }

    /// Whether this record's `managedEntryDigest` identifies `expected`.
    ///
    /// Records written before the entry digest was scoped to the managed
    /// entries stored the digest of the entire target file, which cannot be
    /// re-derived once a co-tenant edits that file.  Such a record is
    /// recognized by its entry digest being its whole-file digest, and is
    /// satisfied by the caller's separate proof that the exact managed entries
    /// are present — the same evidence the digest was standing in for.
    public func identifiesManagedEntries(_ expected: String) -> Bool {
        managedEntryDigest == expected || managedEntryDigest == postMutationDigest
    }

    public static func sidecarURL(for targetURL: URL) -> URL {
        targetURL.deletingLastPathComponent()
            .appendingPathComponent(".\(targetURL.lastPathComponent).open-island-provenance.json")
    }

    /// Returns nil when no provenance exists.  A present but malformed,
    /// foreign, stale, or tampered sidecar is an ambiguity, never an excuse to
    /// overwrite it.
    ///
    /// `ownership` defaults to `.exclusive` so an unconsidered call site keeps
    /// the strictest check.  Pass `.shared` only for a target whose caller
    /// verifies `managedEntryDigest` against the current content.
    public static func loadVerified(
        for targetURL: URL,
        managerID: String,
        ownership: TargetOwnership = .exclusive,
        fileManager: FileManager = .default
    ) throws -> ManagedHookProvenance? {
        let sidecar = sidecarURL(for: targetURL)
        guard try ManagedHookFileSystem.existsNoFollow(sidecar) else { return nil }
        try ManagedHookFileSystem.validateTarget(sidecar, allowMissing: false)
        let mode = (try fileManager.attributesOfItem(atPath: sidecar.path)[.posixPermissions] as? NSNumber)?.intValue
        guard mode == 0o600 else { throw ManagedHookFileSystemError.ambiguous(sidecar.path) }
        let record: ManagedHookProvenance
        do { record = try JSONDecoder().decode(ManagedHookProvenance.self, from: Data(contentsOf: sidecar, options: [.mappedIfSafe])) }
        catch { throw ManagedHookFileSystemError.ambiguous(sidecar.path) }
        guard record.schemaVersion == schemaVersion,
              record.marker == marker,
              record.targetPath == targetURL.standardizedFileURL.path,
              record.managerID == managerID,
              !record.formatVersion.isEmpty,
              !record.managedEntryDigest.isEmpty,
              !record.postMutationDigest.isEmpty,
              record.backupPath == ManagedHookBackupLifecycle.backupURL(for: targetURL).standardizedFileURL.path,
              !record.generation.isEmpty,
              // The target must still exist and be readable under either
              // ownership: a record pointing at nothing proves nothing.
              let digest = try? ManagedHookFileSystem.digest(ofFile: targetURL),
              ownership == .shared || digest == record.postMutationDigest
        else { throw ManagedHookFileSystemError.ambiguous(sidecar.path) }
        return record
    }

    /// Persist only after target replacement has completed and fsynced.
    /// Existing provenance may be updated only when it is structurally for the
    /// same target/manager; a user-created sibling remains untouched.
    public static func record(
        _ record: ManagedHookProvenance,
        for targetURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let sidecar = sidecarURL(for: targetURL)
        if try ManagedHookFileSystem.existsNoFollow(sidecar) {
            try ManagedHookFileSystem.validateTarget(sidecar, allowMissing: false)
            let existing: ManagedHookProvenance
            do { existing = try JSONDecoder().decode(ManagedHookProvenance.self, from: Data(contentsOf: sidecar, options: [.mappedIfSafe])) }
            catch { throw ManagedHookFileSystemError.ambiguous(sidecar.path) }
            guard existing.schemaVersion == schemaVersion,
                  existing.marker == marker,
                  existing.targetPath == targetURL.standardizedFileURL.path,
                  existing.managerID == record.managerID else {
                throw ManagedHookFileSystemError.ambiguous(sidecar.path)
            }
        }
        let data = try JSONEncoder().encode(record)
        try ManagedHookFileSystem.replace(data, at: sidecar, mode: 0o600, expectedDigest: ManagedHookFileSystem.digest(of: data), fileManager: fileManager)
    }

    public static func removeVerified(
        for targetURL: URL,
        managerID: String,
        ownership: TargetOwnership = .exclusive,
        fileManager: FileManager = .default
    ) throws {
        guard let _ = try loadVerified(for: targetURL, managerID: managerID, ownership: ownership, fileManager: fileManager) else { return }
        let sidecar = sidecarURL(for: targetURL)
        try ManagedHookFileSystem.remove(sidecar, expectedDigest: try ManagedHookFileSystem.digest(ofFile: sidecar))
    }
}
