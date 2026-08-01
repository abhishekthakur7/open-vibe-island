#if POURED_PARITY_TESTING
import Foundation
import Testing
@testable import OpenIslandApp

@Suite("Poured parity seam") struct PouredParityTests {
    private func configuration(event:PouredParityEvent?=nil,time:UInt64?=nil)->PouredParityConfiguration { .init(scenario:.a2WorkingOne,profile:.notch,accessibility:.standard,event:event,seed:42,epochMilliseconds:1_700_000_000_000,manualTimeMilliseconds:time) }

    @Test func launch_configuration_rejects_incomplete_unknown_and_invalid_inputs() {
        let incomplete=HarnessLaunchConfiguration(environment:["OPEN_ISLAND_POURED_PARITY":"1"],arguments:["app"])
        #expect(incomplete.pouredParity == .rejected(.missing("--poured-scenario")))
        let unknown=HarnessLaunchConfiguration(environment:[:],arguments:["app","--poured-parity","--poured-scenario","invented","--poured-profile","notch-v1","--poured-accessibility","standard","--poured-seed","42","--poured-epoch-ms","1700000000000"])
        #expect(unknown.pouredParity == .rejected(.unknown("--poured-scenario","invented")))
    }

    @Test @MainActor func driver_forces_poured_profile_preferences_and_isolated_demo_fixture() throws {
        let model=AppModel(); model.pouredParityBootstrapIsolation = .init(runtimeStateLoadingDisabled:true,bridgeStartupDisabled:true)
        let driver=PouredParityDriver(configuration:configuration())
        try driver.apply(to:model,presentOverlay:false)
        #expect(model.islandTheme.id == "poured"); #expect(model.activeAppearanceProfile == .notch)
        #expect(model.appearancePreferences(for:.notch).sessionGroup == .state)
        #expect(model.appearancePreferences(for:.notch).sessionSort == .attention)
        #expect(model.sessions.allSatisfy{$0.origin == .demo}); #expect(model.pouredParityStateDump?.resolvedThemeID == "poured")
        #expect(driver.fixture.record.canonicalDisposition == "diagnostic-partial")
    }

    @Test @MainActor func driver_rejects_wrong_a11y_and_unsupported_events() throws {
        let model=AppModel(); let mismatch=PouredParityDriver(configuration:configuration(),accessibilityMatches:{_ in false})
        #expect(throws:PouredParityError.accessibilityMismatch(.standard)){try mismatch.apply(to:model,presentOverlay:false)}
        let hover=PouredParityDriver(configuration:configuration(event:.hover)); try hover.apply(to:model,presentOverlay:false)
        #expect(throws:PouredParityError.unsupportedEvent(.hover)){try hover.applyConfiguredEvent(to:model)}
        #expect(hover.acknowledgedEvents.isEmpty)
    }

    @Test @MainActor func manual_clock_never_claims_canonical_pixels() throws {
        let model=AppModel(); model.pouredParityBootstrapIsolation = .init(runtimeStateLoadingDisabled:true,bridgeStartupDisabled:true)
        let driver=PouredParityDriver(configuration:configuration(time:100)); try driver.apply(to:model,presentOverlay:false)
        #expect(driver.stateDump(model).clock.consumedByPouredViews == false)
        #expect(throws:PouredParityError.manualClockNotConsumed){try driver.captureManifest(model:model,executablePath:"/tmp/app",executableSHA256:"abc",gitRevision:"deadbeef",sourceTreeDirty:false,bundleIdentifier:"app",signingIdentity:nil,windowServerPlacement:"window-1")}
    }

