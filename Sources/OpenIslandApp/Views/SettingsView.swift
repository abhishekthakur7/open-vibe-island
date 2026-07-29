import SwiftUI
import AppKit
import OpenIslandCore

// MARK: - Settings tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case setup
    case display
    case sound
    case appearance
    case shortcuts
    case lab
    case about

    var id: String { rawValue }

    func label(_ lang: LanguageManager) -> String {
        switch self {
        case .general:    lang.t("settings.tab.general")
        case .setup:      lang.t("settings.tab.setup")
        case .appearance: lang.t("settings.tab.appearance")
        case .display:    lang.t("settings.tab.display")
        case .sound:      lang.t("settings.tab.sound")
        case .shortcuts:  lang.t("settings.tab.shortcuts")
        case .lab:        lang.t("settings.tab.lab")
        case .about:      lang.t("settings.tab.about")
        }
    }

    var icon: String {
        switch self {
        case .general:    "gearshape.fill"
        case .setup:      "arrow.down.circle.fill"
        case .appearance: "paintbrush.fill"
        case .display:    "textformat.size"
        case .sound:      "speaker.wave.2.fill"
        case .shortcuts:  "keyboard.fill"
        case .lab:        "flask.fill"
        case .about:      "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:    .gray
        case .setup:      .orange
        case .appearance: .purple
        case .display:    .blue
        case .sound:      .green
        case .shortcuts:  .gray
        case .lab:        .pink
        case .about:      .blue
        }
    }

    var section: SettingsSection {
        switch self {
        case .general, .setup, .display, .sound, .appearance: .system
        case .shortcuts, .lab:                                .advanced
        case .about:                                          .app
        }
    }
}

enum SettingsSection: String, CaseIterable {
    case system
    case advanced
    case app

    func header(_ lang: LanguageManager) -> String {
        switch self {
        case .system:   lang.t("settings.section.system")
        case .advanced: lang.t("settings.section.advanced")
        case .app:      "Open Island"
        }
    }

    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.section == self }
    }
}

// MARK: - Root settings view

struct SettingsView: View {
    var model: AppModel
    @State private var selectedTab: SettingsTab = .general

