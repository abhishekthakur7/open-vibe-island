#if POURED_PARITY_TESTING
import CryptoKit
import Foundation

@MainActor final class PouredParityDriver {
    let configuration:PouredParityConfiguration; let fixture:PouredParityFixture
    private let accessibilityMatches:(PouredParityAccessibility)->Bool
    private(set) var acknowledgedEvents:[PouredParityEvent]=[]
    init(configuration:PouredParityConfiguration,accessibilityMatches:@escaping(PouredParityAccessibility)->Bool={_ in true}) { self.configuration=configuration; self.fixture=PouredParityFixtureCatalog.resolve(configuration); self.accessibilityMatches=accessibilityMatches }
    func apply(to model:AppModel,presentOverlay:Bool=true)throws {
        guard accessibilityMatches(configuration.accessibility) else { throw PouredParityError.accessibilityMismatch(configuration.accessibility) }
        guard fixture.snapshot.sessions.allSatisfy({$0.origin == .demo}) else { throw PouredParityError.liveDataContamination }
        model.pouredParityThemeIDOverride="poured"; model.pouredParityAppearanceProfileOverride=configuration.profile == .notch ? .notch:.topBar
        var notch=model.appearancePreferences(for:.notch); notch.sessionGroup = .state; notch.sessionSort = .attention
        var top=model.appearancePreferences(for:.topBar); top.sessionGroup = .state; top.sessionSort = .attention
        model.pouredParityNotchAppearancePreferencesOverride=notch; model.pouredParityTopBarAppearancePreferencesOverride=top
        guard model.islandTheme.id == "poured" else { throw PouredParityError.wrongTheme(model.islandTheme.id) }
        model.ignoresPointerExitDuringHarness=true; model.disablesOverlayEventMonitoringDuringHarness=true; model.debugSuppressesInstallHint=true
        model.loadDebugSnapshot(fixture.snapshot,presentOverlay:presentOverlay); model.pouredParityStateDump=stateDump(model)
    }
    func applyConfiguredEvent(to model:AppModel)throws {
        guard let event=configuration.event else{return}
        switch event { case .open:model.notchStatus = .opened; case .close:model.notchStatus = .closed; case .hover,.reverse,.settle,.rowMutation,.success:throw PouredParityError.unsupportedEvent(event) }
        acknowledgedEvents.append(event); model.pouredParityStateDump=stateDump(model)
    }
    func stateDump(_ model:AppModel)->PouredParityStateDump { .init(schemaVersion:"poured-state-v1",scenario:configuration.scenario,resolvedThemeID:model.islandTheme.id,fixture:fixture.record,sessionIDs:model.sessions.map(\.id),selectedSessionID:model.selectedSessionID,presentation:model.notchStatus == .opened ? "opened":"closed",profile:configuration.profile,accessibility:configuration.accessibility,acknowledgedEvents:acknowledgedEvents,clock:PouredParityEventClock.attestation(configuration),complete:true) }
    func captureManifest(model:AppModel,executablePath:String,executableSHA256:String,gitRevision:String,sourceTreeDirty:Bool,bundleIdentifier:String,signingIdentity:String?,windowServerPlacement:String?)throws->PouredParityCaptureManifest {
        guard configuration.manualTimeMilliseconds == nil else { throw PouredParityError.manualClockNotConsumed }
        guard model.islandTheme.id == "poured" else { throw PouredParityError.wrongTheme(model.islandTheme.id) }
        guard let isolation=model.pouredParityBootstrapIsolation,isolation.runtimeStateLoadingDisabled,isolation.bridgeStartupDisabled else { throw PouredParityError.liveDataContamination }
        guard model.sessions == fixture.snapshot.sessions else { throw PouredParityError.fixtureMismatch }
        guard !sourceTreeDirty,!gitRevision.isEmpty,!executableSHA256.isEmpty,!executablePath.isEmpty else { throw PouredParityError.staleExecutable }
        guard let windowServerPlacement,!windowServerPlacement.isEmpty else { throw PouredParityError.missingPlacement }
        guard fixture.record.canonicalDisposition == "exact" else { throw PouredParityError.partialFixture(configuration.scenario) }
        let dump=stateDump(model); let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]; let data=try encoder.encode(dump); let hash=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        return .init(schemaVersion:"poured-capture-manifest-v1",namespace:"poured-parity",scenario:configuration.scenario,resolvedThemeID:"poured",fixtureHash:fixture.record.dataHash,executablePath:executablePath,executableSHA256:executableSHA256,gitRevision:gitRevision,sourceTreeDirty:false,bundleIdentifier:bundleIdentifier,signingIdentity:signingIdentity,windowServerPlacement:windowServerPlacement,stateDumpSHA256:hash,complete:true)
    }
}
#endif
