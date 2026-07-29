import Darwin
import Foundation

/// The complete, closed set of operations that can cross the app boundary.
/// Values arriving from hooks, transcripts, Apple Events, or the UI are never
/// converted into an executable, shell command, URL, environment, or cwd.
public enum LocalAutomationAction: String, CaseIterable, Sendable {
    case inspectProcessSnapshot
    case inspectProcessParent
    case inspectProcessCommand
    case inspectOpenFiles
    case inspectChildProcesses
    case activateTerminal
    case revealLocalFile

    public var requiredRole: BridgeClientRole { .appInternalControl }
}

/// Source is private and immutable; callers can provide only positional data
/// consumed by an `on run argv` handler.  This prevents quotation, newline,
/// and shell metacharacters from becoming AppleScript source.
public enum LocalAppleScriptTemplate: String, Sendable {
    case ghosttyFocusedTerminalProbe
    case terminalFocusedTTYProbe
    case iTermFocusedSessionProbe
    case ghosttySnapshot
    case terminalSnapshot
    case iTermSnapshot
    case ghosttyFocus
    case terminalFocus
    case iTermFocus

    fileprivate var source: String {
        switch self {
        case .ghosttyFocusedTerminalProbe:
            return "tell application id \"com.mitchellh.ghostty\"\nif not (it is running) then return \"\"\nreturn id of focused terminal of selected tab of front window as text\nend tell"
        case .terminalFocusedTTYProbe:
            return "tell application id \"com.apple.Terminal\"\nif not (it is running) then return \"\"\nreturn tty of selected tab of front window as text\nend tell"
        case .iTermFocusedSessionProbe:
            return "tell application id \"com.googlecode.iterm2\"\nif not (it is running) then return \"\"\ntell current session of current window\nreturn (id as text) & (ASCII character 31) & (tty as text)\nend tell\nend tell"
        case .ghosttySnapshot:
            return "set fieldSeparator to ASCII character 31\nset recordSeparator to ASCII character 30\ntell application id \"com.mitchellh.ghostty\"\nif not (it is running) then return \"\"\nset outputLines to {}\nrepeat with aTerminal in terminals\nset end of outputLines to (id of aTerminal as text) & fieldSeparator & (working directory of aTerminal as text) & fieldSeparator & (name of aTerminal as text)\nend repeat\nset AppleScript's text item delimiters to recordSeparator\nset joinedOutput to outputLines as string\nset AppleScript's text item delimiters to \"\"\nreturn joinedOutput\nend tell"
        case .terminalSnapshot:
            return "set fieldSeparator to ASCII character 31\nset recordSeparator to ASCII character 30\ntell application id \"com.apple.Terminal\"\nif not (it is running) then return \"\"\nset outputLines to {}\nrepeat with aWindow in windows\nrepeat with aTab in tabs of aWindow\nset end of outputLines to (tty of aTab as text) & fieldSeparator & (custom title of aTab as text)\nend repeat\nend repeat\nset AppleScript's text item delimiters to recordSeparator\nset joinedOutput to outputLines as string\nset AppleScript's text item delimiters to \"\"\nreturn joinedOutput\nend tell"
        case .iTermSnapshot:
            return "set fieldSeparator to ASCII character 31\nset recordSeparator to ASCII character 30\ntell application id \"com.googlecode.iterm2\"\nif not (it is running) then return \"\"\nset outputLines to {}\nrepeat with aWindow in windows\nrepeat with aTab in tabs of aWindow\nrepeat with aSession in sessions of aTab\nset end of outputLines to (id of aSession as text) & fieldSeparator & (tty of aSession as text) & fieldSeparator & (name of aSession as text)\nend repeat\nend repeat\nend repeat\nset AppleScript's text item delimiters to recordSeparator\nset joinedOutput to outputLines as string\nset AppleScript's text item delimiters to \"\"\nreturn joinedOutput\nend tell"
        case .ghosttyFocus:
            return "on run argv\nset wantedID to item 1 of argv\ntell application id \"com.mitchellh.ghostty\"\nif not (it is running) then return \"\"\nrepeat with aWindow in windows\nrepeat with aTab in tabs of aWindow\nrepeat with aTerminal in terminals of aTab\nif (id of aTerminal as text) is wantedID then\nactivate window aWindow\nselect tab aTab\nfocus aTerminal\nreturn \"matched\"\nend if\nend repeat\nend repeat\nend repeat\nend tell\nreturn \"\"\nend run"
        case .terminalFocus:
            return "on run argv\nset wantedTTY to item 1 of argv\ntell application id \"com.apple.Terminal\"\nif not (it is running) then return \"\"\nrepeat with aWindow in windows\nrepeat with aTab in tabs of aWindow\nif (tty of aTab as text) is wantedTTY then\nactivate window aWindow\nselect aTab\nreturn \"matched\"\nend if\nend repeat\nend repeat\nend tell\nreturn \"\"\nend run"
        case .iTermFocus:
            return "on run argv\nset wantedValue to item 1 of argv\ntell application id \"com.googlecode.iterm2\"\nif not (it is running) then return \"\"\nrepeat with aWindow in windows\nrepeat with aTab in tabs of aWindow\nrepeat with aSession in sessions of aTab\nif (id of aSession as text) is wantedValue or (tty of aSession as text) is wantedValue then\nselect aWindow\ntell aWindow to select aTab\nselect aSession\nreturn \"matched\"\nend if\nend repeat\nend repeat\nend repeat\nend tell\nreturn \"\"\nend run"
        }
    }
}

