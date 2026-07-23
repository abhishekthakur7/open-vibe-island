import AppKit
import OpenIslandCore

/// Owns the optional menu-bar `NSStatusItem` that surfaces a live count of
/// sessions waiting on the user (AB-239 #1).
///
/// Off by default — the status item is only created once `setEnabled(true)`
/// is called, which `AppModel` does from the "Show pending count in menu
/// bar" Settings toggle. `AppModel` calls `update(attentionSessions:)`
/// whenever the live session list changes so the count and menu contents
/// stay current as items resolve.
@MainActor
final class AttentionStatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var attentionSessions: [AgentSession] = []

    /// Invoked when the user picks a session from the menu, with its ID.
    /// `AppModel` wires this to `presentOverlayFocused(onSessionID:)`.
    var onSelectSession: ((String) -> Void)?

    var isEnabled: Bool { statusItem != nil }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }

        if enabled {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem = item
            render()
        } else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        }
    }

    /// Refreshes the live attention list. Cheap no-op beyond caching the
    /// list while the status item is hidden, so `AppModel` can call this
    /// unconditionally on every session-state change.
    func update(attentionSessions: [AgentSession]) {
        self.attentionSessions = attentionSessions
        guard statusItem != nil else { return }
        render()
    }

    private func render() {
        guard let statusItem, let button = statusItem.button else { return }

        let count = attentionSessions.count
        let image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Open Island")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = count > 0 ? " \(count)" : ""

        statusItem.menu = Self.buildMenu(attentionSessions: attentionSessions, target: self)
    }

    /// `@objc`/non-private so it can serve as the real `NSMenuItem` target
    /// while still being directly callable (no `perform(_:with:)` dance)
    /// from `AttentionStatusItemControllerTests`.
    @objc func handleSelect(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? String else { return }
        onSelectSession?(sessionID)
    }

    private static func buildMenu(attentionSessions: [AgentSession], target: AttentionStatusItemController) -> NSMenu {
        let lang = LanguageManager.shared
        let menu = NSMenu()

        if attentionSessions.isEmpty {
            let empty = NSMenuItem(title: lang.t("menuBar.noAttention"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for session in attentionSessions {
                let item = NSMenuItem(
                    title: entryTitle(for: session, lang: lang),
                    action: #selector(handleSelect(_:)),
                    keyEquivalent: ""
                )
                item.target = target
                item.representedObject = session.id
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: lang.t("settings.about.quitApp"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        ))

        return menu
    }

    /// Pure title-building, kept separate from `NSMenuItem` construction so
    /// it's unit-testable without touching `NSStatusBar`.
    static func entryTitle(for session: AgentSession, lang: LanguageManager) -> String {
        let phaseLabel: String
        switch session.phase {
        case .waitingForApproval:
            phaseLabel = lang.t("island.section.needsApproval")
        case .waitingForAnswer:
            phaseLabel = lang.t("island.section.needsAnswer")
        case .running:
            phaseLabel = lang.t("island.section.inProgress")
        case .completed:
            phaseLabel = lang.t("island.section.justDone")
        }

        let title = session.title.isEmpty ? session.tool.displayName : session.title
        return "\(title) — \(phaseLabel)"
    }
}
