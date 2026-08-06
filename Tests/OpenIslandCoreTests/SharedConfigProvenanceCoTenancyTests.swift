import Foundation
import Testing
@testable import OpenIslandCore

/// A managed hook target that Open Island shares with its host tool must stay
/// removable after a co-tenant edits or re-serializes the file.  Ownership is
/// proven by the exact managed entries, never by the whole file's bytes.
struct SharedConfigProvenanceCoTenancyTests {
    // MARK: - The ownership knob itself

    @Test
    func wholeFileDriftIsFatalForAnExclusiveTargetAndIgnoredForASharedOne() throws {
        let root = try makeRoot("ownership")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target.json")
        let original = Data(#"{"a":1}"#.utf8)
        try ManagedHookFileSystem.replace(original, at: target, expectedDigest: ManagedHookFileSystem.digest(of: original))
        try ManagedHookProvenance.record(
            ManagedHookProvenance(
                targetURL: target, managerID: "test-manager", formatVersion: "1",
                managedEntryDigest: "entry", preMutationDigest: nil,
                postMutationDigest: ManagedHookFileSystem.digest(of: original), backupDigest: nil
            ),
            for: target
        )

        // Unchanged: both readings verify.
        #expect(try ManagedHookProvenance.loadVerified(for: target, managerID: "test-manager", ownership: .exclusive) != nil)
        #expect(try ManagedHookProvenance.loadVerified(for: target, managerID: "test-manager", ownership: .shared) != nil)

        let drifted = Data(#"{ "a" : 1, "cotenant": true }"#.utf8)
        try ManagedHookFileSystem.replace(drifted, at: target, expectedDigest: ManagedHookFileSystem.digest(of: drifted))

        #expect(throws: ManagedHookFileSystemError.self) {
            try ManagedHookProvenance.loadVerified(for: target, managerID: "test-manager", ownership: .exclusive)
        }
        let shared = try ManagedHookProvenance.loadVerified(for: target, managerID: "test-manager", ownership: .shared)
        #expect(shared?.managedEntryDigest == "entry")

        // `.exclusive` is the default, so an unconsidered call site stays strict.
        #expect(throws: ManagedHookFileSystemError.self) {
            try ManagedHookProvenance.loadVerified(for: target, managerID: "test-manager")
        }
    }

    @Test
    func aMissingTargetIsAmbiguousUnderEitherOwnership() throws {
        let root = try makeRoot("missing")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target.json")
        let original = Data(#"{"a":1}"#.utf8)
        try ManagedHookFileSystem.replace(original, at: target, expectedDigest: ManagedHookFileSystem.digest(of: original))
        try ManagedHookProvenance.record(
            ManagedHookProvenance(
                targetURL: target, managerID: "test-manager", formatVersion: "1",
                managedEntryDigest: "entry", preMutationDigest: nil,
                postMutationDigest: ManagedHookFileSystem.digest(of: original), backupDigest: nil
            ),
            for: target
        )
        try FileManager.default.removeItem(at: target)

        for ownership in [ManagedHookProvenance.TargetOwnership.exclusive, .shared] {
            #expect(throws: ManagedHookFileSystemError.self) {
                try ManagedHookProvenance.loadVerified(for: target, managerID: "test-manager", ownership: ownership)
            }
        }
    }

    // MARK: - Codex: the reported failure

    /// The observed field failure: another tool rewrote `~/.codex/hooks.json`
    /// with its own serializer.  Not one managed byte changed, yet the whole
    /// file digest moved and reset was permanently blocked.
    @Test
    func codexRemainsManagedAfterACoTenantReserializesHooksJSON() throws {
        let fixture = try CodexFixture()
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "reserialize")
        let installed = try fixture.manager().install(hooksBinaryURL: helper)
        #expect(installed.managementOutcome == .exactManaged)

