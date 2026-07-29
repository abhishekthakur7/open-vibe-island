import Foundation
import Testing
@testable import OpenIslandCore

struct ManagedHookFileSystemTests {
    @Test
    func replacesOnlyRegularCurrentUserFileAndCleansJournalAfterSuccess() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("hooks.json")
        let data = Data("new hook".utf8)

        try ManagedHookFileSystem.replace(data, at: target, expectedDigest: ManagedHookFileSystem.digest(of: data))

        #expect(try Data(contentsOf: target) == data)
        #expect(!FileManager.default.fileExists(atPath: ManagedHookFileSystem.journalURL(for: target).path))
        let mode = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test
    func rejectsDigestMismatchAndLeavesTargetUntouched() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("hooks.json")
        try Data("old".utf8).write(to: target)

        #expect(throws: ManagedHookFileSystemError.self) {
            try ManagedHookFileSystem.replace(Data("new".utf8), at: target, expectedDigest: "not-the-digest")
        }
        #expect(try String(contentsOf: target) == "old")
    }

    @Test
    func rejectsSymlinkAndUnsafeDirectoryModes() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("hooks.json")
        let outside = root.appendingPathComponent("outside")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        #expect(throws: ManagedHookFileSystemError.self) {
            let data = Data("new".utf8)
            try ManagedHookFileSystem.replace(data, at: target, expectedDigest: ManagedHookFileSystem.digest(of: data))
        }

        try FileManager.default.removeItem(at: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o770], ofItemAtPath: root.path)
        #expect(throws: ManagedHookFileSystemError.self) {
            let data = Data("new".utf8)
            try ManagedHookFileSystem.replace(data, at: target, expectedDigest: ManagedHookFileSystem.digest(of: data))
        }
    }

    @Test
    func interruptionRetainsRecoveryJournalAndPriorContents() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("hooks.json")
        try Data("old".utf8).write(to: target)
        #expect(throws: Error.self) {
            let data = Data("new".utf8)
            try ManagedHookFileSystem.replace(data, at: target, expectedDigest: ManagedHookFileSystem.digest(of: data), interruptionPoint: { throw CancellationError() })
        }
        #expect(try String(contentsOf: target) == "old")
        #expect(FileManager.default.fileExists(atPath: ManagedHookFileSystem.journalURL(for: target).path))
    }

    @Test
    func rejectsDirectorySymlinkInsteadOfCanonicalizingIt() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try privateRoot()
        defer { try? FileManager.default.removeItem(at: outside) }
        let linkedDirectory = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: outside)
        let data = Data("new".utf8)

        #expect(throws: ManagedHookFileSystemError.self) {
            try ManagedHookFileSystem.replace(data, at: linkedDirectory.appendingPathComponent("hooks.json"), expectedDigest: ManagedHookFileSystem.digest(of: data))
        }
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("hooks.json").path))
    }

    @Test
    func acceptsPrivateCurrentUserDirectoryAndRejectsHardLinksAndNonRegularFiles() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let target = root.appendingPathComponent("hooks.json")
        let data = Data("new".utf8)
        try ManagedHookFileSystem.replace(data, at: target, expectedDigest: ManagedHookFileSystem.digest(of: data))

        try FileManager.default.setAttributes([.posixPermissions: 0o660], ofItemAtPath: target.path)
        #expect(throws: ManagedHookFileSystemError.self) {
            try ManagedHookFileSystem.validateTarget(target, allowMissing: false)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)

        let hardLink = root.appendingPathComponent("second-link")
        #expect(Darwin.link(target.path, hardLink.path) == 0)
        #expect(throws: ManagedHookFileSystemError.self) {
            try ManagedHookFileSystem.validateTarget(target, allowMissing: false)
        }
        try FileManager.default.removeItem(at: hardLink)

        let fifo = root.appendingPathComponent("not-a-file")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: ManagedHookFileSystemError.self) {
            try ManagedHookFileSystem.validateTarget(fifo, allowMissing: false)
        }
    }

    @Test
    func rejectsUnbundledOpenCodePluginBeforeCreatingAnyTarget() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = OpenCodePluginInstallationManager(openCodeConfigDirectory: root)
        #expect(throws: ManagedHookFileSystemError.self) {
            try manager.install(pluginSourceData: Data("arbitrary plugin".utf8))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("plugins/open-island.js").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("config.json").path))
    }

    @Test
    func recoversInterruptedReplacementOnlyFromVerifiedBackup() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("hooks.json")
        try Data("old".utf8).write(to: target)
        try ManagedHookBackupLifecycle.createBackup(of: target)
        let replacement = Data("new".utf8)
        #expect(throws: Error.self) {
            try ManagedHookFileSystem.replace(replacement, at: target, expectedDigest: ManagedHookFileSystem.digest(of: replacement), interruptionPoint: { throw CancellationError() })
        }

        try ManagedHookFileSystem.recoverIfNeeded(for: target)
        #expect(try String(contentsOf: target) == "old")
        #expect(!FileManager.default.fileExists(atPath: ManagedHookFileSystem.journalURL(for: target).path))
        try ManagedHookFileSystem.recoverIfNeeded(for: target) // idempotent
    }

    @Test
    func refusesRecoveryWhenBackupDoesNotMatchJournal() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("hooks.json")
        try Data("old".utf8).write(to: target)
        try ManagedHookBackupLifecycle.createBackup(of: target)
        let replacement = Data("new".utf8)
        #expect(throws: Error.self) {
            try ManagedHookFileSystem.replace(replacement, at: target, expectedDigest: ManagedHookFileSystem.digest(of: replacement), interruptionPoint: { throw CancellationError() })
        }
        let backup = ManagedHookBackupLifecycle.backupURL(for: target)
        try Data("tampered".utf8).write(to: backup)

        #expect(throws: ManagedHookFileSystemError.self) {
            try ManagedHookFileSystem.recoverIfNeeded(for: target)
        }
        #expect(FileManager.default.fileExists(atPath: ManagedHookFileSystem.journalURL(for: target).path))
    }

    @Test
    func refusesToCleanAnUnverifiedBackupSibling() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("hooks.json")
        let backup = ManagedHookBackupLifecycle.backupURL(for: target)
        try Data("user-owned sibling".utf8).write(to: backup)

        #expect(throws: ManagedHookBackupError.self) {
            try ManagedHookBackupLifecycle.removeBackup(for: target)
        }
        #expect(try String(contentsOf: backup) == "user-owned sibling")
    }

    @Test
    func refusesToUseOrRemoveBackupWhoseModeIsNoLongerPrivate() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("hooks.json")
        try Data("old".utf8).write(to: target)
        try ManagedHookBackupLifecycle.createBackup(of: target)
        let backup = ManagedHookBackupLifecycle.backupURL(for: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: backup.path)

        #expect(!(try ManagedHookBackupLifecycle.isVerifiedBackup(for: target)))
        #expect(throws: ManagedHookBackupError.self) {
            try ManagedHookBackupLifecycle.removeBackup(for: target)
        }
        #expect(try String(contentsOf: backup) == "old")
    }

    @Test
    func statusDoesNotPruneAnExpiredVerifiedBackup() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: config)
        try ManagedHookBackupLifecycle.createBackup(of: config)
        let backup = ManagedHookBackupLifecycle.backupURL(for: config)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.distantPast],
            ofItemAtPath: backup.path
        )

        _ = try OpenCodePluginInstallationManager(openCodeConfigDirectory: root).status()
        #expect(FileManager.default.fileExists(atPath: backup.path))
    }

    @Test
    func renameAndSymlinkRaceCannotRedirectDescriptorAnchoredReplacement() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("managed", isDirectory: true)
        let moved = root.appendingPathComponent("managed-original", isDirectory: true)
        let attacker = root.appendingPathComponent("attacker", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: attacker, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = original.appendingPathComponent("hooks.json")
        let attackerTarget = attacker.appendingPathComponent("hooks.json")
        try Data("attacker".utf8).write(to: attackerTarget)
        let data = Data("verified".utf8)

        #expect(throws: Error.self) {
            try ManagedHookFileSystem.replace(
                data,
                at: target,
                expectedDigest: ManagedHookFileSystem.digest(of: data),
                afterDirectoryOpened: {
                    try FileManager.default.moveItem(at: original, to: moved)
                    try FileManager.default.createSymbolicLink(at: original, withDestinationURL: attacker)
                }
            )
        }
        #expect(try String(contentsOf: attackerTarget) == "attacker")
        #expect(!FileManager.default.fileExists(atPath: moved.appendingPathComponent("hooks.json").path))
    }

    @Test
    func missingOrTamperedBundledManifestLeavesManagerTargetsUntouched() throws {
        let root = try privateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("Open Island.app/Contents/Helpers/OpenIslandHooks")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unverified".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let codex = root.appendingPathComponent(".codex", isDirectory: true)
        let manager = CodexHookInstallationManager(codexDirectory: codex, managedHooksBinaryURL: root.appendingPathComponent("managed/OpenIslandHooks"))
        #expect(throws: BundledHookArtifactError.self) { try manager.install(hooksBinaryURL: helper) }
        #expect(!FileManager.default.fileExists(atPath: codex.path))

        let validHelper = try makeVerifiedHooksApp(at: root, contents: "verified")
        try Data("tampered".utf8).write(to: validHelper)
        #expect(throws: BundledHookArtifactError.self) { try VerifiedBundledHookArtifact.verify(helperURL: validHelper) }
    }

    private func privateRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("open-island-hook-fs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return root
    }
}
