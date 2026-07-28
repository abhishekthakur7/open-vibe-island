import Foundation

/// The only schema used for persisted session state.  Presentation text,
/// transcript locations, command previews, workspace paths, and terminal
/// handles are deliberately in-memory only.
public struct PersistedSessionMetadata: Codable, Equatable, Sendable {
    /// Required marker so legacy presentation-heavy JSON cannot be mistaken
    /// for this minimized schema during migration.
    public let schemaVersion: Int
    public let sessionID: String
    public let origin: SessionOrigin?
    public let attachmentState: SessionAttachmentState
    public let phase: SessionPhase
    public let outcome: SessionOutcome?
    public let updatedAt: Date
    public let firstSeenAt: Date?

    public init(
        sessionID: String,
        origin: SessionOrigin?,
        attachmentState: SessionAttachmentState,
        phase: SessionPhase,
        outcome: SessionOutcome?,
        updatedAt: Date,
        firstSeenAt: Date? = nil
    ) {
        self.schemaVersion = 1
        self.sessionID = sessionID
        self.origin = origin
        self.attachmentState = attachmentState
        self.phase = phase
        self.outcome = outcome
        self.updatedAt = updatedAt
        self.firstSeenAt = firstSeenAt
    }

    /// Expiration is strict: a record at the exact retention boundary remains
    /// available, and it expires only once it is older than that boundary.
    public func isExpired(referenceDate: Date) -> Bool {
        updatedAt < referenceDate.addingTimeInterval(-LocalDataLifecycle.sessionMetadataRetention)
    }

    public var isExpired: Bool {
        isExpired(referenceDate: .now)
    }
}

/// Shared privacy boundary for application-owned local session metadata.
public enum LocalDataLifecycle {
    public static let sessionMetadataRetention: TimeInterval = 30 * 24 * 60 * 60
    public static let contentRetention: TimeInterval = 7 * 24 * 60 * 60

    public static func readMetadata(
        from fileURL: URL,
        fileManager: FileManager = .default,
        referenceDate: Date = .now
    ) throws -> [PersistedSessionMetadata]? {
        try cleanupInterruptedWriteArtifacts(for: fileURL, fileManager: fileManager)
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([PersistedSessionMetadata].self, from: Data(contentsOf: fileURL))
    }

    public static func writeMetadata(
        _ records: [PersistedSessionMetadata],
        to fileURL: URL,
        fileManager: FileManager = .default,
        referenceDate: Date = .now
    ) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        try cleanupInterruptedWriteArtifacts(for: fileURL, fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records.filter { !$0.isExpired(referenceDate: referenceDate) }).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Removes stale temporary siblings left by an interrupted atomic write.
    /// The canonical file is never considered a cleanup candidate. Symlinks
    /// are deliberately left alone for the later hook-hardening work.
    public static func cleanupInterruptedWriteArtifacts(
        for fileURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        let prefix = ".\(fileURL.lastPathComponent)."
        for candidate in try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) where candidate.lastPathComponent.hasPrefix(prefix) {
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            try fileManager.removeItem(at: candidate)
        }
    }

    public static func removeLocalHistory(
        fileURLs: [URL],
        fileManager: FileManager = .default
    ) throws {
        for url in fileURLs where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

public enum LocalHistoryStore {
    public static var sessionFiles: [URL] {
        [
            CodexSessionStore.defaultFileURL,
            ClaudeSessionRegistry.defaultFileURL,
            OpenCodeSessionRegistry.defaultFileURL,
            CursorSessionRegistry.defaultFileURL,
        ]
    }

    public static var clearableFiles: [URL] {
        sessionFiles + [ClaudeUsageLoader.defaultCacheURL]
    }

    /// Clear History deletes app-owned session metadata only.  It never touches
    /// hook backups, preferences, or Keychain bridge credentials.
    public static func clear(
        fileURLs: [URL] = clearableFiles,
        fileManager: FileManager = .default
    ) throws {
        try LocalDataLifecycle.removeLocalHistory(fileURLs: fileURLs, fileManager: fileManager)
    }
}
