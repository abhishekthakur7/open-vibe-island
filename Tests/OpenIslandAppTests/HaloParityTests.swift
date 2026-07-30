#if HALO_PARITY_TESTING
import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

struct HaloParityCatalogTests {
    @Test
    func catalogPinsExactlyTheManifest57IDs() {
        let expected = [
            "A1", "A2", "A2-prime", "A3", "A4", "A5", "A6-interrupted", "A6-failed",
            "B", "B-prime", "C", "D", "E-travel", "E1", "E2", "E3", "F1", "F2",
            "F3", "G", "G-prime", "H-success", "H-interrupted", "H-failed", "I",
            "I-prime", "J", "J-prime", "K-orbit", "K-morph", "K-condense",
            "K-success", "K-row", "K-failure", "K-idle", "K-glyph", "ST-LONG",
            "ST-DUP", "ST-MISSING", "ST-COUNT-0", "ST-COUNT-1", "ST-COUNT-MANY",
            "ST-OVERFLOW", "ST-USAGE-0", "ST-USAGE-MISSING", "ST-ATTN-RUN",
            "ST-Q-P", "ST-IPRIME-ATTN", "AX-RM", "AX-IC", "AX-RT", "AX-KBD",
            "AX-VO", "AX-TEXT", "DP-NOTCH", "DP-TOPBAR", "RESPONSIVE-560",
        ]
        #expect(HaloParityScenarioID.allCases.map(\.rawValue) == expected)
    }

    @MainActor
    @Test
    func everyScenarioHasDeterministicExactFixtureDataWithoutClaimingParity() throws {
        var hashes = Set<String>()
        for scenario in HaloParityScenarioID.allCases {
            let configuration = try configuration(for: scenario)
            let first = HaloParityFixtureCatalog.resolve(configuration: configuration)
            let second = HaloParityFixtureCatalog.resolve(configuration: configuration)

            #expect(first.record == second.record)
            #expect(first.record.dataHash.count == 64)
            #expect(hashes.insert(first.record.dataHash).inserted)
            #expect(first.snapshot.sessions.count == first.record.sessionCount)
            #expect(first.snapshot.sessions.allSatisfy { $0.origin == .demo })
            #expect(first.record.provenance.contains("typed-manifest:\(scenario.rawValue)"))
        }
    }

