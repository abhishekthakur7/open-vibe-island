import Testing
@testable import OpenIslandCore

/// Verifies the per-process hook skip environment contract.
struct HookSkipConfigurationTests {
    /// Accepts common truthy spellings for the preferred Open Island key.
    @Test
    func openIslandSkipHooksAcceptsTruthyValues() {
        for value in ["1", "true", "TRUE", "yes", "on", " 1 "] {
            #expect(HookSkipConfiguration.shouldSkipHooks(environment: [
                HookSkipConfiguration.openIslandSkipKey: value,
            ]))
        }
    }

    /// Rejects unset or non-truthy values so hooks remain enabled by default.
    @Test
    func skipHooksRejectsFalsyOrMissingValues() {
        for value in ["", "0", "false", "no", "off", "random"] {
            #expect(!HookSkipConfiguration.shouldSkipHooks(environment: [
                HookSkipConfiguration.openIslandSkipKey: value,
            ]))
        }

        #expect(!HookSkipConfiguration.shouldSkipHooks(environment: [:]))
    }
}
