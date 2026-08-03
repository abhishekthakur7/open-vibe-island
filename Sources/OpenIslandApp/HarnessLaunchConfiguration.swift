import Foundation

struct HarnessLaunchConfiguration {
    let scenario: IslandDebugScenario?
    let presentOverlay: Bool
    /// Overlay remediation Phase 1 item 1.1 (P1.f): suppresses the "No agent
    /// hooks installed" banner. The bundled harness binary's hooks-installed
    /// probe (`AppModel.hasAnyInstalledAgent`) has no genuine hook state to
    /// read in that environment and always reads `false`, so the banner
    /// always renders — clipping short panels (`emptyState`,
    /// `completedFailed`, ...). Defaults to `false` so an unset var changes
    /// nothing; only an explicit `OPEN_ISLAND_HARNESS_SUPPRESS_INSTALL_HINT=1`
    /// opts in.
    let suppressInstallHint: Bool
    /// Overlay remediation Phase 3 (Task 1): opt-in override that lets
    /// `OverlayPanelController` install its `keyCommandMonitor` even during a
    /// harness scenario launch. Before this existed,
    /// `disablesOverlayEventMonitoringDuringHarness` (set unconditionally for
    /// *any* harness scenario, `OpenIslandAppDelegate
    /// .applicationDidFinishLaunching`) made `startEventMonitoring()` skip
    /// installing the key monitor entirely — pressing `1`/Enter on a
    /// harness-launched panel had zero effect, for every theme, and the
    /// verification protocol's own interactive mode could not exercise
    /// keyboard handling at all (confirmed by source read during Phase 2
    /// verification, not inferred from a failure). Defaults to `false` so an
    /// unset var changes nothing for existing capture runs — only an
    /// explicit `OPEN_ISLAND_HARNESS_ENABLE_KEY_MONITOR=1` opts in.
    let enableKeyMonitor: Bool
    /// Poured Slice 6 (PI-X-001 I1/I2): the Settings → Appearance preview
    /// scenario the pane should start on. The §I meter card renders *only*
    /// inside that preview, and its `.menu` `Picker` opens a transient menu
    /// that accessibility automation cannot drive, so evidence capture had no
    /// deterministic driver. `nil` for an absent or unrecognized value, so an
    /// unset var leaves the pane's own `.list` default untouched — the same
    /// harness-only seam shape as `AppModel.debugInstalledAgentNamesOverride`.
    let previewScenario: AppearancePreviewScenario?
    let shouldStartBridge: Bool
    let shouldPerformBootAnimation: Bool
    let captureDelay: TimeInterval?
    let autoExitAfter: TimeInterval?
    let artifactDirectoryURL: URL?
    #if HALO_PARITY_TESTING
    let haloParity: HaloParityLaunchState
    #endif
    #if POURED_PARITY_TESTING
    let pouredParity: PouredParityLaunchState
    #endif

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) {
        scenario = Self.scenarioValue(from: environment["OPEN_ISLAND_HARNESS_SCENARIO"])
        presentOverlay = Self.boolValue(
            environment["OPEN_ISLAND_HARNESS_PRESENT_OVERLAY"],
            default: false
        )
        suppressInstallHint = Self.boolValue(
            environment["OPEN_ISLAND_HARNESS_SUPPRESS_INSTALL_HINT"],
            default: false
        )
        enableKeyMonitor = Self.boolValue(
            environment["OPEN_ISLAND_HARNESS_ENABLE_KEY_MONITOR"],
            default: false
        )
        previewScenario = Self.previewScenarioValue(
            from: environment["OPEN_ISLAND_HARNESS_PREVIEW_SCENARIO"]
        )
        shouldStartBridge = Self.boolValue(
            environment["OPEN_ISLAND_HARNESS_START_BRIDGE"],
            default: true
        )
        shouldPerformBootAnimation = Self.boolValue(
            environment["OPEN_ISLAND_HARNESS_BOOT_ANIMATION"],
            default: true
        )
        captureDelay = Self.timeIntervalValue(
            from: environment["OPEN_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS"]
        )
        autoExitAfter = Self.timeIntervalValue(
            from: environment["OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS"]
        )
        artifactDirectoryURL = Self.directoryURLValue(
            from: environment["OPEN_ISLAND_HARNESS_ARTIFACT_DIR"]
        )
        #if HALO_PARITY_TESTING
        haloParity = Self.haloParityValue(environment: environment, arguments: arguments)
        #endif
        #if POURED_PARITY_TESTING
        pouredParity = PouredParityConfiguration.launchState(environment: environment, arguments: arguments)
        #endif
    }

    #if HALO_PARITY_TESTING
    private static func haloParityValue(
        environment: [String: String],
        arguments: [String]
    ) -> HaloParityLaunchState {
        let enableArgument = arguments.contains("--halo-parity")
        let enableEnvironment = environment["OPEN_ISLAND_HALO_PARITY"]
        let enabledByEnvironment: Bool
        if let enableEnvironment {
            let normalized = enableEnvironment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "on"].contains(normalized) {
                enabledByEnvironment = true
            } else if ["0", "false", "no", "off", ""].contains(normalized) {
                enabledByEnvironment = false
            } else {
                return .rejected(.unknown("OPEN_ISLAND_HALO_PARITY", enableEnvironment))
            }
        } else {
            enabledByEnvironment = false
        }
        guard enableArgument || enabledByEnvironment else {
            return .inactive
        }

        let valuedArguments = [
            "--halo-scenario", "--halo-profile", "--halo-motion",
            "--halo-accessibility", "--halo-event", "--halo-seed", "--halo-time-ms",
        ]
        var parsed: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if valuedArguments.contains(argument) {
                guard parsed[argument] == nil else {
                    return .rejected(.duplicateArgument(argument))
                }
                guard index + 1 < arguments.count else {
                    return .rejected(.danglingArgument(argument))
                }
                let value = arguments[index + 1]
                guard !value.hasPrefix("--") else {
                    return .rejected(.danglingArgument(argument))
                }
                parsed[argument] = value
                index += 2
            } else {
                index += 1
            }
        }

        func value(_ argument: String, environmentKey: String) -> String? {
            parsed[argument] ?? environment[environmentKey]
        }
        func required(_ argument: String, environmentKey: String) -> Result<String, HaloParityConfigurationError> {
            guard let raw = value(argument, environmentKey: environmentKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !raw.isEmpty else {
                return .failure(.missing(argument))
            }
            return .success(raw)
        }

        let scenarioRaw: String
        let profileRaw: String
        let motionRaw: String
        let accessibilityRaw: String
        let seedRaw: String
        switch required("--halo-scenario", environmentKey: "OPEN_ISLAND_HALO_SCENARIO") {
        case let .success(value): scenarioRaw = value
        case let .failure(error): return .rejected(error)
        }
        switch required("--halo-profile", environmentKey: "OPEN_ISLAND_HALO_PROFILE") {
        case let .success(value): profileRaw = value
        case let .failure(error): return .rejected(error)
        }
        switch required("--halo-motion", environmentKey: "OPEN_ISLAND_HALO_MOTION") {
        case let .success(value): motionRaw = value
        case let .failure(error): return .rejected(error)
        }
        switch required("--halo-accessibility", environmentKey: "OPEN_ISLAND_HALO_ACCESSIBILITY") {
        case let .success(value): accessibilityRaw = value
        case let .failure(error): return .rejected(error)
        }
        switch required("--halo-seed", environmentKey: "OPEN_ISLAND_HALO_SEED") {
        case let .success(value): seedRaw = value
        case let .failure(error): return .rejected(error)
        }

        guard let scenario = HaloParityScenarioID.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(scenarioRaw) == .orderedSame
        }) else {
            return .rejected(.unknown("--halo-scenario", scenarioRaw))
        }
        guard let profile = HaloParityProfile.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(profileRaw) == .orderedSame
        }) else {
            return .rejected(.unknown("--halo-profile", profileRaw))
        }
        guard let motion = HaloParityMotionMode(rawValue: motionRaw.lowercased()) else {
            return .rejected(.unknown("--halo-motion", motionRaw))
        }
        guard let accessibility = HaloParityAccessibility.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(accessibilityRaw) == .orderedSame
        }) else {
            return .rejected(.unknown("--halo-accessibility", accessibilityRaw))
        }
        guard let seed = UInt64(seedRaw) else {
            return .rejected(.invalidSeed)
        }
        let eventRaw = value("--halo-event", environmentKey: "OPEN_ISLAND_HALO_EVENT")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let event: HaloParityEvent?
        if let eventRaw, !eventRaw.isEmpty {
            guard let parsedEvent = HaloParityEvent.allCases.first(where: {
                $0.rawValue.caseInsensitiveCompare(eventRaw) == .orderedSame
            }) else {
                return .rejected(.unknown("--halo-event", eventRaw))
            }
            event = parsedEvent
        } else {
            event = nil
        }
        let timeRaw = value("--halo-time-ms", environmentKey: "OPEN_ISLAND_HALO_TIME_MS")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let time: UInt64?
        if let timeRaw, !timeRaw.isEmpty {
            guard let parsedTime = UInt64(timeRaw) else {
                return .rejected(.invalidTime)
            }
            time = parsedTime
        } else {
            time = nil
        }

        do {
            return .configured(try HaloParityConfiguration(
                scenario: scenario,
                profile: profile,
                motion: motion,
                accessibility: accessibility,
                event: event,
                seed: seed,
                manualTimeMilliseconds: time
            ).validated())
        } catch let error as HaloParityConfigurationError {
            return .rejected(error)
        } catch {
            return .rejected(.unknown("configuration", error.localizedDescription))
        }
    }
    #endif

    private static func scenarioValue(from rawValue: String?) -> IslandDebugScenario? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        return IslandDebugScenario.allCases.first { scenario in
            scenario.rawValue.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    private static func previewScenarioValue(from rawValue: String?) -> AppearancePreviewScenario? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        return AppearancePreviewScenario.allCases.first { scenario in
            scenario.rawValue.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    private static func boolValue(_ rawValue: String?, default defaultValue: Bool) -> Bool {
        guard let rawValue else {
            return defaultValue
        }

        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return defaultValue
        }

        return switch normalized {
        case "1", "true", "yes", "on":
            true
        case "0", "false", "no", "off":
            false
        default:
            defaultValue
        }
    }

    private static func timeIntervalValue(from rawValue: String?) -> TimeInterval? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = TimeInterval(normalized),
              seconds > 0 else {
            return nil
        }

        return seconds
    }

    private static func directoryURLValue(from rawValue: String?) -> URL? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: normalized, isDirectory: true)
    }
}
