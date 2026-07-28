import Foundation

/// Lifecycle for the one reversible backup Open Island may keep beside a
/// managed third-party configuration target. This deliberately manages only
/// the conventional backup siblings created by earlier Open Island releases.
/// Atomic target replacement and stronger path validation remain Round 8 work.
public enum ManagedHookBackupLifecycle {
    public static let retention: TimeInterval = LocalDataLifecycle.sessionMetadataRetention
    public static let filenameSuffix = "backup.open-island"

    public static func backupURL(for targetURL: URL) -> URL {
        targetURL.appendingPathExtension(filenameSuffix)
    }

    /// Creates the sole backup for a target. Existing Open Island timestamped
    /// backups are pruned, so a target never accumulates an unbounded series.
    public static func createBackup(
        of targetURL: URL,
        fileManager: FileManager = .default,
        referenceDate: Date = .now
    ) throws {
        guard fileManager.fileExists(atPath: targetURL.path) else { return }
        try validateRegularNonSymlink(targetURL)
        try removeBackups(for: targetURL, fileManager: fileManager, referenceDate: referenceDate, retainCurrent: false)

        let backupURL = backupURL(for: targetURL)
        try fileManager.copyItem(at: targetURL, to: backupURL)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
    }

    /// Removes backups after a successful uninstall or restore. It is
    /// intentionally idempotent so recovery cleanup also tolerates an already
    /// removed file.
    public static func removeBackup(
        for targetURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try removeBackups(for: targetURL, fileManager: fileManager, referenceDate: .now, retainCurrent: false)
    }

    /// Removes expired backup siblings without touching a current backup.
    /// Managers call this during status and mutation paths, so launch/status
    /// checks also enforce the 30-day retention ceiling.
    public static func pruneExpiredBackups(
        for targetURL: URL,
        fileManager: FileManager = .default,
        referenceDate: Date = .now
    ) throws {
        try removeBackups(for: targetURL, fileManager: fileManager, referenceDate: referenceDate, retainCurrent: true)
    }

    private static func removeBackups(
        for targetURL: URL,
        fileManager: FileManager,
        referenceDate: Date,
        retainCurrent: Bool
    ) throws {
        let candidates = try backupCandidates(for: targetURL, fileManager: fileManager)
        let currentBackupURL = backupURL(for: targetURL).standardizedFileURL
        let cutoff = referenceDate.addingTimeInterval(-retention)

        for candidate in candidates {
            try validateRegularNonSymlink(candidate)
            let isCurrent = candidate.standardizedFileURL == currentBackupURL
            let modifiedAt = (try fileManager.attributesOfItem(atPath: candidate.path)[.modificationDate] as? Date) ?? .distantPast
            if !retainCurrent || modifiedAt < cutoff || !isCurrent {
                try fileManager.removeItem(at: candidate)
            }
        }
    }

    private static func backupCandidates(for targetURL: URL, fileManager: FileManager) throws -> [URL] {
        let directoryURL = targetURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        let prefix = "\(targetURL.lastPathComponent).backup."
        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    private static func validateRegularNonSymlink(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ManagedHookBackupError.unsafeBackupPath(url.path)
        }
    }
}

public enum ManagedHookBackupError: LocalizedError, Sendable {
    case unsafeBackupPath(String)

    public var errorDescription: String? {
        switch self {
        case let .unsafeBackupPath(path):
            return "Open Island will not follow or replace an unsafe hook backup path: \(path)"
        }
    }
}
