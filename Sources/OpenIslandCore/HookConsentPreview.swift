import Darwin
import Foundation

/// An exact, immutable description of one user-approved hook mutation.  It is
/// intentionally constructed from a verified bundled source plus the concrete
/// targets selected by a manager; UI copy is never installation authority.
public struct HookConsentPreview: Sendable, Equatable, Identifiable {
    /// A no-follow observation of a path that was shown to the user.  The
    /// confirmation is invalid when *any* part of this observation changes;
    /// a path name alone is never consent for whatever happens to be there
    /// later.
    public struct TargetSnapshot: Sendable, Equatable, Identifiable {
        public let canonicalPath: String
        public let exists: Bool
        public let fileType: String
        public let ownerID: UInt32?
        public let linkCount: UInt64?
        public let mode: UInt16?
        public let sha256: String?
        public let provenanceGeneration: String?
        public let provenanceArtifactID: String?
        public let provenanceArtifactVersion: Int?
        public let managementOutcome: HookManagementOutcome

        public var id: String { canonicalPath }

        public init(url: URL, managementOutcome: HookManagementOutcome) {
            let url = url.standardizedFileURL
            canonicalPath = url.path
            self.managementOutcome = managementOutcome
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                exists = false
                fileType = "absent"
                ownerID = nil
                linkCount = nil
                mode = nil
                sha256 = nil
                provenanceGeneration = nil
                provenanceArtifactID = nil
                provenanceArtifactVersion = nil
                return
            }

            exists = true
            ownerID = info.st_uid
            linkCount = UInt64(info.st_nlink)
            mode = UInt16(info.st_mode & 0o7777)
            switch info.st_mode & S_IFMT {
            case S_IFREG: fileType = "regular"
            case S_IFDIR: fileType = "directory"
            case S_IFLNK: fileType = "symlink"
            default: fileType = "other"
            }
            // Never follow a link in order to hash it.  A regular-file hash is
            // the exact-byte component of the consent binding.
            sha256 = fileType == "regular" ? try? ManagedHookFileSystem.digest(ofFile: url) : nil
            let provenance = Self.provenance(at: url)
            provenanceGeneration = provenance?.generation
            provenanceArtifactID = provenance?.artifactID
            provenanceArtifactVersion = provenance?.artifactVersion
        }

