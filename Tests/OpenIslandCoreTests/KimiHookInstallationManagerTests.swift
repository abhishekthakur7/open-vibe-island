import Foundation
import Testing
@testable import OpenIslandCore

struct KimiHookInstallationManagerTests {
    @Test
    func verifiedInstallIsExactIdempotentAndUninstallRevokesCredential() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        var revoked = false
        let manager = fixture.manager { revoked = true }
        let installed = try manager.install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: "kimi"))
        #expect(installed.managementOutcome == .exactManaged)
        #expect(installed.manifest?.hookCommand == KimiHookInstaller.hookCommand(for: fixture.binary.path))
        for target in [installed.configURL, installed.manifestURL] {
            let sidecar = ManagedHookProvenance.sidecarURL(for: target)
            #expect(FileManager.default.fileExists(atPath: sidecar.path))
            #expect((try FileManager.default.attributesOfItem(atPath: sidecar.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        let before = try Data(contentsOf: installed.configURL)
        #expect((try manager.install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: "kimi"))).managementOutcome == .exactManaged)
        #expect(try Data(contentsOf: installed.configURL) == before)
        #expect((try manager.uninstall()).managementOutcome == .unowned)
        #expect(revoked)
    }

    @Test
    func mergesUnrelatedTomlButTreatsManagedLookingEntriesAsUnowned() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try fixture.createKimi()
        let config = fixture.directory.appendingPathComponent("config.toml")
        let original = Data("default_model = \"kimi\"\n\n[[hooks]]\nevent = \"Stop\"\ncommand = \"/tmp/OpenIslandHooks-lookalike --source kimi\"\n".utf8)
        try original.write(to: config)
        let status = try fixture.manager().status()
        #expect(status.managementOutcome == .unowned)
        let installed = try fixture.manager().install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: "lookalike"))
        #expect(installed.managementOutcome == .exactManaged)
        #expect(try String(contentsOf: config).contains("OpenIslandHooks-lookalike"))
    }

    @Test(arguments: ["partial", "duplicate", "wrong-command"])
    func malformedManagedBlocksAreAmbiguousAndUntouched(kind: String) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try fixture.createKimi()
        let command = KimiHookInstaller.hookCommand(for: fixture.binary.path)
        var contents = try #require(KimiHookInstaller.installConfigTOML(existingContents: nil, hookCommand: command).contents)
        switch kind {
        case "partial": contents = contents.replacingOccurrences(of: "# open-island: managed hook — do not edit\n[[hooks]]\nevent = \"Notification\"\ncommand = \"\(command)\"\ntimeout = 45\n\n", with: "")
        case "wrong-command": contents = contents.replacingOccurrences(of: "--source kimi", with: "--source claude")
        default: contents += "\n" + contents
        }
        let config = fixture.directory.appendingPathComponent("config.toml")
        try Data(contents.utf8).write(to: config)
        let manager = fixture.manager()
        #expect((try manager.status()).managementOutcome == .ambiguousUnmanaged)
        let before = try Data(contentsOf: config)
        #expect(throws: ManagedHookFileSystemError.self) { try manager.install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: kind)) }
        #expect(try Data(contentsOf: config) == before)
        #expect(throws: ManagedHookFileSystemError.self) { try manager.uninstall() }
    }

    @Test(arguments: ["config", "manifest", "sidecar"])
    func tamperedEvidenceAndRecoveryJournalBlockMutations(target: String) throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let manager = fixture.manager()
        let installed = try manager.install(hooksBinaryURL: makeVerifiedHooksApp(at: fixture.root, contents: "tamper"))
        let targetURL: URL = switch target { case "config": installed.configURL; case "manifest": installed.manifestURL; default: ManagedHookProvenance.sidecarURL(for: installed.configURL) }
        try Data("tampered".utf8).write(to: targetURL)
        let before = try Data(contentsOf: targetURL)
        #expect((try manager.status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try manager.uninstall() }
        #expect(try Data(contentsOf: targetURL) == before)

        let clean = try Fixture(); defer { clean.remove() }
        try clean.createKimi()
        let journal = ManagedHookFileSystem.journalURL(for: clean.directory.appendingPathComponent("config.toml"))
        try Data("unresolved".utf8).write(to: journal)
        #expect((try clean.manager().status()).managementOutcome == .unresolvedRecovery)
        #expect(throws: ManagedHookFileSystemError.self) { try clean.manager().install(hooksBinaryURL: makeVerifiedHooksApp(at: clean.root, contents: "journal")) }
    }

    @Test
    func artifactFailureAndUnsafeFileOrDirectoryNeverCreateOrReplaceTargets() throws {
        let clean = try Fixture(); defer { clean.remove() }
        #expect(throws: BundledHookArtifactError.self) { try clean.manager().install(hooksBinaryURL: clean.root.appendingPathComponent("untrusted/OpenIslandHooks")) }
        #expect(!FileManager.default.fileExists(atPath: clean.directory.path))
        #expect(!FileManager.default.fileExists(atPath: clean.binary.deletingLastPathComponent().path))

        let linked = try Fixture(); defer { linked.remove() }
        try linked.createKimi()
        let outside = linked.root.appendingPathComponent("outside.toml")
        try Data("user = true".utf8).write(to: outside)
        let config = linked.directory.appendingPathComponent("config.toml")
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: outside)
        #expect((try linked.manager().status()).managementOutcome == .unsafePath)
        #expect(throws: ManagedHookFileSystemError.self) { try linked.manager().install(hooksBinaryURL: makeVerifiedHooksApp(at: linked.root, contents: "symlink")) }
        #expect(try Data(contentsOf: outside) == Data("user = true".utf8))

        let unsafeDirectory = try Fixture(); defer { unsafeDirectory.remove() }
        try FileManager.default.createSymbolicLink(at: unsafeDirectory.directory, withDestinationURL: unsafeDirectory.root)
        #expect((try unsafeDirectory.manager().status()).managementOutcome == .unsafePath)
    }

    private struct Fixture {
        let root: URL
        let directory: URL
        let binary: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("open-island-kimi-manager-\(UUID().uuidString)", isDirectory: true)
            directory = root.appendingPathComponent(".kimi", isDirectory: true)
            binary = root.appendingPathComponent("managed/OpenIslandHooks")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        func createKimi() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        func manager(revoker: @escaping () throws -> Void = {}) -> KimiHookInstallationManager { KimiHookInstallationManager(kimiDirectory: directory, managedHooksBinaryURL: binary, credentialRevoker: revoker) }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
