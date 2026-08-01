import Foundation
import Testing
@testable import OpenIslandCore

struct HookConsentPreviewTests {
    @Test
    func confirmationGateCannotBeConsumedBeforeExplicitConfirmation() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let helper = try makeVerifiedHooksApp(at: root, contents: "gate")
        let artifact = try VerifiedBundledHookArtifact.verify(helperURL: helper)
        let preview = HookConsentPreview(artifact: artifact, target: target("test", [root.appendingPathComponent("target")]))
        let gate = HookConsentGate()
        var mutated = false

        let fresh = HookConsentPreview(artifact: artifact, target: target("test", [root.appendingPathComponent("target")]))
        let unconfirmedToken = gate.confirm(HookConsentPreview(artifact: artifact, target: target("other", [root.appendingPathComponent("target")])))
        if gate.consume(unconfirmedToken, preview: preview, revalidatedAs: fresh) { mutated = true }
        #expect(!mutated)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("target").path))
        let token = gate.confirm(preview)
        if gate.consume(token, preview: preview, revalidatedAs: fresh) { mutated = true }
        #expect(mutated)
        #expect(!gate.consume(token, preview: preview, revalidatedAs: fresh), "confirmation is one-shot")
    }

    @Test
    func confirmationBindsContentModeLinksAndExistence() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let helper = try makeVerifiedHooksApp(at: root, contents: "snapshot")
        let artifact = try VerifiedBundledHookArtifact.verify(helperURL: helper)
        let targetURL = root.appendingPathComponent("target")
        try Data("before".utf8).write(to: targetURL)
        let preview = HookConsentPreview(artifact: artifact, target: target("test", [targetURL]))
        let gate = HookConsentGate()

        try Data("after".utf8).write(to: targetURL)
        let contentChanged = HookConsentPreview(artifact: artifact, target: target("test", [targetURL]))
        #expect(!gate.consume(gate.confirm(preview), preview: preview, revalidatedAs: contentChanged))

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: targetURL.path)
        let modeChanged = HookConsentPreview(artifact: artifact, target: target("test", [targetURL]))
        #expect(!gate.consume(gate.confirm(contentChanged), preview: contentChanged, revalidatedAs: modeChanged))

        try FileManager.default.removeItem(at: targetURL)
        let deleted = HookConsentPreview(artifact: artifact, target: target("test", [targetURL]))
        #expect(!gate.consume(gate.confirm(modeChanged), preview: modeChanged, revalidatedAs: deleted))

        try FileManager.default.createSymbolicLink(at: targetURL, withDestinationURL: helper)
        let linked = HookConsentPreview(artifact: artifact, target: target("test", [targetURL]))
        #expect(!gate.consume(gate.confirm(deleted), preview: deleted, revalidatedAs: linked))
    }

    @Test
    func confirmationExpiresAndRejectsArtifactReplacement() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let helper = try makeVerifiedHooksApp(at: root, contents: "expiry")
        let artifact = try VerifiedBundledHookArtifact.verify(helperURL: helper)
        let preview = HookConsentPreview(artifact: artifact, target: target("test", [root.appendingPathComponent("target")]))
        let gate = HookConsentGate(lifetime: 1)
        let then = Date(timeIntervalSince1970: 1_000)
        let token = gate.confirm(preview, now: then)
        #expect(!gate.consume(token, preview: preview, revalidatedAs: preview, now: then.addingTimeInterval(2)))

        var alteredTarget = target("test", [root.appendingPathComponent("target")])
        alteredTarget = HookConsentPreview.Target(
            integrationID: alteredTarget.integrationID, targetURLs: [root.appendingPathComponent("target")], requestedModes: alteredTarget.requestedModes,
            managedAdditions: ["different artifact"], backupURLs: [], journalURLs: [], provenanceURLs: []
        )
        let altered = HookConsentPreview(artifact: artifact, target: alteredTarget)
        #expect(!gate.consume(gate.confirm(preview), preview: preview, revalidatedAs: altered))
    }

    @Test
    func aggregateResetInventoryBindsEveryMemberAndBlocksUnsafeState() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let safe = HookConsentPreview(removalTarget: HookConsentPreview.Target(
            integrationID: "codex-hooks", targetURLs: [first], requestedModes: ["0600"], managedAdditions: [],
            managedRemovals: ["exact uninstall"], managementOutcome: .exactManaged
        ))
        let unowned = HookConsentPreview(removalTarget: HookConsentPreview.Target(
            integrationID: "cursor-hooks", targetURLs: [second], requestedModes: ["0600"], managedAdditions: [],
            managedRemovals: ["skip unowned"], managementOutcome: .unowned
        ))
        let preview = HookAggregateConsentPreview(
            members: [safe, unowned], intentKeys: ["agentIntent.codex"], credentialRoles: ["hookEventSubmit"],
            executionOrder: ["codex-hooks", "cursor-hooks", "clear managed integration intent"]
        )

        #expect(preview.isSafeToExecute)
        #expect(preview.targetSnapshots.count == 2)
        #expect(preview.executionOrder.prefix(2) == ["codex-hooks", "cursor-hooks"])

        let unsafe = HookAggregateConsentPreview(
            members: [safe, HookConsentPreview(removalTarget: HookConsentPreview.Target(
                integrationID: "cursor-hooks", targetURLs: [second], requestedModes: ["0600"], managedAdditions: [],
                managedRemovals: ["exact uninstall"], managementOutcome: .ambiguousUnmanaged
            ))], intentKeys: preview.intentKeys, credentialRoles: preview.credentialRoles, executionOrder: preview.executionOrder
        )
        #expect(!unsafe.isSafeToExecute)
        #expect(unsafe.blockingMembers.map(\.integrationID) == ["cursor-hooks"])
    }

    @Test
    func aggregateResetConfirmationIsOneShotAndAbortsBeforeMutationWhenAnyTargetChanges() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        func preview() -> HookAggregateConsentPreview {
            HookAggregateConsentPreview(
                members: [
                    HookConsentPreview(removalTarget: HookConsentPreview.Target(integrationID: "first", targetURLs: [first], requestedModes: ["0600"], managedAdditions: [], managedRemovals: ["remove"], managementOutcome: .exactManaged)),
                    HookConsentPreview(removalTarget: HookConsentPreview.Target(integrationID: "second", targetURLs: [second], requestedModes: ["0600"], managedAdditions: [], managedRemovals: ["remove"], managementOutcome: .exactManaged)),
                ], intentKeys: ["agentIntent.first"], credentialRoles: ["hookEventSubmit"], executionOrder: ["first", "second"]
            )
        }
        let displayed = preview()
        let gate = HookConsentGate(lifetime: 1)
        let token = gate.confirm(displayed, now: Date(timeIntervalSince1970: 100))
        try Data("changed".utf8).write(to: second)
        #expect(!gate.consume(token, aggregate: displayed, revalidatedAs: preview(), now: Date(timeIntervalSince1970: 100)))
        #expect(try Data(contentsOf: first) == Data("first".utf8), "preflight must not partially mutate the first member")
        #expect(!gate.consume(token, aggregate: displayed, revalidatedAs: displayed, now: Date(timeIntervalSince1970: 100)), "failed tokens are also one-shot")

        let expiration = gate.confirm(preview(), now: Date(timeIntervalSince1970: 100))
        #expect(!gate.consume(expiration, aggregate: preview(), revalidatedAs: preview(), now: Date(timeIntervalSince1970: 102)))
    }

    @Test
    func missingOrTamperedSourceCannotProducePreviewOrCreateTargets() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent(".codex/hooks.json")
        let missing = root.appendingPathComponent("missing.app/Contents/Helpers/OpenIslandHooks")
        #expect(throws: BundledHookArtifactError.self) { try VerifiedBundledHookArtifact.verify(helperURL: missing) }
        #expect(!FileManager.default.fileExists(atPath: target.path))

        let helper = try makeVerifiedHooksApp(at: root, contents: "before-tamper")
        try Data("tampered".utf8).write(to: helper)
        #expect(throws: BundledHookArtifactError.self) { try VerifiedBundledHookArtifact.verify(helperURL: helper) }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    private func target(_ integration: String, _ urls: [URL]) -> HookConsentPreview.Target {
        HookConsentPreview.Target(
            integrationID: integration, targetURLs: urls, requestedModes: ["0600 targets"],
            managedAdditions: ["exact managed entries"], backupURLs: urls.map(ManagedHookBackupLifecycle.backupURL),
            journalURLs: urls.map(ManagedHookFileSystem.journalURL), provenanceURLs: urls.map(ManagedHookProvenance.sidecarURL)
        )
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("open-island-consent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return root
    }
}
