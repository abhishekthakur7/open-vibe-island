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