public enum LocalAutomationPolicyError: Error, Equatable, Sendable {
    case unauthorizedRole
    case unsupportedAction
    case invalidArgument
    case invalidBundleIdentifier
    case invalidURL
    case invalidLocalPath
    case outputLimitExceeded
    case timedOut
    case processFailed(Int32)
}

/// Keeps authorization adjacent to the operation allowlist.  The UI invokes
/// the policy as the app-internal principal; bridge callers must not be able to
/// substitute a weaker role for an automation action.
public enum LocalAutomationPolicy {
    public static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
    ]

    public static func authorize(_ action: LocalAutomationAction, role: BridgeClientRole) throws {
        guard role == action.requiredRole else { throw LocalAutomationPolicyError.unauthorizedRole }
    }

    public static func validateTerminalBundleIdentifier(_ value: String) throws -> String {
        guard terminalBundleIdentifiers.contains(value) else {
            throw LocalAutomationPolicyError.invalidBundleIdentifier
        }
        return value
    }

    /// Local navigation is intentionally narrow: an already-approved root is
    /// supplied by the app's file picker, and the target must stay beneath it.
    /// Every path component must be real (not a symlink), so a checked local
    /// file cannot later escape the approved root through filesystem indirection.
    public static func validatedLocalFileURL(_ url: URL, beneath root: URL) throws -> URL {
        guard url.isFileURL, root.isFileURL else { throw LocalAutomationPolicyError.invalidURL }
        try validateRawLocalPath(url.path)
        let normalizedRoot = root.standardizedFileURL
        let normalizedTarget = url.standardizedFileURL
        let rootPath = normalizedRoot.path.hasSuffix("/") ? normalizedRoot.path : normalizedRoot.path + "/"
        guard normalizedTarget.path == normalizedRoot.path || normalizedTarget.path.hasPrefix(rootPath),
              FileManager.default.fileExists(atPath: normalizedRoot.path),
              FileManager.default.fileExists(atPath: normalizedTarget.path),
              try containsNoSymbolicLinks(normalizedTarget, beneath: normalizedRoot),
              try isRegularFileOrDirectory(normalizedTarget) else {
            throw LocalAutomationPolicyError.invalidLocalPath
        }
        return normalizedTarget
    }

    /// The only Finder-reveal roots accepted from UI/session data. This is not
    /// a general file opener: it accepts existing regular files/directories in
    /// the specific local agent/config trees that Open Island already reads.
    public static func validatedApprovedLocalRevealURL(
        _ url: URL,
        role: BridgeClientRole
    ) throws -> URL {
        try authorize(.revealLocalFile, role: role)
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let roots = [
            ".codex", ".claude", ".cursor", ".gemini", ".kimi",
            ".config/opencode", "Library/Application Support/OpenIsland",
        ].map { home.appendingPathComponent($0, isDirectory: true) }
        for root in roots {
            if let validated = try? validatedLocalFileURL(url, beneath: root) {
                return validated
            }
        }
        throw LocalAutomationPolicyError.invalidLocalPath
    }

    public static func validateURL(_ url: URL) throws -> URL {
        if url.isFileURL { return url }
        guard url.scheme == "x-apple.systempreferences",
              url.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                || url.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation" else {
            throw LocalAutomationPolicyError.invalidURL
        }
        return url
    }

    private static func validateRawLocalPath(_ path: String) throws {
        guard !path.isEmpty,
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw LocalAutomationPolicyError.invalidLocalPath
        }
        let forbidden = CharacterSet(charactersIn: ";|&$<>`\\\"'")
        guard !path.unicodeScalars.contains(where: { forbidden.contains($0) }) else {
            throw LocalAutomationPolicyError.invalidLocalPath
        }
        for component in (path as NSString).pathComponents where component != "/" {
            guard component != ".", component != "..", !component.hasPrefix("-") else {
                throw LocalAutomationPolicyError.invalidLocalPath
            }
        }
    }

    private static func containsNoSymbolicLinks(_ url: URL, beneath root: URL) throws -> Bool {
        let rootValues = try root.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard rootValues.isSymbolicLink != true else { return false }
        var current = root
        let suffix = url.path.dropFirst(root.path.count)
        for component in suffix.split(separator: "/").map(String.init) {
            current.appendPathComponent(component)
            let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true { return false }
        }
        return true
    }

    private static func isRegularFileOrDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        return values.isRegularFile == true || values.isDirectory == true
    }
}

