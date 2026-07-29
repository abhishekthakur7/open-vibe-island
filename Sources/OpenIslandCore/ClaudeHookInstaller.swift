import Foundation

public struct ClaudeHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-claude-hooks-install.json"
    public static let legacyFileName = "vibe-island-claude-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct ClaudeHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool
    public var hasClaudeIslandHooks: Bool

    public init(
        contents: Data?,
        changed: Bool,
        managedHooksPresent: Bool,
        hasClaudeIslandHooks: Bool
    ) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
        self.hasClaudeIslandHooks = hasClaudeIslandHooks
    }
}

/// Classification used by the installation manager.  A matching command is
/// never ownership on its own: `.exact` only describes the settings bytes;
/// the manager also requires the source-specific manifest and both private
/// provenance records before it may mutate anything.
public enum ClaudeManagedSettingsState: Equatable, Sendable {
    case none
    case exact(entryDigest: String)
    case managedLooking
}

public enum ClaudeHookInstallerError: Error, LocalizedError {
    case invalidSettingsJSON

    public var errorDescription: String? {
        switch self {
        case .invalidSettingsJSON:
            "The existing Claude settings.json is not valid JSON."
        }
    }
}

public enum ClaudeHookInstaller {
    public static let managedTimeout = 86_400

    private static let eventSpecs: [(name: String, matcher: String?, timeout: Int?)] = [
        ("UserPromptSubmit", nil, nil),
        ("SessionStart", nil, nil),
        ("SessionEnd", nil, nil),
        ("Stop", nil, nil),
        ("StopFailure", nil, nil),
        ("SubagentStart", nil, nil),
        ("SubagentStop", nil, nil),
        ("Notification", "*", nil),
        ("PreToolUse", "*", nil),
        ("PermissionRequest", "*", managedTimeout),
        ("PostToolUse", "*", nil),
        ("PostToolUseFailure", "*", nil),
        ("PermissionDenied", "*", nil),
        ("PreCompact", nil, nil),
    ]

    public static func hookCommand(for binaryPath: String, source: String = "claude") -> String {
        "\(shellQuote(binaryPath)) --source \(source)"
    }

