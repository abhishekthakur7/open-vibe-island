import CryptoKit
import Darwin
import Foundation

/// The narrow filesystem boundary used by hook installers.  Hook targets live
/// outside the application container, so a normal `Data.write(options: .atomic)`
/// is not sufficient: it can follow a replaced path between checks.
public enum ManagedHookFileSystem {
    public static let managedMode: mode_t = 0o600

    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func validateDirectoryPath(_ directoryURL: URL) throws {
        let path = canonicalCompatibilityPath(directoryURL.standardizedFileURL.path)
        guard path.hasPrefix("/") else {
            throw ManagedHookFileSystemError.unsafePath(path, "is not absolute")
        }

        // Do not call realpath here. It would bless an arbitrary symlink in a
        // requested path before we have inspected it.  openat with O_NOFOLLOW
        // keeps each checked component pinned while the next is opened.
        let rootFD = open("/", O_RDONLY | O_DIRECTORY)
        guard rootFD >= 0 else { throw ManagedHookFileSystemError.io("/") }
        defer { close(rootFD) }
        var parentFD = rootFD
        var ownedFD: Int32?
        var current = ""
        for component in path.split(separator: "/") {
            current += "/\(component)"
            let childFD = openat(parentFD, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard childFD >= 0 else {
                throw ManagedHookFileSystemError.unsafePath(current, "is missing, not a directory, or is a symbolic link")
            }
            var info = stat()
            guard fstat(childFD, &info) == 0 else {
                close(childFD)
                throw ManagedHookFileSystemError.unsafePath(current, "cannot be inspected")
            }
            guard (info.st_mode & S_IFMT) == S_IFDIR else {
                close(childFD)
                throw ManagedHookFileSystemError.unsafePath(current, "is not a directory")
            }
            guard info.st_uid == 0 || info.st_uid == getuid() else {
                close(childFD)
                throw ManagedHookFileSystemError.unsafePath(current, "is not owned by the current user or root")
            }
            guard (info.st_mode & 0o022) == 0 else {
                close(childFD)
                throw ManagedHookFileSystemError.unsafePath(current, "is group or world writable")
            }
            if let ownedFD { close(ownedFD) }
            ownedFD = childFD
            parentFD = childFD
        }
        if let ownedFD { close(ownedFD) }
    }

    public static func createDirectory(_ directoryURL: URL, fileManager: FileManager = .default) throws {
        let path = canonicalCompatibilityPath(directoryURL.standardizedFileURL.path)
        guard path.hasPrefix("/") else { throw ManagedHookFileSystemError.unsafePath(path, "is not absolute") }
        let rootFD = open("/", O_RDONLY | O_DIRECTORY)
        guard rootFD >= 0 else { throw ManagedHookFileSystemError.io("/") }
        defer { close(rootFD) }
        var parentFD = rootFD
        var ownedFD: Int32?
        var current = ""
        for component in path.split(separator: "/") {
            current += "/\(component)"
            if mkdirat(parentFD, String(component), 0o700) != 0, errno != EEXIST {
                throw ManagedHookFileSystemError.io(current)
            }
            let childFD = openat(parentFD, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard childFD >= 0 else { throw ManagedHookFileSystemError.unsafePath(current, "is not a directory or is a symbolic link") }
            var info = stat()
            guard fstat(childFD, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFDIR,
                  (info.st_mode & 0o022) == 0,
                  info.st_uid == 0 || info.st_uid == getuid() else {
                close(childFD)
                throw ManagedHookFileSystemError.unsafePath(current, "has unsafe ownership or permissions")
            }
            if let ownedFD { close(ownedFD) }
            ownedFD = childFD
            parentFD = childFD
        }
        if let ownedFD { close(ownedFD) }
    }

    public static func validateTarget(_ targetURL: URL, allowMissing: Bool = true) throws {
        try validateDirectoryPath(targetURL.deletingLastPathComponent())
        var info = stat()
        if lstat(targetURL.path, &info) != 0 {
            if errno == ENOENT, allowMissing { return }
            throw ManagedHookFileSystemError.unsafePath(targetURL.path, "cannot be inspected")
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw ManagedHookFileSystemError.unsafePath(targetURL.path, "is not a regular file")
        }
        guard info.st_uid == getuid() else {
            throw ManagedHookFileSystemError.unsafePath(targetURL.path, "is not owned by the current user")
        }
        guard info.st_nlink <= 1 else {
            throw ManagedHookFileSystemError.unsafePath(targetURL.path, "has more than one hard link")
        }
        guard (info.st_mode & 0o022) == 0 else {
            throw ManagedHookFileSystemError.unsafePath(targetURL.path, "is group or world writable")
        }
    }

    /// Answers existence using `lstat`, so a dangling link cannot be mistaken
    /// for an absent target. Callers still need `validateTarget` before using
    /// a present path.
    public static func existsNoFollow(_ targetURL: URL) throws -> Bool {
        var info = stat()
        if lstat(targetURL.path, &info) == 0 { return true }
        if errno == ENOENT { return false }
        throw ManagedHookFileSystemError.unsafePath(targetURL.path, "cannot be inspected")
    }

    /// Replaces a file in its existing directory.  The journal is deliberately
    /// retained until verification and directory fsync finish, making startup
    /// recovery deterministic after a killed install.
    public static func replace(
        _ data: Data,
        at targetURL: URL,
        mode: mode_t = managedMode,
        expectedDigest: String,
        fileManager: FileManager = .default,
        interruptionPoint: (() throws -> Void)? = nil,
        afterDirectoryOpened: (() throws -> Void)? = nil,
        recordJournal: Bool = true
    ) throws {
        try validateTarget(targetURL)
        let contentDigest = digest(of: data)
        guard expectedDigest == contentDigest else {
            throw ManagedHookFileSystemError.digestMismatch(targetURL.path)
        }
        let directory = targetURL.deletingLastPathComponent()
        let journal = journalURL(for: targetURL)
        if recordJournal {
            try recoverIfNeeded(for: targetURL, fileManager: fileManager)
            try writeJournal(target: targetURL, digest: contentDigest, fileManager: fileManager)
        }

        let temporaryName = ".\(targetURL.lastPathComponent).open-island-\(UUID().uuidString)"
        let temporary = directory.appendingPathComponent(temporaryName)
        let directoryFD = try openValidatedDirectory(directory)
        defer { close(directoryFD) }
        // Test seam for a real rename/symlink race. All mutation below stays
        // descriptor-relative even if the pathname is replaced here.
        try afterDirectoryOpened?()
        let descriptor = openat(directoryFD, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw ManagedHookFileSystemError.io(temporary.path) }
        do {
            defer { close(descriptor) }
            try writeAll(data, descriptor: descriptor, path: temporary.path)
            guard fsync(descriptor) == 0, fchmod(descriptor, mode) == 0, fsync(descriptor) == 0 else {
                throw ManagedHookFileSystemError.io(temporary.path)
            }
        } catch {
            _ = unlinkat(directoryFD, temporaryName, 0)
            throw error
        }
        try validateTarget(temporary, allowMissing: false)
        guard try digest(ofFile: temporary) == contentDigest else {
            _ = unlinkat(directoryFD, temporaryName, 0)
            throw ManagedHookFileSystemError.digestMismatch(temporary.path)
        }
        try interruptionPoint?()
        guard renameat(directoryFD, temporaryName, directoryFD, targetURL.lastPathComponent) == 0 else {
            _ = unlinkat(directoryFD, temporaryName, 0)
            throw ManagedHookFileSystemError.io(targetURL.path)
        }
        try validateTarget(targetURL, allowMissing: false)
        guard try digest(ofFile: targetURL) == contentDigest else { throw ManagedHookFileSystemError.digestMismatch(targetURL.path) }
        guard fsync(directoryFD) == 0 else { throw ManagedHookFileSystemError.io(directory.path) }
        if recordJournal { try remove(journal, expectedDigest: try digest(ofFile: journal)) }
    }

    /// Removes only a validated, current-user regular file.  The unlink is
    /// anchored to an already-validated parent descriptor so a replacement of
    /// the pathname cannot redirect deletion elsewhere.
    public static func remove(_ targetURL: URL, expectedDigest: String? = nil, afterDirectoryOpened: (() throws -> Void)? = nil) throws {
        try validateTarget(targetURL, allowMissing: false)
        let directory = targetURL.deletingLastPathComponent()
        let directoryFD = try openValidatedDirectory(directory)
        defer { close(directoryFD) }
        try afterDirectoryOpened?()
        let fileFD = openat(directoryFD, targetURL.lastPathComponent, O_RDONLY | O_NOFOLLOW)
        guard fileFD >= 0 else { throw ManagedHookFileSystemError.unsafePath(targetURL.path, "is missing or is a symbolic link") }
        defer { close(fileFD) }
        var info = stat()
        guard fstat(fileFD, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), info.st_nlink <= 1 else {
            throw ManagedHookFileSystemError.unsafePath(targetURL.path, "is not a private regular file")
        }
        if let expectedDigest, try digest(ofFile: targetURL) != expectedDigest {
            throw ManagedHookFileSystemError.ambiguous(targetURL.path)
        }
        guard unlinkat(directoryFD, targetURL.lastPathComponent, 0) == 0 else {
            throw ManagedHookFileSystemError.io(targetURL.path)
        }
        guard fsync(directoryFD) == 0 else { throw ManagedHookFileSystemError.io(directory.path) }
    }

    public static func removeIfPresent(_ targetURL: URL, expectedDigest: String? = nil) throws {
        var info = stat()
        if lstat(targetURL.path, &info) != 0 {
            if errno == ENOENT { return }
            throw ManagedHookFileSystemError.unsafePath(targetURL.path, "cannot be inspected")
        }
        try remove(targetURL, expectedDigest: expectedDigest)
    }

    public static func digest(ofFile url: URL) throws -> String { digest(of: try Data(contentsOf: url, options: [.mappedIfSafe])) }

    public static func journalURL(for targetURL: URL) -> URL {
        targetURL.deletingLastPathComponent().appendingPathComponent(".\(targetURL.lastPathComponent).open-island-journal")
    }

    /// Resolves an interrupted replacement without guessing. A journal can be
    /// cleared only when the target has the intended digest, or restored only
    /// from the private adjacent backup whose digest was recorded before the
    /// rename. Every other state is surfaced as an explicit ambiguity.
    public static func recoverIfNeeded(for targetURL: URL, fileManager: FileManager = .default) throws {
        let journal = journalURL(for: targetURL)
        guard fileManager.fileExists(atPath: journal.path) else { return }
        try validateTarget(journal, allowMissing: false)
        var fields: [String: String] = [:]
        for line in String(decoding: try Data(contentsOf: journal), as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, fields[parts[0]] == nil else {
                throw ManagedHookFileSystemError.ambiguous(journal.path)
            }
            fields[parts[0]] = parts[1]
        }
        guard fields["version"] == "1", fields["target"] == targetURL.path,
              let intendedDigest = fields["intendedDigest"], let backupDigest = fields["backupDigest"]
        else { throw ManagedHookFileSystemError.ambiguous(journal.path) }

        if let targetDigest = try? digest(ofFile: targetURL), targetDigest == intendedDigest {
            try remove(journal, expectedDigest: try digest(ofFile: journal))
            return
        }
        let backup = targetURL.appendingPathExtension(ManagedHookBackupLifecycle.filenameSuffix)
        guard backupDigest != "absent", fileManager.fileExists(atPath: backup.path),
              try ManagedHookBackupLifecycle.isVerifiedBackup(for: targetURL, fileManager: fileManager) else {
            throw ManagedHookFileSystemError.ambiguous(targetURL.path)
        }
        try validateTarget(backup, allowMissing: false)
        let backupData = try Data(contentsOf: backup, options: [.mappedIfSafe])
        guard digest(of: backupData) == backupDigest else {
            throw ManagedHookFileSystemError.ambiguous(backup.path)
        }
        try replace(backupData, at: targetURL, expectedDigest: backupDigest, fileManager: fileManager, recordJournal: false)
        try remove(journal, expectedDigest: try digest(ofFile: journal))
    }

    private static func writeJournal(target: URL, digest expectedContentDigest: String, fileManager: FileManager) throws {
        let priorDigest = (try? digest(ofFile: target)) ?? "absent"
        let backupURL = target.appendingPathExtension(ManagedHookBackupLifecycle.filenameSuffix)
        let backupDigest = (try? digest(ofFile: backupURL)) ?? "absent"
        let payload = Data("version=1\ntarget=\(target.path)\nintendedDigest=\(expectedContentDigest)\npriorDigest=\(priorDigest)\nbackupDigest=\(backupDigest)\nphase=prepared\n".utf8)
        try replace(payload, at: journalURL(for: target), mode: managedMode, expectedDigest: digest(of: payload), fileManager: fileManager, recordJournal: false)
    }

    private static func canonicalCompatibilityPath(_ requestedPath: String) -> String {
        // The only symlink compatibility exception is Apple's fixed /var root
        // alias. No user-controlled component is resolved or followed.
        if requestedPath == "/var" { return "/private/var" }
        if requestedPath.hasPrefix("/var/") { return "/private/var/" + requestedPath.dropFirst(5) }
        return requestedPath
    }

    private static func openValidatedDirectory(_ directoryURL: URL) throws -> Int32 {
        try validateDirectoryPath(directoryURL)
        let path = canonicalCompatibilityPath(directoryURL.standardizedFileURL.path)
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw ManagedHookFileSystemError.unsafePath(path, "cannot be opened safely") }
        return fd
    }

    private static func writeAll(_ data: Data, descriptor: Int32, path: String) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard written > 0 else { throw ManagedHookFileSystemError.io(path) }
                offset += written
            }
        }
    }
}

public enum ManagedHookFileSystemError: LocalizedError, Sendable, Equatable {
    case unsafePath(String, String)
    case digestMismatch(String)
    case io(String)
    /// An interrupted replacement journal is recovery evidence. Callers that
    /// have not already proven ownership must leave it for explicit repair.
    case recoveryRequired(String)
    case ambiguous(String)

    public var errorDescription: String? {
        switch self {
        case let .unsafePath(path, reason): return "Open Island will not modify \(path): \(reason)."
        case let .digestMismatch(path): return "Open Island rejected unverified hook content for \(path)."
        case let .io(path): return "Open Island could not safely update \(path)."
        case let .recoveryRequired(path): return "Open Island left \(path) untouched because recovery evidence is present. Resolve the journal and verified backup before retrying."
        case let .ambiguous(path): return "Open Island left \(path) untouched because it is not a verified managed hook. Review or remove the conflicting hook, then retry from Settings."
        }
    }
}