public struct LocalProcessResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
}

/// A bounded direct-exec runner.  It deliberately has no API that accepts a
/// command string, cwd, inherited/login environment, or caller-selected path.
/// The runner owns the child process group so timeout and output-limit cleanup
/// also terminate descendants.
public final class LocalProcessRunner: @unchecked Sendable {
    public static let shared = LocalProcessRunner()
    public static let maximumInputBytes = 4 * 1024
    public static let maximumOutputBytes = 64 * 1024

    public init() {}

    public func run(
        _ action: LocalAutomationAction,
        pid: pid_t? = nil,
        timeout: TimeInterval = 1
    ) throws -> LocalProcessResult {
        try LocalAutomationPolicy.authorize(action, role: .appInternalControl)
        let spec = try specification(for: action, pid: pid)
        return try execute(spec, timeout: timeout)
    }

    /// App-only terminal activation. The bundle identifier is validated before
    /// becoming the single data argument to the fixed `/usr/bin/open -b` call.
    public func activateTerminal(_ bundleIdentifier: String, timeout: TimeInterval = 1) throws -> LocalProcessResult {
        try LocalAutomationPolicy.authorize(.activateTerminal, role: .appInternalControl)
        let bundleIdentifier = try LocalAutomationPolicy.validateTerminalBundleIdentifier(bundleIdentifier)
        return try execute(.init(executable: "/usr/bin/open", arguments: ["-b", bundleIdentifier]), timeout: timeout)
    }

    public func runAppleScript(_ template: LocalAppleScriptTemplate, parameters: [String], timeout: TimeInterval = 1) throws -> LocalProcessResult {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/-"))
        guard parameters.count <= 3,
              parameters.allSatisfy({
                  !$0.isEmpty && !$0.hasPrefix("-") && $0.utf8.count <= 256
                      && $0.unicodeScalars.allSatisfy(allowed.contains)
              }) else {
            throw LocalAutomationPolicyError.invalidArgument
        }
        return try execute(.init(executable: "/usr/bin/osascript", arguments: ["-e", template.source, "--"] + parameters), timeout: timeout)
    }