    @Test
    func lockedManifestDispositionsProvideAll57ExactNativeFixtures() {
        let capturable = HaloParityScenarioID.allCases.filter {
            $0.manifestDisposition == .exact && $0.lockedNativeFixtureIdentifier != nil
        }
        #expect(capturable == HaloParityScenarioID.allCases)
        #expect(HaloParityScenarioID.a1.lockedNativeFixtureIdentifier == "HaloParityFixtureCatalog.A1")
        #expect(
            HaloParityScenarioID.responsive560.lockedNativeFixtureIdentifier
                == "HaloParityFixtureCatalog.RESPONSIVE-560"
        )
    }

    @Test
    func compiledCatalogMatchesManifestIDsDispositionsAndExactFixtures() throws {
        var manifestURL = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { manifestURL.deleteLastPathComponent() }
        manifestURL.append(path: "Validation/HaloParity/halo-scenarios.json")
        let data = try Data(contentsOf: manifestURL)
        let root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let records = try #require(root["scenarios"] as? [[String: Any]])
        #expect(records.count == HaloParityScenarioID.allCases.count)

        for record in records {
            let rawID = try #require(record["id"] as? String)
            let scenario = try #require(HaloParityScenarioID(rawValue: rawID))
            let disposition = try #require(record["disposition"] as? String)
            #expect(scenario.manifestDisposition.rawValue == disposition)
            let native = record["native"] as? [String: Any]
            let manifestFixture = native?["fixture"] as? String
            #expect(scenario.manifestDisposition == .exact)
            #expect(scenario.lockedNativeFixtureIdentifier == manifestFixture)
        }
    }

    @Test
    func exactMachineReadableVariantsPinCountsOrderAndQuestionState() {
        let c = HaloParityFixtureCatalog.record(for: .c, seed: 7)
        #expect(c.sessionCount == 6)
        #expect(c.phaseCounts == ["waiting": 2, "running": 2, "done": 2])
        #expect(c.grouping == ["Needs you 2", "Running 2", "Done 2"])
        #expect(c.order == ["Needs you", "Running", "Done"])

        let f2 = HaloParityFixtureCatalog.record(for: .f2, seed: 7)
        #expect(f2.state["page"] == "2")
        #expect(f2.state["selected"] == "1,2")
        #expect(f2.state["freeform"] == "")
        #expect(f2.state["submission"] == "pending")

        let overflow = HaloParityFixtureCatalog.record(for: .stressOverflow, seed: 7)
        #expect(overflow.sessionCount == 9)
        #expect(overflow.state["overflow"] == "3")

        let priority = HaloParityFixtureCatalog.record(for: .stressIPrimeAttention, seed: 7)
        #expect(priority.state["priority"] == "attention>critical-usage")
    }

    @MainActor
    @Test
    func exactPayloadsExposeRunningGridQuestionUsageAndMissingDataVariants() throws {
        let three = HaloParityFixtureCatalog.resolve(
            configuration: try configuration(for: .a2Prime)
        ).snapshot
        #expect(three.sessions.count == 3)
        #expect(three.sessions.allSatisfy { $0.phase == .running })

        let pageTwo = HaloParityFixtureCatalog.resolve(
            configuration: try configuration(for: .f2)
        ).snapshot.sessions[0]
        #expect(pageTwo.questionPrompt?.questions.count == 2)
        #expect(pageTwo.questionPrompt?.questions[1].header == "Platforms")
        #expect(pageTwo.questionPrompt?.questions[1].multiSelect == true)
        #expect(pageTwo.questionPrompt?.questions[1].options.last?.allowsFreeform == true)

        let usage = HaloParityFixtureCatalog.resolve(
            configuration: try configuration(for: .i)
        ).snapshot.usageProviders
        #expect(usage?.last?.peakUsagePercentage == 94)
        #expect(usage?.last?.title == "Codex · Pro")

        let missingUsage = HaloParityFixtureCatalog.resolve(
            configuration: try configuration(for: .stressUsageMissing)
        ).snapshot.usageProviders
        #expect(missingUsage?.flatMap(\.windows).allSatisfy { $0.resetsAt == nil } == true)

        let missingMetadata = HaloParityFixtureCatalog.resolve(
            configuration: try configuration(for: .stressMissing)
        ).snapshot.sessions
        #expect(missingMetadata.allSatisfy { $0.jumpTarget == nil })
        #expect(missingMetadata.allSatisfy {
            $0.codexMetadata == nil && $0.claudeMetadata == nil && $0.cursorMetadata == nil
        })
    }

    private func configuration(for scenario: HaloParityScenarioID) throws -> HaloParityConfiguration {
        let profile: HaloParityProfile = scenario == .displayTopBar ? .topBar : .notch
        let accessibility: HaloParityAccessibility
        let motion: HaloParityMotionMode
        switch scenario {
        case .accessibilityReduceMotion:
            accessibility = .reduceMotion
            motion = .reduced
        case .accessibilityIncreaseContrast:
            accessibility = .increaseContrast
            motion = .normal
        case .accessibilityReduceTransparency:
            accessibility = .reduceTransparency
            motion = .normal
        case .accessibilityKeyboard:
            accessibility = .keyboard
            motion = .normal
        case .accessibilityVoiceOver:
            accessibility = .voiceOver
            motion = .normal
        case .accessibilityText:
            accessibility = .textScale
            motion = .normal
        default:
            accessibility = .standard
            motion = .normal
        }
        return try HaloParityConfiguration(
            scenario: scenario,
            profile: profile,
            motion: motion,
            accessibility: accessibility,
            event: nil,
            seed: 42,
            manualTimeMilliseconds: nil
        ).validated()
    }
}

struct HaloParityLaunchTests {
    @Test
    func parityArgumentsAreIgnoredWithoutExplicitEnable() {
        let launch = HarnessLaunchConfiguration(
            environment: [:],
            arguments: ["OpenIslandApp", "--halo-scenario", "A1"]
        )
        #expect(launch.haloParity == .inactive)
        #expect(launch.shouldStartBridge)
        #expect(launch.shouldPerformBootAnimation)
    }

