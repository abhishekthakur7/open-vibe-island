import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeStatusLineTemplateTests {
    @Test
    func signedFixtureManifestInventoriesEveryStatusLineTemplate() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let templates = try makeVerifiedClaudeStatusLineTemplateResources(at: root)
        #expect([templates.normal, templates.wrapper, templates.delegate].map(\.entry.artifactID).sorted() == [
            "claude-statusline-delegate-template",
            "claude-statusline-script-template",
            "claude-statusline-wrapper-template",
        ])
        for resource in [templates.normal, templates.wrapper, templates.delegate] {
            #expect(resource.entry.version == 1)
            #expect(resource.entry.templateVersion == "1")
            #expect(resource.entry.managedMarker == ClaudeStatusLineInstallationManager.managedTemplateMarker)
            #expect(resource.entry.relativePath.hasPrefix("Contents/Resources/ClaudeStatusLineTemplates/"))
            #expect(resource.entry.sha256 == ManagedHookFileSystem.digest(of: resource.data))
            #expect(resource.entry.expectedMode == 0o644)
        }
    }

    @Test(arguments: ["unexpected", "missing"])
    func rejectsUnexpectedOrMissingTemplatePlaceholdersWithoutMutation(kind: String) throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let templates = try makeVerifiedClaudeStatusLineTemplateResources(at: root)
        let source = String(data: templates.normal.data, encoding: .utf8)!
        let changed = kind == "unexpected"
            ? source.replacingOccurrences(of: "{{OPEN_ISLAND_CACHE_PATH_SHELL_QUOTED}}", with: "{{UNEXPECTED_PLACEHOLDER}}")
            : source.replacingOccurrences(of: "{{OPEN_ISLAND_CACHE_PATH_SHELL_QUOTED}}", with: "cache")
        let changedData = Data(changed.utf8)
        try changedData.write(to: templates.normal.resourceURL)
        let invalid = resourceLike(templates.normal, data: changedData)
        let manager = manager(root: root, templates: ClaudeStatusLineTemplateResources(normal: invalid, wrapper: templates.wrapper, delegate: templates.delegate))

        #expect(throws: ClaudeStatusLineInstallationError.self) { try manager.install() }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".claude").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("bin").path))
    }

    @Test
    func tamperedOrMissingTemplateFailsBeforeAnyTargetMutation() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let templates = try makeVerifiedClaudeStatusLineTemplateResources(at: root)
        try Data("tampered".utf8).write(to: templates.normal.resourceURL)
        let manager = manager(root: root, templates: templates)

        #expect(throws: ClaudeStatusLineInstallationError.self) { try manager.install() }
        #expect(HookManagementOutcome.from(error: ClaudeStatusLineInstallationError.unverifiedTemplate) == .unverifiedArtifact)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".claude").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("bin").path))

        let missing = templates.wrapper.resourceURL.deletingLastPathComponent().appendingPathComponent("missing.template")
        #expect(throws: BundledHookArtifactError.self) { try VerifiedBundledHookArtifact.verifiedResource(at: missing) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".claude").path))
    }

    @Test
    func staleTemplateVersionFailsBeforeAnyTargetMutation() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let templates = try makeVerifiedClaudeStatusLineTemplateResources(at: root)
        var staleEntry = templates.normal.entry
        staleEntry.templateVersion = "0"
        let stale = VerifiedBundledResource(resourceURL: templates.normal.resourceURL, entry: staleEntry, data: templates.normal.data)
        let manager = manager(root: root, templates: ClaudeStatusLineTemplateResources(normal: stale, wrapper: templates.wrapper, delegate: templates.delegate))

        #expect(throws: ClaudeStatusLineInstallationError.self) { try manager.install() }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".claude").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("bin").path))
    }

    @Test
    func interpolationShellQuotesLocalPathsAndOriginalCommands() throws {
        let root = try temporaryRoot(named: "open-island status'line"); defer { try? FileManager.default.removeItem(at: root) }
        let templates = try makeVerifiedClaudeStatusLineTemplateResources(at: root)
        let scriptDirectory = root.appendingPathComponent("bin path'quoted")
        let claudeDirectory = root.appendingPathComponent(".claude")
        let original = "printf '%s' \"status line\"; echo done"
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": original]], options: [.sortedKeys]).write(to: claudeDirectory.appendingPathComponent("settings.json"))
        let manager = ClaudeStatusLineInstallationManager(claudeDirectory: claudeDirectory, scriptDirectoryURL: scriptDirectory, templateResources: templates)

        let installed = try manager.installAsWrapper()
        let wrapper = try String(contentsOf: installed.scriptURL, encoding: .utf8)
        let delegate = try String(contentsOf: scriptDirectory.appendingPathComponent(ClaudeStatusLineInstallationManager.wrappedDelegateScriptName), encoding: .utf8)
        #expect(wrapper.contains("delegate_path='"))
        #expect(wrapper.contains("'\"'\"'"))
        #expect(delegate.contains("original_command='printf '"))
        #expect(delegate.contains("exec /bin/bash -c \"$original_command\""))
        #expect(!delegate.contains("\n\(original)\n"))
    }

    @Test
    func danglingStatusLineProvenanceBlocksBeforeScriptCreation() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let templates = try makeVerifiedClaudeStatusLineTemplateResources(at: root)
        let claudeDirectory = root.appendingPathComponent(".claude")
        let settings = claudeDirectory.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data("{}".utf8).write(to: settings)
        let sidecar = ManagedHookProvenance.sidecarURL(for: settings)
        try FileManager.default.createSymbolicLink(at: sidecar, withDestinationURL: root.appendingPathComponent("missing-sidecar"))
        let manager = ClaudeStatusLineInstallationManager(
            claudeDirectory: claudeDirectory,
            scriptDirectoryURL: root.appendingPathComponent("bin"),
            legacyScriptDirectoryURL: root.appendingPathComponent("legacy-bin"),
            templateResources: templates
        )

        #expect(throws: ManagedHookFileSystemError.self) { try manager.install() }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("bin/open-island-statusline").path))
        #expect(try Data(contentsOf: settings) == Data("{}".utf8))
    }

    private func resourceLike(_ resource: VerifiedBundledResource, data: Data) -> VerifiedBundledResource {
        var entry = resource.entry
        entry.sha256 = ManagedHookFileSystem.digest(of: data)
        return VerifiedBundledResource(resourceURL: resource.resourceURL, entry: entry, data: data)
    }

    private func manager(root: URL, templates: ClaudeStatusLineTemplateResources) -> ClaudeStatusLineInstallationManager {
        ClaudeStatusLineInstallationManager(
            claudeDirectory: root.appendingPathComponent(".claude"),
            scriptDirectoryURL: root.appendingPathComponent("bin"),
            templateResources: templates
        )
    }

    private func temporaryRoot(named: String = "open-island-status-template") throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("\(named)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return root
    }
}