    private struct Specification {
        let executable: String
        let arguments: [String]
    }

    private func specification(for action: LocalAutomationAction, pid: pid_t?) throws -> Specification {
        func decimalPID() throws -> String {
            guard let pid, pid > 1 else { throw LocalAutomationPolicyError.invalidArgument }
            return String(pid)
        }
        switch action {
        case .inspectProcessSnapshot:
            return .init(executable: "/bin/ps", arguments: ["-Ao", "pid=,ppid=,tty=,command="])
        case .inspectProcessParent:
            return .init(executable: "/bin/ps", arguments: ["-o", "ppid=", "-p", try decimalPID()])
        case .inspectProcessCommand:
            return .init(executable: "/bin/ps", arguments: ["-o", "command=", "-p", try decimalPID()])
        case .inspectOpenFiles:
            return .init(executable: "/usr/sbin/lsof", arguments: ["-a", "-p", try decimalPID(), "-Fn"])
        case .inspectChildProcesses:
            return .init(executable: "/usr/bin/pgrep", arguments: ["-P", try decimalPID()])
        case .activateTerminal, .revealLocalFile:
            throw LocalAutomationPolicyError.unsupportedAction
        }
    }

    private func execute(_ spec: Specification, timeout: TimeInterval) throws -> LocalProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: spec.executable)
        process.arguments = spec.arguments
        process.environment = [:]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        let output = Pipe(); let errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        let captured = CapturedOutput()
        output.fileHandleForReading.readabilityHandler = { handle in
            captured.append(handle.availableData, toStandardError: false, limit: Self.maximumOutputBytes)
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            captured.append(handle.availableData, toStandardError: true, limit: Self.maximumOutputBytes)
        }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        // `Process` does not expose setpgid; set it immediately after exec and
        // fail closed if it cannot be made an isolated group.
        guard setpgid(process.processIdentifier, process.processIdentifier) == 0 || errno == EACCES else {
            process.terminate(); throw LocalAutomationPolicyError.unsupportedAction
        }
        let result = finished.wait(timeout: .now() + timeout)
        let didOverflow = captured.didOverflow
        if result == .timedOut || didOverflow {
            _ = kill(-process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 0.2)
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            if didOverflow { throw LocalAutomationPolicyError.outputLimitExceeded }
            throw LocalAutomationPolicyError.timedOut
        }
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        captured.append(output.fileHandleForReading.readDataToEndOfFile(), toStandardError: false, limit: Self.maximumOutputBytes)
        captured.append(errors.fileHandleForReading.readDataToEndOfFile(), toStandardError: true, limit: Self.maximumOutputBytes)
        let (stdout, stderr) = captured.values
        guard stdout.count <= Self.maximumOutputBytes, stderr.count <= Self.maximumOutputBytes else {
            throw LocalAutomationPolicyError.outputLimitExceeded
        }
        guard process.terminationStatus == 0 || actionAllowsNoMatches(spec) else {
            throw LocalAutomationPolicyError.processFailed(process.terminationStatus)
        }
        return .init(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func actionAllowsNoMatches(_ spec: Specification) -> Bool { spec.executable == "/usr/bin/pgrep" }

    private final class CapturedOutput: @unchecked Sendable {
        private let lock = NSLock()
        private var stdout = Data()
        private var stderr = Data()
        private var overflow = false

        func append(_ data: Data, toStandardError: Bool, limit: Int) {
            guard !data.isEmpty else { return }
            lock.lock(); defer { lock.unlock() }
            if overflow { return }
            if toStandardError {
                guard data.count <= limit - stderr.count else { overflow = true; return }
                stderr.append(data)
            } else {
                guard data.count <= limit - stdout.count else { overflow = true; return }
                stdout.append(data)
            }
        }

        var didOverflow: Bool { lock.lock(); defer { lock.unlock() }; return overflow }
        var values: (Data, Data) { lock.lock(); defer { lock.unlock() }; return (stdout, stderr) }
    }
}