        // Same JSON, different bytes: no `.sortedKeys`, no `.prettyPrinted`.
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.hooksURL))
        let reserialized = try JSONSerialization.data(withJSONObject: object)
        #expect(reserialized != (try Data(contentsOf: installed.hooksURL)))
        try reserialized.write(to: installed.hooksURL)

        #expect((try fixture.manager().status()).managementOutcome == .exactManaged)
        let uninstalled = try fixture.manager().uninstall()
        #expect(uninstalled.managementOutcome == .unowned)
        #expect(!FileManager.default.fileExists(atPath: ManagedHookProvenance.sidecarURL(for: installed.hooksURL).path))
    }

    @Test
    func codexRemainsManagedAfterACoTenantAppendsItsOwnHookGroup() throws {
        let fixture = try CodexFixture()
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "cotenant")
        let installed = try fixture.manager().install(hooksBinaryURL: helper)

        let foreign: [String: Any] = [
            "hooks": [["type": "command", "command": "/bin/sh '/tmp/other-tool/hook.sh'", "timeout": 10]]
        ]
        var root = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.hooksURL)) as! [String: Any]
        var hooks = root["hooks"] as! [String: Any]
        hooks["Stop"] = (hooks["Stop"] as! [Any]) + [foreign]
        hooks["PostToolUse"] = [foreign]
        root["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]).write(to: installed.hooksURL)

        #expect((try fixture.manager().status()).managementOutcome == .exactManaged)
        #expect(try fixture.manager().uninstall().managementOutcome == .unowned)

        // Only our four groups left; the co-tenant's survive untouched.
        let after = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.hooksURL)) as! [String: Any]
        let remaining = after["hooks"] as! [String: Any]
        #expect(commands(in: remaining).allSatisfy { !$0.contains(fixture.binary.path) })
        #expect(commands(in: remaining).filter { $0.contains("other-tool/hook.sh") }.count == 2)
        #expect((remaining["Stop"] as! [Any]).count == 1)
    }

    /// The relaxation is scoped: changing a *managed* entry is still fatal.
    @Test
    func codexManagedEntryTamperingStillBlocksUninstall() throws {
        let fixture = try CodexFixture()
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "entry-tamper")
        let installed = try fixture.manager().install(hooksBinaryURL: helper)

        var root = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.hooksURL)) as! [String: Any]
        var hooks = root["hooks"] as! [String: Any]
        var groups = hooks["Stop"] as! [[String: Any]]
        var group = groups[0]
        var entries = group["hooks"] as! [[String: Any]]
        entries[0]["command"] = "'/tmp/attacker/OpenIslandHooks'"
        group["hooks"] = entries; groups[0] = group; hooks["Stop"] = groups
        root["hooks"] = hooks
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try tampered.write(to: installed.hooksURL)

        #expect((try fixture.manager().status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try fixture.manager().uninstall() }
        #expect(try Data(contentsOf: installed.hooksURL) == tampered)
    }

    /// The manifest is ours alone, so it keeps the strict whole-file check.
    @Test
    func codexManifestDriftStillBlocksUninstall() throws {
        let fixture = try CodexFixture()
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "manifest-drift")
        let installed = try fixture.manager().install(hooksBinaryURL: helper)

        // Still-decodable JSON, different bytes — an exclusive target must
        // reject this even though nothing semantic changed.
        let manifest = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.manifestURL))
        let drifted = try JSONSerialization.data(withJSONObject: manifest, options: [])
        #expect(drifted != (try Data(contentsOf: installed.manifestURL)))
        try drifted.write(to: installed.manifestURL)

        #expect((try fixture.manager().status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try fixture.manager().uninstall() }
    }

    // MARK: - Claude: settings.json is rewritten by its own host tool

    @Test
    func claudeRemainsManagedAfterItsHostToolEditsSettings() throws {
        let fixture = try ClaudeFixture()
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "claude-cotenant")
        let installed = try fixture.manager().install(hooksBinaryURL: helper)
        #expect(installed.managementOutcome == .exactManaged)

        // Claude Code writes to settings.json on every permission grant.
        var settings = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.settingsURL)) as! [String: Any]
        settings["permissions"] = ["allow": ["Bash(git status:*)"]]
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted]).write(to: installed.settingsURL)

        #expect((try fixture.manager().status()).managementOutcome == .exactManaged)
        #expect(try fixture.manager().uninstall().managementOutcome == .unowned)

        let after = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.settingsURL)) as! [String: Any]
        #expect(after["permissions"] != nil, "an unrelated co-tenant key must survive uninstall")
        #expect(!(try String(contentsOf: installed.settingsURL, encoding: .utf8)).contains(fixture.binary.path))
    }

    /// A co-tenant that installs after us appends its group past ours, so the
    /// managed group is no longer last in the event's list.
    @Test
    func claudeRemainsManagedWhenACoTenantAppendsAfterTheManagedGroup() throws {
        let fixture = try ClaudeFixture()
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "claude-order")
        let installed = try fixture.manager().install(hooksBinaryURL: helper)

        var settings = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.settingsURL)) as! [String: Any]
        var hooks = settings["hooks"] as! [String: Any]
        let foreign: [String: Any] = ["hooks": [["type": "command", "command": "/bin/sh '/tmp/late-tool/hook.sh'"]]]
        hooks["Stop"] = (hooks["Stop"] as! [Any]) + [foreign]
        settings["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: installed.settingsURL)

        #expect((try fixture.manager().status()).managementOutcome == .exactManaged)
        #expect(try fixture.manager().uninstall().managementOutcome == .unowned)

        let after = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.settingsURL)) as! [String: Any]
        let remaining = (after["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        #expect(remaining.count == 1)
        #expect(commands(in: ["Stop": remaining]) == ["/bin/sh '/tmp/late-tool/hook.sh'"])
    }

    /// Order-insensitivity must not become duplicate-insensitivity.
    @Test
    func claudeDuplicatedManagedGroupIsStillAmbiguous() throws {
        let fixture = try ClaudeFixture()
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "claude-dupe")
        let installed = try fixture.manager().install(hooksBinaryURL: helper)

        var settings = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.settingsURL)) as! [String: Any]
        var hooks = settings["hooks"] as! [String: Any]
        let groups = hooks["Stop"] as! [Any]
        hooks["Stop"] = groups + [groups.last!]
        settings["hooks"] = hooks
        let doubled = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try doubled.write(to: installed.settingsURL)

        #expect((try fixture.manager().status()).managementOutcome == .ambiguousUnmanaged)
        #expect(throws: ManagedHookFileSystemError.self) { try fixture.manager().uninstall() }
        #expect(try Data(contentsOf: installed.settingsURL) == doubled)
    }

    /// Installs predating the entry-scoped digest recorded the whole settings
    /// file instead.  Those records exist on disk today and must keep working.
    @Test
    func claudeLegacyWholeFileEntryDigestStillVerifiesAfterCoTenantEdits() throws {
        let fixture = try ClaudeFixture()
        defer { fixture.remove() }
        let helper = try makeVerifiedHooksApp(at: fixture.root, contents: "claude-legacy")
        let installed = try fixture.manager().install(hooksBinaryURL: helper)

        // Rewrite the sidecar the way the previous format did.
        let sidecarURL = ManagedHookProvenance.sidecarURL(for: installed.settingsURL)
        var record = try JSONDecoder().decode(ManagedHookProvenance.self, from: try Data(contentsOf: sidecarURL))
        #expect(record.managedEntryDigest != record.postMutationDigest, "install must write the entry-scoped digest")
        record.managedEntryDigest = record.postMutationDigest
        try ManagedHookProvenance.record(record, for: installed.settingsURL)

        #expect((try fixture.manager().status()).managementOutcome == .exactManaged)

        var settings = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.settingsURL)) as! [String: Any]
        settings["permissions"] = ["allow": ["Bash(git status:*)"]]
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted]).write(to: installed.settingsURL)

        #expect((try fixture.manager().status()).managementOutcome == .exactManaged)
        #expect(try fixture.manager().uninstall().managementOutcome == .unowned)
    }

    @Test
    func geminiRemainsManagedAfterACoTenantReserializesSettings() throws {
        let root = try makeRoot("gemini")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent(".gemini", isDirectory: true)
        let binary = root.appendingPathComponent("managed/OpenIslandHooks")
        func manager() -> GeminiHookInstallationManager {
            GeminiHookInstallationManager(geminiDirectory: directory, managedHooksBinaryURL: binary, credentialRevoker: {})
        }
        let helper = try makeVerifiedHooksApp(at: root, contents: "gemini-cotenant")
        let installed = try manager().install(hooksBinaryURL: helper)
        #expect(installed.managementOutcome == .exactManaged)

        var settings = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.settingsURL)) as! [String: Any]
        settings["theme"] = "Default"
        try JSONSerialization.data(withJSONObject: settings, options: []).write(to: installed.settingsURL)

        #expect((try manager().status()).managementOutcome == .exactManaged)
        #expect(try manager().uninstall().managementOutcome == .unowned)
        let after = try JSONSerialization.jsonObject(with: try Data(contentsOf: installed.settingsURL)) as! [String: Any]
        #expect(after["theme"] as? String == "Default")
    }

    // MARK: - Fixtures

    /// Every hook command in a `hooks` object, flattened across events.
    private func commands(in hooks: [String: Any]) -> [String] {
        hooks.values.flatMap { value -> [String] in
            (value as? [[String: Any]] ?? []).flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            }
        }
    }

    private func makeRoot(_ label: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-shared-provenance-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return root
    }

    private struct CodexFixture {
        let root: URL
        let codex: URL
        let binary: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("open-island-codex-cotenant-\(UUID().uuidString)", isDirectory: true)
            codex = root.appendingPathComponent(".codex", isDirectory: true)
            binary = root.appendingPathComponent("managed/OpenIslandHooks")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        func manager() -> CodexHookInstallationManager {
            CodexHookInstallationManager(codexDirectory: codex, managedHooksBinaryURL: binary, credentialRevoker: {})
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private struct ClaudeFixture {
        let root: URL
        let directory: URL
        let binary: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("open-island-claude-cotenant-\(UUID().uuidString)", isDirectory: true)
            directory = root.appendingPathComponent(".claude", isDirectory: true)
            binary = root.appendingPathComponent("managed/OpenIslandHooks")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        func manager() -> ClaudeHookInstallationManager {
            ClaudeHookInstallationManager(claudeDirectory: directory, managedHooksBinaryURL: binary, hookSource: "claude", credentialRevoker: {})
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
