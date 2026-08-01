import AppKit
import OpenIslandCore
import SwiftUI

@MainActor
final class OpenIslandAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let harnessLaunchConfiguration = HarnessLaunchConfiguration()
    private let launchedAt = Date()
    private lazy var harnessRuntimeMonitor = HarnessRuntimeMonitor(launchedAt: launchedAt)

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Open Island should remain active while monitoring local agent sessions."
        )
        ProcessInfo.processInfo.disableSuddenTermination()
        NSApp.setActivationPolicy(model.showDockIcon ? .regular : .accessory)
        harnessRuntimeMonitor.recordMilestone("applicationDidFinishLaunching")
        _ = RuntimeNetworkPolicy.validateProductionInvariant()

        DispatchQueue.main.async { [self] in
            harnessRuntimeMonitor.recordMilestone("bootstrapStarted")
            model.harnessRuntimeMonitor = harnessRuntimeMonitor
            harnessRuntimeMonitor.recordLog(model.lastActionMessage)

            #if POURED_PARITY_TESTING
            let parityRequested: Bool
            switch harnessLaunchConfiguration.pouredParity {
            case .inactive: parityRequested = false
            case .configured, .rejected: parityRequested = true
            }
            #elseif HALO_PARITY_TESTING
            let parityRequested: Bool
            switch harnessLaunchConfiguration.haloParity {
            case .inactive:
                parityRequested = false
            case .configured, .rejected:
                parityRequested = true
            }
            #else
            let parityRequested = false
            #endif
            model.ignoresPointerExitDuringHarness = harnessLaunchConfiguration.scenario != nil || parityRequested
            model.disablesOverlayEventMonitoringDuringHarness = harnessLaunchConfiguration.scenario != nil || parityRequested
            // Overlay remediation Phase 3, Task 1: harness-only, opt-in via env
            // var — see `AppModel.enablesOverlayKeyMonitorDuringHarness` for why
            // this exists and why it can't reach a real user.
            model.enablesOverlayKeyMonitorDuringHarness = harnessLaunchConfiguration.enableKeyMonitor
            // Overlay remediation Phase 1 item 1.1: harness-only, opt-in via env
            // var — see `AppModel.debugSuppressesInstallHint` for why this can't
            // reach a real user.
            model.debugSuppressesInstallHint = harnessLaunchConfiguration.suppressInstallHint
            #if HALO_PARITY_TESTING
            if parityRequested {
                model.haloParityBootstrapIsolation = HaloParityBootstrapIsolationProof(
                    runtimeStateLoadingDisabled: true,
                    bridgeStartupDisabled: true
                )
            }
            #endif
            #if POURED_PARITY_TESTING
            if parityRequested {
                model.pouredParityBootstrapIsolation = PouredParityBootstrapIsolationProof(runtimeStateLoadingDisabled:true,bridgeStartupDisabled:true)
            }
            #endif
            model.startIfNeeded(
                startBridge: parityRequested ? false : harnessLaunchConfiguration.shouldStartBridge,
                shouldPerformBootAnimation: parityRequested ? false : harnessLaunchConfiguration.shouldPerformBootAnimation,
                loadRuntimeState: !parityRequested && harnessLaunchConfiguration.scenario == nil
            )
            harnessRuntimeMonitor.recordMilestone("modelStarted")

            // Settings/chrome is never part of a parity crop. Hide it before
            // presenting parity so the real overlay window remains visible to
            // WindowServer capture.
            if parityRequested {
                OpenIslandAppDelegate.hideAllAppWindows()
            }

            #if HALO_PARITY_TESTING
            switch harnessLaunchConfiguration.haloParity {
            case .inactive:
                break
            case let .configured(configuration):
                do {
                    let driver = HaloParityDriver(configuration: configuration)
                    try driver.apply(to: model, presentOverlay: true)
                    if configuration.event == nil {
                        // Overlay placement is resolved by the real panel show
                        // path. Give that existing lifecycle one run-loop turn,
                        // then require positive diagnostics before emission.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self, driver] in
                            if let directory = harnessLaunchConfiguration.artifactDirectoryURL {
                                writeHaloParitySidecarsWhenReady(
                                    driver: driver,
                                    directory: directory,
                                    stage: "sidecar",
                                    attemptsRemaining: 50
                                )
                            }
                        }
                    } else {
                        // The real SwiftUI question card registers its
                        // production keyboard closures on appearance. Apply
                        // the configured command after that registration, then
                        // emit sidecars containing the acknowledgement.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self, driver] in
                            do {
                                try driver.applyConfiguredEvent(to: model)
                                if let directory = harnessLaunchConfiguration.artifactDirectoryURL {
                                    writeHaloParitySidecarsWhenReady(
                                        driver: driver,
                                        directory: directory,
                                        stage: "event",
                                        attemptsRemaining: 50
                                    )
                                }
                                harnessRuntimeMonitor.recordMilestone(
                                    "haloParityEventAcknowledged",
                                    message: configuration.event?.rawValue
                                )
                            } catch {
                                model.lastActionMessage = "Halo parity event rejected: \(error)"
                                recordHaloParityRejection(
                                    stage: "event",
                                    error: error,
                                    directory: harnessLaunchConfiguration.artifactDirectoryURL
                                )
                                harnessRuntimeMonitor.recordMilestone(
                                    "haloParityEventRejected",
                                    message: "\(error)"
                                )
                            }
                        }
                    }
                    harnessRuntimeMonitor.recordMilestone(
                        "haloParityLoaded",
                        message: "\(configuration.scenario.rawValue) \(driver.fixture.record.dataHash)"
                    )
                } catch {
                    // Fail closed: the model was started without bridge/runtime
                    // loading and remains isolated if fixture application fails.
                    model.loadDebugSnapshot(
                        IslandDebugScenario.emptyState.snapshot(at: launchedAt),
                        presentOverlay: false
                    )
                    model.lastActionMessage = "Halo parity rejected: \(error)"
                    recordHaloParityRejection(
                        stage: "configuration",
                        error: error,
                        directory: harnessLaunchConfiguration.artifactDirectoryURL
                    )
                    harnessRuntimeMonitor.recordMilestone("haloParityRejected", message: "\(error)")
                }
            case let .rejected(error):
                model.loadDebugSnapshot(
                    IslandDebugScenario.emptyState.snapshot(at: launchedAt),
                    presentOverlay: false
                )
                model.lastActionMessage = "Halo parity rejected: \(error.description)"
                harnessRuntimeMonitor.recordMilestone("haloParityRejected", message: error.description)
            }
            #endif

            #if POURED_PARITY_TESTING
            switch harnessLaunchConfiguration.pouredParity {
            case .inactive: break
            case .rejected(let error):
                model.loadDebugSnapshot(IslandDebugScenario.emptyState.snapshot(at:launchedAt),presentOverlay:false)
                model.lastActionMessage="Poured parity rejected: \(error.description)"
            case .configured(let configuration):
                do {
                    let driver=PouredParityDriver(configuration:configuration)
                    try driver.apply(to:model,presentOverlay:true)
                    if configuration.event != nil { try driver.applyConfiguredEvent(to:model) }
                    harnessRuntimeMonitor.recordMilestone("pouredParityLoaded",message:"\(configuration.scenario.rawValue) \(driver.fixture.record.dataHash)")
                } catch {
                    model.loadDebugSnapshot(IslandDebugScenario.emptyState.snapshot(at:launchedAt),presentOverlay:false)
                    model.lastActionMessage="Poured parity rejected: \(error)"
                    harnessRuntimeMonitor.recordMilestone("pouredParityRejected",message:"\(error)")
                }
            }
            #endif

            if !parityRequested, let scenario = harnessLaunchConfiguration.scenario {
                model.loadDebugSnapshot(
                    scenario.snapshot(),
                    presentOverlay: harnessLaunchConfiguration.presentOverlay
                )
            }

            // Hide all windows on launch — settings opens on demand only.
            if !parityRequested {
                OpenIslandAppDelegate.hideAllAppWindows()
            }

            harnessRuntimeMonitor.recordMilestone("bootstrapCompleted")

            if let captureDelay = harnessLaunchConfiguration.captureDelay,
               harnessLaunchConfiguration.artifactDirectoryURL != nil {
                harnessRuntimeMonitor.recordMilestone(
                    "captureScheduled",
                    message: String(format: "%.3fs", captureDelay)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) { [self] in
                    harnessRuntimeMonitor.recordMilestone("captureStarted")
                    try? HarnessArtifactRecorder.record(
                        configuration: harnessLaunchConfiguration,
                        model: model,
                        launchedAt: launchedAt,
                        runtimeMonitor: harnessRuntimeMonitor
                    )
                }
            }

            if let autoExitAfter = harnessLaunchConfiguration.autoExitAfter {
                harnessRuntimeMonitor.recordMilestone(
                    "autoExitScheduled",
                    message: String(format: "%.3fs", autoExitAfter)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + autoExitAfter) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private static func hideAllAppWindows() {
        for window in NSApp.windows {
            window.orderOut(nil)
        }
    }

    #if HALO_PARITY_TESTING
    private func writeHaloParitySidecarsWhenReady(
        driver: HaloParityDriver,
        directory: URL,
        stage: String,
        attemptsRemaining: Int
    ) {
        do {
            try driver.writeSidecars(
                to: directory,
                model: model,
                processStartedAt: launchedAt
            )
        } catch HaloParityConfigurationError.missingWindowServerPlacement
            where attemptsRemaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self, driver] in
                writeHaloParitySidecarsWhenReady(
                    driver: driver,
                    directory: directory,
                    stage: stage,
                    attemptsRemaining: attemptsRemaining - 1
                )
            }
        } catch {
            model.lastActionMessage = "Halo parity \(stage) rejected: \(error)"
            recordHaloParityRejection(stage: stage, error: error, directory: directory)
            harnessRuntimeMonitor.recordMilestone(
                "haloParitySidecarRejected",
                message: "\(error)"
            )
        }
    }

    private func recordHaloParityRejection(
        stage: String,
        error: Error,
        directory: URL?
    ) {
        guard let directory else { return }
        let record: [String: String] = [
            "schemaVersion": "1.0.0",
            "stage": stage,
            "error": String(describing: error),
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(
                withJSONObject: record,
                options: [.prettyPrinted, .sortedKeys]
              ) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? data.write(
            to: directory.appendingPathComponent("halo-parity-rejection.json"),
            options: .atomic
        )
    }
    #endif

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showSettings()
        return false
    }
}

@main
struct OpenIslandApp: App {
    @NSApplicationDelegateAdaptor(OpenIslandAppDelegate.self)
    private var appDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Open Island Settings", id: "settings") {
            SettingsWindowContent(model: appDelegate.model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openWindow(id: "settings")
                    appDelegate.model.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Refreshes the `openWindow` registration each time the settings
/// window opens, keeping the closure current after window recreation.
private struct SettingsWindowContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsView(model: model)
            .onAppear {
                model.openSettingsWindow = { [openWindow] in
                    openWindow(id: "settings")
                }
            }
    }
}
