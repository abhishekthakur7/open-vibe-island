#if HALO_PARITY_TESTING
import AppKit
import Foundation

enum HaloParityDriverError: Error, Equatable {
    case nonDemoFixtureSession(String)
    case fixtureCountMismatch(expected: Int, actual: Int)
    case unsupportedEvent(HaloParityEvent, HaloParityScenarioID)
}

/// Main-actor controller for the real AppModel/root-composition path. It never
/// starts discovery, reads persisted sessions, or swaps in a proxy view.
@MainActor
final class HaloParityDriver {
    let configuration: HaloParityConfiguration
    let fixture: HaloParityResolvedFixture
    private let accessibilityEnvironmentMatches:
        (HaloParityAccessibility, HaloParityMotionMode) -> Bool
    private let executableProvenance: (String) throws -> HaloParityExecutableProvenance
    private let bundleIdentifier: () -> String?
    private let windowServerPlacement:
        (Int32, CGRect) throws -> HaloParityWindowServerWindow
    private(set) var acknowledgedEvents: [HaloParityEvent] = []

    init(
        configuration: HaloParityConfiguration,
        accessibilityEnvironmentMatches:
            @escaping (HaloParityAccessibility, HaloParityMotionMode) -> Bool = {
            HaloParityDriver.actualAccessibilityEnvironmentMatches($0, motion: $1)
        },
        executableProvenance: @escaping (String) throws -> HaloParityExecutableProvenance = {
            try HaloParityExecutableProvenance.resolve(configuration: $0)
        },
        bundleIdentifier: @escaping () -> String? = { Bundle.main.bundleIdentifier },
        windowServerPlacement:
            @escaping (Int32, CGRect) throws -> HaloParityWindowServerWindow = {
            try HaloParityWindowServerWindow.resolve(
                processID: $0,
                expectedAppKitFrame: $1
            )
        }
    ) {
        self.configuration = configuration
        self.fixture = HaloParityFixtureCatalog.resolve(configuration: configuration)
        self.accessibilityEnvironmentMatches = accessibilityEnvironmentMatches
        self.executableProvenance = executableProvenance
        self.bundleIdentifier = bundleIdentifier
        self.windowServerPlacement = windowServerPlacement
    }

    func apply(to model: AppModel, presentOverlay: Bool = true) throws {
        guard configuration.scenario.manifestDisposition == .exact else {
            throw HaloParityConfigurationError.manifestNotCapturable(
                configuration.scenario,
                configuration.scenario.manifestDisposition
            )
        }
        guard configuration.scenario.lockedNativeFixtureIdentifier != nil else {
            throw HaloParityConfigurationError.missingLockedNativeFixture(configuration.scenario)
        }
        guard configuration.motion != .manual else {
            throw HaloParityConfigurationError.manualCanonicalCaptureUnsupported(
                configuration.scenario
            )
        }
        guard accessibilityEnvironmentMatches(
            configuration.accessibility,
            configuration.motion
        ) else {
            throw HaloParityConfigurationError.accessibilityEnvironmentMismatch(
                configuration.accessibility
            )
        }
        for session in fixture.snapshot.sessions where session.origin != .demo {
            throw HaloParityDriverError.nonDemoFixtureSession(session.id)
        }
        guard fixture.snapshot.sessions.count == fixture.record.sessionCount else {
            throw HaloParityDriverError.fixtureCountMismatch(
                expected: fixture.record.sessionCount,
                actual: fixture.snapshot.sessions.count
            )
        }

        model.haloParityAppearanceProfileOverride = configuration.profile == .notch ? .notch : .topBar
        model.haloParityThemeIDOverride = "halo"
        guard model.islandTheme.id == "halo" else {
            throw HaloParityConfigurationError.resolvedThemeMismatch(model.islandTheme.id)
        }

        var notchPreferences = model.appearancePreferences(for: .notch)
        notchPreferences.sessionGroup = .state
        notchPreferences.sessionSort = .attention
        model.haloParityNotchAppearancePreferencesOverride = notchPreferences

        var topBarPreferences = model.appearancePreferences(for: .topBar)
        topBarPreferences.sessionGroup = .state
        topBarPreferences.sessionSort = .attention
        model.haloParityTopBarAppearancePreferencesOverride = topBarPreferences

        model.ignoresPointerExitDuringHarness = true
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.enablesOverlayKeyMonitorDuringHarness = configuration.accessibility == .keyboard
        model.debugSuppressesInstallHint = true
        model.haloParityCaptureManifest = nil
        HaloParityEventClock.install(configuration: configuration)
        model.loadDebugSnapshot(fixture.snapshot, presentOverlay: presentOverlay)

        model.haloParityStateDump = stateDump(model: model)
    }