        private static func provenance(at url: URL) -> ManagedHookProvenance? {
            guard url.lastPathComponent.hasSuffix(".open-island-provenance.json"),
                  let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  let record = try? JSONDecoder().decode(ManagedHookProvenance.self, from: data) else {
                return nil
            }
            return record
        }
    }

    public struct Target: Sendable, Equatable {
        public let integrationID: String
        public let targetPaths: [String]
        public let requestedModes: [String]
        public let managedAdditions: [String]
        public let managedRemovals: [String]
        public let backupPaths: [String]
        public let journalPaths: [String]
        public let provenancePaths: [String]
        public let backupRetentionDays: Int
        public let involvesWrapping: Bool
        public let involvesRestoration: Bool
        public let snapshots: [TargetSnapshot]
        public let managementOutcome: HookManagementOutcome

        public init(
            integrationID: String,
            targetURLs: [URL],
            requestedModes: [String],
            managedAdditions: [String],
            managedRemovals: [String] = [],
            backupURLs: [URL] = [],
            journalURLs: [URL] = [],
            provenanceURLs: [URL] = [],
            backupRetentionDays: Int = 30,
            involvesWrapping: Bool = false,
            involvesRestoration: Bool = false,
            managementOutcome: HookManagementOutcome = .unowned
        ) {
            self.integrationID = integrationID
            self.targetPaths = targetURLs.map { $0.standardizedFileURL.path }.sorted()
            self.requestedModes = requestedModes.sorted()
            self.managedAdditions = managedAdditions.sorted()
            self.managedRemovals = managedRemovals.sorted()
            self.backupPaths = backupURLs.map { $0.standardizedFileURL.path }.sorted()
            self.journalPaths = journalURLs.map { $0.standardizedFileURL.path }.sorted()
            self.provenancePaths = provenanceURLs.map { $0.standardizedFileURL.path }.sorted()
            self.backupRetentionDays = backupRetentionDays
            self.involvesWrapping = involvesWrapping
            self.involvesRestoration = involvesRestoration
            self.managementOutcome = managementOutcome
            // Sidecars, journals, and backups are mutation inputs too.  They
            // are therefore part of the snapshot, rather than merely UI copy.
            self.snapshots = Array(Set((targetURLs + backupURLs + journalURLs + provenanceURLs).map { $0.standardizedFileURL.path }))
                .sorted()
                .map { TargetSnapshot(url: URL(fileURLWithPath: $0), managementOutcome: managementOutcome) }
        }
    }

    public let id: String
    public let integrationID: String
    public let sourceID: String
    public let artifactVersion: Int
    public let sha256: String
    public let digestPrefix: String
    public let sourceBundlePath: String
    public let target: Target

    public var targetPaths: [String] { target.targetPaths }
    public var requestedModes: [String] { target.requestedModes }
    public var managedAdditions: [String] { target.managedAdditions }
    public var managedRemovals: [String] { target.managedRemovals }
    public var backupPaths: [String] { target.backupPaths }
    public var journalPaths: [String] { target.journalPaths }
    public var provenancePaths: [String] { target.provenancePaths }
    public var involvesWrapping: Bool { target.involvesWrapping }
    public var involvesRestoration: Bool { target.involvesRestoration }
    public var targetSnapshots: [TargetSnapshot] { target.snapshots }

    public init(artifact: VerifiedBundledHookArtifact, target: Target) {
        self.init(entry: artifact.entry, target: target)
    }

    public init(resource: VerifiedBundledResource, target: Target) {
        self.init(entry: resource.entry, target: target)
    }

    public init(template: VerifiedHookTemplateDescriptor, target: Target) {
        self.init(entry: template.entry, target: target)
    }

    /// Retains the already-verified source identity while describing a
    /// different, explicit operation over the same integration state.
    public init(reusing source: HookConsentPreview, target: Target) {
        integrationID = target.integrationID
        sourceID = source.sourceID
        artifactVersion = source.artifactVersion
        sha256 = source.sha256
        digestPrefix = source.digestPrefix
        sourceBundlePath = source.sourceBundlePath
        self.target = target
        id = "\(target.integrationID):\(source.sourceID):\(source.artifactVersion):\(source.sha256):\(target.targetPaths.joined(separator: ",")):remove"
    }

    /// A removal does not consume a bundled source.  Its authority is the
    /// exact, sidecar-backed state already present on disk, so represent it
    /// explicitly rather than pretending a currently bundled helper is an
    /// input to uninstall.
    public init(removalTarget target: Target) {
        integrationID = target.integrationID
        sourceID = "managed-state-removal"
        artifactVersion = 0
        sha256 = ""
        digestPrefix = ""
        sourceBundlePath = "managed state already on disk"
        self.target = target
        id = "\(target.integrationID):managed-state-removal:\(target.targetPaths.joined(separator: ","))"
    }

    private init(entry: BundledArtifactManifest.Entry, target: Target) {
        self.integrationID = target.integrationID
        self.sourceID = entry.artifactID
        self.artifactVersion = entry.version
        self.sha256 = entry.sha256
        self.digestPrefix = String(entry.sha256.prefix(12))
        self.sourceBundlePath = entry.relativePath
        self.target = target
        self.id = "\(target.integrationID):\(entry.artifactID):\(entry.version):\(entry.sha256):\(target.targetPaths.joined(separator: ","))"
    }
}

/// A single confirmation for Reset Integrations.  It intentionally preserves
/// member order: the order shown to the user is the order the coordinator
/// revalidates and then removes.  Any unsafe, ambiguous, or unresolved member
/// blocks the *entire* reset before the first manager is invoked.
public struct HookAggregateConsentPreview: Sendable, Equatable, Identifiable {
    public let members: [HookConsentPreview]
    public let intentKeys: [String]
    public let credentialRoles: [String]
    public let executionOrder: [String]

    public init(
        members: [HookConsentPreview],
        intentKeys: [String],
        credentialRoles: [String],
        executionOrder: [String]
    ) {
        self.members = members
        self.intentKeys = intentKeys.sorted()
        self.credentialRoles = credentialRoles.sorted()
        self.executionOrder = executionOrder
    }

