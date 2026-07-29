import Foundation
import Testing
@testable import OpenIslandCore

struct CodexHookInstallationManagerTests {
    @Test
    func cleanInstallWritesPrivateExactProvenanceAndIsIdempotent() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager()
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "codex-provenance")

        let installed = try manager.install(hooksBinaryURL: helper)
        #expect(installed.managementOutcome == .exactManaged)
        for target in [installed.hooksURL, installed.manifestURL, installed.configURL] {
            let sidecar = ManagedHookProvenance.sidecarURL(for: target)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                let mode = (try FileManager.default.attributesOfItem(atPath: sidecar.path)[.posixPermissions] as? NSNumber)?.intValue
                #expect(mode == 0o600)
            }
        }
        let hooksBefore = try Data(contentsOf: installed.hooksURL)
        let sidecarBefore = try Data(contentsOf: ManagedHookProvenance.sidecarURL(for: installed.hooksURL))
        let reinstalled = try manager.install(hooksBinaryURL: helper)
        #expect(reinstalled.managementOutcome == .exactManaged)
        #expect(try Data(contentsOf: installed.hooksURL) == hooksBefore)
        #expect(try Data(contentsOf: ManagedHookProvenance.sidecarURL(for: installed.hooksURL)) == sidecarBefore)
    }

    @Test
    func installPreservesUnrelatedConfigAndDoesNotTreatLookalikesAsOwnership() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createCodex()
        let config = fixture.codex.appendingPathComponent("config.toml")
        let hooks = fixture.codex.appendingPathComponent("hooks.json")
        try Data("model = \"o3\"\n[projects.\"/tmp\"]\ntrust_level = \"trusted\"\n".utf8).write(to: config)
        let lookalike = """
        {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"'/tmp/OpenIslandHooks-lookalike'","timeout":7}]}]}}
        """
        try Data(lookalike.utf8).write(to: hooks)
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "lookalike")

        let status = try fixture.manager().install(hooksBinaryURL: helper)
        #expect(status.managementOutcome == .exactManaged)
        let resultingConfig = try String(contentsOf: config)
        #expect(resultingConfig.contains("model = \"o3\""))
        #expect(resultingConfig.contains("trust_level = \"trusted\""))
        #expect(try String(contentsOf: hooks).contains("OpenIslandHooks-lookalike"))
    }

    @Test(arguments: ["partial", "wrong-command", "extra-conflict"])
    func managedLookingEntriesAreAmbiguousAndNeverMutated(kind: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createCodex()
        let command = CodexHookInstaller.hookCommand(for: fixture.binary.path)
        let base = try CodexHookInstaller.appendExactManagedHooksJSON(existingData: nil, hookCommand: command).contents!
        var root = try JSONSerialization.jsonObject(with: base) as! [String: Any]
        var hooks = root["hooks"] as! [String: Any]
        switch kind {
        case "partial":
            hooks.removeValue(forKey: "Stop")
        case "wrong-command":
            var groups = hooks["Stop"] as! [[String: Any]]
            var group = groups[0]
            var entries = group["hooks"] as! [[String: Any]]
            entries[0]["command"] = "'/tmp/stale/OpenIslandHooks'"
            group["hooks"] = entries; groups[0] = group; hooks["Stop"] = groups
        default:
            let group = (hooks["Stop"] as! [[String: Any]])[0]
            hooks["Stop"] = (hooks["Stop"] as! [[String: Any]]) + [group]
        }
        root["hooks"] = hooks
        let conflicting = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try conflicting.write(to: fixture.codex.appendingPathComponent("hooks.json"))
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "conflict")

        #expect((try fixture.manager().status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try fixture.manager().install(hooksBinaryURL: helper) }
        #expect(try Data(contentsOf: fixture.codex.appendingPathComponent("hooks.json")) == conflicting)
        #expect(throws: ManagedHookFileSystemError.self) { try fixture.manager().uninstall() }
        #expect(try Data(contentsOf: fixture.codex.appendingPathComponent("hooks.json")) == conflicting)
    }

    @Test
    func tamperedOrMissingProvenanceBlocksUninstallWithoutChangingTargets() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "tamper")
        let manager = fixture.manager()
        let installed = try manager.install(hooksBinaryURL: helper)
        try Data("tampered".utf8).write(to: installed.hooksURL)
        let tampered = try Data(contentsOf: installed.hooksURL)
        let tamperedOutcome = try manager.status().managementOutcome
        #expect(tamperedOutcome == .ambiguousUnmanaged, "actual: \(tamperedOutcome.rawValue)")
        #expect(throws: ManagedHookFileSystemError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: installed.hooksURL) == tampered)

        let second = try Fixture()
        defer { second.remove() }
        let secondHelper = try makeVerifiedHooksApp(at: second.root, contents: "missing-sidecar")
        let secondManager = second.manager()
        let secondInstalled = try secondManager.install(hooksBinaryURL: secondHelper)
        try FileManager.default.removeItem(at: ManagedHookProvenance.sidecarURL(for: secondInstalled.hooksURL))
        let bytes = try Data(contentsOf: secondInstalled.hooksURL)
        #expect((try secondManager.status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try secondManager.uninstall() }
        #expect(try Data(contentsOf: secondInstalled.hooksURL) == bytes)

        let third = try Fixture()
        defer { third.remove() }
        let thirdHelper = try makeVerifiedHooksApp(at: third.root, contents: "tampered-sidecar")
        let thirdManager = third.manager()
        let thirdInstalled = try thirdManager.install(hooksBinaryURL: thirdHelper)
        let sidecar = ManagedHookProvenance.sidecarURL(for: thirdInstalled.hooksURL)
        try Data("tampered-sidecar".utf8).write(to: sidecar)
        let thirdBytes = try Data(contentsOf: thirdInstalled.hooksURL)
        #expect((try thirdManager.status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try thirdManager.uninstall() }
        #expect(try Data(contentsOf: thirdInstalled.hooksURL) == thirdBytes)
    }

    @Test
    func verifiedUninstallRevokesCredentialAndJournalIsReadOnlyRecoveryState() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var revoked = false
        let manager = fixture.manager { revoked = true }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "revoke")
        let installed = try manager.install(hooksBinaryURL: helper)
        let removed = try manager.uninstall()
        #expect(revoked)
        #expect(removed.managementOutcome == .unowned)
        #expect(!FileManager.default.fileExists(atPath: ManagedHookProvenance.sidecarURL(for: installed.hooksURL).path))

        let recovery = try Fixture()
        defer { recovery.remove() }
        try recovery.createCodex()
        let journal = ManagedHookFileSystem.journalURL(for: recovery.codex.appendingPathComponent("hooks.json"))
        try Data("unresolved".utf8).write(to: journal)
        let before = try Data(contentsOf: journal)
        #expect((try recovery.manager().status()).managementOutcome == .unresolvedRecovery)
        #expect(throws: ManagedHookFileSystemError.self) { try recovery.manager().uninstall() }
        #expect(try Data(contentsOf: journal) == before)
    }

    @Test
    func danglingProvenanceSiblingBlocksBeforeCodexTargetMutation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createCodex()
        let config = fixture.codex.appendingPathComponent("config.toml")
        let configBefore = Data("model = \"o3\"\n".utf8)
        try configBefore.write(to: config)
        try FileManager.default.createSymbolicLink(
            at: ManagedHookProvenance.sidecarURL(for: config),
            withDestinationURL: fixture.root.appendingPathComponent("missing-sidecar")
        )
        let manager = fixture.manager()

        #expect((try manager.status()).managementOutcome == .unsafePath)
        #expect(throws: ManagedHookFileSystemError.self) {
            try manager.install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: "codex-dangling-sidecar"))
        }
        #expect(try Data(contentsOf: config) == configBefore)
        #expect(!FileManager.default.fileExists(atPath: fixture.codex.appendingPathComponent("hooks.json").path))
    }

    private struct Fixture {
        let root: URL
        let codex: URL
        let binary: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("open-island-codex-provenance-\(UUID().uuidString)", isDirectory: true)
            codex = root.appendingPathComponent(".codex", isDirectory: true)
            binary = root.appendingPathComponent("managed/OpenIslandHooks")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        func createCodex() throws {
            try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        func manager(revoker: @escaping () throws -> Void = {}) -> CodexHookInstallationManager {
            CodexHookInstallationManager(codexDirectory: codex, managedHooksBinaryURL: binary, credentialRevoker: revoker)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