    /// Drives only existing production controls. The question commands route
    /// through the same coordinator closures as real keyboard input; callers
    /// invoke this after the SwiftUI card has appeared and registered them.
    func applyConfiguredEvent(to model: AppModel) throws {
        guard let event = configuration.event else { return }
        switch event {
        case .open:
            model.notchStatus = .opened
        case .close:
            model.notchStatus = .closed
        case .advanceQuestion:
            guard model.overlay.handleQuestionOptionKey(0) else {
                throw HaloParityDriverError.unsupportedEvent(event, configuration.scenario)
            }
            _ = model.overlay.handleQuestionSubmitKey()
        case .selectOptions:
            // F2 begins at the production page-one state. Select one answer,
            // invoke the real Next action, then select the first two options
            // on page two.
            guard model.overlay.handleQuestionOptionKey(0) else {
                throw HaloParityDriverError.unsupportedEvent(event, configuration.scenario)
            }
            _ = model.overlay.handleQuestionSubmitKey()
            guard model.overlay.handleQuestionOptionKey(0),
                  model.overlay.handleQuestionOptionKey(1) else {
                throw HaloParityDriverError.unsupportedEvent(event, configuration.scenario)
            }
        case .submit:
            guard model.overlay.handleQuestionSubmitKey() else {
                throw HaloParityDriverError.unsupportedEvent(event, configuration.scenario)
            }
        case .launch, .settle:
            break
        case .hover, .retriggerSuccess:
            // No fake peek/success implementation: these need a production
            // event seam in a later packet and therefore never acknowledge.
            throw HaloParityDriverError.unsupportedEvent(event, configuration.scenario)
        }
        acknowledgedEvents.append(event)
        model.haloParityStateDump = stateDump(model: model)
    }

    func stateDump(model: AppModel) -> HaloParityStateDump {
        HaloParityStateDump(
            scenario: configuration.scenario,
            fixture: fixture.record,
            sessions: model.sessions.map {
                HaloParityStateDump.Session(
                    id: $0.id,
                    title: $0.title,
                    phase: $0.phase.rawValue,
                    outcome: $0.outcome.rawValue,
                    origin: String(describing: $0.origin)
                )
            },
            selectedSessionID: model.selectedSessionID,
            presentation: model.notchStatus == .opened ? "opened" : "closed",
            profile: configuration.profile,
            accessibility: configuration.accessibility,
            motion: configuration.motion,
            acknowledgedEvents: acknowledgedEvents
        )
    }

    func captureManifest(
        model: AppModel,
        processStartedAt: Date = Date()
    ) throws -> HaloParityCaptureManifest {
        guard configuration.scenario.manifestDisposition == .exact else {
            throw HaloParityConfigurationError.manifestNotCapturable(
                configuration.scenario,
                configuration.scenario.manifestDisposition
            )
        }
        guard let lockedNativeFixtureIdentifier =
            configuration.scenario.lockedNativeFixtureIdentifier else {
            throw HaloParityConfigurationError.missingLockedNativeFixture(configuration.scenario)
        }
        guard model.islandTheme.id == "halo" else {
            throw HaloParityConfigurationError.resolvedThemeMismatch(model.islandTheme.id)
        }
        guard configuration.motion != .manual else {
            throw HaloParityConfigurationError.manualCanonicalCaptureUnsupported(
                configuration.scenario
            )
        }
        guard accessibilityEnvironmentMatches(
            configuration.accessibility,
            configuration.motion
        ) else {
            throw HaloParityConfigurationError.accessibilityEnvironmentMismatch(
                configuration.accessibility
            )
        }
        guard let bootstrap = model.haloParityBootstrapIsolation,
              bootstrap.runtimeStateLoadingDisabled,
              bootstrap.bridgeStartupDisabled else {
            throw HaloParityConfigurationError.bootstrapIsolationUnproven
        }
        let sessions = model.sessions
        let expectedSessionIDs = fixture.snapshot.sessions.map(\.id)
        guard sessions.allSatisfy({ $0.origin == .demo }),
              sessions == fixture.snapshot.sessions,
              sessions.map(\.id) == expectedSessionIDs,
              sessions.count == fixture.record.sessionCount,
              model.selectedSessionID
                == (fixture.snapshot.selectedSessionID ?? expectedSessionIDs.first) else {
            throw HaloParityConfigurationError.fixtureIsolationMismatch
        }
        guard let diagnostics = model.overlayPlacementDiagnostics else {
            throw HaloParityConfigurationError.missingPlacementDiagnostics
        }
        let expectedMode: OverlayPlacementMode =
            configuration.profile == .notch ? .notch : .topBar
        guard diagnostics.mode == expectedMode else {
            throw HaloParityConfigurationError.placementProfileMismatch(
                expected: configuration.profile,
                actual: diagnostics.mode.rawValue
            )
        }
        guard !diagnostics.targetScreenID.isEmpty,
              !diagnostics.targetScreenName.isEmpty,
              diagnostics.overlayFrame.width > 0,
              diagnostics.overlayFrame.height > 0 else {
            throw HaloParityConfigurationError.invalidPlacementGeometry
        }
        guard let bundleID = bundleIdentifier(), !bundleID.isEmpty else {
            throw HaloParityConfigurationError.missingExecutableProvenance(
                "Bundle.main has no bundle identifier"
            )
        }
        let processID = ProcessInfo.processInfo.processIdentifier
        let window = try windowServerPlacement(processID, diagnostics.overlayFrame)
        let payloadHash = try HaloParityFixturePayloadHasher.hash(
            fixture: fixture,
            model: model
        )
        let executable = try executableProvenance(Self.buildConfiguration)
        return HaloParityCaptureManifest(
            schemaVersion: "halo-native-capture-sidecar-v1",
            scenario: configuration.scenario,
            manifestDisposition: configuration.scenario.manifestDisposition,
            lockedNativeFixtureIdentifier: lockedNativeFixtureIdentifier,
            profile: configuration.profile,
            motion: configuration.motion,
            accessibility: configuration.accessibility,
            event: HaloParityEventProvenance(configuration.event),
            seed: configuration.seed,
            fixtureSchemaVersion: HaloParityFixtureCatalog.schemaVersion,
            fixtureHash: payloadHash,
            fixtureVariant: fixture.record.variant,
            resolvedThemeID: model.islandTheme.id,
            clock: HaloParityEventClock.attestation(for: configuration),
            executable: executable,
            process: HaloParityProcessProvenance(
                pid: processID,
                startTime: processStartedAt,
                bundleId: bundleID
            ),
            fixture: HaloParityFixtureProvenance(
                id: lockedNativeFixtureIdentifier,
                payloadSha256: payloadHash,
                liveDataAbsent: true
            ),
            placement: HaloParityPlacementProvenance(
                requestedProfileId: configuration.profile.rawValue,
                resolvedMode: diagnostics.mode == .notch ? "notch" : "topBar",
                targetScreenId: diagnostics.targetScreenID,
                targetScreenName: diagnostics.targetScreenName,
                selectionSummary: diagnostics.selectionSummary,
                screenFrame: HaloParityRect(diagnostics.screenFrame),
                visibleFrame: HaloParityRect(diagnostics.visibleFrame),
                safeAreaInsets: HaloParityInsets(diagnostics.safeAreaInsets),
                cgWindowId: window.cgWindowId,
                windowLayer: window.layer,
                actualWindowGeometry: HaloParityRect(window.bounds)
            ),
            generatedAt: Date(),
            isolation: HaloParityLiveDataIsolationProof(
                runtimeStateLoadingDisabled: true,
                bridgeStartupDisabled: true,
                allSessionsAreDemoOrigin: sessions.allSatisfy { $0.origin == .demo },
                fixtureSessionIDs: sessions.map(\.id)
            ),
            acknowledgedEvents: acknowledgedEvents
        )
    }

