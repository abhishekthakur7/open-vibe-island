import Foundation

public struct CursorHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-cursor-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct CursorHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: Data?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
    }
}

/// Classification of Cursor's six exact managed entries. A command-shaped
/// entry is only collision evidence; the installation manager still requires
/// verified manifest and provenance records before it treats a file as owned.
public enum CursorManagedHookState: Equatable, Sendable {
    case none
    case exact(entryDigest: String)
    case managedLooking
}

public enum CursorHookInstallerError: Error, LocalizedError {
    case invalidHooksJSON

    public var errorDescription: String? {
        switch self {
        case .invalidHooksJSON:
            "The existing Cursor hooks.json is not valid JSON."
        }
    }
}

public enum CursorHookInstaller {
    private static let hookEvents: [String] = [
        "beforeSubmitPrompt",
        "beforeShellExecution",
        "beforeMCPExecution",
        "beforeReadFile",
        "afterFileEdit",
        "stop",
    ]

    public static func hookCommand(for binaryPath: String) -> String {
        "\(shellQuote(binaryPath)) --source cursor"
    }

    /// Detect the canonical six-entry shape without using a marker or command
    /// substring as ownership. A stale helper path, duplicate, or partial set
    /// deliberately remains a collision that an automatic install must not
    /// merge into.
    public static func managedHookState(
        existingData: Data?,
        hookCommand: String
    ) throws -> CursorManagedHookState {
        guard let existingData else { return .none }
        let root = try loadRootObject(from: existingData)
        guard let hooksValue = root["hooks"] else { return .none }
        guard let hooks = hooksValue as? [String: Any] else { return .managedLooking }

        var candidateCount = 0
        var exactCount = 0
        for event in hookEvents {
            guard let eventValue = hooks[event] else { continue }
            guard let entries = eventValue as? [Any] else { return .managedLooking }
            for item in entries {
                guard let entry = item as? [String: Any],
                      let command = entry["command"] as? String,
                      canonicalManagedCommand(command) else { continue }
                candidateCount += 1
                if entry.count == 1, command == hookCommand { exactCount += 1 }
            }
        }
        guard candidateCount > 0 else { return .none }
        guard candidateCount == hookEvents.count, exactCount == hookEvents.count else { return .managedLooking }
        return .exact(entryDigest: managedEntriesDigest(hookCommand: hookCommand))
    }

    public static func managedEntriesDigest(hookCommand: String) -> String {
        let entries = Dictionary(uniqueKeysWithValues: hookEvents.map { ($0, ["command": hookCommand]) })
        let data = (try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])) ?? Data()
        return ManagedHookFileSystem.digest(of: data)
    }

    public static func installHooksJSON(
        existingData: Data?,
        hookCommand: String
    ) throws -> CursorHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)
        rootObject["version"] = 1

        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]

        for event in hookEvents {
            var entries = hooksObject[event] as? [[String: Any]] ?? []
            entries = entries.filter { !isManagedHook($0, managedCommand: hookCommand) }
            entries.append(["command": hookCommand])
            hooksObject[event] = entries
        }

        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)

        return CursorHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true
        )
    }

    public static func uninstallHooksJSON(
        existingData: Data?,
        managedCommand: String?
    ) throws -> CursorHookFileMutation {
        guard let existingData else {
            return CursorHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var mutated = false

        for event in hookEvents {
            let entries = hooksObject[event] as? [[String: Any]] ?? []
            let filtered = entries.filter { !isManagedHook($0, managedCommand: managedCommand) }

            if filtered.count != entries.count {
                mutated = true
            }

            if filtered.isEmpty {
                hooksObject.removeValue(forKey: event)
            } else {
                hooksObject[event] = filtered
            }
        }

        if hooksObject.isEmpty {
            rootObject.removeValue(forKey: "hooks")
        } else {
            rootObject["hooks"] = hooksObject
        }

        if rootObject.count == 1, rootObject["version"] != nil {
            rootObject = [:]
        }

        let contents = rootObject.isEmpty ? nil : try serialize(rootObject)

        return CursorHookFileMutation(
            contents: contents,
            changed: mutated || contents != existingData,
            managedHooksPresent: mutated
        )
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }

        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw CursorHookInstallerError.invalidHooksJSON }
        guard let rootObject = object as? [String: Any] else {
            throw CursorHookInstallerError.invalidHooksJSON
        }

        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func isManagedHook(_ hook: [String: Any], managedCommand: String?) -> Bool {
        guard let command = hook["command"] as? String else { return false }

        return managedCommand.map { command == $0 } ?? false
    }

    /// Conservative collision parsing, never ownership. It accepts only the
    /// quoted command syntax produced by `hookCommand` and the real helper
    /// filename, leaving lookalike names and arbitrary user commands alone.
    private static func canonicalManagedCommand(_ command: String) -> Bool {
        let suffix = "' --source cursor"
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
