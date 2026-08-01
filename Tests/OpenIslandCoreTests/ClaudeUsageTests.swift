import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeUsageTests {
    @Test
    func claudeUsageLoaderParsesCachedRateLimits() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-usage-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("open-island-rl.json")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let payload = """
        {
          "five_hour": {
            "used_percentage": 42,
            "resets_at": 1760000000
          },
          "seven_day": {
            "used_percentage": 17.5,
            "resets_at": 1760500000
          }
        }
        """
        try payload.write(to: cacheURL, atomically: true, encoding: .utf8)

        let snapshot = try ClaudeUsageLoader.load(from: cacheURL)

        #expect(snapshot?.fiveHour?.roundedUsedPercentage == 42)
        #expect(snapshot?.sevenDay?.roundedUsedPercentage == 18)
        #expect(snapshot?.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(snapshot?.cachedAt != nil)
    }

    @Test
    func claudeUsageCacheRetentionUsesInjectedReferenceDateAndStrictBoundary() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-usage-boundary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let cacheURL = rootURL.appendingPathComponent("rate-limits.json")
        try "{ \"five_hour\": { \"used_percentage\": 42 } }".write(to: cacheURL, atomically: true, encoding: .utf8)
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

        try FileManager.default.setAttributes(
            [.modificationDate: referenceDate.addingTimeInterval(-ClaudeUsageLoader.cacheRetention)],
            ofItemAtPath: cacheURL.path
        )
        #expect(try ClaudeUsageLoader.load(from: [cacheURL], referenceDate: referenceDate)?.fiveHour?.roundedUsedPercentage == 42)

        try FileManager.default.setAttributes(
            [.modificationDate: referenceDate.addingTimeInterval(-ClaudeUsageLoader.cacheRetention - 1)],
            ofItemAtPath: cacheURL.path
        )
        #expect(try ClaudeUsageLoader.load(from: [cacheURL], referenceDate: referenceDate) == nil)
    }

    @Test
    func claudeStatusLineInstallationManagerInstallsManagedScriptWithoutOverwritingCustomCommand() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-status-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".open-island", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let manager = ClaudeStatusLineInstallationManager(
            claudeDirectory: claudeDirectory,
            scriptDirectoryURL: scriptDirectory,
            templateResources: try makeVerifiedClaudeStatusLineTemplateResources(at: rootURL)
        )

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let installed = try manager.install()

        #expect(installed.managedStatusLineInstalled)
        #expect(installed.statusLineCommand == installed.scriptURL.path)
        #expect(FileManager.default.fileExists(atPath: installed.scriptURL.path))

        let settingsObject = try jsonObject(from: Data(contentsOf: installed.settingsURL))
        let statusLine = settingsObject["statusLine"] as? [String: Any]
        #expect(statusLine?["command"] as? String == installed.scriptURL.path)
        #expect(statusLine?["type"] as? String == "command")

        let scriptContents = try String(contentsOf: installed.scriptURL, encoding: .utf8)
        #expect(scriptContents.contains(installed.cacheURL.path))
        #expect(scriptContents.contains(".rate_limits // empty"))

        let uninstalled = try manager.uninstall()
        #expect(!uninstalled.managedStatusLineInstalled)
        #expect(!FileManager.default.fileExists(atPath: installed.scriptURL.path))
    }

    @Test
    func claudeStatusLineInstallationRequiresExactProvenanceForIdempotenceAndUninstall() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("open-island-claude-provenance-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let manager = ClaudeStatusLineInstallationManager(
            claudeDirectory: rootURL.appendingPathComponent(".claude", isDirectory: true),
            scriptDirectoryURL: rootURL.appendingPathComponent(".open-island", isDirectory: true).appendingPathComponent("bin", isDirectory: true),
            templateResources: try makeVerifiedClaudeStatusLineTemplateResources(at: rootURL)
        )
        let installed = try manager.install()
        let settingsSidecar = ManagedHookProvenance.sidecarURL(for: installed.settingsURL)
        let scriptSidecar = ManagedHookProvenance.sidecarURL(for: installed.scriptURL)
        let settingsBefore = try Data(contentsOf: installed.settingsURL)
        let scriptBefore = try Data(contentsOf: installed.scriptURL)
        let settingsSidecarBefore = try Data(contentsOf: settingsSidecar)
        #expect(try manager.status().managementOutcome == .exactManaged)
        #expect(try manager.install().managementOutcome == .exactManaged)
        #expect(try Data(contentsOf: installed.settingsURL) == settingsBefore)
        #expect(try Data(contentsOf: installed.scriptURL) == scriptBefore)
        #expect(try Data(contentsOf: settingsSidecar) == settingsSidecarBefore)
        #expect((try FileManager.default.attributesOfItem(atPath: settingsSidecar.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((try FileManager.default.attributesOfItem(atPath: scriptSidecar.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        try "copied marker Open Island status-line template version: 1".write(to: installed.scriptURL, atomically: true, encoding: .utf8)
        #expect(try manager.status().managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try manager.uninstall() }
        #expect(try String(contentsOf: installed.scriptURL, encoding: .utf8) == "copied marker Open Island status-line template version: 1")
    }

    @Test
    func claudeStatusLineInstallationManagerRejectsExistingCustomStatusLine() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-conflict-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = rootURL.appendingPathComponent(".claude", isDirectory: true)
        let scriptDirectory = rootURL
            .appendingPathComponent(".open-island", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let manager = ClaudeStatusLineInstallationManager(
            claudeDirectory: claudeDirectory,
            scriptDirectoryURL: scriptDirectory,
            templateResources: try makeVerifiedClaudeStatusLineTemplateResources(at: rootURL)
        )
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let settingsData = try JSONSerialization.data(
            withJSONObject: [
                "theme": "dark",
                "statusLine": [
                    "type": "command",
                    "command": "/usr/local/bin/custom-status",
                ],
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        try settingsData.write(to: settingsURL, options: .atomic)

        let status = try manager.status()
        #expect(status.hasConflictingStatusLine)
        #expect(status.statusLineCommand == "/usr/local/bin/custom-status")

        do {
            _ = try manager.install()
            Issue.record("Expected install to reject an existing custom status line")
        } catch let error as ClaudeStatusLineInstallationError {
            switch error {
            case let .existingStatusLineConflict(command):
                #expect(command == "/usr/local/bin/custom-status")
            default:
                Issue.record("Unexpected Claude status line error: \(error)")
            }
        }
    }

}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}
