import Foundation

/// Lifecycle for the one reversible backup Open Island may keep beside a
/// managed third-party configuration target. Backups are accepted only when
/// they are regular current-user files; an ambiguous sibling is never replaced
/// or removed on the assumption that Open Island owns it.
public enum ManagedHookBackupLifecycle {
    public static let retention: TimeInterval = LocalDataLifecycle.sessionMetadataRetention
    public static let filenameSuffix = "backup.open-island"

    public static func backupURL(for targetURL: URL) -> URL {
        targetURL.appendingPathExtension(filenameSuffix)
    }

    public static func metadataURL(for targetURL: URL) -> URL {
        backupURL(for: targetURL).appendingPathExtension("meta")
    }

    /// Creates the sole backup for a target. Existing Open Island timestamped
    /// backups are pruned, so a target never accumulates an unbounded series.
    public static func createBackup(
        of targetURL: URL,
        fileManager: FileManager = .default,
        referenceDate: Date = .now
    ) throws {
        guard fileManager.fileExists(atPath: targetURL.path) else { return }
        try ManagedHookFileSystem.validateTarget(targetURL, allowMissing: false)

        let backupURL = backupURL(for: targetURL)
        if fileManager.fileExists(atPath: backupURL.path) {
            guard try isVerifiedBackup(for: targetURL, fileManager: fileManager) else {
                throw ManagedHookBackupError.unmanagedBackupPath(backupURL.path)
            }
            return
        }
        // Never clear a sibling merely because it has our filename.  A stale
        // or manually created backup is ambiguous ownership, not permission to
        // overwrite it. Timestamped legacy siblings may still be pruned.
        try removeBackups(for: targetURL, fileManager: fileManager, referenceDate: referenceDate, retainCurrent: true)
        let contents = try Data(contentsOf: targetURL, options: [.mappedIfSafe])
        try ManagedHookFileSystem.replace(contents, at: backupURL, mode: 0o600, expectedDigest: ManagedHookFileSystem.digest(of: contents), fileManager: fileManager)
        let metadata = Data("version=1\ndigest=\(ManagedHookFileSystem.digest(of: contents))\n".utf8)
        try ManagedHookFileSystem.replace(metadata, at: metadataURL(for: targetURL), mode: 0o600, expectedDigest: ManagedHookFileSystem.digest(of: metadata), fileManager: fileManager)
    }

    /// Replace an existing *verified* backup with the target's current bytes
    /// immediately before a managed mutation.  This keeps the filesystem
    /// journal's backup identity aligned with its prior digest while never
    /// replacing a user-created sibling that merely has our filename.
    public static func snapshotForMutation(
        of targetURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: targetURL.path) else { return }
        let backupURL = backupURL(for: targetURL)
        guard fileManager.fileExists(atPath: backupURL.path) else {
            return try createBackup(of: targetURL, fileManager: fileManager)
        }
        guard try isVerifiedBackup(for: targetURL, fileManager: fileManager) else {
            throw ManagedHookBackupError.unmanagedBackupPath(backupURL.path)
        }
        try ManagedHookFileSystem.validateTarget(targetURL, allowMissing: false)
        let contents = try Data(contentsOf: targetURL, options: [.mappedIfSafe])
        try ManagedHookFileSystem.replace(contents, at: backupURL, mode: 0o600, expectedDigest: ManagedHookFileSystem.digest(of: contents), fileManager: fileManager)
        let metadata = Data("version=1\ndigest=\(ManagedHookFileSystem.digest(of: contents))\n".utf8)
        try ManagedHookFileSystem.replace(metadata, at: metadataURL(for: targetURL), mode: 0o600, expectedDigest: ManagedHookFileSystem.digest(of: metadata), fileManager: fileManager)
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

    /// Removes an expired *verified current* backup. Status reads never call
    /// this: status must not alter recovery evidence or any adjacent user file.
    public static func pruneExpiredBackups(
        for targetURL: URL,
        fileManager: FileManager = .default,
        referenceDate: Date = .now
    ) throws {
        try removeCurrentBackup(
            for: targetURL,
            fileManager: fileManager,
            referenceDate: referenceDate,
            onlyIfExpired: true
        )
    }

    public static func isVerifiedBackup(for targetURL: URL, fileManager: FileManager = .default) throws -> Bool {
        let backup = backupURL(for: targetURL)
        let metadata = metadataURL(for: targetURL)
        guard fileManager.fileExists(atPath: backup.path), fileManager.fileExists(atPath: metadata.path) else { return false }
        try ManagedHookFileSystem.validateTarget(backup, allowMissing: false)
        try ManagedHookFileSystem.validateTarget(metadata, allowMissing: false)
        let backupMode = (try fileManager.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber)?.intValue
        let metadataMode = (try fileManager.attributesOfItem(atPath: metadata.path)[.posixPermissions] as? NSNumber)?.intValue
        guard backupMode == 0o600, metadataMode == 0o600 else { return false }
        var metadataFields: [String: String] = [:]
        for line in String(decoding: try Data(contentsOf: metadata), as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, metadataFields[parts[0]] == nil else { return false }
            metadataFields[parts[0]] = parts[1]
        }
        let actualDigest = try ManagedHookFileSystem.digest(ofFile: backup)
        return metadataFields["version"] == "1" && metadataFields["digest"] == actualDigest
    }

    private static func removeBackups(
        for targetURL: URL,
        fileManager: FileManager,
        referenceDate: Date,
        retainCurrent: Bool
    ) throws {
        try removeCurrentBackup(
            for: targetURL,
            fileManager: fileManager,
            referenceDate: referenceDate,
            onlyIfExpired: retainCurrent
        )
    }

    private static func removeCurrentBackup(
        for targetURL: URL,
        fileManager: FileManager,
        referenceDate: Date,
        onlyIfExpired: Bool
    ) throws {
        let backup = backupURL(for: targetURL)
        let metadata = metadataURL(for: targetURL)
        guard fileManager.fileExists(atPath: backup.path) || fileManager.fileExists(atPath: metadata.path) else { return }
        guard try isVerifiedBackup(for: targetURL, fileManager: fileManager) else {
            throw ManagedHookBackupError.unmanagedBackupPath(backup.path)
        }
        if onlyIfExpired {
            let modifiedAt = (try fileManager.attributesOfItem(atPath: backup.path)[.modificationDate] as? Date) ?? .distantPast
            guard modifiedAt < referenceDate.addingTimeInterval(-retention) else { return }
        }
        let backupDigest = try ManagedHookFileSystem.digest(ofFile: backup)
        let metadataDigest = try ManagedHookFileSystem.digest(ofFile: metadata)
        try ManagedHookFileSystem.remove(backup, expectedDigest: backupDigest)
        try ManagedHookFileSystem.remove(metadata, expectedDigest: metadataDigest)
    }

}

public enum ManagedHookBackupError: LocalizedError, Sendable {
    case unsafeBackupPath(String)
    case unmanagedBackupPath(String)

    public var errorDescription: String? {
        switch self {
        case let .unsafeBackupPath(path):
            return "Open Island will not follow or replace an unsafe hook backup path: \(path)"
        case let .unmanagedBackupPath(path):
            return "Open Island left \(path) untouched because it is not a verified managed backup. Remove or inspect it, then retry."
        }
    }
}
