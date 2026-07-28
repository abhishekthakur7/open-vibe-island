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
    let shouldStartBridge: Bool
    let shouldPerformBootAnimation: Bool
    let captureDelay: TimeInterval?
    let autoExitAfter: TimeInterval?
    let artifactDirectoryURL: URL?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
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
    }

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