    public static func installSettingsJSON(
        existingData: Data?,
        hookCommand: String
    ) throws -> ClaudeHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)
        let existingHooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var hooksObject: [String: Any] = [:]

        for (eventName, value) in existingHooksObject {
            let existingGroups = value as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups, replacingCommand: hookCommand)

            if !cleanedGroups.isEmpty {
                hooksObject[eventName] = cleanedGroups
            }
        }

        for spec in eventSpecs {
            let existingGroups = hooksObject[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups, replacingCommand: hookCommand)
            hooksObject[spec.name] = cleanedGroups + [managedGroup(matcher: spec.matcher, timeout: spec.timeout, hookCommand: hookCommand)]
        }

        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)

        return ClaudeHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true,
            hasClaudeIslandHooks: containsClaudeIslandHook(in: hooksObject)
        )
    }

    public static func uninstallSettingsJSON(
        existingData: Data?,
        managedCommand: String?
    ) throws -> ClaudeHookFileMutation {
        guard let existingData else {
            return ClaudeHookFileMutation(
                contents: nil,
                changed: false,
                managedHooksPresent: false,
                hasClaudeIslandHooks: false
            )
        }

        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var mutated = false

        for spec in eventSpecs {
            let existingGroups = hooksObject[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitize(groups: existingGroups, managedCommand: managedCommand)

            if cleanedGroups.count != existingGroups.count || containsManagedHook(in: existingGroups, managedCommand: managedCommand) {
                mutated = true
            }

            if cleanedGroups.isEmpty {
                hooksObject.removeValue(forKey: spec.name)
            } else {
                hooksObject[spec.name] = cleanedGroups
            }
        }

        if hooksObject.isEmpty {
            rootObject.removeValue(forKey: "hooks")
        } else {
            rootObject["hooks"] = hooksObject
        }

        let contents = rootObject.isEmpty ? nil : try serialize(rootObject)
        return ClaudeHookFileMutation(
            contents: contents,
            changed: mutated || contents != existingData,
            managedHooksPresent: mutated,
            hasClaudeIslandHooks: containsClaudeIslandHook(in: hooksObject)
        )
    }

    /// Returns exact only for the canonical settings representation produced
    /// by `installSettingsJSON`. Duplicate, partial, stale-path, and otherwise
    /// conflicting managed entries deliberately remain ambiguous.
    public static func managedSettingsState(
        existingData: Data?,
        hookCommand: String,
        source: String
    ) throws -> ClaudeManagedSettingsState {
        guard let existingData else { return .none }
        let root = try loadRootObject(from: existingData)
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let canonical = try installSettingsJSON(existingData: existingData, hookCommand: hookCommand).contents
        if canonical == existingData {
            return .exact(entryDigest: ManagedHookFileSystem.digest(of: existingData))
        }
        return containsManagedLookingHook(in: hooks, source: source) ? .managedLooking : .none
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else {
            return [:]
        }

        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw ClaudeHookInstallerError.invalidSettingsJSON }
        guard let rootObject = object as? [String: Any] else {
            throw ClaudeHookInstallerError.invalidSettingsJSON
        }

        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func sanitize(groups: [Any], managedCommand: String?) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else {
                return nil
            }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else {
                    return nil
                }

                return isManagedHook(hook, managedCommand: managedCommand) ? nil : hook
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
    }

    private static func sanitizeForInstall(groups: [Any], replacingCommand: String) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else {
                return nil
            }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else {
                    return nil
                }

                return isManagedHookForInstall(hook, replacingCommand: replacingCommand) ? nil : hook
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
    }

    private static func containsManagedHook(in groups: [Any], managedCommand: String?) -> Bool {
        groups.contains { item in
            guard let group = item as? [String: Any],
                  let hooks = group["hooks"] as? [Any] else {
                return false
            }

            return hooks.contains { hook in
                guard let hook = hook as? [String: Any] else {
                    return false
                }

                return isManagedHook(hook, managedCommand: managedCommand)
            }
        }
    }

    private static func containsClaudeIslandHook(in hooksObject: [String: Any]) -> Bool {
        hooksObject.values.contains { value in
            let groups = value as? [Any] ?? []
            return groups.contains { item in
                guard let group = item as? [String: Any],
                      let hooks = group["hooks"] as? [Any] else {
                    return false
                }

                return hooks.contains { hook in
                    guard let hook = hook as? [String: Any],
                          let command = hook["command"] as? String else {
                        return false
                    }

                    return command.contains("claude-island-state.py")
                }
            }
        }
    }

    /// This is intentionally a parser, not a substring check. It is only a
    /// conservative collision detector (never ownership): a stale canonical
    /// OpenIslandHooks command for the same source blocks automatic merging.
    private static func containsManagedLookingHook(in hooksObject: [String: Any], source: String) -> Bool {
        hooksObject.values.contains { value in
            let groups = value as? [Any] ?? []
            return groups.contains { item in
                guard let group = item as? [String: Any], let hooks = group["hooks"] as? [Any] else { return false }
                return hooks.contains { item in
                    guard let hook = item as? [String: Any], let command = hook["command"] as? String else { return false }
                    return canonicalManagedCommand(command, source: source)
                }
            }
        }
    }

    private static func canonicalManagedCommand(_ command: String, source: String) -> Bool {
        let suffix = "' --source \(source)"
        guard command.hasPrefix("'"), command.hasSuffix(suffix) else { return false }
        let path = String(command.dropFirst().dropLast(suffix.count))
        // `shellQuote` escapes embedded quotes, which cannot occur in the
        // installed helper path. Treat such strings as unrelated user input.
        guard !path.contains("'\\\\''") else { return false }
        return URL(fileURLWithPath: path).lastPathComponent == ManagedHooksBinary.binaryName
    }

    private static func managedGroup(
        matcher: String?,
        timeout: Int?,
        hookCommand: String
    ) -> [String: Any] {
        var hook: [String: Any] = [
            "type": "command",
            "command": hookCommand,
        ]
        if let timeout {
            hook["timeout"] = timeout
        }

        var group: [String: Any] = [
            "hooks": [hook],
        ]

        if let matcher {
            group["matcher"] = matcher
        }

        return group
    }

    private static func isManagedHook(_ hook: [String: Any], managedCommand: String?) -> Bool {
        guard let command = hook["command"] as? String else {
            return false
        }

        // A marker-like command is not ownership.  Callers must supply the
        // exact command recorded in verified provenance before a hook can be
        // removed or replaced.
        return managedCommand.map { command == $0 } ?? false
    }

    private static func isManagedHookForInstall(_ hook: [String: Any], replacingCommand: String) -> Bool {
        isManagedHook(hook, managedCommand: replacingCommand)
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else {
            return "''"
        }

        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