    @Test
    func completeArgumentContractParses() {
        let launch = HarnessLaunchConfiguration(
            environment: [:],
            arguments: [
                "OpenIslandApp", "--halo-parity",
                "--halo-scenario", "F2",
                "--halo-profile", "notch-v1",
                "--halo-motion", "manual",
                "--halo-accessibility", "standard",
                "--halo-event", "advance-question",
                "--halo-seed", "19",
                "--halo-time-ms", "950",
            ]
        )
        let expected = HaloParityConfiguration(
            scenario: .f2,
            profile: .notch,
            motion: .manual,
            accessibility: .standard,
            event: .advanceQuestion,
            seed: 19,
            manualTimeMilliseconds: 950
        )
        #expect(launch.haloParity == .configured(expected))
    }

    @Test
    func malformedOrIncompleteParityFailsClosed() {
        let incomplete = HarnessLaunchConfiguration(
            environment: [:],
            arguments: ["OpenIslandApp", "--halo-parity", "--halo-scenario", "A1"]
        )
        #expect(incomplete.haloParity == .rejected(.missing("--halo-profile")))

        let unknown = HarnessLaunchConfiguration(
            environment: [
                "OPEN_ISLAND_HALO_PARITY": "1",
                "OPEN_ISLAND_HALO_SCENARIO": "invented",
                "OPEN_ISLAND_HALO_PROFILE": "notch-v1",
                "OPEN_ISLAND_HALO_MOTION": "normal",
                "OPEN_ISLAND_HALO_ACCESSIBILITY": "standard",
                "OPEN_ISLAND_HALO_SEED": "1",
            ],
            arguments: []
        )
        #expect(unknown.haloParity == .rejected(.unknown("--halo-scenario", "invented")))
    }

    @Test
    func legacyProfileAliasesAreRejected() {
        for alias in ["notch", "topbar"] {
            let launch = HarnessLaunchConfiguration(
                environment: [:],
                arguments: [
                    "OpenIslandApp", "--halo-parity",
                    "--halo-scenario", "A3",
                    "--halo-profile", alias,
                    "--halo-motion", "normal",
                    "--halo-accessibility", "standard",
                    "--halo-seed", "1",
                ]
            )
            #expect(launch.haloParity == .rejected(.unknown("--halo-profile", alias)))
        }
    }

    @Test
    func manualAndNormalClockInputsCannotBeConfused() {
        let missingTime = HaloParityConfiguration(
            scenario: .kOrbit,
            profile: .notch,
            motion: .manual,
            accessibility: .standard,
            event: nil,
            seed: 1,
            manualTimeMilliseconds: nil
        )
        #expect(throws: HaloParityConfigurationError.manualMotionRequiresTime) {
            try missingTime.validated()
        }

        let normalWithTime = HaloParityConfiguration(
            scenario: .kOrbit,
            profile: .notch,
            motion: .normal,
            accessibility: .standard,
            event: nil,
            seed: 1,
            manualTimeMilliseconds: 10
        )
        #expect(throws: HaloParityConfigurationError.timeRequiresManualMotion) {
            try normalWithTime.validated()
        }
    }

    @Test
    func motionAndReduceMotionAccessibilityMustAgreeInBothDirections() {
        let reducedStandard = HaloParityConfiguration(
            scenario: .e1,
            profile: .notch,
            motion: .reduced,
            accessibility: .standard,
            event: nil,
            seed: 1,
            manualTimeMilliseconds: nil
        )
        #expect(throws: HaloParityConfigurationError.contradictoryMotionAndAccessibility) {
            try reducedStandard.validated()
        }

        let normalReduceMotion = HaloParityConfiguration(
            scenario: .e1,
            profile: .notch,
            motion: .normal,
            accessibility: .reduceMotion,
            event: nil,
            seed: 1,
            manualTimeMilliseconds: nil
        )
        #expect(throws: HaloParityConfigurationError.contradictoryMotionAndAccessibility) {
            try normalReduceMotion.validated()
        }
    }
}

