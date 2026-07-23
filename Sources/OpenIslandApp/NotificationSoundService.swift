import AppKit

/// Manages notification sound playback using macOS system sounds.
///
/// AB-239: previously a single global sound played for every event type
/// (permission, question, completion). Each `NotificationEventKind` now has
/// its own persisted sound preference, but every one of them reads through
/// `legacyDefaultsKey` until explicitly customized — so an upgrading user
/// who already picked a sound keeps hearing exactly that sound for every
/// event, identical to today's behavior, until they change one of the three
/// independently in the Sounds settings pane.
@MainActor
struct NotificationSoundService {
    private static let soundsDirectory = "/System/Library/Sounds"
    private static let legacyDefaultsKey = "notification.sound.name"
    static let defaultSoundName = "Bottle"

    /// Returns the list of available system sound names (without file extension).
    static func availableSounds() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: soundsDirectory) else {
            return []
        }
        return contents
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }

    private static func defaultsKey(for kind: NotificationEventKind) -> String {
        "notification.sound.name.\(kind.rawValue)"
    }

    /// The persisted sound name for a given event kind. Falls back to the
    /// pre-AB-239 single-sound preference (and finally `defaultSoundName`)
    /// when the user hasn't customized this specific event yet.
    static func soundName(for kind: NotificationEventKind) -> String {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: defaultsKey(for: kind)) {
            return stored
        }
        return defaults.string(forKey: legacyDefaultsKey) ?? defaultSoundName
    }

    static func setSoundName(_ name: String, for kind: NotificationEventKind) {
        UserDefaults.standard.set(name, forKey: defaultsKey(for: kind))
    }

    /// Plays a system sound by name.
    static func play(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            return
        }
        sound.stop()
        sound.play()
    }

    /// Plays the sound configured for `kind`, respecting the mute setting.
    /// `kind == nil` (e.g. a `.running` session) plays nothing.
    static func playNotification(for kind: NotificationEventKind?, isMuted: Bool) {
        guard !isMuted, let kind else { return }
        play(soundName(for: kind))
    }
}
