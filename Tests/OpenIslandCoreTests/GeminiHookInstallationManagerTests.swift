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
