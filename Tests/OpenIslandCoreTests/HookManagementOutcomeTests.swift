import Testing
@testable import OpenIslandCore

struct HookManagementOutcomeTests {
    @Test(arguments: HookManagementOutcome.allCases)
    func exposesStableStatusAndRemediation(for outcome: HookManagementOutcome) {
        #expect(!outcome.remediation.isEmpty)
        #expect(outcome.displayMessage(operation: "Settings") == "Settings [\(outcome.rawValue)]: \(outcome.remediation)")
        #expect(outcome.exitStatus >= 0)
    }

    @Test
    func mapsFilesystemAmbiguityToTheNoninteractiveAmbiguityStatus() {
        let outcome = HookManagementOutcome.from(
            error: ManagedHookFileSystemError.ambiguous("/tmp/hooks.json")
        )
        #expect(outcome == .ambiguousUnmanaged)
        #expect(outcome.exitStatus == 23)
    }

    @Test
    func mapsRecoveryEvidenceFailureToTheRecoveryStatus() {
        let outcome = HookManagementOutcome.from(
            error: ManagedHookBackupError.unmanagedBackupPath("/tmp/hooks.json.backup.open-island")
        )
        #expect(outcome == .unresolvedRecovery)
        #expect(outcome.exitStatus == 24)
    }

    @Test
    func mapsClaudeTemplateMismatchToTheArtifactStatus() {
        #expect(HookManagementOutcome.from(error: ClaudeStatusLineInstallationError.unverifiedTemplate) == .unverifiedArtifact)
    }

    @Test(arguments: HookIntegrationFamily.allCases)
    func everyFamilyPreservesMachineFieldsAndRemediation(family: HookIntegrationFamily) {
        for outcome in [HookManagementOutcome.exactManaged, .unowned, .ambiguousUnmanaged, .unresolvedRecovery, .ioFailure] {
            let status = outcome.status(for: family)
            #expect(status.family == family)
            #expect(status.outcomeCode == outcome.rawValue)
            #expect(status.exitCode == outcome.exitStatus)
            #expect(status.remediation == outcome.remediation)
        }
    }

    @Test
    func keepsThePublishedExitCodesStable() {
        #expect(HookManagementOutcome.exactManaged.exitStatus == 0)
        #expect(HookManagementOutcome.consentRequired.exitStatus == 20)
        #expect(HookManagementOutcome.unsafePath.exitStatus == 21)
        #expect(HookManagementOutcome.unverifiedArtifact.exitStatus == 22)
        #expect(HookManagementOutcome.ambiguousUnmanaged.exitStatus == 23)
        #expect(HookManagementOutcome.unresolvedRecovery.exitStatus == 24)
        #expect(HookManagementOutcome.ioFailure.exitStatus == 25)
    }

    @Test
    func healthUsesTheIdenticalFamilyStatusMapping() {
        let outcome = HookManagementOutcome.unresolvedRecovery
        let issue = HookHealthReport.Issue.ownershipUnverified(outcome: outcome)
        #expect(issue.managementStatus(for: .kimi) == outcome.status(for: .kimi))
        #expect(issue.description.contains(outcome.remediation))
    }

    @Test
    func mapsFilesystemIOToItsOwnReadOnlyOutcome() {
        let outcome = HookManagementOutcome.from(error: ManagedHookFileSystemError.io("/tmp/hooks.json"))
        #expect(outcome == .ioFailure)
        #expect(outcome.exitStatus == 25)
    }
}
