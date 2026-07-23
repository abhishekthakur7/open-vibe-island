import Carbon.HIToolbox
import Foundation

/// A single global (system-wide) keyboard shortcut, expressed in the
/// "Carbon" key-code + modifier-mask vocabulary that `RegisterEventHotKey`
/// expects — distinct from (and not directly convertible from)
/// `NSEvent.ModifierFlags`/`NSEvent.keyCode`.
struct GlobalHotKeyCombo: Equatable, Sendable {
    let carbonKeyCode: UInt32
    let carbonModifiers: UInt32
    /// Human-readable glyph shown in Settings, e.g. "⌥⌘O".
    let symbol: String
}

/// User-facing choices for the global summon/dismiss hotkey (AB-227). Kept
/// as a short curated list rather than a full key-recorder UI to stay in
/// scope for v1 — the combos were picked to avoid common macOS/app
/// shortcuts (Spotlight, Alfred, input-source switching, etc).
enum GlobalHotKeyOption: String, CaseIterable, Identifiable, Sendable {
    case off
    case optionCommandO
    case controlOptionSpace

    var id: String { rawValue }

    var combo: GlobalHotKeyCombo? {
        switch self {
        case .off:
            return nil
        case .optionCommandO:
            return GlobalHotKeyCombo(
                carbonKeyCode: UInt32(kVK_ANSI_O),
                carbonModifiers: UInt32(optionKey | cmdKey),
                symbol: "⌥⌘O"
            )
        case .controlOptionSpace:
            return GlobalHotKeyCombo(
                carbonKeyCode: UInt32(kVK_Space),
                carbonModifiers: UInt32(controlKey | optionKey),
                symbol: "⌃⌥Space"
            )
        }
    }

    @MainActor
    func displayName(_ lang: LanguageManager) -> String {
        combo?.symbol ?? lang.t("settings.shortcuts.global.off")
    }
}

/// Thin wrapper around the classic Carbon hotkey APIs
/// (`RegisterEventHotKey` / `InstallEventHandler`).
///
/// Chosen over `NSEvent.addGlobalMonitorForEvents` (which only observes,
/// can't claim a combo, and would require reimplementing exclusivity) and
/// over a `CGEventTap` (which needs Accessibility/Input Monitoring
/// permission). `RegisterEventHotKey` needs neither permission and fires
/// even when Open Island isn't the frontmost app — required for AB-227's
/// "summon overlay from any app" hotkey while keeping the app local-first
/// with no new dependencies or permission prompts.
@MainActor
final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onInvoke: (() -> Void)?

    private static let signature: FourCharCode = {
        "OIsl".utf8.reduce(FourCharCode(0)) { ($0 << 8) | FourCharCode($1) }
    }()

    /// Registers `combo` as the sole global hotkey, tearing down any
    /// previously registered combo first. Pass `nil` to only unregister
    /// (used when the user turns the feature off).
    func register(_ combo: GlobalHotKeyCombo?, action: @escaping () -> Void) {
        unregister()

        guard let combo else {
            return
        }

        onInvoke = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                // Hotkey callbacks fire on the main run loop; `assumeIsolated`
                // lets us re-enter MainActor-isolated state synchronously
                // instead of hopping a run-loop turn via `Task { @MainActor }`,
                // which would add a visible delay before the overlay opens.
                MainActor.assumeIsolated {
                    manager.onInvoke?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(
            combo.carbonKeyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        eventHandlerRef = nil

        onInvoke = nil
    }

    isolated deinit {
        unregister()
    }
}