    private var lang: LanguageManager { model.lang }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailView
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 480, idealHeight: 560)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .openIslandSelectSetupTab)) { _ in
            selectedTab = .setup
        }
    }

    // MARK: Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                Section(section.header(lang)) {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.label(lang))
                        } icon: {
                            Image(systemName: tab.icon)
                                .foregroundStyle(tab.iconColor)
                        }
                        .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsPane(model: model)
        case .setup:
            SetupSettingsPane(model: model)
        case .appearance:
            AppearanceSettingsPane(model: model)
        case .display:
            DisplaySettingsPane(model: model)
        case .sound:
            SoundSettingsPane(model: model)
        case .shortcuts:
            ShortcutsSettingsPane(model: model)
        case .lab:
            // AB-306: the real theme picker now lives in Settings →
            // Appearance, so the temporary theme switch that AB-299 parked
            // here is retired. The Lab tab stays as an experimental-features
            // placeholder for whatever lands next.
            PlaceholderSettingsPane(
                model: model,
                titleKey: "settings.tab.lab",
                subtitleKey: "settings.lab.comingSoon"
            )
        case .about:
            AboutSettingsPane(model: model)
        }
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    var model: AppModel

    @State private var pendingIntegrationReset: HookAggregateConsentPreview?

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section(lang.t("settings.section.system")) {
                Toggle(lang.t("settings.general.launchAtLogin"), isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.launchAtLoginEnabled = $0 }
                ))

                Picker(lang.t("settings.general.monitor"), selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

            Section(lang.t("settings.general.language")) {
                Picker(lang.t("settings.general.language"), selection: Binding(
                    get: { lang.language },
                    set: { lang.language = $0 }
                )) {
                    Text(lang.t("settings.general.languageSystem")).tag(LanguageManager.AppLanguage.system)
                    Text(lang.t("settings.general.languageEnglish")).tag(LanguageManager.AppLanguage.en)
                    Text(lang.t("settings.general.languageChinese")).tag(LanguageManager.AppLanguage.zhHans)
                    Text(lang.t("settings.general.languageTraditionalChinese")).tag(LanguageManager.AppLanguage.zhHant)
                }
            }

            Section(lang.t("settings.general.behavior")) {
                Toggle(lang.t("settings.general.autoCollapse"), isOn: Binding(
                    get: { model.autoCollapseEnabled },
                    set: { model.autoCollapseEnabled = $0 }
                ))
                Toggle(lang.t("settings.general.showDockIcon"), isOn: Binding(
                    get: { model.showDockIcon },
                    set: { model.showDockIcon = $0 }
                ))
                Toggle(lang.t("settings.general.hapticFeedback"), isOn: Binding(
                    get: { model.hapticFeedbackEnabled },
                    set: { model.hapticFeedbackEnabled = $0 }
                ))
                Toggle(lang.t("settings.general.completionReply"), isOn: Binding(
                    get: { model.completionReplyEnabled },
                    set: { model.completionReplyEnabled = $0 }
                ))
                Toggle(lang.t("settings.general.suppressFrontmostNotifications"), isOn: Binding(
                    get: { model.suppressFrontmostNotifications },
                    set: { model.suppressFrontmostNotifications = $0 }
                ))
            }

            Section {
                Toggle(lang.t("settings.general.menuBarAttention"), isOn: Binding(
                    get: { model.menuBarAttentionEnabled },
                    set: { model.menuBarAttentionEnabled = $0 }
                ))
                Toggle(lang.t("settings.general.systemNotifications"), isOn: Binding(
                    get: { model.systemNotificationsEnabled },
                    set: { model.systemNotificationsEnabled = $0 }
                ))
                Toggle(lang.t("settings.general.dockBadge"), isOn: Binding(
                    get: { model.dockBadgeEnabled },
                    set: { model.dockBadgeEnabled = $0 }
                ))
                .disabled(!model.showDockIcon)
                if !model.showDockIcon {
                    Text(lang.t("settings.general.dockBadgeRequiresIcon"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(lang.t("settings.general.attention"))
            } footer: {
                Text(lang.t("settings.general.attentionFooter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Button("Clear History", role: .destructive) {
                    model.clearHistory()
                }
                Text("Deletes Open Island session metadata and eligible local logs. It preserves preferences, hook backups, source transcripts, and enabled integration credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reset Integrations", role: .destructive) {
                    pendingIntegrationReset = model.prepareResetIntegrations()
                }
                Text("Shows every managed target, backup, provenance record, intent key, and bridge credential role before reset. Unsafe or unresolved members block the whole reset. It does not delete history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.general"))
        .alert(item: $pendingIntegrationReset) { preview in
            Alert(
                title: Text(preview.isSafeToExecute ? "Review integration reset" : "Integration reset is blocked"),
                message: Text(resetConsentMessage(preview)),
                primaryButton: preview.isSafeToExecute
                    ? .destructive(Text("Confirm reset"), action: { model.confirmResetIntegrations(preview) })
                    : .default(Text("OK")),
                secondaryButton: .cancel()
            )
        }
    }

    private func resetConsentMessage(_ preview: HookAggregateConsentPreview) -> String {
        let members = preview.members.map { member in
            let snapshots = member.targetSnapshots.map { snapshot in
                "\(snapshot.canonicalPath): \(snapshot.exists ? snapshot.fileType : "absent"), SHA \(snapshot.sha256 ?? "absent"), provenance \(snapshot.provenanceGeneration ?? "absent"), artifact \(snapshot.provenanceArtifactID ?? "absent")@\(snapshot.provenanceArtifactVersion.map(String.init) ?? "—")"
            }.joined(separator: "\n")
            return "\(member.integrationID) [\(member.target.managementOutcome.rawValue)]\nTargets: \(member.targetPaths.joined(separator: ", "))\nSnapshots:\n\(snapshots)\nChanges: \(member.managedRemovals.joined(separator: "; "))\nBackups: \(member.backupPaths.joined(separator: ", "))"
        }.joined(separator: "\n\n")
        let blocked = preview.blockingMembers.map { "\($0.integrationID): \($0.target.managementOutcome.rawValue)" }.joined(separator: ", ")
        return "Order: \(preview.executionOrder.joined(separator: " → "))\n\n\(members)\n\nIntent keys cleared: \(preview.intentKeys.joined(separator: ", "))\nCredentials revoked: \(preview.credentialRoles.joined(separator: ", "))\n\n\(blocked.isEmpty ? "All members are exact-managed or unowned. History is preserved." : "Blocked members: \(blocked). No mutation will run.")"
    }
}

// MARK: - Display

struct DisplaySettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section(lang.t("settings.display.monitor")) {
                Picker(lang.t("settings.display.position"), selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

            if let diag = model.overlayPlacementDiagnostics {
                Section(lang.t("settings.display.diagnostics")) {
                    LabeledContent(lang.t("settings.display.currentScreen"), value: diag.targetScreenName)
                    LabeledContent(lang.t("settings.display.layoutMode"), value: diag.modeDescription)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.display"))
    }
}

// MARK: - Sound

struct SoundSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    private var availableSounds: [String] {
        NotificationSoundService.availableSounds()
    }

    var body: some View {
        Form {
            Section(lang.t("settings.sound.notifications")) {
                Toggle(lang.t("settings.sound.mute"), isOn: Binding(
                    get: { model.isSoundMuted },
                    set: { _ in model.toggleSoundMuted() }
                ))
            }

            // AB-239: permission/question/completion each get their own
            // sound, instead of one sound for every event.
            Section {
                soundRow(
                    title: lang.t("settings.sound.permission"),
                    selection: Binding(
                        get: { model.permissionSoundName },
                        set: { model.permissionSoundName = $0 }
                    )
                )
                soundRow(
                    title: lang.t("settings.sound.question"),
                    selection: Binding(
                        get: { model.questionSoundName },
                        set: { model.questionSoundName = $0 }
                    )
                )
                soundRow(
                    title: lang.t("settings.sound.completion"),
                    selection: Binding(
                        get: { model.completionSoundName },
                        set: { model.completionSoundName = $0 }
                    )
                )
            } header: {
                Text(lang.t("settings.sound.selectSound"))
            } footer: {
                Text(lang.t("settings.sound.perEventFooter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.sound"))
    }

    @ViewBuilder
    private func soundRow(title: String, selection: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(availableSounds, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            Button {
                NotificationSoundService.play(selection.wrappedValue)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lang.t("settings.sound.preview"))
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    private struct ShortcutRow: Identifiable {
        let id: String
        let keys: String
        let labelKey: String
    }

    /// Fixed for v1 — see AB-227. These map 1:1 to the handling in
    /// `OverlayPanelController.handleOverlayKeyDown` and
    /// `StructuredQuestionPromptView`'s keyboard registration.
    private var overlayShortcuts: [ShortcutRow] {
        [
            ShortcutRow(id: "allowOnce", keys: "⌘Y", labelKey: "settings.shortcuts.overlay.allowOnce"),
            ShortcutRow(id: "deny", keys: "⌘N", labelKey: "settings.shortcuts.overlay.deny"),
            ShortcutRow(id: "alwaysAllow", keys: "⌘⇧Y", labelKey: "settings.shortcuts.overlay.alwaysAllow"),
            ShortcutRow(id: "selectOption", keys: "1–9 / ⌘1–9", labelKey: "settings.shortcuts.overlay.selectOption"),
            ShortcutRow(id: "submit", keys: "⏎", labelKey: "settings.shortcuts.overlay.submit"),
            ShortcutRow(id: "close", keys: "⎋", labelKey: "settings.shortcuts.overlay.close"),
        ]
    }

    var body: some View {
        Form {
            Section(lang.t("settings.shortcuts.global.section")) {
                Picker(lang.t("settings.shortcuts.global.picker"), selection: Binding(
                    get: { model.globalHotKeyOption },
                    set: { model.globalHotKeyOption = $0 }
                )) {
                    ForEach(GlobalHotKeyOption.allCases) { option in
                        Text(option.displayName(lang)).tag(option)
                    }
                }

                Text(lang.t("settings.shortcuts.global.footnote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(lang.t("settings.shortcuts.overlay.section")) {
                ForEach(overlayShortcuts) { row in
                    LabeledContent(lang.t(row.labelKey)) {
                        Text(row.keys)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(lang.t("settings.shortcuts.overlay.footnote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.shortcuts"))
    }
}

// MARK: - About

struct AboutSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)

                Text(lang.t("app.name"))
                    .font(.title.bold())

                Text(lang.t("app.description"))
                    .foregroundStyle(.secondary)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text(lang.t("settings.about.version", version))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            Form {
                Section {
                    aboutActionRow(
                        title: lang.t("settings.about.quitApp"),
                        systemImage: "rectangle.portrait.and.arrow.right",
                        tint: Color(red: 1.0, green: 0.29, blue: 0.29),
                        action: {
                            model.quitApplication()
                        }
                    )
                    .accessibilityIdentifier("settings.about.quitApp")
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(lang.t("settings.tab.about"))
    }

    private func aboutActionRow(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, alignment: .leading)

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))

                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Setup

private struct HookInstallConfirmation: Identifiable {
    let preview: HookConsentPreview
    let request: HookConsentRequest
    let isUninstall: Bool
    var id: String { preview.id }
}

struct SetupSettingsPane: View {
    var model: AppModel

    @State private var pendingHookInstall: HookInstallConfirmation?

    @State private var confirmingUninstallClaude = false
    @State private var confirmingUninstallCodex = false
    @State private var confirmingUninstallOpenCode = false
    @State private var confirmingUninstallQoder = false
    @State private var confirmingUninstallQwenCode = false
    @State private var confirmingUninstallFactory = false
    @State private var confirmingUninstallCodebuddy = false
    @State private var confirmingUninstallCursor = false
    @State private var confirmingUninstallGemini = false
    @State private var confirmingUninstallKimi = false
    @State private var confirmingUninstallClaudeUsage = false

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            if !model.hasAnyInstalledAgent {
                emptyStateBanner
            }

            claudeConfigDirectorySection

            Section(lang.t("setup.section.hooks")) {
                hookRow(
                    name: "Claude Code",
                    installed: model.claudeHooksInstalled,
                    busy: model.isClaudeHookSetupBusy,
                    configLocationURL: model.claudeHookStatus?.settingsURL,
                    installAction: { requestHookInstall(.claude) },
                    uninstallAction: { requestHookUninstall(.claude) }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallClaude) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallClaudeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.claude"))
                }

                hookRow(
                    name: "Codex",
                    installed: model.codexHooksInstalled,
                    busy: model.isCodexSetupBusy,
                    configLocationURL: codexHookConfigURL,
                    installAction: { requestHookInstall(.codex) },
                    uninstallAction: { requestHookUninstall(.codex) }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCodex) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCodexHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.codex"))
                }

                hookRow(
                    name: "OpenCode",
                    installed: model.openCodePluginInstalled,
                    busy: model.isOpenCodeSetupBusy,
                    requiresBinary: false,
                    configLocationURL: model.openCodePluginStatus?.configURL,
                    installAction: { requestHookInstall(.openCode) },
                    uninstallAction: { requestHookUninstall(.openCode) }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallOpenCode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallOpenCodePlugin()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove the Open Island plugin from ~/.config/opencode/plugins/.")
                }

                hookRow(
                    name: "Qoder",
                    installed: model.qoderHooksInstalled,
                    busy: model.isQoderHookSetupBusy,
                    configLocationURL: model.qoderHookStatus?.settingsURL,
                    installAction: { requestHookInstall(.qoder) },
                    uninstallAction: { requestHookUninstall(.qoder) }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallQoder) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallQoderHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.qoder/settings.json.")
                }

                hookRow(
                    name: "Qwen Code",
                    installed: model.qwenCodeHooksInstalled,
                    busy: model.isQwenCodeHookSetupBusy,
                    configLocationURL: model.qwenCodeHookStatus?.settingsURL,
                    installAction: { requestHookInstall(.qwenCode) },
                    uninstallAction: { requestHookUninstall(.qwenCode) }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallQwenCode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallQwenCodeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.qwen/settings.json.")
                }

                hookRow(
                    name: "Factory",
                    installed: model.factoryHooksInstalled,
                    busy: model.isFactoryHookSetupBusy,
                    configLocationURL: model.factoryHookStatus?.settingsURL,
                    installAction: { requestHookInstall(.factory) },
                    uninstallAction: { requestHookUninstall(.factory) }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallFactory) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallFactoryHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.factory/settings.json.")
                }

                hookRow(
                    name: "CodeBuddy",
                    installed: model.codebuddyHooksInstalled,
                    busy: model.isCodebuddyHookSetupBusy,
                    configLocationURL: model.codebuddyHookStatus?.settingsURL,
                    installAction: { requestHookInstall(.codebuddy) },
                    uninstallAction: { requestHookUninstall(.codebuddy) }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCodebuddy) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCodebuddyHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.codebuddy/settings.json.")
                }

                hookRow(
                    name: "Cursor",
                    installed: model.cursorHooksInstalled,
                    busy: model.isCursorHookSetupBusy,
                    requiresBinary: true,
                    configLocationURL: model.cursorHookStatus?.hooksURL,
                    installAction: { requestHookInstall(.cursor) },
                    uninstallAction: { requestHookUninstall(.cursor) }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCursor) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCursorHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove the Open Island hooks from ~/.cursor/hooks.json.")
                }

                hookRow(
                    name: "Gemini CLI",
                    installed: model.geminiHooksInstalled,
                    busy: model.isGeminiHookSetupBusy,
                    configLocationURL: geminiHookConfigURL,
                    installAction: { requestHookInstall(.gemini) },
                    uninstallAction: { requestHookUninstall(.gemini) }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallGemini) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallGeminiHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.gemini/settings.json.")
                }

                hookRow(
                    name: "Kimi CLI",
                    installed: model.kimiHooksInstalled,
                    busy: model.isKimiHookSetupBusy,
                    configLocationURL: model.kimiHookStatus?.configURL,
                    installAction: { requestHookInstall(.kimi) },
                    uninstallAction: { requestHookUninstall(.kimi) }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallKimi) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallKimiHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.kimi/config.toml.")
                }
            }

            Section {
                HStack {
                    Label(lang.t("setup.usageBridge"), systemImage: "chart.bar")
                    Spacer()
                    if model.claudeUsageInstalled {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(lang.t("setup.usageBridgeReady"))
                                .foregroundStyle(.secondary)
                        }
                        Button(lang.t("settings.general.uninstall")) {
                            requestHookUninstall(.claudeUsage)
                        }
                    } else if model.isClaudeUsageSetupBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(lang.t("settings.general.install")) {
                            requestHookInstall(.claudeUsage)
                        }
                    }
                }
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallClaudeUsage) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallClaudeUsageBridge()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.claudeUsage"))
                }

                Toggle(lang.t("settings.general.showCodexUsage"), isOn: Binding(
                    get: { model.showCodexUsage },
                    set: { model.showCodexUsage = $0 }
                ))
            } header: {
                HStack(spacing: 4) {
                    Text(lang.t("setup.section.usage"))
                    Text(lang.t("setup.optional"))
                        .foregroundStyle(.tertiary)
                }
            }

            Section(lang.t("setup.section.permissions")) {
                HStack(alignment: .top) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.t("setup.permissionsTitle"))
                            Text(lang.t("setup.permissionsDesc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                    Spacer()
                }
            }

            hookDiagnosticsSection

            Section {
                Button(lang.t("setup.installAll")) {
                    model.lastActionMessage = "Review each integration's target and managed changes before installing. Bulk installation is intentionally disabled."
                }
                .disabled(model.hooksBinaryURL == nil || allReady)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.setup"))
        .alert(item: $pendingHookInstall) { request in
            Alert(
                title: Text("Review Open Island changes"),
                message: Text(consentMessage(request.preview)),
                primaryButton: .default(Text(request.isUninstall ? "Confirm removal" : "Confirm install"), action: {
                    if request.isUninstall { model.confirmHookUninstall(request.request, preview: request.preview) }
                    else { model.confirmHookInstall(request.request, preview: request.preview) }
                }),
                secondaryButton: .cancel()
            )
        }
    }

    private func requestHookInstall(_ request: HookConsentRequest) {
        guard let preview = model.prepareHookInstall(request) else { return }
        pendingHookInstall = HookInstallConfirmation(preview: preview, request: request, isUninstall: false)
    }

    private func requestHookUninstall(_ request: HookConsentRequest) {
        guard let preview = model.prepareHookUninstall(request) else { return }
        pendingHookInstall = HookInstallConfirmation(preview: preview, request: request, isUninstall: true)
    }

    private func consentMessage(_ preview: HookConsentPreview) -> String {
        let changes = (preview.managedAdditions.map { "+ \($0)" } + preview.managedRemovals.map { "− \($0)" }).joined(separator: "\n")
        let snapshots = preview.targetSnapshots.map { snapshot in
            "\(snapshot.canonicalPath): \(snapshot.exists ? snapshot.fileType : "absent"), mode \(snapshot.mode.map { String($0, radix: 8) } ?? "—"), owner \(snapshot.ownerID.map(String.init) ?? "—"), links \(snapshot.linkCount.map(String.init) ?? "—"), SHA \(snapshot.sha256 ?? "absent"), provenance \(snapshot.provenanceGeneration ?? "absent"), outcome \(snapshot.managementOutcome.rawValue)"
        }.joined(separator: "\n")
        return "Integration: \(preview.integrationID)\nSource: \(preview.sourceBundlePath)\nVersion: \(preview.artifactVersion)\nSHA-256: \(preview.sha256)\nTargets:\n\(preview.targetPaths.joined(separator: "\n"))\nTarget snapshots:\n\(snapshots)\nModes: \(preview.requestedModes.joined(separator: ", "))\nChanges:\n\(changes)\nBackups (\(preview.target.backupRetentionDays)d):\n\(preview.backupPaths.joined(separator: "\n"))\nJournals:\n\(preview.journalPaths.joined(separator: "\n"))\nProvenance:\n\(preview.provenancePaths.joined(separator: "\n"))\nWrapping: \(preview.involvesWrapping ? "yes" : "no") · restoration: \(preview.involvesRestoration ? "yes" : "no")"
    }

    @ViewBuilder
    private var claudeConfigDirectorySection: some View {
        Section {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.t("setup.claudeConfigDir.title"))
                        Text(ClaudeConfigDirectory.resolved().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: "folder")
                }
                Spacer()
                if ClaudeConfigDirectory.customDirectory != nil {
                    Button(lang.t("setup.claudeConfigDir.reset")) {
                        model.updateClaudeConfigDirectory(to: nil)
                    }
                    .font(.caption)
                }
                Button(lang.t("setup.claudeConfigDir.choose")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.showsHiddenFiles = true
                    panel.prompt = lang.t("setup.claudeConfigDir.choose")
                    if panel.runModal() == .OK, let url = panel.url {
                        model.updateClaudeConfigDirectory(to: url)
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text(lang.t("setup.claudeConfigDir.section"))
                Text(lang.t("setup.optional"))
                    .foregroundStyle(.tertiary)
            }
        } footer: {
            Text(lang.t("setup.claudeConfigDir.footer"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var allReady: Bool {
        model.claudeHooksInstalled && model.codexHooksInstalled && model.openCodePluginInstalled
            && model.qoderHooksInstalled && model.qwenCodeHooksInstalled && model.factoryHooksInstalled && model.codebuddyHooksInstalled
            && model.cursorHooksInstalled && model.geminiHooksInstalled && model.kimiHooksInstalled && model.claudeUsageInstalled
    }

    @ViewBuilder
    private var emptyStateBanner: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.t("setup.banner.noHooks.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(lang.t("setup.banner.noHooks.message"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var codexHookConfigURL: URL? {
        if let hooksURL = model.codexHookStatus?.hooksURL, FileManager.default.fileExists(atPath: hooksURL.path) {
            return hooksURL
        }
        return model.codexHookStatus?.configURL ?? model.codexHookStatus?.hooksURL
    }

    private var geminiHookConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/settings.json")
    }

    private var hasErrors: Bool {
        let claudeErrors = model.claudeHealthReport?.errors.count ?? 0
        let codexErrors = model.codexHealthReport?.errors.count ?? 0
        return claudeErrors + codexErrors > 0
    }

    private var hasRepairableIssues: Bool {
        let claude = model.claudeHealthReport?.repairableIssues.isEmpty == false
        let codex = model.codexHealthReport?.repairableIssues.isEmpty == false
        return claude || codex
    }

    private var hasNotices: Bool {
        let claude = model.claudeHealthReport?.notices.isEmpty == false
        let codex = model.codexHealthReport?.notices.isEmpty == false
        return claude || codex
    }

    @ViewBuilder
    private var hookDiagnosticsSection: some View {
        Section {
            if let claudeReport = model.claudeHealthReport, !claudeReport.issues.isEmpty {
                issueList(report: claudeReport)
            }
            if let codexReport = model.codexHealthReport, !codexReport.issues.isEmpty {
                issueList(report: codexReport)
            }

            if model.claudeHealthReport == nil && model.codexHealthReport == nil {
                HStack {
                    Text(lang.t("setup.diagnostics.notRun"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(lang.t("setup.diagnostics.runCheck")) {
                        model.runHealthChecks()
                    }
                }
            } else if !hasErrors {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(lang.t("setup.diagnostics.allHealthy"))
                    Spacer()
                    Button(lang.t("setup.diagnostics.recheck")) {
                        model.runHealthChecks()
                    }
                    .font(.caption)
                }
            } else {
                HStack(spacing: 10) {
                    Button(lang.t("setup.diagnostics.recheck")) {
                        model.runHealthChecks()
                    }

                    if hasRepairableIssues {
                        Button(lang.t("setup.diagnostics.repair")) {
                            model.repairHooks()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text(lang.t("setup.section.diagnostics"))
                if hasErrors {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                }
            }
        }
    }

    @ViewBuilder
    private func issueList(report: HookHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.agent == "claude" ? "Claude Code" : "Codex")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: issueIcon(for: issue))
                        .font(.caption2)
                        .foregroundStyle(issueColor(for: issue))
                        .frame(width: 14)

                    Text(issue.description)
                        .font(.caption)
                        .foregroundStyle(issue.severity == .info ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let binaryPath = report.binaryPath {
                Text("Binary: \(binaryPath)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func issueIcon(for issue: HookHealthReport.Issue) -> String {
        switch issue.severity {
        case .info: "info.circle.fill"
        case .error: issue.isAutoRepairable ? "wrench.fill" : "exclamationmark.triangle.fill"
        }
    }

    private func issueColor(for issue: HookHealthReport.Issue) -> Color {
        switch issue.severity {
        case .info: .blue
        case .error: issue.isAutoRepairable ? .orange : .red
        }
    }

    @ViewBuilder
    private func hookRow(
        name: String,
        installed: Bool,
        busy: Bool,
        requiresBinary: Bool = true,
        configLocationURL: URL? = nil,
        installAction: @escaping () -> Void,
        uninstallAction: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(name, systemImage: "terminal")
            Spacer()
            if installed {
                HStack(spacing: 8) {
                    if let configLocationURL {
                        Button {
                            revealInFinder(configLocationURL)
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(lang.t("setup.revealConfigLocation"))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(lang.t("settings.general.activated"))
                            .foregroundStyle(.secondary)
                    }
                    Button(lang.t("settings.general.uninstall")) {
                        uninstallAction()
                    }
                    .foregroundStyle(.red)
                    .font(.caption)
                }
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                Button(lang.t("settings.general.install")) {
                    installAction()
                }
                .disabled(requiresBinary && model.hooksBinaryURL == nil)
            }
        }
    }

    private func revealInFinder(_ url: URL) {
        LocalFileReveal.reveal(url)
    }
}

// MARK: - Placeholder

struct PlaceholderSettingsPane: View {
    var model: AppModel
    let titleKey: String
    let subtitleKey: String

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(lang.t(subtitleKey))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(lang.t(titleKey))
    }
}
