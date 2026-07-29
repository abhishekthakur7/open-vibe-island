import Foundation
import Testing
@testable import OpenIslandCore

struct ManagedHooksBinaryTests {
    @Test
    func verifiedInstallWritesExactPrivateProvenanceAndIsIdempotent() throws {
        let root = try helperRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = try makeVerifiedHooksApp(at: root, contents: "helper-v1")
        let artifact = try VerifiedBundledHookArtifact.verify(helperURL: helper)
        let destination = root.appendingPathComponent("managed/OpenIslandHooks")

        #expect(try ManagedHooksBinary.install(from: artifact, to: destination) == destination.standardizedFileURL)
        let loadedRecord = try ManagedHookProvenance.loadVerified(for: destination, managerID: "open-island-hooks-binary")
        let record = try #require(loadedRecord)
        #expect(record.targetPath == destination.standardizedFileURL.path)
        #expect(record.artifactID == VerifiedBundledHookArtifact.helperID)
        #expect(record.artifactVersion == 1)
        #expect(record.artifactSHA256 == artifact.entry.sha256)
        #expect(record.artifactExpectedMode == artifact.entry.expectedMode)
        #expect(record.artifactManagedMarker == artifact.entry.managedMarker)
        #expect(record.artifactTemplateVersion == artifact.entry.templateVersion)
        #expect(record.postMutationDigest == artifact.entry.sha256)
        #expect(record.preMutationDigest == nil)
        #expect((try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber)?.uint16Value == artifact.entry.expectedMode)
        let sidecar = ManagedHookProvenance.sidecarURL(for: destination)
        let sidecarBefore = try Data(contentsOf: sidecar)

        _ = try ManagedHooksBinary.install(from: artifact, to: destination)
        #expect(try Data(contentsOf: sidecar) == sidecarBefore)
        #expect(ManagedHooksBinary.managementOutcome(at: destination) == .exactManaged)
    }

