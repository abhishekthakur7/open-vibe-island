import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
@Suite(.serialized)
struct HookManagementPresentationTests {
    @Test
    func appModelAndSettingsSummaryUseTheSharedOutcomeMapping() {
        let model = AppModel()
        let root = URL(fileURLWithPath: "/tmp/open-island-presentation")
        model.hooks.codexHookStatus = CodexHookInstallationStatus(
            codexDirectory: root,
            configURL: root.appendingPathComponent("config.toml"),
            hooksURL: root.appendingPathComponent("hooks.json"),
            manifestURL: root.appendingPathComponent("manifest.json"),
            hooksBinaryURL: nil,
            featureFlagEnabled: false,
            managedHooksPresent: false,
            manifest: nil,
            managementOutcome: .unsafePath
        )

        let expected = HookManagementOutcome.unsafePath.status(for: .codexCLI)
        #expect(model.hookManagementStatus(for: .codexCLI) == expected)
        #expect(model.codexHookStatusSummary == expected.remediation)
    }
}
