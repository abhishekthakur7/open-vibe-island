import Foundation

/// Centralizes the per-subprocess "skip hook" environment variable protocol.
public enum HookSkipConfiguration {
    /// The recommended current environment switch for disabling hooks in this process.
    public static let openIslandSkipKey = "OPEN_ISLAND_SKIP_HOOKS"
    /// The legacy Vibe Island switch, kept for compatibility.
    public static let legacyVibeIslandSkipKey = "VIBE_ISLAND_SKIP"

    /// Returns true when the incoming environment explicitly requests skipping the hook.
    public static func shouldSkipHooks(environment: [String: String]) -> Bool {
        isTruthy(environment[openIslandSkipKey])
            || isTruthy(environment[legacyVibeIslandSkipKey])
    }

    /// Accepts only common shell-friendly truthy values; everything else is treated as false.
    private static func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}
