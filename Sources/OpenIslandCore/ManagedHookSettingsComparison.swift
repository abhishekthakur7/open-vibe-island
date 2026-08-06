import Foundation

/// Content comparison for hook settings files that Open Island shares with
/// their owning tool.
enum ManagedHookSettingsComparison {
    /// Canonical bytes for a `hooks`-bearing settings object, with each event's
    /// group list order-normalized.
    ///
    /// A managed install appends its group to the end of each event's list, but
    /// a co-tenant that installs afterwards appends past it.  That moves our
    /// group without changing it, so ownership classification — which is about
    /// *content* — must not depend on where in the list our group sits.
    ///
    /// Sorting rather than de-duplicating keeps a doubled managed group
    /// detectable: the two lists still differ in length.
    static func orderInsensitiveForm(_ root: [String: Any]) throws -> Data {
        var normalized = root
        if let hooks = root["hooks"] as? [String: Any] {
            var normalizedHooks: [String: Any] = [:]
            for (event, value) in hooks {
                guard let groups = value as? [Any] else {
                    normalizedHooks[event] = value
                    continue
                }
                normalizedHooks[event] = groups
                    .map { (key: canonicalKey($0), group: $0) }
                    .sorted { $0.key < $1.key }
                    .map(\.group)
            }
            normalized["hooks"] = normalizedHooks
        }
        return try JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys])
    }

    /// A stable total-order key.  Values that cannot be serialized sort first
    /// and compare only against each other, which keeps them visible as a
    /// difference rather than silently equal.
    private static func canonicalKey(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys]) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }
}