    public var id: String {
        members.map(\.id).joined(separator: "|") + "|" + intentKeys.joined(separator: ",") + "|" + credentialRoles.joined(separator: ",")
    }

    public var targetSnapshots: [HookConsentPreview.TargetSnapshot] {
        members.flatMap(\.targetSnapshots)
    }

    public var blockingMembers: [HookConsentPreview] {
        members.filter { member in
            member.target.managementOutcome != .exactManaged && member.target.managementOutcome != .unowned
        }
    }

    public var isSafeToExecute: Bool { blockingMembers.isEmpty }

    public func matchesRevalidation(_ current: HookAggregateConsentPreview) -> Bool {
        intentKeys == current.intentKeys &&
            credentialRoles == current.credentialRoles &&
            executionOrder == current.executionOrder &&
            members.count == current.members.count &&
            zip(members, current.members).allSatisfy { $0.matchesRevalidation($1) }
    }
}

public extension HookConsentPreview {
    /// Re-observe every path just before mutation.  Artifact identity and
    /// target state must agree with the displayed preview exactly.
    func matchesRevalidation(_ current: HookConsentPreview) -> Bool {
        integrationID == current.integrationID &&
            sourceID == current.sourceID &&
            artifactVersion == current.artifactVersion &&
            sha256 == current.sha256 &&
            target.targetPaths == current.target.targetPaths &&
            target.requestedModes == current.target.requestedModes &&
            target.managedAdditions == current.target.managedAdditions &&
            target.managedRemovals == current.target.managedRemovals &&
            target.snapshots == current.target.snapshots
    }
}

/// A template descriptor is deliberately opaque outside OpenIslandCore.  The
/// status-line manager is the only producer and verifies its built-in bytes
/// before exposing it for consent.
public struct VerifiedHookTemplateDescriptor: Sendable, Equatable {
    public let entry: BundledArtifactManifest.Entry
    init(entry: BundledArtifactManifest.Entry) { self.entry = entry }
}

/// One-shot confirmation ledger used by UI coordinators.  Calling `consume`
/// without a preceding explicit `confirm` returns false and must not mutate.
public final class HookConsentGate: @unchecked Sendable {
    public struct Token: Sendable, Equatable {
        fileprivate let value: UUID
    }

    private enum ConfirmedPreview: Equatable {
        case single(HookConsentPreview)
        case aggregate(HookAggregateConsentPreview)
    }

    private struct Confirmation {
        let preview: ConfirmedPreview
        let expiresAt: Date
    }

    private let lock = NSLock()
    private let lifetime: TimeInterval
    private var confirmed: [UUID: Confirmation] = [:]

    public init(lifetime: TimeInterval = 60) { self.lifetime = lifetime }

    /// Tokens are process-local, short-lived, and can be consumed once only.
    @discardableResult
    public func confirm(_ preview: HookConsentPreview, now: Date = .now) -> Token {
        lock.withLock {
            let token = Token(value: UUID())
            confirmed[token.value] = Confirmation(preview: .single(preview), expiresAt: now.addingTimeInterval(lifetime))
            return token
        }
    }

    public func consume(_ token: Token, preview: HookConsentPreview, revalidatedAs current: HookConsentPreview, now: Date = .now) -> Bool {
        lock.withLock {
            guard let confirmation = confirmed.removeValue(forKey: token.value),
                  confirmation.expiresAt >= now,
                  confirmation.preview == .single(preview),
                  preview.matchesRevalidation(current) else {
                return false
            }
            return true
        }
    }

    @discardableResult
    public func confirm(_ preview: HookAggregateConsentPreview, now: Date = .now) -> Token {
        lock.withLock {
            let token = Token(value: UUID())
            confirmed[token.value] = Confirmation(preview: .aggregate(preview), expiresAt: now.addingTimeInterval(lifetime))
            return token
        }
    }

    public func consume(
        _ token: Token,
        aggregate preview: HookAggregateConsentPreview,
        revalidatedAs current: HookAggregateConsentPreview,
        now: Date = .now
    ) -> Bool {
        lock.withLock {
            guard let confirmation = confirmed.removeValue(forKey: token.value),
                  confirmation.expiresAt >= now,
                  confirmation.preview == .aggregate(preview),
                  preview.matchesRevalidation(current),
                  preview.isSafeToExecute else {
                return false
            }
            return true
        }
    }
}
