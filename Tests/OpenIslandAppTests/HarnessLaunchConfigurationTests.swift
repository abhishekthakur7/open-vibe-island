import Foundation
import Testing
@testable import OpenIslandApp

struct HarnessLaunchConfigurationTests {
    @Test
    func defaultsMatchNormalAppLaunch() {
        let configuration = HarnessLaunchConfiguration(environment: [:])

        #expect(configuration.scenario == nil)
        #expect(!configuration.presentOverlay)
        #expect(!configuration.suppressInstallHint)
        #expect(!configuration.enableKeyMonitor)
        #expect(configuration.shouldStartBridge)
        #expect(configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
        #if HALO_PARITY_TESTING
        #expect(configuration.haloParity == .inactive)
        #endif
    }
}
