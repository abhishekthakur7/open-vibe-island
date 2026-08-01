import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeHookInstallationManagerTests {
    private static let sources = ["claude", "qoder", "qwen", "factory", "codebuddy"]

    @Test(arguments: sources)
    func everyClaudeFamilySourceWritesExactProvenanceIsIdempotentAndRevokesOnUninstall(source: String) throws {
        let fixture = try Fixture(source: source)
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "\(source)-helper")
        var revoked = false
        let manager = fixture.manager { revoked = true }

        let installed = try manager.install(hooksBinaryURL: helper)
        #expect(installed.managementOutcome == .exactManaged)
        #expect(installed.manifest?.hookCommand == ClaudeHookInstaller.hookCommand(for: fixture.binary.path, source: source))
        for target in [installed.settingsURL, installed.manifestURL] {
            let sidecar = ManagedHookProvenance.sidecarURL(for: target)
            #expect(FileManager.default.fileExists(atPath: sidecar.path))
            #expect((try FileManager.default.attributesOfItem(atPath: sidecar.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        let settingsBefore = try Data(contentsOf: installed.settingsURL)
        let sidecarBefore = try Data(contentsOf: ManagedHookProvenance.sidecarURL(for: installed.settingsURL))
        let repeated = try manager.install(hooksBinaryURL: helper)
        #expect(repeated.managementOutcome == .exactManaged)
        #expect(try Data(contentsOf: installed.settingsURL) == settingsBefore)
        #expect(try Data(contentsOf: ManagedHookProvenance.sidecarURL(for: installed.settingsURL)) == sidecarBefore)

        let removed = try manager.uninstall()
        #expect(removed.managementOutcome == .unowned)
        #expect(revoked)
    }

    @Test(arguments: sources)
    func everyClaudeFamilySourcePreservesUnrelatedAndSubstringLookalikeConfig(source: String) throws {
        let fixture = try Fixture(source: source)
        defer { fixture.remove() }
        try fixture.createDirectory()
        let settings = fixture.directory.appendingPathComponent("settings.json")
        let lookalike = "'/tmp/OpenIslandHooks-lookalike' --source \(source)"
        let original = Data("{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"\(lookalike)\"}]}]},\"custom\":true}".utf8)
        try original.write(to: settings)

        let installed = try fixture.manager().install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: "lookalike"))
        #expect(installed.managementOutcome == .exactManaged)
        let result = try String(contentsOf: settings)
        #expect(result.contains("OpenIslandHooks-lookalike"))
        #expect(result.contains("\"custom\" : true"))
    }

    @Test(arguments: ["partial", "stale-path", "extra-conflict"])
    func managedLookingSettingsAreAmbiguousAndNeverMutated(kind: String) throws {
        let fixture = try Fixture(source: "claude")
        defer { fixture.remove() }
        try fixture.createDirectory()
        let command = ClaudeHookInstaller.hookCommand(for: fixture.binary.path, source: fixture.source)
        let base = try ClaudeHookInstaller.installSettingsJSON(existingData: nil, hookCommand: command).contents!
        var root = try JSONSerialization.jsonObject(with: base) as! [String: Any]
        var hooks = root["hooks"] as! [String: Any]
        switch kind {
        case "partial": hooks.removeValue(forKey: "Stop")
        case "stale-path":
            var groups = hooks["Stop"] as! [[String: Any]]
            var group = groups[0]
            var entries = group["hooks"] as! [[String: Any]]
            entries[0]["command"] = "'/tmp/stale/OpenIslandHooks' --source claude"
            group["hooks"] = entries; groups[0] = group; hooks["Stop"] = groups
        default:
            hooks["Stop"] = (hooks["Stop"] as! [[String: Any]]) + [(hooks["Stop"] as! [[String: Any]])[0]]
        }
        root["hooks"] = hooks
        let conflicting = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let settings = fixture.directory.appendingPathComponent("settings.json")
        try conflicting.write(to: settings)
        let manager = fixture.manager()

        #expect((try manager.status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try manager.install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: kind)) }
        #expect(try Data(contentsOf: settings) == conflicting)
        #expect(throws: ManagedHookFileSystemError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: settings) == conflicting)
    }

    @Test(arguments: ["settings", "manifest", "sidecar"])
    func tamperedOwnershipEvidenceIsAmbiguousAndUninstallLeavesBytesUntouched(target: String) throws {
        let fixture = try Fixture(source: "qoder")
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "tamper")
        let manager = fixture.manager()
        let installed = try manager.install(hooksBinaryURL: helper)
        let targetURL: URL = switch target {
        case "settings": installed.settingsURL
        case "manifest": installed.manifestURL
        default: ManagedHookProvenance.sidecarURL(for: installed.settingsURL)
        }
        try Data("tampered".utf8).write(to: targetURL)
        let bytes = try Data(contentsOf: targetURL)
        #expect((try manager.status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: targetURL) == bytes)
    }

    @Test
    func unsafeFileAndDirectoryLinksAreReportedWithoutReadingOrCreating() throws {
        let fixture = try Fixture(source: "factory")
        defer { fixture.remove() }
        try fixture.createDirectory()
        let settings = fixture.directory.appendingPathComponent("settings.json")
        let outside = fixture.root.appendingPathComponent("outside")
        try Data("{}".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: outside)
        #expect((try fixture.manager().status()).managementOutcome == .unsafePath)

        let linked = fixture.root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: fixture.directory)
        let linkedManager = ClaudeHookInstallationManager(claudeDirectory: linked, managedHooksBinaryURL: fixture.binary, hookSource: fixture.source)
        #expect((try linkedManager.status()).managementOutcome == .unsafePath)
    }

    private struct Fixture {
        let root: URL
        let directory: URL
        let binary: URL
        let source: String

        init(source: String) throws {
            self.source = source
            root = FileManager.default.temporaryDirectory.appendingPathComponent("open-island-claude-manager-\(UUID().uuidString)", isDirectory: true)
            directory = root.appendingPathComponent(".\(source)", isDirectory: true)
            binary = root.appendingPathComponent("managed/OpenIslandHooks")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        func createDirectory() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        func manager(revoker: @escaping () throws -> Void = {}) -> ClaudeHookInstallationManager { ClaudeHookInstallationManager(claudeDirectory: directory, managedHooksBinaryURL: binary, hookSource: source, credentialRevoker: revoker) }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