    @Test @MainActor func capture_contract_rejects_theme_fixture_executable_placement_and_partial_authority() throws {
        let model=AppModel(); model.pouredParityBootstrapIsolation = .init(runtimeStateLoadingDisabled:true,bridgeStartupDisabled:true)
        let driver=PouredParityDriver(configuration:configuration()); try driver.apply(to:model,presentOverlay:false)
        model.pouredParityThemeIDOverride="halo"
        #expect(throws:PouredParityError.wrongTheme("halo")){try driver.captureManifest(model:model,executablePath:"/tmp/app",executableSHA256:"abc",gitRevision:"deadbeef",sourceTreeDirty:false,bundleIdentifier:"app",signingIdentity:nil,windowServerPlacement:"window-1")}
        model.pouredParityThemeIDOverride="poured"; model.loadDebugSnapshot(IslandDebugScenario.emptyState.snapshot(at:Date(timeIntervalSince1970:0)),presentOverlay:false)
        #expect(throws:PouredParityError.fixtureMismatch){try driver.captureManifest(model:model,executablePath:"/tmp/app",executableSHA256:"abc",gitRevision:"deadbeef",sourceTreeDirty:false,bundleIdentifier:"app",signingIdentity:nil,windowServerPlacement:"window-1")}
        try driver.apply(to:model,presentOverlay:false)
        #expect(throws:PouredParityError.staleExecutable){try driver.captureManifest(model:model,executablePath:"/tmp/app",executableSHA256:"abc",gitRevision:"deadbeef",sourceTreeDirty:true,bundleIdentifier:"app",signingIdentity:nil,windowServerPlacement:"window-1")}
        #expect(throws:PouredParityError.missingPlacement){try driver.captureManifest(model:model,executablePath:"/tmp/app",executableSHA256:"abc",gitRevision:"deadbeef",sourceTreeDirty:false,bundleIdentifier:"app",signingIdentity:nil,windowServerPlacement:nil)}
        #expect(throws:PouredParityError.partialFixture(.a2WorkingOne)){try driver.captureManifest(model:model,executablePath:"/tmp/app",executableSHA256:"abc",gitRevision:"deadbeef",sourceTreeDirty:false,bundleIdentifier:"app",signingIdentity:nil,windowServerPlacement:"window-1")}
    }

    @Test func sidecar_writer_is_fail_closed_and_manifest_is_last() throws {
        let fixture=PouredParityFixtureRecord(id:"fixture",sourceScenario:"closed",dataHash:"abc",sessionCount:0,canonicalDisposition:"exact")
        let state=PouredParityStateDump(schemaVersion:"poured-state-v1",scenario:.a2WorkingOne,resolvedThemeID:"poured",fixture:fixture,sessionIDs:[],selectedSessionID:nil,presentation:"closed",profile:.notch,accessibility:.standard,acknowledgedEvents:[],clock:.init(fixedEpochMilliseconds:1,seed:1,manualTimeMilliseconds:nil,consumedByPouredViews:false),complete:true)
        let manifest=PouredParityCaptureManifest(schemaVersion:"poured-capture-manifest-v1",namespace:"poured-parity",scenario:.a2WorkingOne,resolvedThemeID:"poured",fixtureHash:"abc",executablePath:"/tmp/app",executableSHA256:"def",gitRevision:"deadbeef",sourceTreeDirty:false,bundleIdentifier:"app",signingIdentity:nil,windowServerPlacement:"window",stateDumpSHA256:"hash",complete:true)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try PouredParitySidecarWriter.write(state:state,manifest:manifest,to:directory)
        #expect(FileManager.default.fileExists(atPath:directory.appendingPathComponent("poured-state.json").path)); #expect(FileManager.default.fileExists(atPath:directory.appendingPathComponent("poured-capture-manifest.json").path))
        var incomplete=manifest; incomplete=PouredParityCaptureManifest(schemaVersion:incomplete.schemaVersion,namespace:incomplete.namespace,scenario:incomplete.scenario,resolvedThemeID:incomplete.resolvedThemeID,fixtureHash:incomplete.fixtureHash,executablePath:incomplete.executablePath,executableSHA256:incomplete.executableSHA256,gitRevision:incomplete.gitRevision,sourceTreeDirty:incomplete.sourceTreeDirty,bundleIdentifier:incomplete.bundleIdentifier,signingIdentity:incomplete.signingIdentity,windowServerPlacement:incomplete.windowServerPlacement,stateDumpSHA256:incomplete.stateDumpSHA256,complete:false)
        #expect(throws:PouredParityError.incompleteSidecar){try PouredParitySidecarWriter.write(state:state,manifest:incomplete,to:directory)}
        try? FileManager.default.removeItem(at:directory)
    }
}
#endif
