import Foundation
import Testing
@testable import OpenIslandCore

struct CursorHookInstallationManagerTests {
    @Test
    func verifiedInstallIsIdempotentAndVerifiedUninstallRevokesCredential() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "cursor-verified")
        var revoked = false
        let manager = fixture.manager { revoked = true }

        let installed = try manager.install(hooksBinaryURL: helper)
        #expect(installed.managementOutcome == .exactManaged)
        #expect(installed.managedHooksPresent)
        #expect(installed.manifest?.hookCommand == CursorHookInstaller.hookCommand(for: fixture.binary.path))
        for target in [installed.hooksURL, installed.manifestURL] {
            let sidecar = ManagedHookProvenance.sidecarURL(for: target)
            #expect(FileManager.default.fileExists(atPath: sidecar.path))
            #expect((try FileManager.default.attributesOfItem(atPath: sidecar.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        let hooksBefore = try Data(contentsOf: installed.hooksURL)
        let sidecarBefore = try Data(contentsOf: ManagedHookProvenance.sidecarURL(for: installed.hooksURL))
        #expect((try manager.install(hooksBinaryURL: helper)).managementOutcome == .exactManaged)
        #expect(try Data(contentsOf: installed.hooksURL) == hooksBefore)
        #expect(try Data(contentsOf: ManagedHookProvenance.sidecarURL(for: installed.hooksURL)) == sidecarBefore)

        let upgradedHelper = try makeVerifiedHooksApp(at: fixture.root.appendingPathComponent("upgraded", isDirectory: true), contents: "cursor-upgraded")
        #expect((try manager.install(hooksBinaryURL: upgradedHelper)).managementOutcome == .exactManaged)
        #expect(try Data(contentsOf: installed.hooksURL) == hooksBefore)

        let removed = try manager.uninstall()
        #expect(removed.managementOutcome == .unowned)
        #expect(revoked)
        #expect(!FileManager.default.fileExists(atPath: ManagedHookProvenance.sidecarURL(for: installed.hooksURL).path))
    }

    @Test
    func preservesUnrelatedHooksAndDoesNotTreatLookalikesAsOwnership() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createCursor()
        let hooks = fixture.directory.appendingPathComponent("hooks.json")
        let lookalike = "'/tmp/OpenIslandHooks-lookalike' --source cursor"
        let original = Data("{\"custom\":true,\"hooks\":{\"stop\":[{\"command\":\"\(lookalike)\"}]}}".utf8)
        try original.write(to: hooks)

        let installed = try fixture.manager().install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: "lookalike"))
        #expect(installed.managementOutcome == .exactManaged)
        #expect(try String(contentsOf: hooks).contains("OpenIslandHooks-lookalike"))
        #expect(try String(contentsOf: hooks).contains("custom"))
    }

    @Test(arguments: ["partial", "stale-path", "extra-conflict"])
    func managedLookingEntriesAreAmbiguousAndNeverMutated(kind: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createCursor()
        let command = CursorHookInstaller.hookCommand(for: fixture.binary.path)
        let base = try CursorHookInstaller.installHooksJSON(existingData: nil, hookCommand: command).contents!
        var root = try JSONSerialization.jsonObject(with: base) as! [String: Any]
        var hooks = root["hooks"] as! [String: Any]
        switch kind {
        case "partial": hooks.removeValue(forKey: "stop")
        case "stale-path":
            var entries = hooks["stop"] as! [[String: Any]]
            entries[0]["command"] = "'/tmp/stale/OpenIslandHooks' --source cursor"
            hooks["stop"] = entries
        default:
            hooks["stop"] = (hooks["stop"] as! [[String: Any]]) + [(hooks["stop"] as! [[String: Any]])[0]]
        }
        root["hooks"] = hooks
        let conflicting = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let target = fixture.directory.appendingPathComponent("hooks.json")
        try conflicting.write(to: target)

        let manager = fixture.manager()
        let outcome = try manager.status().managementOutcome
        #expect(outcome == .ambiguousUnmanaged, "actual: \(outcome.rawValue)")
        #expect(throws: ManagedHookFileSystemError.self) { try manager.install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: kind)) }
        #expect(try Data(contentsOf: target) == conflicting)
        #expect(throws: ManagedHookFileSystemError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: target) == conflicting)
    }

    @Test(arguments: ["hooks", "manifest", "sidecar"])
    func tamperedOwnershipEvidenceBlocksUninstallWithoutChangingBytes(target: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager()
        let installed = try manager.install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: "tamper"))
        let targetURL: URL = switch target {
        case "hooks": installed.hooksURL
        case "manifest": installed.manifestURL
        default: ManagedHookProvenance.sidecarURL(for: installed.hooksURL)
        }
        try Data("tampered".utf8).write(to: targetURL)
        let bytes = try Data(contentsOf: targetURL)
        let outcome = try manager.status().managementOutcome
        #expect(outcome == .ambiguousUnmanaged, "actual: \(outcome.rawValue)")
        #expect(throws: ManagedHookFileSystemError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: targetURL) == bytes)
    }

    @Test
    func failedArtifactJournalAndUnsafeLinksNeverCreateOrReadTargets() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager()
        #expect(throws: BundledHookArtifactError.self) { try manager.install(hooksBinaryURL: fixture.root.appendingPathComponent("untrusted/OpenIslandHooks")) }
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.binary.deletingLastPathComponent().path))

        try fixture.createCursor()
        let journal = ManagedHookFileSystem.journalURL(for: fixture.directory.appendingPathComponent("hooks.json"))
        try Data("unresolved".utf8).write(to: journal)
        let before = try Data(contentsOf: journal)
        #expect((try manager.status()).managementOutcome == .unresolvedRecovery)
        #expect(throws: ManagedHookFileSystemError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: journal) == before)

        let linkFixture = try Fixture()
        defer { linkFixture.remove() }
        try linkFixture.createCursor()
        let outside = linkFixture.root.appendingPathComponent("outside")
        try Data("{}".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: linkFixture.directory.appendingPathComponent("hooks.json"), withDestinationURL: outside)
        #expect((try linkFixture.manager().status()).managementOutcome == .unsafePath)
    }

    private struct Fixture {
        let root: URL
        let directory: URL
        let binary: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("open-island-cursor-manager-\(UUID().uuidString)", isDirectory: true)
            directory = root.appendingPathComponent(".cursor", isDirectory: true)
            binary = root.appendingPathComponent("managed/OpenIslandHooks")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        func createCursor() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        func manager(revoker: @escaping () throws -> Void = {}) -> CursorHookInstallationManager { CursorHookInstallationManager(cursorDirectory: directory, managedHooksBinaryURL: binary, credentialRevoker: revoker) }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