@MainActor
struct HaloParityDriverTests {
    @Test
    func driverAppliesRealAppModelWithIsolationAndAuthenticitySidecar() throws {
        let configuration = try HaloParityConfiguration(
            scenario: .e1,
            profile: .topBar,
            motion: .normal,
            accessibility: .standard,
            event: .launch,
            seed: 5,
            manualTimeMilliseconds: nil
        ).validated()
        let model = AppModel()
        prepareCanonicalModel(model, profile: .topBar)
        let driver = canonicalDriver(configuration)
        try driver.apply(to: model, presentOverlay: false)
        let manifest = try driver.captureManifest(
            model: model,
            processStartedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(model.sessions.count == 1)
        #expect(model.sessions.allSatisfy { $0.origin == .demo })
        #expect(model.activeAppearanceProfile == .topBar)
        #expect(model.islandSessionGroup == .state)
        #expect(model.islandSessionSort == .attention)
        #expect(model.islandTheme.id == "halo")
        #expect(model.haloParityStateDump?.fixture.dataHash == driver.fixture.record.dataHash)
        #expect(manifest.isolation.runtimeStateLoadingDisabled == true)
        #expect(manifest.isolation.bridgeStartupDisabled == true)
        #expect(manifest.isolation.allSessionsAreDemoOrigin == true)
        #expect(manifest.clock == .productionMonotonic)
        #expect(manifest.manifestDisposition == .exact)
        #expect(manifest.resolvedThemeID == "halo")
        #expect(manifest.executable.sha256 == String(repeating: "a", count: 64))
        #expect(manifest.process.bundleId == "dev.open-island.tests")
        #expect(manifest.fixture.liveDataAbsent)
        #expect(manifest.placement.resolvedMode == "topBar")
        #expect(manifest.placement.cgWindowId == 42)
        #expect(manifest.placement.actualWindowGeometry.y == 38)
        #expect(manifest.acknowledgedEvents.isEmpty)
        #expect(manifest.fixture.payloadSha256 == manifest.fixtureHash)
        #expect(manifest.fixture.payloadSha256 != driver.fixture.record.dataHash)
    }

    @Test
    func manualClockAttestationCarriesDiagnosticTimeAndPhase() throws {
        let configuration = try HaloParityConfiguration(
            scenario: .kOrbit,
            profile: .notch,
            motion: .manual,
            accessibility: .standard,
            event: nil,
            seed: 1,
            manualTimeMilliseconds: 1_500
        ).validated()
        let clock = HaloParityEventClock.attestation(for: configuration)
        guard case let .manualDiagnostic(milliseconds, orbitAngle, pulse) = clock else {
            Issue.record("Expected manual diagnostic attestation")
            return
        }
        #expect(milliseconds == 1_500)
        #expect(orbitAngle == 90)
        #expect((0...1).contains(pulse))
    }

    @Test
    func manualMotionIsDiagnosticOnlyAndCannotCreateCanonicalNativeCapture() throws {
        let configuration = try HaloParityConfiguration(
            scenario: .e1,
            profile: .notch,
            motion: .manual,
            accessibility: .standard,
            event: nil,
            seed: 1,
            manualTimeMilliseconds: 1_500
        ).validated()
        let model = AppModel()
        prepareCanonicalModel(model, profile: .notch)
        let driver = canonicalDriver(configuration)

        #expect(throws: HaloParityConfigurationError.manualCanonicalCaptureUnsupported(.e1)) {
            try driver.apply(to: model, presentOverlay: false)
        }
    }

    @Test
    func configuredQuestionEventUsesProductionCoordinatorAndAcknowledges() throws {
        let configuration = try HaloParityConfiguration(
            scenario: .f1,
            profile: .notch,
            motion: .normal,
            accessibility: .standard,
            event: .advanceQuestion,
            seed: 3,
            manualTimeMilliseconds: nil
        ).validated()
        let model = AppModel()
        prepareCanonicalModel(model, profile: .notch)
        let driver = canonicalDriver(configuration)
        try driver.apply(to: model, presentOverlay: false)

        var page = 0
        var selected: [Int] = []
        model.overlay.registerQuestionCardKeyboardHandlers(
            .init(
                optionCount: { page == 0 ? 3 : 4 },
                toggleOption: { selected.append($0) },
                submit: { page = 1 }
            )
        )
        try driver.applyConfiguredEvent(to: model)

        #expect(page == 1)
        #expect(selected == [0])
        #expect(model.haloParityStateDump?.acknowledgedEvents == [.advanceQuestion])
        let manifest = try driver.captureManifest(model: model)
        #expect(manifest.acknowledgedEvents == [.advanceQuestion])
    }

