import Foundation
import Testing
@testable import OpenIslandCore

struct DataLifecycleTests {
    @Test
    func migrationDropsTranscriptContentAndSetsPrivateModes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-lifecycle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("session-terminals.json")
        let secret = "seeded-secret-must-not-persist"
        let legacy = [CodexTrackedSessionRecord(
            sessionID: "session-1", title: secret, origin: .live,
            attachmentState: .attached, summary: secret, phase: .running,
            updatedAt: .now,
            jumpTarget: JumpTarget(terminalApp: "Terminal", workspaceName: secret, paneTitle: secret),
            codexMetadata: CodexSessionMetadata(
                transcriptPath: secret, initialUserPrompt: secret,
                lastUserPrompt: secret, lastAssistantMessage: secret,
                currentTool: secret, currentCommandPreview: secret, model: "model"
            )
        )]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(legacy).write(to: file)

        let loaded = try CodexSessionStore(fileURL: file).load()
        let stored = try String(contentsOf: file, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)

        #expect(loaded.first?.codexMetadata == nil)
        #expect(loaded.first?.jumpTarget == nil)
        #expect(!stored.contains(secret))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test
    func interruptedAtomicWriteArtifactsDoNotAlterCanonicalMetadataAndCleanupIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-lifecycle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("session-terminals.json")
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let canonical = PersistedSessionMetadata(
            sessionID: "canonical", origin: .live, attachmentState: .attached,
            phase: .running, outcome: nil, updatedAt: referenceDate
        )
        try LocalDataLifecycle.writeMetadata([canonical], to: file, referenceDate: referenceDate)
        let interrupted = root.appendingPathComponent(".session-terminals.json.interrupted")
        try Data("not metadata".utf8).write(to: interrupted)

        let loaded = try CodexSessionStore(fileURL: file).load(referenceDate: referenceDate)
        #expect(loaded.map(\.sessionID) == ["canonical"])
        #expect(!FileManager.default.fileExists(atPath: interrupted.path))

        try LocalDataLifecycle.cleanupInterruptedWriteArtifacts(for: file)
        try LocalDataLifecycle.cleanupInterruptedWriteArtifacts(for: file)
        #expect(try LocalDataLifecycle.readMetadata(from: file)?.map(\.sessionID) == ["canonical"])
    }

    @Test
    func managedHookBackupLifecycleKeepsOnePrivateBackupAndLeavesUnverifiedLegacySiblingUntouched() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-hook-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("settings.json")
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let legacyBackup = root.appendingPathComponent("settings.json.backup.2026-01-01T00-00-00Z")
        try Data("first".utf8).write(to: target)
        try Data("legacy".utf8).write(to: legacyBackup)

        try ManagedHookBackupLifecycle.createBackup(of: target, referenceDate: referenceDate)
        let backup = ManagedHookBackupLifecycle.backupURL(for: target)
        // A timestamped filename alone is not proof of ownership. The hook
        // backup lifecycle must never delete a user-created or legacy sibling
        // without private metadata that verifies its bytes.
        #expect(FileManager.default.fileExists(atPath: legacyBackup.path))
        #expect(try Data(contentsOf: backup) == Data("first".utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: backup.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        try FileManager.default.setAttributes(
            [.modificationDate: referenceDate.addingTimeInterval(-ManagedHookBackupLifecycle.retention)],
            ofItemAtPath: backup.path
        )
        try ManagedHookBackupLifecycle.pruneExpiredBackups(for: target, referenceDate: referenceDate)
        #expect(FileManager.default.fileExists(atPath: backup.path))

        try FileManager.default.setAttributes(
            [.modificationDate: referenceDate.addingTimeInterval(-ManagedHookBackupLifecycle.retention - 1)],
            ofItemAtPath: backup.path
        )
        try ManagedHookBackupLifecycle.pruneExpiredBackups(for: target, referenceDate: referenceDate)
        #expect(!FileManager.default.fileExists(atPath: backup.path))
        try ManagedHookBackupLifecycle.removeBackup(for: target)
    }

}
