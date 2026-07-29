import Foundation
import Observation
import OpenIslandCore

enum HookConsentRequest: String, Sendable {
    case claude, codex, openCode, qoder, qwenCode, factory, codebuddy, cursor, gemini, kimi, claudeUsage
}

private enum HookConsentOperation { case install, uninstall }

@MainActor
@Observable
final class HookInstallationCoordinator {
    @ObservationIgnored
    let intentStore: AgentIntentStore

    init(intentStore: AgentIntentStore = AgentIntentStore()) {
        self.intentStore = intentStore
    }

    var codexHookStatus: CodexHookInstallationStatus?
    var claudeHookStatus: ClaudeHookInstallationStatus?
    var qoderHookStatus: ClaudeHookInstallationStatus?
    var qwenCodeHookStatus: ClaudeHookInstallationStatus?
    var factoryHookStatus: ClaudeHookInstallationStatus?
    var codebuddyHookStatus: ClaudeHookInstallationStatus?
    var openCodePluginStatus: OpenCodePluginInstallationStatus?
    var cursorHookStatus: CursorHookInstallationStatus?
    var geminiHookStatus: GeminiHookInstallationStatus?
    var kimiHookStatus: KimiHookInstallationStatus?
    var claudeStatusLineStatus: ClaudeStatusLineInstallationStatus?
    var claudeUsageSnapshot: ClaudeUsageSnapshot?
    var codexUsageSnapshot: CodexUsageSnapshot?
    var hooksBinaryURL: URL?
    var isCodexSetupBusy = false
    var isClaudeHookSetupBusy = false
    var isQoderHookSetupBusy = false
    var isQwenCodeHookSetupBusy = false
    var isFactoryHookSetupBusy = false
    var isCodebuddyHookSetupBusy = false
    var isOpenCodeSetupBusy = false
    var isCursorHookSetupBusy = false
    var isGeminiHookSetupBusy = false
    var isKimiHookSetupBusy = false
    var isClaudeUsageSetupBusy = false

    @ObservationIgnored
    private let consentGate = HookConsentGate()

    @ObservationIgnored
    private var confirmedRequests: [HookConsentRequest: (preview: HookConsentPreview, token: HookConsentGate.Token, operation: HookConsentOperation)] = [:]

    @ObservationIgnored
    private var confirmedReset: (preview: HookAggregateConsentPreview, token: HookConsentGate.Token)?

    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    @ObservationIgnored
    private let codexHookInstallationManager = CodexHookInstallationManager()

    /// Computed so it always reflects the latest `ClaudeConfigDirectory` setting.
    private var claudeHookInstallationManager: ClaudeHookInstallationManager {
        ClaudeHookInstallationManager()
    }

