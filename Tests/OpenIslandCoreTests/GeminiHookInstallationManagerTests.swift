import Foundation
import Testing
@testable import OpenIslandCore

struct GeminiHookInstallationManagerTests {
    @Test
    func verifiedInstallIsIdempotentAndVerifiedUninstallRevokesCredential() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "gemini-verified")
        var revoked = false
        let manager = fixture.manager { revoked = true }

        let installed = try manager.install(hooksBinaryURL: helper)
        #expect(installed.managementOutcome == .exactManaged)
        #expect(installed.managedHooksPresent)
        #expect(installed.manifest?.hookCommand == GeminiHookInstaller.hookCommand(for: fixture.binary.path))
        for target in [installed.settingsURL, installed.manifestURL] {
            let sidecar = ManagedHookProvenance.sidecarURL(for: target)
            #expect(FileManager.default.fileExists(atPath: sidecar.path))
            #expect((try FileManager.default.attributesOfItem(atPath: sidecar.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        let settingsBefore = try Data(contentsOf: installed.settingsURL)
        let sidecarBefore = try Data(contentsOf: ManagedHookProvenance.sidecarURL(for: installed.settingsURL))
        #expect((try manager.install(hooksBinaryURL: helper)).managementOutcome == .exactManaged)
        #expect(try Data(contentsOf: installed.settingsURL) == settingsBefore)
        #expect(try Data(contentsOf: ManagedHookProvenance.sidecarURL(for: installed.settingsURL)) == sidecarBefore)

        let upgradedHelper = try makeVerifiedHooksApp(at: fixture.root.appendingPathComponent("upgraded", isDirectory: true), contents: "gemini-upgraded")
        #expect((try manager.install(hooksBinaryURL: upgradedHelper)).managementOutcome == .exactManaged)
        #expect(try Data(contentsOf: installed.settingsURL) == settingsBefore)

        let removed = try manager.uninstall()
        #expect(removed.managementOutcome == .unowned)
        #expect(revoked)
        #expect(!FileManager.default.fileExists(atPath: ManagedHookProvenance.sidecarURL(for: installed.settingsURL).path))
    }

    @Test
    func safelyMergesUnrelatedSettingsButLeavesLookalikesUnowned() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createGemini()
        let settings = fixture.directory.appendingPathComponent("settings.json")
        let lookalike = "'/tmp/OpenIslandHooks-lookalike' --source gemini"
        let original = Data("{\"custom\":true,\"hooks\":{\"Notification\":[{\"hooks\":[{\"command\":\"\(lookalike)\"}]}]}}".utf8)
        try original.write(to: settings)

        let installed = try fixture.manager().install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: "lookalike"))
        #expect(installed.managementOutcome == .exactManaged)
        #expect(try String(contentsOf: settings).contains("OpenIslandHooks-lookalike"))
        #expect(try String(contentsOf: settings).contains("custom"))
    }

    @Test(arguments: ["partial", "stale-path", "duplicate", "wrong-command"])
    func managedLookingEntriesAreAmbiguousAndNeverMutated(kind: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createGemini()
        let command = GeminiHookInstaller.hookCommand(for: fixture.binary.path)
        let base = try GeminiHookInstaller.installSettingsJSON(existingData: nil, hookCommand: command).contents!
        var root = try JSONSerialization.jsonObject(with: base) as! [String: Any]
        var hooks = root["hooks"] as! [String: Any]
        switch kind {
        case "partial": hooks.removeValue(forKey: "Notification")
        case "stale-path":
            var groups = hooks["Notification"] as! [[String: Any]]
            var entries = groups[0]["hooks"] as! [[String: Any]]
            entries[0]["command"] = "'/tmp/stale/OpenIslandHooks' --source gemini"
            groups[0]["hooks"] = entries
            hooks["Notification"] = groups
        case "wrong-command":
            var groups = hooks["Notification"] as! [[String: Any]]
            var entries = groups[0]["hooks"] as! [[String: Any]]
            entries[0]["command"] = "'/tmp/OpenIslandHooks' --source claude"
            groups[0]["hooks"] = entries
            hooks["Notification"] = groups
        default:
            hooks["Notification"] = (hooks["Notification"] as! [[String: Any]]) + [(hooks["Notification"] as! [[String: Any]])[0]]
        }
        root["hooks"] = hooks
        let conflicting = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let target = fixture.directory.appendingPathComponent("settings.json")
        try conflicting.write(to: target)

        let manager = fixture.manager()
        #expect((try manager.status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try manager.install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: kind)) }
        #expect(try Data(contentsOf: target) == conflicting)
        #expect(throws: ManagedHookFileSystemError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: target) == conflicting)
    }

    @Test(arguments: ["settings", "manifest", "sidecar"])
    func tamperedOwnershipEvidenceBlocksUninstallWithoutChangingBytes(target: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager()
        let installed = try manager.install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: "tamper"))
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
    func artifactFailureJournalsAndUnsafeLinksNeverMutateTargets() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager()
        #expect(throws: BundledHookArtifactError.self) { try manager.install(hooksBinaryURL: fixture.root.appendingPathComponent("untrusted/OpenIslandHooks")) }
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.binary.deletingLastPathComponent().path))

        try fixture.createGemini()
        let journal = ManagedHookFileSystem.journalURL(for: fixture.directory.appendingPathComponent("settings.json"))
        try Data("unresolved".utf8).write(to: journal)
        let before = try Data(contentsOf: journal)
        #expect((try manager.status()).managementOutcome == .unresolvedRecovery)
        #expect(throws: ManagedHookFileSystemError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: journal) == before)

        let linkFixture = try Fixture()
        defer { linkFixture.remove() }
        try linkFixture.createGemini()
        let outside = linkFixture.root.appendingPathComponent("outside")
        try Data("{}".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: linkFixture.directory.appendingPathComponent("settings.json"), withDestinationURL: outside)
        #expect((try linkFixture.manager().status()).managementOutcome == .unsafePath)
    }

    private struct Fixture {
        let root: URL
        let directory: URL
        let binary: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("open-island-gemini-manager-\(UUID().uuidString)", isDirectory: true)
            directory = root.appendingPathComponent(".gemini", isDirectory: true)
            binary = root.appendingPathComponent("managed/OpenIslandHooks")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        func createGemini() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        func manager(revoker: @escaping () throws -> Void = {}) -> GeminiHookInstallationManager { GeminiHookInstallationManager(geminiDirectory: directory, managedHooksBinaryURL: binary, credentialRevoker: revoker) }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
