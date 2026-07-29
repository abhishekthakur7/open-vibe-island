import Testing
@testable import OpenIslandCore

struct RuntimeNetworkPolicyTests {
    @Test func acceptsOnlyTheCompiledVersionAndExpectedEntitlements() {
        let entitlements: [String: Any] = [
            "com.apple.security.automation.apple-events": true,
            ["com.apple.security", "network.client"].joined(separator: "."): false,
            ["com.apple.security", "network.server"].joined(separator: "."): false,
        ]
        #expect(RuntimeNetworkPolicy.isValid(entitlements: entitlements))
        #expect(!RuntimeNetworkPolicy.isValid(entitlements: entitlements, compiledVersion: "other"))
    }

    @Test func rejectsNetworkEntitlementOrMissingAutomationAuthorization() {
        let networkClient = ["com.apple.security", "network.client"].joined(separator: ".")
        let networkServer = ["com.apple.security", "network.server"].joined(separator: ".")
        #expect(!RuntimeNetworkPolicy.isValid(entitlements: [
            "com.apple.security.automation.apple-events": true,
            networkClient: true,
            networkServer: false,
        ]))
        #expect(!RuntimeNetworkPolicy.isValid(entitlements: [
            networkClient: false,
            networkServer: false,
        ]))
    }
}
