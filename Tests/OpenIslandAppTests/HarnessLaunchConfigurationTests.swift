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
        #expect(configuration.previewScenario == nil)
        #if HALO_PARITY_TESTING
        #expect(configuration.haloParity == .inactive)
        #endif
    }

    /// Poured Slice 6 (PI-X-001 I1/I2): the §I meter card only renders in the
    /// Settings → Appearance preview, whose `.menu` picker accessibility
    /// automation cannot drive — so the harness needs an env-var driver.
    @Test
    func previewScenarioParsesRecognizedRawValue() {
        let configuration = HarnessLaunchConfiguration(
            environment: ["OPEN_ISLAND_HARNESS_PREVIEW_SCENARIO": "meters"]
        )

        #expect(configuration.previewScenario == .meters)
    }

    @Test
    func previewScenarioIgnoresUnrecognizedAndEmptyValues() {
        #expect(
            HarnessLaunchConfiguration(
                environment: ["OPEN_ISLAND_HARNESS_PREVIEW_SCENARIO": "invented"]
            ).previewScenario == nil
        )
        #expect(
            HarnessLaunchConfiguration(
                environment: ["OPEN_ISLAND_HARNESS_PREVIEW_SCENARIO": "   "]
            ).previewScenario == nil
        )
    }

    /// The pane's starting scenario resolves from the harness value when it is
    /// present and falls back to the AB-326 `.list` default otherwise, so the
    /// seam is inert in normal launches.
    @MainActor
    @Test
    func appearancePaneInitialScenarioResolvesFromHarnessOverride() {
        #expect(AppearanceSettingsPane.initialPreviewScenario(override: nil) == .list)
        #expect(AppearanceSettingsPane.initialPreviewScenario(override: .meters) == .meters)
    }
}
