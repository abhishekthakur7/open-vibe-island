import Foundation
import Testing
@testable import OpenIslandCore

struct OpenCodePluginInstallationManagerTests {
    @Test
    func verifiedInstallWritesExactPrivateProvenanceAndIsIdempotent() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let manager = fixture.manager()
        let resource = try makeVerifiedOpenCodePluginApp(at: fixture.root)

        let installed = try manager.install(pluginSourceURL: resource)
        #expect(installed.managementOutcome == .exactManaged)
        #expect(installed.isInstalled)
        for target in [installed.configURL, installed.pluginFileURL] {
            let sidecar = ManagedHookProvenance.sidecarURL(for: target)
            #expect((try FileManager.default.attributesOfItem(atPath: sidecar.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            let evidence = try ManagedHookProvenance.loadVerified(for: target, managerID: "opencode-plugin")
            #expect(evidence?.artifactID == "resource:Contents/Resources/open-island-opencode.js")
            #expect(evidence?.artifactSHA256 == OpenCodePluginInstallationManager.bundledPluginDigest)
        }
        let configBefore = try Data(contentsOf: installed.configURL)
        let pluginBefore = try Data(contentsOf: installed.pluginFileURL)
        let sidecarBefore = try Data(contentsOf: ManagedHookProvenance.sidecarURL(for: installed.configURL))
        let repeated = try manager.install(pluginSourceURL: resource)
        #expect(repeated.managementOutcome == .exactManaged)
        #expect(try Data(contentsOf: installed.configURL) == configBefore)
        #expect(try Data(contentsOf: installed.pluginFileURL) == pluginBefore)
        #expect(try Data(contentsOf: ManagedHookProvenance.sidecarURL(for: installed.configURL)) == sidecarBefore)
    }

    @Test
    func installPreservesUnrelatedConfigButLeavesManagedLookingEntriesUntouched() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try fixture.createConfig(["theme": "dark", "plugin": ["file:///tmp/other-plugin.js"]])
        let resource = try makeVerifiedOpenCodePluginApp(at: fixture.root)
        let installed = try fixture.manager().install(pluginSourceURL: resource)
        #expect(installed.managementOutcome == .exactManaged)
        #expect(try String(contentsOf: installed.configURL).contains("other-plugin.js"))
        #expect(try String(contentsOf: ManagedHookBackupLifecycle.backupURL(for: installed.configURL)).contains("other-plugin.js"))

        for kind in ["suffix-lookalike", "wrong-path", "partial", "extra-conflict"] {
            let conflicting = try Fixture(); defer { conflicting.remove() }
            let expected = "file://\(conflicting.config.appendingPathComponent("plugins/open-island.js").path)"
            let plugins: [String] = switch kind {
            case "suffix-lookalike": ["file:///tmp/lookalike-open-island.js"]
            case "wrong-path": ["file:///tmp/open-island.js"]
            case "partial": [expected]
            default: [expected, "file:///tmp/open-island-conflict.js"]
            }
            try conflicting.createConfig(["plugin": plugins])
            let before = try Data(contentsOf: conflicting.configFile)
            #expect((try conflicting.manager().status()).managementOutcome == .ambiguousUnmanaged)
            #expect(throws: ManagedHookFileSystemError.self) { try conflicting.manager().install(pluginSourceURL: resource) }
            #expect(try Data(contentsOf: conflicting.configFile) == before)
            #expect(!FileManager.default.fileExists(atPath: conflicting.config.appendingPathComponent("plugins/open-island.js").path))
        }
    }

    @Test
    func tamperedTargetsOrEvidenceAndRecoveryJournalAreNeverUninstalled() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let resource = try makeVerifiedOpenCodePluginApp(at: fixture.root)
        let installed = try fixture.manager().install(pluginSourceURL: resource)
        try Data("tampered-plugin".utf8).write(to: installed.pluginFileURL)
        let pluginBefore = try Data(contentsOf: installed.pluginFileURL)
        #expect((try fixture.manager().status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try fixture.manager().uninstall() }
        #expect(try Data(contentsOf: installed.pluginFileURL) == pluginBefore)

        let missing = try Fixture(); defer { missing.remove() }
        let missingInstalled = try missing.manager().install(pluginSourceURL: resource)
        try FileManager.default.removeItem(at: ManagedHookProvenance.sidecarURL(for: missingInstalled.configURL))
        let configBefore = try Data(contentsOf: missingInstalled.configURL)
        #expect((try missing.manager().status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try missing.manager().uninstall() }
        #expect(try Data(contentsOf: missingInstalled.configURL) == configBefore)

        let tamperedConfig = try Fixture(); defer { tamperedConfig.remove() }
        let tamperedInstalled = try tamperedConfig.manager().install(pluginSourceURL: resource)
        try Data("{\"plugin\":[]}".utf8).write(to: tamperedInstalled.configURL)
        let tamperedConfigBefore = try Data(contentsOf: tamperedInstalled.configURL)
        #expect((try tamperedConfig.manager().status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try tamperedConfig.manager().uninstall() }
        #expect(try Data(contentsOf: tamperedInstalled.configURL) == tamperedConfigBefore)

        let tamperedSidecar = try Fixture(); defer { tamperedSidecar.remove() }
        let sidecarInstalled = try tamperedSidecar.manager().install(pluginSourceURL: resource)
        let sidecar = ManagedHookProvenance.sidecarURL(for: sidecarInstalled.pluginFileURL)
        try Data("tampered-sidecar".utf8).write(to: sidecar)
        #expect((try tamperedSidecar.manager().status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try tamperedSidecar.manager().uninstall() }

        let recovery = try Fixture(); defer { recovery.remove() }
        try recovery.createConfig([:])
        let journal = ManagedHookFileSystem.journalURL(for: recovery.configFile)
        try Data("unresolved".utf8).write(to: journal)
        let journalBefore = try Data(contentsOf: journal)
        #expect((try recovery.manager().status()).managementOutcome == .unresolvedRecovery)
        #expect(throws: ManagedHookFileSystemError.self) { try recovery.manager().uninstall() }
        #expect(try Data(contentsOf: journal) == journalBefore)
    }

    @Test
    func verifiedUninstallRemovesOnlyProvenanceAndRevokesCredential() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try fixture.createConfig(["theme": "dark", "plugin": ["file:///tmp/other.js"]])
        var revoked = false
        let manager = fixture.manager { revoked = true }
        let resource = try makeVerifiedOpenCodePluginApp(at: fixture.root)
        let installed = try manager.install(pluginSourceURL: resource)
        let removed = try manager.uninstall()
        #expect(revoked)
        #expect(removed.managementOutcome == .unowned)
        #expect(try String(contentsOf: installed.configURL).contains("other.js"))
        #expect(!FileManager.default.fileExists(atPath: installed.pluginFileURL.path))
        #expect(!FileManager.default.fileExists(atPath: ManagedHookProvenance.sidecarURL(for: installed.configURL).path))
        #expect(!FileManager.default.fileExists(atPath: ManagedHookProvenance.sidecarURL(for: installed.pluginFileURL).path))
    }

    @Test
    func artifactFailureOccursBeforeAnyTargetCreationAndOutcomesHaveRemediation() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let bad = fixture.root.appendingPathComponent("untrusted.js")
        try Data("untrusted".utf8).write(to: bad)
        #expect(throws: BundledHookArtifactError.self) { try fixture.manager().install(pluginSourceURL: bad) }
        #expect(!FileManager.default.fileExists(atPath: fixture.config.path))
        #expect(HookManagementOutcome.ambiguousUnmanaged.exitStatus == 23)
        #expect(!HookManagementOutcome.unresolvedRecovery.remediation.isEmpty)
    }

    @Test
    func danglingProvenanceSiblingBlocksBeforePluginOrConfigMutation() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try fixture.createConfig(["theme": "dark"])
        let configBefore = try Data(contentsOf: fixture.configFile)
        let sidecar = ManagedHookProvenance.sidecarURL(for: fixture.configFile)
        try FileManager.default.createSymbolicLink(at: sidecar, withDestinationURL: fixture.root.appendingPathComponent("missing-sidecar"))

        let manager = fixture.manager()
        #expect((try manager.status()).managementOutcome == .unsafePath)
        #expect(throws: ManagedHookFileSystemError.self) {
            try manager.install(pluginSourceURL: makeVerifiedOpenCodePluginApp(at: fixture.root))
        }
        #expect(try Data(contentsOf: fixture.configFile) == configBefore)
        #expect(!FileManager.default.fileExists(atPath: fixture.config.appendingPathComponent("plugins/open-island.js").path))
    }

    private struct Fixture {
        let root: URL
        let config: URL
        var configFile: URL { config.appendingPathComponent("config.json") }
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("open-island-opencode-provenance-\(UUID().uuidString)", isDirectory: true)
            config = root.appendingPathComponent("opencode", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        func createConfig(_ object: [String: Any]) throws {
            try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: configFile)
        }
        func manager(revoker: @escaping () throws -> Void = {}) -> OpenCodePluginInstallationManager {
            OpenCodePluginInstallationManager(openCodeConfigDirectory: config, credentialRevoker: revoker)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