    @Test
    func unavailableFakeProductEventDoesNotAcknowledge() throws {
        let configuration = try HaloParityConfiguration(
            scenario: .e1,
            profile: .notch,
            motion: .normal,
            accessibility: .standard,
            event: .hover,
            seed: 3,
            manualTimeMilliseconds: nil
        ).validated()
        let model = AppModel()
        let driver = canonicalDriver(configuration)
        try driver.apply(to: model, presentOverlay: false)

        #expect(throws: HaloParityDriverError.unsupportedEvent(.hover, .e1)) {
            try driver.applyConfiguredEvent(to: model)
        }
        #expect(model.haloParityStateDump?.acknowledgedEvents.isEmpty == true)
    }

    @Test
    func everyLockedScenarioCanApplyItsExactFixture() throws {
        let configuration = try HaloParityConfiguration(
            scenario: .a1,
            profile: .notch,
            motion: .normal,
            accessibility: .standard,
            event: nil,
            seed: 3,
            manualTimeMilliseconds: nil
        ).validated()
        let model = AppModel()
        let driver = canonicalDriver(configuration)

        try driver.apply(to: model, presentOverlay: false)
        #expect(model.sessions.isEmpty)
        #expect(model.haloParityCaptureManifest == nil)
        #expect(model.haloParityStateDump?.scenario == .a1)
    }

    @Test
    func parityOverridesDoNotChangeUserAppearanceDefaults() throws {
        let keys = [
            "appearance.island.v8.theme",
            "appearance.island.v8.notch.sessionGroup",
            "appearance.island.v8.notch.sessionSort",
            "appearance.island.v8.topBar.sessionGroup",
            "appearance.island.v8.topBar.sessionSort",
        ]
        let before = keys.map { UserDefaults.standard.object(forKey: $0) as AnyObject? }
        let configuration = try HaloParityConfiguration(
            scenario: .e1,
            profile: .notch,
            motion: .normal,
            accessibility: .standard,
            event: nil,
            seed: 9,
            manualTimeMilliseconds: nil
        ).validated()
        let model = AppModel()
        let driver = canonicalDriver(configuration)
        try driver.apply(to: model, presentOverlay: false)

        let after = keys.map { UserDefaults.standard.object(forKey: $0) as AnyObject? }
        #expect(before.elementsEqual(after) { lhs, rhs in
            switch (lhs, rhs) {
            case (nil, nil): true
            case let (lhs?, rhs?): lhs.isEqual(rhs)
            default: false
            }
        })
    }

    @Test
    func captureFailsWhenPlacementDiagnosticsAreMissingOrMismatchProfile() throws {
        let configuration = try HaloParityConfiguration(
            scenario: .e1,
            profile: .notch,
            motion: .normal,
            accessibility: .standard,
            event: nil,
            seed: 12,
            manualTimeMilliseconds: nil
        ).validated()
        let model = AppModel()
        model.haloParityBootstrapIsolation = HaloParityBootstrapIsolationProof(
            runtimeStateLoadingDisabled: true,
            bridgeStartupDisabled: true
        )
        let driver = canonicalDriver(configuration)
        try driver.apply(to: model, presentOverlay: false)

        model.overlayPlacementDiagnostics = nil
        #expect(throws: HaloParityConfigurationError.missingPlacementDiagnostics) {
            try driver.captureManifest(model: model)
        }

        model.overlayPlacementDiagnostics = placementDiagnostics(profile: .topBar)
        #expect(throws: HaloParityConfigurationError.placementProfileMismatch(
            expected: .notch,
            actual: OverlayPlacementMode.topBar.rawValue
        )) {
            try driver.captureManifest(model: model)
        }
    }

    @Test
    func captureFailsWithoutProvenBootstrapIsolation() throws {
        let configuration = try HaloParityConfiguration(
            scenario: .j,
            profile: .notch,
            motion: .normal,
            accessibility: .standard,
            event: nil,
            seed: 13,
            manualTimeMilliseconds: nil
        ).validated()
        let model = AppModel()
        model.overlayPlacementDiagnostics = placementDiagnostics(profile: .notch)
        let driver = canonicalDriver(configuration)
        try driver.apply(to: model, presentOverlay: false)

        #expect(throws: HaloParityConfigurationError.bootstrapIsolationUnproven) {
            try driver.captureManifest(model: model)
        }
    }

    @Test
    func encodedNativeSidecarHasConsumerRequiredNestedShape() throws {
        let configuration = try HaloParityConfiguration(
            scenario: .e2,
            profile: .notch,
            motion: .normal,
            accessibility: .standard,
            event: nil,
            seed: 14,
            manualTimeMilliseconds: nil
        ).validated()
        let model = AppModel()
        prepareCanonicalModel(model, profile: .notch)
        let driver = canonicalDriver(configuration)
        try driver.apply(to: model, presentOverlay: false)
        let data = try driver.captureManifest(model: model).encoded()
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let executable = try #require(json["executable"] as? [String: Any])
        let process = try #require(json["process"] as? [String: Any])
        let fixture = try #require(json["fixture"] as? [String: Any])

        for key in [
            "path",
            "sha256",
            "buildId",
            "configuration",
            "gitRevision",
            "sourceTreeDirty",
        ] {
            #expect(executable[key] != nil)
        }
        for key in ["pid", "startTime", "bundleId"] {
            #expect(process[key] != nil)
        }
        for key in ["id", "payloadSha256", "liveDataAbsent"] {
            #expect(fixture[key] != nil)
        }
        #expect(fixture["liveDataAbsent"] as? Bool == true)
        #expect(json["placement"] is [String: Any])
        #expect(json["acknowledgedEvents"] is [String])
        #expect(json["event"] is NSNull)
        #expect(json["processID"] == nil)
        #expect(json["executablePath"] == nil)
    }

    private func canonicalDriver(
        _ configuration: HaloParityConfiguration
    ) -> HaloParityDriver {
        HaloParityDriver(
            configuration: configuration,
            accessibilityEnvironmentMatches: { _, _ in true },
            executableProvenance: { buildConfiguration in
                HaloParityExecutableProvenance(
                    path: "/tmp/OpenIslandApp",
                    sha256: String(repeating: "a", count: 64),
                    buildId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                    configuration: buildConfiguration,
                    gitRevision: String(repeating: "b", count: 40),
                    sourceTreeDirty: false
                )
            },
            bundleIdentifier: { "dev.open-island.tests" },
            windowServerPlacement: { _, expectedAppKitFrame in
                HaloParityWindowServerWindow(
                    cgWindowId: 42,
                    layer: 25,
                    bounds: CGRect(
                        x: expectedAppKitFrame.minX,
                        y: 38,
                        width: expectedAppKitFrame.width,
                        height: expectedAppKitFrame.height
                    )
                )
            }
        )
    }

    private func prepareCanonicalModel(
        _ model: AppModel,
        profile: HaloParityProfile
    ) {
        model.haloParityBootstrapIsolation = HaloParityBootstrapIsolationProof(
            runtimeStateLoadingDisabled: true,
            bridgeStartupDisabled: true
        )
        model.overlayPlacementDiagnostics = placementDiagnostics(profile: profile)
    }

    private func placementDiagnostics(
        profile: HaloParityProfile
    ) -> OverlayPlacementDiagnostics {
        OverlayPlacementDiagnostics(
            targetScreenID: "display-\(profile.rawValue)",
            targetScreenName: "Parity Display",
            selectionSummary: "test",
            mode: profile == .notch ? .notch : .topBar,
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaInsets: NSEdgeInsets(
                top: profile == .notch ? 32 : 0,
                left: 0,
                bottom: 0,
                right: 0
            ),
            overlayFrame: NSRect(x: 402, y: 430, width: 708, height: 514)
        )
    }
}
#endif
