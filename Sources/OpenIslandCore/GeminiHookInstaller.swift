import Foundation

public struct GeminiHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-gemini-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct GeminiHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: Data?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
    }
}

/// Classification of Gemini's canonical five event groups. A command-shaped
/// group is only collision evidence: the installation manager additionally
/// requires an exact manifest, sidecars, backup identity, and helper artifact
/// before it will regard a settings file as ours.
public enum GeminiManagedSettingsState: Equatable, Sendable {
    case none
    case exact(entryDigest: String)
    case managedLooking
}

public enum GeminiHookInstallerError: Error, LocalizedError {
    case invalidSettingsJSON

    public var errorDescription: String? {
        switch self {
        case .invalidSettingsJSON:
            "The existing Gemini settings.json is not valid JSON."
        }
    }
}

public enum GeminiHookInstaller {
    private static let eventSpecs: [(name: String, matcher: String?)] = [
        ("SessionStart", "*"),
        ("SessionEnd", "*"),
        ("BeforeAgent", "*"),
        ("AfterAgent", "*"),
        ("Notification", "*"),
    ]

    public static func hookCommand(for binaryPath: String) -> String {
        "\(shellQuote(binaryPath)) --source gemini"
    }

    public static func installSettingsJSON(
        existingData: Data?,
        hookCommand: String
    ) throws -> GeminiHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]

        for spec in eventSpecs {
            var groups = hooksObject[spec.name] as? [[String: Any]] ?? []
            groups = groups.filter { !isManagedGroup($0, managedCommand: hookCommand) }
            groups.append(managedGroup(matcher: spec.matcher, hookCommand: hookCommand))
            hooksObject[spec.name] = groups
        }

        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)
        return GeminiHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true
        )
    }

    public static func uninstallSettingsJSON(
        existingData: Data?,
        managedCommand: String?
    ) throws -> GeminiHookFileMutation {
        guard let existingData else {
            return GeminiHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var mutated = false

        for spec in eventSpecs {
            let groups = hooksObject[spec.name] as? [[String: Any]] ?? []
            let filtered = groups.filter { !isManagedGroup($0, managedCommand: managedCommand) }
            if filtered.count != groups.count {
                mutated = true
            }

            if filtered.isEmpty {
                hooksObject.removeValue(forKey: spec.name)
            } else {
                hooksObject[spec.name] = filtered
            }
        }

        if hooksObject.isEmpty {
            rootObject.removeValue(forKey: "hooks")
        } else {
            rootObject["hooks"] = hooksObject
        }

        let contents = rootObject.isEmpty ? nil : try serialize(rootObject)
        return GeminiHookFileMutation(
            contents: contents,
            changed: mutated || contents != existingData,
            managedHooksPresent: mutated
        )
    }

    /// Returns exact only for the complete canonical settings document emitted
    /// by `installSettingsJSON`. Partial, duplicate, stale-path and altered
    /// groups are deliberately collisions rather than repair candidates.
    public static func managedSettingsState(
        existingData: Data?,
        hookCommand: String
    ) throws -> GeminiManagedSettingsState {
        guard let existingData else { return .none }
        let root = try loadRootObject(from: existingData)
        let canonical = try installSettingsJSON(existingData: existingData, hookCommand: hookCommand).contents
        // Compare content, not raw bytes: a co-tenant re-serializing
        // settings.json or appending its own group after ours changes byte
        // layout and group order without changing a managed entry.
        let canonicalRoot = try loadRootObject(from: canonical)
        if try ManagedHookSettingsComparison.orderInsensitiveForm(canonicalRoot)
            == ManagedHookSettingsComparison.orderInsensitiveForm(root) {
            return .exact(entryDigest: managedEntriesDigest(hookCommand: hookCommand))
        }
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        return containsManagedLookingHook(in: hooks) ? .managedLooking : .none
    }

    /// Identifies the managed entries alone, so unrelated co-tenant keys and
    /// hook groups cannot invalidate a recorded ownership digest.
    public static func managedEntriesDigest(hookCommand: String) -> String {
        let entries = Dictionary(uniqueKeysWithValues: eventSpecs.map { spec in
            (spec.name, managedGroup(matcher: spec.matcher, hookCommand: hookCommand))
        })
        return ManagedHookFileSystem.digest(of: canonicalJSONData(entries))
    }

    private static func canonicalJSONData(_ object: Any) -> Data {
        // Built from JSON-compatible values above; a failure would be a
        // programming error, not an untrusted-data path.
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }

        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw GeminiHookInstallerError.invalidSettingsJSON }
        guard let rootObject = object as? [String: Any] else {
            throw GeminiHookInstallerError.invalidSettingsJSON
        }

        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func managedGroup(matcher: String?, hookCommand: String) -> [String: Any] {
        let hook: [String: Any] = [
            "type": "command",
            "command": hookCommand,
            "name": "Open Island"
        ]

        var group: [String: Any] = [
            "hooks": [hook]
        ]

        if let matcher {
            group["matcher"] = matcher
        }

        return group
    }

    private static func isManagedGroup(_ group: [String: Any], managedCommand: String?) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else {
            return false
        }

        return hooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return managedCommand.map { command == $0 } ?? false
        }
    }

    /// This recognises only the quoting syntax we emit and the actual helper
    /// filename. It deliberately does not use a marker, a substring, or a
    /// caller-selected path as ownership evidence.
    private static func containsManagedLookingHook(in hooksObject: [String: Any]) -> Bool {
        hooksObject.values.contains { value in
            guard let groups = value as? [Any] else { return false }
            return groups.contains { item in
                guard let group = item as? [String: Any],
                      let hooks = group["hooks"] as? [Any] else { return false }
                return hooks.contains { hook in
                    guard let hook = hook as? [String: Any],
                          let command = hook["command"] as? String else { return false }
                    return canonicalManagedCommand(command)
                }
            }
        }
    }

    private static func canonicalManagedCommand(_ command: String) -> Bool {
        let suffix = "' --source gemini"
        guard command.hasPrefix("'"), command.hasSuffix(suffix) else { return false }
        let path = String(command.dropFirst().dropLast(suffix.count))
        guard !path.contains("'\\\\''") else { return false }
        return URL(fileURLWithPath: path).lastPathComponent == ManagedHooksBinary.binaryName
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