    func writeSidecars(to directory: URL, model: AppModel, processStartedAt: Date) throws {
        let manifest = try captureManifest(model: model, processStartedAt: processStartedAt)
        model.haloParityCaptureManifest = manifest
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifestURL = directory.appendingPathComponent("halo-parity-capture-manifest.json")
        let stateURL = directory.appendingPathComponent("halo-parity-state.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(stateDump(model: model)).write(to: stateURL, options: .atomic)
        // The manifest is the completion marker. Write it last so a capture
        // coordinator never observes new provenance paired with a stale state.
        try manifest.encoded()
            .write(to: manifestURL, options: .atomic)
    }

    private static var buildConfiguration: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }

    private static func actualAccessibilityEnvironmentMatches(
        _ requested: HaloParityAccessibility,
        motion: HaloParityMotionMode
    ) -> Bool {
        let workspace = NSWorkspace.shared
        guard workspace.accessibilityDisplayShouldReduceMotion == (motion == .reduced) else {
            return false
        }
        switch requested {
        case .standard:
            return !workspace.accessibilityDisplayShouldIncreaseContrast
                && !workspace.accessibilityDisplayShouldReduceTransparency
                && !workspace.isVoiceOverEnabled
        case .reduceMotion:
            return !workspace.accessibilityDisplayShouldIncreaseContrast
                && !workspace.accessibilityDisplayShouldReduceTransparency
                && !workspace.isVoiceOverEnabled
        case .increaseContrast:
            return workspace.accessibilityDisplayShouldIncreaseContrast
                && !workspace.accessibilityDisplayShouldReduceTransparency
                && !workspace.isVoiceOverEnabled
        case .reduceTransparency:
            return !workspace.accessibilityDisplayShouldIncreaseContrast
                && workspace.accessibilityDisplayShouldReduceTransparency
                && !workspace.isVoiceOverEnabled
        case .voiceOver:
            return !workspace.accessibilityDisplayShouldIncreaseContrast
                && !workspace.accessibilityDisplayShouldReduceTransparency
                && workspace.isVoiceOverEnabled
        case .keyboard, .textScale:
            // AppKit exposes no process-local truth for these requested modes.
            // Without a real root environment injection, canonical capture
            // must reject them instead of attesting an unobserved request.
            return false
        }
    }
}
#endif