    @Test
    func explicitInstallUpdatesOnlyVerifiedHelperToNewArtifactVersion() throws {
        let root = try helperRoot()
        let updateRoot = try helperRoot()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: updateRoot) }
        let initial = try VerifiedBundledHookArtifact.verify(helperURL: makeVerifiedHooksApp(at: root, contents: "helper-v1"))
        let destination = root.appendingPathComponent("managed/OpenIslandHooks")
        _ = try ManagedHooksBinary.install(from: initial, to: destination)

        let updatedHelper = try makeVerifiedHooksApp(at: updateRoot, contents: "helper-v2")
        try setArtifactVersion(2, for: updatedHelper)
        let updated = try VerifiedBundledHookArtifact.verify(helperURL: updatedHelper)
        _ = try ManagedHooksBinary.install(from: updated, to: destination)

        let loadedRecord = try ManagedHookProvenance.loadVerified(for: destination, managerID: "open-island-hooks-binary")
        let record = try #require(loadedRecord)
        #expect(try String(contentsOf: destination) == "helper-v2")
        #expect(record.artifactVersion == 2)
        #expect(record.preMutationDigest == initial.entry.sha256)
        #expect(record.postMutationDigest == updated.entry.sha256)
    }

    @Test
    func tamperedSourceOrUnmanagedDestinationNeverCreatesOrReplacesHelper() throws {
        let root = try helperRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = try makeVerifiedHooksApp(at: root, contents: "source")
        let verifiedBeforeTamper = try VerifiedBundledHookArtifact.verify(helperURL: helper)
        let destination = root.appendingPathComponent("managed/OpenIslandHooks")
        let manifest = helper.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/\(BundledArtifactManifest.fileName)")
        try Data("tampered-manifest".utf8).write(to: manifest)
        #expect(throws: BundledHookArtifactError.self) {
            try ManagedHooksBinary.install(from: verifiedBeforeTamper, to: destination)
        }
        #expect(!(try ManagedHookFileSystem.existsNoFollow(destination)))

        let cleanRoot = try helperRoot()
        defer { try? FileManager.default.removeItem(at: cleanRoot) }
        let clean = try VerifiedBundledHookArtifact.verify(helperURL: makeVerifiedHooksApp(at: cleanRoot, contents: "clean"))
        let conflicting = cleanRoot.appendingPathComponent("managed/OpenIslandHooks")
        try ManagedHookFileSystem.createDirectory(conflicting.deletingLastPathComponent())
        try Data("user-helper".utf8).write(to: conflicting)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: conflicting.path)
        #expect(throws: ManagedHookFileSystemError.self) { try ManagedHooksBinary.install(from: clean, to: conflicting) }
        #expect(try String(contentsOf: conflicting) == "user-helper")
        #expect(ManagedHooksBinary.managementOutcome(at: conflicting) == .ambiguousUnmanaged)
    }

    @Test
    func tamperedBytesModeSidecarAndLinksAreReportedWithoutMutation() throws {
        let root = try helperRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let artifact = try VerifiedBundledHookArtifact.verify(helperURL: makeVerifiedHooksApp(at: root, contents: "verified"))
        let destination = root.appendingPathComponent("managed/OpenIslandHooks")
        _ = try ManagedHooksBinary.install(from: artifact, to: destination)
        try Data("tampered".utf8).write(to: destination)
        #expect(ManagedHooksBinary.managementOutcome(at: destination) == .ambiguousUnmanaged)
        let health = HookHealthCheck.checkCodex(
            codexDirectory: root.appendingPathComponent(".codex", isDirectory: true),
            managedHooksBinaryURL: destination
        )
        #expect(health.issues.contains(.ownershipUnverified(outcome: .ambiguousUnmanaged)))
        #expect(throws: ManagedHookFileSystemError.self) { try ManagedHooksBinary.install(from: artifact, to: destination) }
        #expect(try String(contentsOf: destination) == "tampered")

        let modeRoot = try helperRoot()
        defer { try? FileManager.default.removeItem(at: modeRoot) }
        let modeArtifact = try VerifiedBundledHookArtifact.verify(helperURL: makeVerifiedHooksApp(at: modeRoot, contents: "mode"))
        let modeDestination = modeRoot.appendingPathComponent("managed/OpenIslandHooks")
        _ = try ManagedHooksBinary.install(from: modeArtifact, to: modeDestination)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: modeDestination.path)
        #expect(ManagedHooksBinary.managementOutcome(at: modeDestination) == .ambiguousUnmanaged)

        let sidecar = ManagedHookProvenance.sidecarURL(for: modeDestination)
        try Data("tampered-sidecar".utf8).write(to: sidecar)
        #expect(ManagedHooksBinary.managementOutcome(at: modeDestination) == .ambiguousUnmanaged)

        let linkRoot = try helperRoot()
        defer { try? FileManager.default.removeItem(at: linkRoot) }
        let linkArtifact = try VerifiedBundledHookArtifact.verify(helperURL: makeVerifiedHooksApp(at: linkRoot, contents: "link"))
        let linkDestination = linkRoot.appendingPathComponent("managed/OpenIslandHooks")
        try ManagedHookFileSystem.createDirectory(linkDestination.deletingLastPathComponent())
        let outside = linkRoot.appendingPathComponent("outside")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: linkDestination, withDestinationURL: outside)
        #expect(ManagedHooksBinary.managementOutcome(at: linkDestination) == .unsafePath)
        #expect(throws: ManagedHookFileSystemError.self) { try ManagedHooksBinary.install(from: linkArtifact, to: linkDestination) }
        #expect(try String(contentsOf: outside) == "outside")
    }

    @Test
    func statusNeverUpdatesAndRemovalRequiresExactProvenance() throws {
        let root = try helperRoot()
        let updateRoot = try helperRoot()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: updateRoot) }
        let initial = try VerifiedBundledHookArtifact.verify(helperURL: makeVerifiedHooksApp(at: root, contents: "old"))
        let destination = root.appendingPathComponent("managed/OpenIslandHooks")
        _ = try ManagedHooksBinary.install(from: initial, to: destination)
        _ = try makeVerifiedHooksApp(at: updateRoot, contents: "new")
        #expect(ManagedHooksBinary.managementOutcome(at: destination) == .exactManaged)
        #expect(try String(contentsOf: destination) == "old")
        #expect(try ManagedHooksBinary.removeVerified(at: destination))
        #expect(!(try ManagedHookFileSystem.existsNoFollow(destination)))
        #expect(!(try ManagedHookFileSystem.existsNoFollow(ManagedHookProvenance.sidecarURL(for: destination))))

        let ambiguous = root.appendingPathComponent("ambiguous/OpenIslandHooks")
        try ManagedHookFileSystem.createDirectory(ambiguous.deletingLastPathComponent())
        try Data("user-helper".utf8).write(to: ambiguous)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ambiguous.path)
        #expect(throws: ManagedHookFileSystemError.self) { try ManagedHooksBinary.removeVerified(at: ambiguous) }
        #expect(try String(contentsOf: ambiguous) == "user-helper")
    }

    private func helperRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("open-island-managed-helper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return root
    }

    private func setArtifactVersion(_ version: Int, for helperURL: URL) throws {
        let manifest = helperURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/\(BundledArtifactManifest.fileName)")
        var inventory = try JSONDecoder().decode(BundledArtifactManifest.self, from: Data(contentsOf: manifest))
        inventory.artifacts[0].version = version
        try JSONEncoder().encode(inventory).write(to: manifest)
    }
}