    @ObservationIgnored
    private let qoderHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qoder", isDirectory: true),
        hookSource: "qoder"
    )

    @ObservationIgnored
    private let qwenCodeHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qwen", isDirectory: true),
        hookSource: "qwen"
    )

    @ObservationIgnored
    private let factoryHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".factory", isDirectory: true),
        hookSource: "factory"
    )

    @ObservationIgnored
    private let codebuddyHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codebuddy", isDirectory: true),
        hookSource: "codebuddy"
    )

    @ObservationIgnored
    private let openCodePluginInstallationManager = OpenCodePluginInstallationManager()

    @ObservationIgnored
    private let cursorHookInstallationManager = CursorHookInstallationManager()

    @ObservationIgnored
    private let geminiHookInstallationManager = GeminiHookInstallationManager()

    @ObservationIgnored
    private let kimiHookInstallationManager = KimiHookInstallationManager()

    /// Computed so it always reflects the latest `ClaudeConfigDirectory` setting.
    private var claudeStatusLineInstallationManager: ClaudeStatusLineInstallationManager {
        ClaudeStatusLineInstallationManager()
    }

    @ObservationIgnored
    private var claudeUsageMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var codexUsageMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var relativeTimestampFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }

    // MARK: - Computed display properties

    var codexHooksInstalled: Bool {
        codexHookStatus?.managedHooksPresent == true
    }

    var claudeHooksInstalled: Bool {
        claudeHookStatus?.managedHooksPresent == true
    }

    var qoderHooksInstalled: Bool {
        qoderHookStatus?.managedHooksPresent == true
    }

    var qwenCodeHooksInstalled: Bool {
        qwenCodeHookStatus?.managedHooksPresent == true
    }

    var factoryHooksInstalled: Bool {
        factoryHookStatus?.managedHooksPresent == true
    }

    var codebuddyHooksInstalled: Bool {
        codebuddyHookStatus?.managedHooksPresent == true
    }

    var openCodePluginInstalled: Bool {
        openCodePluginStatus?.isInstalled == true
    }

    var cursorHooksInstalled: Bool {
        cursorHookStatus?.managedHooksPresent == true
    }

    var geminiHooksInstalled: Bool {
        geminiHookStatus?.managedHooksPresent == true
    }

    var kimiHooksInstalled: Bool {
        kimiHookStatus?.managedHooksPresent == true
    }

    var claudeUsageInstalled: Bool {
        claudeStatusLineStatus?.managedStatusLineInstalled == true
    }

    /// The sole family-aware presentation boundary for Settings and AppModel.
    /// Status inspection has already occurred before this is called; this
    /// accessor never repairs, prunes, creates, or updates anything.
    func managementStatus(for family: HookIntegrationFamily) -> HookManagementStatus? {
        let outcome: HookManagementOutcome? = switch family {
        case .claude: claudeHookStatus?.managementOutcome
        case .qoder: qoderHookStatus?.managementOutcome
        case .qwenCode: qwenCodeHookStatus?.managementOutcome
        case .factoryDroid: factoryHookStatus?.managementOutcome
        case .codebuddy: codebuddyHookStatus?.managementOutcome
        case .codexCLI: codexHookStatus?.managementOutcome
        case .cursor: cursorHookStatus?.managementOutcome
        case .gemini: geminiHookStatus?.managementOutcome
        case .kimi: kimiHookStatus?.managementOutcome
        case .openCodeConfig, .openCodePlugin: openCodePluginStatus?.managementOutcome
        case .claudeStatusLine: claudeStatusLineStatus?.managementOutcome
        case .sharedHelper: hooksBinaryURL.map { ManagedHooksBinary.managementOutcome(at: $0) }
        }
        return outcome?.status(for: family)
    }

    private func remediation(for outcome: HookManagementOutcome, family: HookIntegrationFamily) -> String? {
        switch outcome {
        case .success, .noChange, .exactManaged, .unowned: nil
        default: outcome.status(for: family).remediation
        }
    }

    var claudeHookStatusTitle: String {
        if claudeHooksInstalled {
            return "Claude hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Claude hooks not installed"
    }

    var claudeHookStatusSummary: String {
        guard let status = claudeHookStatus else {
            return "Reading \(ClaudeConfigDirectory.resolved().appendingPathComponent("settings.json").path)."
        }

        if claudeHooksInstalled {
            if status.hasClaudeIslandHooks {
                return "managed hooks present · claude-island hooks also detected"
            }
            return "managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Refresh Open Island Dev with zsh scripts/launch-dev-app.sh before installing."
        }

        if let remediation = remediation(for: status.managementOutcome, family: .claude) { return remediation }

        if status.hasClaudeIslandHooks {
            return "claude-island hooks detected · managed hooks absent"
        }

        return "no managed Claude hooks"
    }

    var claudeUsageStatusTitle: String {
        guard let status = claudeStatusLineStatus else {
            return "Claude usage status unavailable"
        }

        if status.managedStatusLineInstalled {
            return "Claude usage bridge installed"
        }

        if status.managedStatusLineNeedsRepair {
            return "Claude usage bridge needs repair"
        }

        if status.hasConflictingStatusLine {
            return "Custom Claude status line detected"
        }

        return "Claude usage bridge not installed"
    }

    var claudeUsageStatusSummary: String {
        guard let status = claudeStatusLineStatus else {
            return "Reading \(ClaudeConfigDirectory.resolved().appendingPathComponent("settings.json").path)."
        }

        if let remediation = remediation(for: status.managementOutcome, family: .claudeStatusLine) { return remediation }

        if status.managedStatusLineInstalled {
            if let summary = claudeUsageSummaryText {
                return "Caching rate limits from Claude Code · \(summary)"
            }
            return "Caching rate limits from Claude Code into \(status.cacheURL.path)."
        }

        if status.managedStatusLineNeedsRepair {
            return "Open Island detected a missing managed Claude status line script and will repair it automatically."
        }

        if status.hasConflictingStatusLine {
            return "Open Island will not overwrite an existing Claude status line automatically."
        }

        return "Install a managed Claude status line to cache 5h and 7d usage locally."
    }

    var claudeUsageSummaryText: String? {
        guard let snapshot = claudeUsageSnapshot else {
            return nil
        }

        var components: [String] = []
        if let fiveHour = snapshot.fiveHour {
            components.append("5h \(fiveHour.roundedUsedPercentage)%")
        }
        if let sevenDay = snapshot.sevenDay {
            components.append("7d \(sevenDay.roundedUsedPercentage)%")
        }
        if let cachedAt = snapshot.cachedAt {
            components.append("updated \(relativeTimestampFormatter.localizedString(for: cachedAt, relativeTo: .now))")
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var codexUsageStatusTitle: String {
        if codexUsageSnapshot?.isEmpty == false {
            return "Codex rate limits detected"
        }

        return "Waiting for Codex rate limits"
    }

    var codexUsageStatusSummary: String {
        if let summary = codexUsageSummaryText {
            return "Reading the latest local rollout token_count snapshots · \(summary)"
        }

        return "Passively reading ~/.codex/sessions/**/rollout-*.jsonl and extracting token_count.rate_limits."
    }

    var codexUsageSummaryText: String? {
        guard let snapshot = codexUsageSnapshot else {
            return nil
        }

        var components = snapshot.windows.map { window in
            "\(window.label) \(window.roundedUsedPercentage)%"
        }

        if let planType = snapshot.planType {
            components.append("plan \(planType)")
        }

        if let capturedAt = snapshot.capturedAt {
            components.append("updated \(relativeTimestampFormatter.localizedString(for: capturedAt, relativeTo: .now))")
        }

        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var openCodePluginStatusTitle: String {
        if openCodePluginInstalled {
            return "OpenCode plugin installed"
        }

        return "OpenCode plugin not installed"
    }

    var openCodePluginStatusSummary: String {
        guard let status = openCodePluginStatus else {
            return "Reading ~/.config/opencode state."
        }

        if status.isInstalled {
            return "managed plugin present in \(status.pluginsDirectory.path)"
        }

        if let remediation = remediation(for: status.managementOutcome, family: .openCodePlugin) { return remediation }

        if status.pluginFilePresent && !status.pluginRegistered {
            return "plugin file present but not registered in config.json"
        }

        return "no managed OpenCode plugin"
    }

    var cursorHookStatusTitle: String {
        if cursorHooksInstalled {
            return "Cursor hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Cursor hooks not installed"
    }

    var cursorHookStatusSummary: String {
        guard let status = cursorHookStatus else {
            return "Reading ~/.cursor/hooks.json."
        }

        if let remediation = remediation(for: status.managementOutcome, family: .cursor) { return remediation }

        if cursorHooksInstalled {
            return "managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Refresh Open Island Dev with zsh scripts/launch-dev-app.sh before installing."
        }

        return "no managed Cursor hooks"
    }

    var geminiHookStatusTitle: String {
        guard let status = geminiHookStatus else { return "Gemini hooks loading" }
        if status.managementOutcome != .exactManaged, status.managementOutcome != .unowned {
            return "Gemini hooks need attention"
        }
        return status.managedHooksPresent ? "Gemini hooks installed" : "Gemini hooks not installed"
    }

    var geminiHookStatusSummary: String {
        guard let status = geminiHookStatus else {
            return "Reading ~/.gemini/settings.json."
        }

        if let remediation = remediation(for: status.managementOutcome, family: .gemini) { return remediation }

        if hooksBinaryURL == nil {
            return "Refresh Open Island Dev with zsh scripts/launch-dev-app.sh before installing."
        }

        return status.managedHooksPresent ? "managed hooks present" : "no managed Gemini hooks"
    }

    var kimiHookStatusTitle: String {
        if kimiHooksInstalled {
            return "Kimi hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Kimi hooks not installed"
    }

    var kimiHookStatusSummary: String {
        guard let status = kimiHookStatus else {
            return "Reading ~/.kimi/config.toml."
        }

        if let remediation = remediation(for: status.managementOutcome, family: .kimi) { return remediation }

        if kimiHooksInstalled {
            return "managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Refresh Open Island Dev with zsh scripts/launch-dev-app.sh before installing."
        }

        return "no managed Kimi hooks"
    }

    var codexHookStatusTitle: String {
        if codexHooksInstalled {
            return "Codex hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Codex hooks not installed"
    }

    var codexHookStatusSummary: String {
        guard let status = codexHookStatus else {
            return "Reading ~/.codex state."
        }

        if let remediation = remediation(for: status.managementOutcome, family: .codexCLI) { return remediation }

        if codexHooksInstalled {
            let featureText = status.featureFlagEnabled ? "feature on" : "feature off"
            return "\(featureText) · managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Refresh Open Island Dev with zsh scripts/launch-dev-app.sh before installing."
        }

        return status.featureFlagEnabled ? "feature on · no managed hooks" : "feature off · no managed hooks"
    }

    // MARK: - Claude config directory

    /// Updates the custom Claude config directory, cleans up old hooks if present, and refreshes status.
    func updateClaudeConfigDirectory(to newDirectory: URL?) {
        let oldDirectory = ClaudeConfigDirectory.resolved()
        let oldHadHooks = claudeHookStatus?.managedHooksPresent == true

        ClaudeConfigDirectory.customDirectory = newDirectory

        // Refresh status from the new directory
        refreshClaudeHookStatus()
        refreshClaudeUsageState()

        let newPath = ClaudeConfigDirectory.resolved().path
        if oldHadHooks {
            let oldPath = oldDirectory.path
            if oldPath != newPath {
                onStatusMessage?("Claude config directory changed to \(newPath). Hooks in \(oldPath) were not removed — uninstall them manually if no longer needed.")
            }
        } else {
            onStatusMessage?("Claude config directory set to \(newPath).")
        }
    }

    // MARK: - Auto-update hooks binary

    /// Hook helper updates are performed only as part of the user-confirmed
    /// installer.  Startup must never mutate an agent configuration or helper.
    func updateHooksBinaryIfNeeded() {
        guard hooksBinaryURL != nil else { return }
        onStatusMessage?("Hook helper updates require an explicit install confirmation in Setup.")
    }

    // MARK: - Health check & auto-repair

    var codexHealthReport: HookHealthReport?
    var claudeHealthReport: HookHealthReport?
    var openCodeHealthReport: HookHealthReport?
    var cursorHealthReport: HookHealthReport?
    var geminiHealthReport: HookHealthReport?


    /// Runs read-only health checks for Claude, Codex, Gemini and OpenCode hooks.
    func runHealthChecks() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let binaryURL = self.hooksBinaryURL
            let (claudeReport, codexReport, geminiReport, openCodeReport) = await Task.detached(priority: .utility) {
                let claude = HookHealthCheck.checkClaude(hooksBinaryURL: binaryURL)
                let codex = HookHealthCheck.checkCodex(hooksBinaryURL: binaryURL)
                let gemini = HookHealthCheck.checkGemini(hooksBinaryURL: binaryURL)
                let openCode = HookHealthCheck.checkOpenCode()
                return (claude, codex, gemini, openCode)
            }.value

            self.claudeHealthReport = claudeReport
            self.codexHealthReport = codexReport
            self.geminiHealthReport = geminiReport
            self.openCodeHealthReport = openCodeReport

            if !claudeReport.isHealthy || !codexReport.isHealthy || !geminiReport.isHealthy || !openCodeReport.isHealthy {
                let claudeIssueCount = claudeReport.errors.count
                let codexIssueCount = codexReport.errors.count
                let geminiIssueCount = geminiReport.errors.count
                let openCodeIssueCount = openCodeReport.errors.count
                self.onStatusMessage?("Hook health check: \(claudeIssueCount) Claude, \(codexIssueCount) Codex, \(geminiIssueCount) Gemini, \(openCodeIssueCount) OpenCode issue(s).")
            }
        }
    }

    /// Repair is observational until the user reviews a fresh preview in
    /// Settings.  Startup and diagnostics must never mutate agent files.
    @discardableResult
    func repairHooksIfNeeded() async -> Bool {
        // Re-run health checks first
        let binaryURL = hooksBinaryURL
        let (claudeReport, codexReport, geminiReport, openCodeReport) = await Task.detached(priority: .utility) {
            let claude = HookHealthCheck.checkClaude(hooksBinaryURL: binaryURL)
            let codex = HookHealthCheck.checkCodex(hooksBinaryURL: binaryURL)
            let gemini = HookHealthCheck.checkGemini(hooksBinaryURL: binaryURL)
            let openCode = HookHealthCheck.checkOpenCode()
            return (claude, codex, gemini, openCode)
        }.value

        claudeHealthReport = claudeReport
        codexHealthReport = codexReport
        geminiHealthReport = geminiReport
        openCodeHealthReport = openCodeReport

        if !claudeReport.repairableIssues.isEmpty || !codexReport.repairableIssues.isEmpty || !geminiReport.repairableIssues.isEmpty || !openCodeReport.repairableIssues.isEmpty {
            onStatusMessage?("Repair requires a new source and target preview plus explicit confirmation in Setup.")
        }
        return false
    }

    // MARK: - Refresh

    func refreshCodexHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.codexHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.codexHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Codex hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshClaudeHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.claudeHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.claudeHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Claude hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshCCForkHookStatuses() {
        refreshCCForkHookStatus(manager: qoderHookInstallationManager, name: "Qoder") { [weak self] in self?.qoderHookStatus = $0 }
        refreshCCForkHookStatus(manager: qwenCodeHookInstallationManager, name: "Qwen Code") { [weak self] in self?.qwenCodeHookStatus = $0 }
        refreshCCForkHookStatus(manager: factoryHookInstallationManager, name: "Factory") { [weak self] in self?.factoryHookStatus = $0 }
        refreshCCForkHookStatus(manager: codebuddyHookInstallationManager, name: "CodeBuddy") { [weak self] in self?.codebuddyHookStatus = $0 }
    }

    private func refreshCCForkHookStatus(
        manager: ClaudeHookInstallationManager,
        name: String,
        apply: @MainActor @escaping (ClaudeHookInstallationStatus) -> Void
    ) {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try manager.status(hooksBinaryURL: self.hooksBinaryURL)
                apply(status)
            } catch {
                self.onStatusMessage?("Failed to read \(name) hook status: \(error.localizedDescription)")
            }
        }
    }

    /// Awaitable versions of refresh for use in startup flow to avoid race conditions.
    func refreshAllHookStatusAndWait() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.claudeHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.claudeHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Claude hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.codexHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.codexHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Codex hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.openCodePluginInstallationManager.status()
                    self.openCodePluginStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read OpenCode plugin status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let usageState = try self.readClaudeUsageState(repairManagedBridgeIfNeeded: true)
                    self.claudeStatusLineStatus = usageState.status
                    self.claudeUsageSnapshot = usageState.snapshot
                } catch {
                    self.onStatusMessage?("Failed to read Claude usage state: \(error.localizedDescription)")
                }
            }

            // CC fork agents
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                for (manager, name, apply) in [
                    (self.qoderHookInstallationManager, "Qoder", { [weak self] (s: ClaudeHookInstallationStatus) in self?.qoderHookStatus = s }),
                    (self.qwenCodeHookInstallationManager, "Qwen Code", { [weak self] (s: ClaudeHookInstallationStatus) in self?.qwenCodeHookStatus = s }),
                    (self.factoryHookInstallationManager, "Factory", { [weak self] (s: ClaudeHookInstallationStatus) in self?.factoryHookStatus = s }),
                    (self.codebuddyHookInstallationManager, "CodeBuddy", { [weak self] (s: ClaudeHookInstallationStatus) in self?.codebuddyHookStatus = s }),
                ] {
                    do {
                        let status = try manager.status(hooksBinaryURL: self.hooksBinaryURL)
                        apply(status)
                    } catch {
                        self.onStatusMessage?("Failed to read \(name) hook status: \(error.localizedDescription)")
                    }
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.geminiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.geminiHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Gemini hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.kimiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.kimiHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Kimi hook status: \(error.localizedDescription)")
                }
            }
        }
    }

    func refreshOpenCodePluginStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.openCodePluginInstallationManager.status()
                self.openCodePluginStatus = status
            } catch {
                self.onStatusMessage?("Failed to read OpenCode plugin status: \(error.localizedDescription)")
            }
        }
    }

    func refreshCursorHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.cursorHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.cursorHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Cursor hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshGeminiHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.geminiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.geminiHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Gemini hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshKimiHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.kimiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.kimiHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Kimi hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshClaudeUsageState() {
        let manager = claudeStatusLineInstallationManager
        Task { [weak self] in
            guard let self else { return }

            do {
                let usageState = try await Task.detached(priority: .utility) {
                    // Status refresh is intentionally observational. A missing
                    // script or copied marker is ambiguous until the user
                    // explicitly chooses an install/repair action in Settings.
                    let status = try manager.status()
                    let repairedManagedBridge = false
                    let snapshot = try ClaudeUsageLoader.load()
                    return (status: status, snapshot: snapshot, repairedManagedBridge: repairedManagedBridge)
                }.value
                self.claudeStatusLineStatus = usageState.status
                self.claudeUsageSnapshot = usageState.snapshot
                if usageState.repairedManagedBridge {
                    self.onStatusMessage?("Recovered the Claude usage bridge after repairing a missing managed script.")
                }
            } catch {
                self.onStatusMessage?("Failed to read Claude usage state: \(error.localizedDescription)")
            }
        }
    }

    func refreshCodexUsageState() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    try CodexUsageLoader.load()
                }.value
                self.codexUsageSnapshot = snapshot
            } catch {
                self.onStatusMessage?("Failed to read Codex usage state: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Intent-aware helpers

    /// Reports whether the startup flow should auto-install hooks for the
    /// given agent.
    ///
    /// Post-onboarding, the only case that triggers auto-install is
    /// `.installed && !present` — i.e. the user asked for this hook in the
    /// past but it is currently missing (fresh machine, config wiped,
    /// upgraded binary path, etc). This is a repair, not a surprise
    /// install. `.untouched` and `.uninstalled` both return false;
    /// untouched agents are surfaced to the user via the first-run
    /// onboarding window and the empty-state banner instead.
    func shouldAutoInstall(_ agent: AgentIdentifier) -> Bool {
        _ = agent
        return false
    }

    // MARK: - Intent store migration

    /// Reconciles the persisted intent store with the hook status currently
    /// observed on disk. Must be called only after
    /// `refreshAllHookStatusAndWait()` has returned, otherwise every agent
    /// will be recorded as `.untouched` and legacy users will have their
    /// installed hooks silently forgotten.
    func migrateIntentStoreIfNeeded() {
        intentStore.migrateFromLegacyStateIfNeeded { [self] agent in
            switch agent {
            case .claudeCode: return claudeHooksInstalled
            case .codex: return codexHooksInstalled
            case .cursor: return cursorHooksInstalled
            case .qoder: return qoderHooksInstalled
            case .qwenCode: return qwenCodeHooksInstalled
            case .factory: return factoryHooksInstalled
            case .codebuddy: return codebuddyHooksInstalled
            case .openCode: return openCodePluginInstalled
            case .gemini: return geminiHooksInstalled
            case .kimi: return kimiHooksInstalled
            case .claudeUsageBridge: return claudeUsageInstalled
            }
        }
    }

    // MARK: - Install / uninstall

    /// Builds a concrete consent record without touching any user target. A
    /// bad helper/resource is reported before a preview can be shown.
    func prepareInstallConsent(_ request: HookConsentRequest) -> HookConsentPreview? {
        do {
            let preview: HookConsentPreview
            switch request {
            case .openCode:
                guard let url = bundledOpenCodePluginURL() else { throw BundledHookArtifactError.untrustedLocation("bundled OpenCode plugin") }
                let resource = try VerifiedBundledHookArtifact.verifiedResource(at: url)
                let status = try openCodePluginInstallationManager.status()
                preview = HookConsentPreview(resource: resource, target: consentTarget(
                    integration: "opencode-plugin", targets: [status.configURL, status.pluginFileURL, status.manifestURL],
                    modes: ["0600 config/plugin/provenance"], additions: ["plugin reference", "Open Island plugin file", "provenance records"], outcome: status.managementOutcome
                ))
            case .claudeUsage:
                let manager = claudeStatusLineInstallationManager
                let status = try manager.status()
                let wrapping = status.hasConflictingStatusLine
                let template = try manager.verifiedTemplateDescriptor(wrapping: wrapping)
                let targets = wrapping ? [status.settingsURL, status.scriptURL, status.scriptDirectoryURL.appendingPathComponent(ClaudeStatusLineInstallationManager.wrappedDelegateScriptName)] : [status.settingsURL, status.scriptURL]
                preview = HookConsentPreview(template: template, target: consentTarget(
                    integration: "claude-status-line", targets: targets, modes: ["0755 scripts", "0600 settings/provenance"],
                    additions: ["managed Claude statusLine", "local rate-limit bridge"], wrapping: wrapping, restoration: wrapping, outcome: status.managementOutcome
                ))
            default:
                guard let hooksBinaryURL else { throw BundledHookArtifactError.untrustedLocation("missing bundled OpenIslandHooks") }
                let artifact = try VerifiedBundledHookArtifact.verify(helperURL: hooksBinaryURL)
                let target = try helperConsentTarget(for: request)
                preview = HookConsentPreview(artifact: artifact, target: target)
            }
            return preview
        } catch {
            let outcome = HookManagementOutcome.from(error: error)
            onStatusMessage?("[\(outcome.rawValue)] \(outcome.remediation)")
            return nil
        }
    }

    func confirmInstallConsent(_ request: HookConsentRequest, preview: HookConsentPreview) {
        let token = consentGate.confirm(preview)
        confirmedRequests[request] = (preview, token, .install)
        switch request {
        case .claude: installClaudeHooks()
        case .codex: installCodexHooks()
        case .openCode: installOpenCodePlugin()
        case .qoder: installQoderHooks()
        case .qwenCode: installQwenCodeHooks()
        case .factory: installFactoryHooks()
        case .codebuddy: installCodebuddyHooks()
        case .cursor: installCursorHooks()
        case .gemini: installGeminiHooks()
        case .kimi: installKimiHooks()
        case .claudeUsage: installClaudeUsageBridge()
        }
    }

    /// Uninstall is destructive too: it can restore a backup, remove a
    /// manifest/sidecar, and revoke a credential.  It receives the same
    /// explicit snapshot review as installation.
    func prepareUninstallConsent(_ request: HookConsentRequest) -> HookConsentPreview? {
        guard let installPreview = prepareInstallConsent(request) else { return nil }
        let target = HookConsentPreview.Target(
            integrationID: installPreview.integrationID,
            targetURLs: installPreview.targetPaths.map(URL.init(fileURLWithPath:)),
            requestedModes: installPreview.requestedModes,
            managedAdditions: [],
            managedRemovals: ["remove only exact verified managed entries", "restore only matching verified backups", "remove verified provenance, journals, and credentials"],
            backupURLs: installPreview.backupPaths.map(URL.init(fileURLWithPath:)),
            journalURLs: installPreview.journalPaths.map(URL.init(fileURLWithPath:)),
            provenanceURLs: installPreview.provenancePaths.map(URL.init(fileURLWithPath:)),
            backupRetentionDays: installPreview.target.backupRetentionDays,
            involvesWrapping: installPreview.involvesWrapping,
            involvesRestoration: true,
            managementOutcome: installPreview.target.managementOutcome
        )
        return HookConsentPreview(reusing: installPreview, target: target)
    }

    func confirmUninstallConsent(_ request: HookConsentRequest, preview: HookConsentPreview) {
        let token = consentGate.confirm(preview)
        confirmedRequests[request] = (preview, token, .uninstall)
        switch request {
        case .claude: uninstallClaudeHooks()
        case .codex: uninstallCodexHooks()
        case .openCode: uninstallOpenCodePlugin()
        case .qoder: uninstallQoderHooks()
        case .qwenCode: uninstallQwenCodeHooks()
        case .factory: uninstallFactoryHooks()
        case .codebuddy: uninstallCodebuddyHooks()
        case .cursor: uninstallCursorHooks()
        case .gemini: uninstallGeminiHooks()
        case .kimi: uninstallKimiHooks()
        case .claudeUsage: uninstallClaudeUsageBridge()
        }
    }

    private func consumeConsent(for request: HookConsentRequest, operation: HookConsentOperation = .install) -> Bool {
        guard let confirmation = confirmedRequests.removeValue(forKey: request),
              confirmation.operation == operation,
              let current = operation == .install ? prepareInstallConsent(request) : prepareUninstallConsent(request),
              consentGate.consume(confirmation.token, preview: confirmation.preview, revalidatedAs: current) else {
            onStatusMessage?("[\(HookManagementOutcome.consentRequired.rawValue)] \(HookManagementOutcome.consentRequired.remediation)")
            return false
        }
        return true
    }

    private func reportManagementFailure(_ error: Error, operation: String) {
        let outcome = HookManagementOutcome.from(error: error)
        onStatusMessage?(outcome.displayMessage(operation: operation))
    }

    private func consentTarget(integration: String, targets: [URL], modes: [String], additions: [String], wrapping: Bool = false, restoration: Bool = false, outcome: HookManagementOutcome = .unowned) -> HookConsentPreview.Target {
        HookConsentPreview.Target(
            integrationID: integration, targetURLs: targets, requestedModes: modes, managedAdditions: additions,
            backupURLs: targets.map(ManagedHookBackupLifecycle.backupURL),
            journalURLs: targets.map(ManagedHookFileSystem.journalURL),
            provenanceURLs: targets.map(ManagedHookProvenance.sidecarURL),
            involvesWrapping: wrapping, involvesRestoration: restoration, managementOutcome: outcome
        )
    }

    private func helperConsentTarget(for request: HookConsentRequest) throws -> HookConsentPreview.Target {
        switch request {
        case .codex:
            let status = try codexHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL)
            return consentTarget(integration: "codex-hooks", targets: [status.configURL, status.hooksURL, status.manifestURL], modes: ["0600 config/hooks/provenance", "0755 shared helper"], additions: ["Codex hooks feature", "exact Stop/Notification hooks", "manager manifest"], outcome: status.managementOutcome)
        case .claude, .qoder, .qwenCode, .factory, .codebuddy:
            let manager: ClaudeHookInstallationManager = switch request {
            case .claude: claudeHookInstallationManager
            case .qoder: qoderHookInstallationManager
            case .qwenCode: qwenCodeHookInstallationManager
            case .factory: factoryHookInstallationManager
            case .codebuddy: codebuddyHookInstallationManager
            default: claudeHookInstallationManager
            }
            let status = try manager.status(hooksBinaryURL: hooksBinaryURL)
            return consentTarget(integration: "claude-hooks:\(manager.hookSource)", targets: [status.settingsURL, status.manifestURL], modes: ["0600 settings/provenance", "0755 shared helper"], additions: ["exact managed hook entries", "manager manifest"], outcome: status.managementOutcome)
        case .cursor:
            let status = try cursorHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL)
            return consentTarget(integration: "cursor-hooks", targets: [status.hooksURL, status.manifestURL], modes: ["0600 hooks/provenance", "0755 shared helper"], additions: ["exact managed hook entries", "manager manifest"], outcome: status.managementOutcome)
        case .gemini:
            let status = try geminiHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL)
            return consentTarget(integration: "gemini-hooks", targets: [status.settingsURL, status.manifestURL], modes: ["0600 settings/provenance", "0755 shared helper"], additions: ["exact managed hook entries", "manager manifest"], outcome: status.managementOutcome)
        case .kimi:
            let status = try kimiHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL)
            return consentTarget(integration: "kimi-hooks", targets: [status.configURL, status.manifestURL], modes: ["0600 config/provenance", "0755 shared helper"], additions: ["exact managed hook entries", "manager manifest"], outcome: status.managementOutcome)
        case .openCode, .claudeUsage:
            throw ManagedHookFileSystemError.ambiguous("invalid helper consent request")
        }
    }

    func installCodexHooks() {
        guard consumeConsent(for: .codex) else { return }
        guard let hooksBinaryURL else {
            onStatusMessage?("Hook installation requires a verified dev bundle. Run zsh scripts/launch-dev-app.sh, then retry.")
            return
        }

        updateCodexHooks(userMessage: "Installing Codex hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallCodexHooks() {
        guard consumeConsent(for: .codex, operation: .uninstall) else { return }
        updateCodexHooks(userMessage: "Removing Codex hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installClaudeHooks() {
        guard consumeConsent(for: .claude) else { return }
        guard let hooksBinaryURL else {
            onStatusMessage?("Hook installation requires a verified dev bundle. Run zsh scripts/launch-dev-app.sh, then retry.")
            return
        }

        updateClaudeHooks(userMessage: "Installing Claude hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallClaudeHooks() {
        guard consumeConsent(for: .claude, operation: .uninstall) else { return }
        updateClaudeHooks(userMessage: "Removing Claude hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installQoderHooks() {
        guard consumeConsent(for: .qoder) else { return }
        updateCCForkHooks(manager: qoderHookInstallationManager, name: "Qoder", agent: .qoder, isBusySetter: { [weak self] in self?.isQoderHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qoderHookStatus = $0 }, install: true)
    }

    func uninstallQoderHooks() {
        guard consumeConsent(for: .qoder, operation: .uninstall) else { return }
        updateCCForkHooks(manager: qoderHookInstallationManager, name: "Qoder", agent: .qoder, isBusySetter: { [weak self] in self?.isQoderHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qoderHookStatus = $0 }, install: false)
    }

    func installQwenCodeHooks() {
        guard consumeConsent(for: .qwenCode) else { return }
        updateCCForkHooks(manager: qwenCodeHookInstallationManager, name: "Qwen Code", agent: .qwenCode, isBusySetter: { [weak self] in self?.isQwenCodeHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qwenCodeHookStatus = $0 }, install: true)
    }

    func uninstallQwenCodeHooks() {
        guard consumeConsent(for: .qwenCode, operation: .uninstall) else { return }
        updateCCForkHooks(manager: qwenCodeHookInstallationManager, name: "Qwen Code", agent: .qwenCode, isBusySetter: { [weak self] in self?.isQwenCodeHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qwenCodeHookStatus = $0 }, install: false)
    }

    func installFactoryHooks() {
        guard consumeConsent(for: .factory) else { return }
        updateCCForkHooks(manager: factoryHookInstallationManager, name: "Factory", agent: .factory, isBusySetter: { [weak self] in self?.isFactoryHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.factoryHookStatus = $0 }, install: true)
    }

    func uninstallFactoryHooks() {
        guard consumeConsent(for: .factory, operation: .uninstall) else { return }
        updateCCForkHooks(manager: factoryHookInstallationManager, name: "Factory", agent: .factory, isBusySetter: { [weak self] in self?.isFactoryHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.factoryHookStatus = $0 }, install: false)
    }

    func installCodebuddyHooks() {
        guard consumeConsent(for: .codebuddy) else { return }
        updateCCForkHooks(manager: codebuddyHookInstallationManager, name: "CodeBuddy", agent: .codebuddy, isBusySetter: { [weak self] in self?.isCodebuddyHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.codebuddyHookStatus = $0 }, install: true)
    }

    func uninstallCodebuddyHooks() {
        guard consumeConsent(for: .codebuddy, operation: .uninstall) else { return }
        updateCCForkHooks(manager: codebuddyHookInstallationManager, name: "CodeBuddy", agent: .codebuddy, isBusySetter: { [weak self] in self?.isCodebuddyHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.codebuddyHookStatus = $0 }, install: false)
    }

    private func updateCCForkHooks(
        manager: ClaudeHookInstallationManager,
        name: String,
        agent: AgentIdentifier,
        isBusySetter: @MainActor @escaping (Bool) -> Void,
        statusSetter: @MainActor @escaping (ClaudeHookInstallationStatus) -> Void,
        install: Bool
    ) {
        guard !install || hooksBinaryURL != nil else {
            onStatusMessage?("Hook installation requires a verified dev bundle. Run zsh scripts/launch-dev-app.sh, then retry.")
            return
        }

        isBusySetter(true)
        onStatusMessage?(install ? "Installing \(name) hooks." : "Removing \(name) hooks.")

        Task { [weak self] in
            guard let self else { return }

            defer { isBusySetter(false) }

            do {
                let status = install
                    ? try manager.install(hooksBinaryURL: hooksBinaryURL!)
                    : try manager.uninstall()
                statusSetter(status)
                self.intentStore.setIntent(install ? .installed : .uninstalled, for: agent)
                if status.managedHooksPresent {
                    self.onStatusMessage?("\(name) hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("\(name) hooks are not installed.")
                }
            } catch {
                self.reportManagementFailure(error, operation: "\(name) hook update")
            }
        }
    }

    func installOpenCodePlugin() {
        guard consumeConsent(for: .openCode) else { return }
        guard let pluginURL = bundledOpenCodePluginURL() else {
            onStatusMessage?("Could not find the bundled OpenCode plugin resource.")
            return
        }

        isOpenCodeSetupBusy = true
        onStatusMessage?("Installing OpenCode plugin.")

        Task { [weak self] in
            guard let self else { return }

            defer { self.isOpenCodeSetupBusy = false }

            do {
                let status = try self.openCodePluginInstallationManager.install(pluginSourceURL: pluginURL)
                self.openCodePluginStatus = status
                self.intentStore.setIntent(.installed, for: .openCode)
                if status.isInstalled {
                    self.onStatusMessage?("OpenCode plugin is installed. Restart OpenCode to activate.")
                } else {
                    self.onStatusMessage?("OpenCode plugin installation incomplete.")
                }
            } catch {
                self.reportManagementFailure(error, operation: "OpenCode plugin install")
            }
        }
    }

    func uninstallOpenCodePlugin() {
        guard consumeConsent(for: .openCode, operation: .uninstall) else { return }
        isOpenCodeSetupBusy = true
        onStatusMessage?("Removing OpenCode plugin.")

        Task { [weak self] in
            guard let self else { return }

            defer { self.isOpenCodeSetupBusy = false }

            do {
                let status = try self.openCodePluginInstallationManager.uninstall()
                self.openCodePluginStatus = status
                self.intentStore.setIntent(.uninstalled, for: .openCode)
                self.onStatusMessage?("OpenCode plugin removed.")
            } catch {
                self.reportManagementFailure(error, operation: "OpenCode plugin removal")
            }
        }
    }

    func installCursorHooks() {
        guard consumeConsent(for: .cursor) else { return }
        guard let hooksBinaryURL else {
            onStatusMessage?("Hook installation requires a verified dev bundle. Run zsh scripts/launch-dev-app.sh, then retry.")
            return
        }

        updateCursorHooks(userMessage: "Installing Cursor hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallCursorHooks() {
        guard consumeConsent(for: .cursor, operation: .uninstall) else { return }
        updateCursorHooks(userMessage: "Removing Cursor hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installGeminiHooks() {
        guard consumeConsent(for: .gemini) else { return }
        guard let hooksBinaryURL else {
            onStatusMessage?("Hook installation requires a verified dev bundle. Run zsh scripts/launch-dev-app.sh, then retry.")
            return
        }

        updateGeminiHooks(userMessage: "Installing Gemini hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallGeminiHooks() {
        guard consumeConsent(for: .gemini, operation: .uninstall) else { return }
        updateGeminiHooks(userMessage: "Removing Gemini hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installKimiHooks() {
        guard consumeConsent(for: .kimi) else { return }
        guard let hooksBinaryURL else {
            onStatusMessage?("Hook installation requires a verified dev bundle. Run zsh scripts/launch-dev-app.sh, then retry.")
            return
        }

        updateKimiHooks(userMessage: "Installing Kimi hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallKimiHooks() {
        guard consumeConsent(for: .kimi, operation: .uninstall) else { return }
        updateKimiHooks(userMessage: "Removing Kimi hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installClaudeUsageBridge() {
        guard consumeConsent(for: .claudeUsage) else { return }
        updateClaudeUsageBridge(userMessage: "Installing Claude usage bridge.", intent: .installed) { manager in
            do {
                return try manager.install()
            } catch ClaudeStatusLineInstallationError.existingStatusLineConflict {
                // User already has a custom statusLine (e.g. claude-hud). Install as a
                // wrapper so their script keeps running and we still get rate_limits.
                return try manager.installAsWrapper()
            }
        }
    }

    func uninstallClaudeUsageBridge() {
        guard consumeConsent(for: .claudeUsage, operation: .uninstall) else { return }
        updateClaudeUsageBridge(userMessage: "Removing Claude usage bridge.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    /// Builds the complete, read-only reset inventory.  We retain unowned
    /// members in the preview so the user can see that they are skipped, and
    /// retain unsafe members so they block the entire operation instead of
    /// being silently skipped.
    func prepareResetIntegrationsConsent() -> HookAggregateConsentPreview {
        let helperURL = ManagedHooksBinary.defaultURL()
        let members = [
            resetMember("codex-hooks", urls: { let s = try codexHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL); return [s.configURL, s.hooksURL, s.manifestURL] }, outcome: { try codexHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL).managementOutcome }),
            resetMember("claude-hooks:claude", urls: { let s = try claudeHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL); return [s.settingsURL, s.manifestURL] }, outcome: { try claudeHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL).managementOutcome }),
            resetMember("claude-hooks:qoder", urls: { let s = try qoderHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL); return [s.settingsURL, s.manifestURL] }, outcome: { try qoderHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL).managementOutcome }),
            resetMember("claude-hooks:qwen", urls: { let s = try qwenCodeHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL); return [s.settingsURL, s.manifestURL] }, outcome: { try qwenCodeHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL).managementOutcome }),
            resetMember("claude-hooks:factory", urls: { let s = try factoryHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL); return [s.settingsURL, s.manifestURL] }, outcome: { try factoryHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL).managementOutcome }),
            resetMember("claude-hooks:codebuddy", urls: { let s = try codebuddyHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL); return [s.settingsURL, s.manifestURL] }, outcome: { try codebuddyHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL).managementOutcome }),
            resetMember("opencode-plugin", urls: { let s = try openCodePluginInstallationManager.status(); return [s.configURL, s.pluginFileURL, s.manifestURL] }, outcome: { try openCodePluginInstallationManager.status().managementOutcome }),
            resetMember("cursor-hooks", urls: { let s = try cursorHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL); return [s.hooksURL, s.manifestURL] }, outcome: { try cursorHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL).managementOutcome }),
            resetMember("gemini-hooks", urls: { let s = try geminiHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL); return [s.settingsURL, s.manifestURL] }, outcome: { try geminiHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL).managementOutcome }),
            resetMember("kimi-hooks", urls: { let s = try kimiHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL); return [s.configURL, s.manifestURL] }, outcome: { try kimiHookInstallationManager.status(hooksBinaryURL: hooksBinaryURL).managementOutcome }),
            resetMember("claude-status-line", urls: { let s = try claudeStatusLineInstallationManager.status(); return [s.settingsURL, s.scriptURL, s.scriptDirectoryURL.appendingPathComponent(ClaudeStatusLineInstallationManager.wrappedDelegateScriptName)] }, outcome: { try claudeStatusLineInstallationManager.status().managementOutcome }),
            HookConsentPreview(removalTarget: HookConsentPreview.Target(
                integrationID: "shared-helper", targetURLs: [helperURL], requestedModes: ["0755 shared helper"],
                managedAdditions: [], managedRemovals: ["remove the exact verified shared helper last"],
                journalURLs: [ManagedHookFileSystem.journalURL(for: helperURL)],
                provenanceURLs: [ManagedHookProvenance.sidecarURL(for: helperURL)],
                managementOutcome: ManagedHooksBinary.managementOutcome(at: helperURL)
            ))
        ]
        return HookAggregateConsentPreview(
            members: members,
            intentKeys: AgentIntentStore.managedIntegrationResetKeys,
            credentialRoles: BridgeClientRole.allCases.filter { $0 != .observer }.map(\.rawValue),
            executionOrder: members.dropLast().map(\.integrationID) + ["clear managed integration intent", "revoke all integration credentials", "shared-helper"]
        )
    }

    func confirmResetIntegrationsConsent(_ preview: HookAggregateConsentPreview) {
        guard preview.isSafeToExecute else {
            onStatusMessage?("[\(HookManagementOutcome.ambiguousUnmanaged.rawValue)] Reset Integrations is blocked by: \(preview.blockingMembers.map(\.integrationID).joined(separator: ", ")). \(HookManagementOutcome.ambiguousUnmanaged.remediation)")
            return
        }
        confirmedReset = (preview, consentGate.confirm(preview))
        executeConfirmedResetIntegrations()
    }

    /// Explicitly removes managed integration state and every bridge
    /// credential. It is intentionally separate from Clear History.
    func resetManagedIntegrations() {
        onStatusMessage?("[\(HookManagementOutcome.consentRequired.rawValue)] Reset Integrations requires a reviewed aggregate removal preview and explicit confirmation.")
    }

    private func resetMember(
        _ integrationID: String,
        urls: () throws -> [URL],
        outcome: () throws -> HookManagementOutcome
    ) -> HookConsentPreview {
        var targetURLs: [URL]
        var currentOutcome: HookManagementOutcome
        do {
            targetURLs = try urls()
            currentOutcome = try outcome()
        } catch {
            // We still show every known member and bind its currently visible
            // artifacts.  A failed inspection is unsafe, not permission to
            // quietly omit that integration from reset.
            targetURLs = []
            currentOutcome = HookManagementOutcome.from(error: error)
        }
        return HookConsentPreview(removalTarget: HookConsentPreview.Target(
            integrationID: integrationID,
            targetURLs: targetURLs,
            requestedModes: ["preserve existing target modes"],
            managedAdditions: [],
            managedRemovals: ["remove only exact verified managed entries", "restore only matching verified backups", "remove verified provenance and journals when the manager confirms removal"],
            backupURLs: targetURLs.map(ManagedHookBackupLifecycle.backupURL),
            journalURLs: targetURLs.map(ManagedHookFileSystem.journalURL),
            provenanceURLs: targetURLs.map(ManagedHookProvenance.sidecarURL),
            involvesRestoration: true,
            managementOutcome: currentOutcome
        ))
    }

    private func executeConfirmedResetIntegrations() {
        guard let confirmation = confirmedReset else {
            onStatusMessage?("[\(HookManagementOutcome.consentRequired.rawValue)] Reset Integrations requires explicit confirmation.")
            return
        }
        confirmedReset = nil
        let current = prepareResetIntegrationsConsent()
        guard consentGate.consume(confirmation.token, aggregate: confirmation.preview, revalidatedAs: current) else {
            onStatusMessage?("[\(HookManagementOutcome.consentRequired.rawValue)] Reset Integrations was not started because a reviewed target, artifact, provenance record, or outcome changed. Review a new preview.")
            return
        }

        var stage = "manager preflight"
        do {
            // Managers are constructed with a no-op credential callback here
            // so credentials are revoked exactly once, after every manager
            // has completed. Their mutation and recovery behavior is unchanged.
            stage = "Codex"
            _ = try CodexHookInstallationManager(credentialRevoker: {}).uninstall()
            stage = "Claude"
            _ = try ClaudeHookInstallationManager(credentialRevoker: {}).uninstall()
            stage = "Qoder"
            _ = try ClaudeHookInstallationManager(claudeDirectory: qoderHookInstallationManager.claudeDirectory, hookSource: "qoder", credentialRevoker: {}).uninstall()
            stage = "Qwen Code"
            _ = try ClaudeHookInstallationManager(claudeDirectory: qwenCodeHookInstallationManager.claudeDirectory, hookSource: "qwen", credentialRevoker: {}).uninstall()
            stage = "Factory"
            _ = try ClaudeHookInstallationManager(claudeDirectory: factoryHookInstallationManager.claudeDirectory, hookSource: "factory", credentialRevoker: {}).uninstall()
            stage = "CodeBuddy"
            _ = try ClaudeHookInstallationManager(claudeDirectory: codebuddyHookInstallationManager.claudeDirectory, hookSource: "codebuddy", credentialRevoker: {}).uninstall()
            stage = "OpenCode"
            _ = try OpenCodePluginInstallationManager(credentialRevoker: {}).uninstall()
            stage = "Cursor"
            _ = try CursorHookInstallationManager(credentialRevoker: {}).uninstall()
            stage = "Gemini"
            _ = try GeminiHookInstallationManager(credentialRevoker: {}).uninstall()
            stage = "Kimi"
            _ = try KimiHookInstallationManager(credentialRevoker: {}).uninstall()
            stage = "Claude status-line"
            _ = try ClaudeStatusLineInstallationManager().uninstall()
            stage = "managed integration intent"
            intentStore.resetManagedIntegrationState()
            stage = "integration credentials"
            try BridgeCredentialLifecycle.revokeAllIntegrationCredentials()
            stage = "shared helper"
            _ = try ManagedHooksBinary.removeVerified()
            refreshCodexHookStatus()
            refreshClaudeHookStatus()
            refreshCCForkHookStatuses()
            refreshOpenCodePluginStatus()
            refreshCursorHookStatus()
            refreshGeminiHookStatus()
            refreshKimiHookStatus()
            refreshClaudeUsageState()
            onStatusMessage?("Reset Integrations completed: exact managed state removed, setup intent cleared, integration credentials revoked, and the shared helper removed last. Clear History was not run.")
        } catch {
            let outcome = HookManagementOutcome.from(error: error)
            onStatusMessage?("\(outcome.displayMessage(operation: "Reset Integrations interrupted during \(stage)")) Existing manager journals and verified backups were retained for recovery.")
        }
    }

    // MARK: - Monitoring

    func startClaudeUsageMonitoringIfNeeded() {
        guard claudeUsageMonitorTask == nil else { return }

        claudeUsageMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.refreshClaudeUsageState()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func startCodexUsageMonitoringIfNeeded() {
        guard codexUsageMonitorTask == nil else { return }

        codexUsageMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.refreshCodexUsageState()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    // MARK: - Internal: readClaudeUsageState

    nonisolated func readClaudeUsageState(
        repairManagedBridgeIfNeeded: Bool
    ) throws -> (
        status: ClaudeStatusLineInstallationStatus,
        snapshot: ClaudeUsageSnapshot?,
        repairedManagedBridge: Bool
    ) {
        _ = repairManagedBridgeIfNeeded
        let manager = ClaudeStatusLineInstallationManager()
        let status = try manager.status()
        // Kept for source compatibility with callers; repair now requires an
        // explicit install action backed by exact provenance.
        let repairedManagedBridge = false

        let snapshot = try ClaudeUsageLoader.load()
        return (status, snapshot, repairedManagedBridge)
    }

    // MARK: - Private helpers

    private func updateCodexHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (CodexHookInstallationManager) throws -> CodexHookInstallationStatus
    ) {
        isCodexSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isCodexSetupBusy = false }

            do {
                let status = try operation(self.codexHookInstallationManager)
                self.codexHookStatus = status
                self.intentStore.setIntent(intent, for: .codex)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Codex hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Codex hooks are not installed.")
                }
            } catch {
                self.reportManagementFailure(error, operation: "Codex hook update")
            }
        }
    }

    private func updateClaudeHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (ClaudeHookInstallationManager) throws -> ClaudeHookInstallationStatus
    ) {
        isClaudeHookSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isClaudeHookSetupBusy = false }

            do {
                let status = try operation(self.claudeHookInstallationManager)
                self.claudeHookStatus = status
                self.intentStore.setIntent(intent, for: .claudeCode)
                if status.managedHooksPresent {
                    self.onStatusMessage?(status.hasClaudeIslandHooks
                        ? "Claude hooks are installed. claude-island hooks are also still present."
                        : "Claude hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Claude hooks are not installed.")
                }
            } catch {
                self.reportManagementFailure(error, operation: "Claude hook update")
            }
        }
    }

    private func updateCursorHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (CursorHookInstallationManager) throws -> CursorHookInstallationStatus
    ) {
        isCursorHookSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isCursorHookSetupBusy = false }

            do {
                let status = try operation(self.cursorHookInstallationManager)
                self.cursorHookStatus = status
                self.intentStore.setIntent(intent, for: .cursor)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Cursor hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Cursor hooks are not installed.")
                }
            } catch {
                self.reportManagementFailure(error, operation: "Cursor hook update")
            }
        }
    }

    private func updateGeminiHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (GeminiHookInstallationManager) throws -> GeminiHookInstallationStatus
    ) {
        isGeminiHookSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isGeminiHookSetupBusy = false }

            do {
                let status = try operation(self.geminiHookInstallationManager)
                self.geminiHookStatus = status
                self.intentStore.setIntent(intent, for: .gemini)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Gemini hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Gemini hooks are not installed.")
                }
            } catch {
                self.reportManagementFailure(error, operation: "Gemini hook update")
            }
        }
    }

    private func updateKimiHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (KimiHookInstallationManager) throws -> KimiHookInstallationStatus
    ) {
        isKimiHookSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isKimiHookSetupBusy = false }

            do {
                let status = try operation(self.kimiHookInstallationManager)
                self.kimiHookStatus = status
                self.intentStore.setIntent(intent, for: .kimi)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Kimi hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Kimi hooks are not installed.")
                }
            } catch {
                self.reportManagementFailure(error, operation: "Kimi hook update")
            }
        }
    }

    private func updateClaudeUsageBridge(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (ClaudeStatusLineInstallationManager) throws -> ClaudeStatusLineInstallationStatus
    ) {
        isClaudeUsageSetupBusy = true
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isClaudeUsageSetupBusy = false }

            do {
                let status = try operation(self.claudeStatusLineInstallationManager)
                self.claudeStatusLineStatus = status
                self.claudeUsageSnapshot = try ClaudeUsageLoader.load()
                self.intentStore.setIntent(intent, for: .claudeUsageBridge)
                if status.managedStatusLineInstalled {
                    if status.managedStatusLineIsWrapper {
                        self.onStatusMessage?("Claude usage bridge installed in wrapper mode — your existing statusLine is preserved. Start a Claude Code turn to refresh cached rate limits.")
                    } else {
                        self.onStatusMessage?("Claude usage bridge is installed. Start a Claude Code turn to refresh cached rate limits.")
                    }
                } else {
                    self.onStatusMessage?("Claude usage bridge is not installed.")
                }
            } catch {
                self.reportManagementFailure(error, operation: "Claude usage bridge update")
            }
        }
    }

    private func bundledOpenCodePluginURL() -> URL? {
        // Use appResources which searches both Contents/Resources/ and .app root
        if let url = Bundle.appResources.url(forResource: "open-island-opencode", withExtension: "js") {
            return url
        }

        // Fallback: Bundle.main for Xcode builds
        if let url = Bundle.main.url(forResource: "open-island-opencode", withExtension: "js") {
            return url
        }

        return nil
    }
}
