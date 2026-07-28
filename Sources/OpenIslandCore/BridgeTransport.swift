import Darwin
import Foundation

public enum BridgeSocketLocation {
    /// Stable per-user directory under ~/Library/Application Support/OpenIsland.
    /// Unlike /tmp, this directory is owner-writable only and not subject to
    /// periodic system cleanup. Shared by the bridge socket and other local
    /// caches so they stay out of world-writable /tmp.
    static var stableDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("OpenIsland")
    }

    public static var defaultURL: URL {
        stableDirectoryURL.appendingPathComponent("bridge.sock")
    }

    public static func uniqueTestURL() -> URL {
        // Tests use the system-provided private temporary directory solely to
        // stay under the AF_UNIX path limit; production always uses the
        // app-owned Application Support directory above.
        let temporaryPath = FileManager.default.temporaryDirectory.path
        // Darwin exposes /var as a compatibility symlink to /private/var.
        // Exercise the same no-symlink path validation as production tests.
        let physicalTemporaryPath = temporaryPath.hasPrefix("/var/")
            ? "/private" + temporaryPath
            : temporaryPath
        return URL(fileURLWithPath: physicalTemporaryPath, isDirectory: true)
            .appendingPathComponent("oi-\(UUID().uuidString.prefix(8))", isDirectory: true)
            .appendingPathComponent("bridge.sock")
    }
}

public enum BridgeTransportError: Error, LocalizedError {
    case alreadyConnected
    case notConnected
    case malformedEnvelope
    case responseTimedOut
    case listenerFailed(String)
    case socketPathTooLong
    case bootstrapUnavailable
    case peerIdentityUnavailable
    case unauthorized
    case protocolUpgradeRequired
    case frameTooLarge
    case unsafeSocketPath(String)
    case systemCallFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .alreadyConnected:
            "The bridge client is already connected."
        case .notConnected:
            "The bridge client is not connected."
        case .malformedEnvelope:
            "The bridge transport received malformed data."
        case .responseTimedOut:
            "The local bridge timed out while waiting for a response."
        case let .listenerFailed(message):
            "The local bridge listener failed: \(message)"
        case .socketPathTooLong:
            "The Unix socket path is too long for `sockaddr_un`."
        case .bootstrapUnavailable:
            "Local bridge bootstrap material is unavailable. Reinstall or reset the Open Island integration."
        case .peerIdentityUnavailable:
            "The local bridge could not verify the connecting process."
        case .unauthorized:
            "The local bridge denied this operation for the authenticated role."
        case .protocolUpgradeRequired:
            "This local bridge client is outdated. Reinstall Open Island hooks and try again."
        case .frameTooLarge:
            "The local bridge frame exceeds the maximum permitted size."
        case let .unsafeSocketPath(path):
            "The local bridge left unsafe existing socket path untouched: \(path)"
        case let .systemCallFailed(name, code):
            "\(name) failed with errno \(code)."
        }
    }
}

public struct BridgeHello: Equatable, Codable, Sendable {
    public var protocolVersion: Int
    public var serverLabel: String
    public var serverNonce: String

    public init(protocolVersion: Int = 2, serverLabel: String = "local-bridge", serverNonce: String = UUID().uuidString) {
        self.protocolVersion = protocolVersion
        self.serverLabel = serverLabel
        self.serverNonce = serverNonce
    }
}

public struct BridgeAuthentication: Equatable, Codable, Sendable {
    public let protocolVersion: Int
    public let role: BridgeClientRole
    public let clientNonce: String
    public let proof: Data
    public init(protocolVersion: Int = 2, role: BridgeClientRole, clientNonce: String, proof: Data) {
        self.protocolVersion = protocolVersion; self.role = role; self.clientNonce = clientNonce; self.proof = proof
    }
}

public struct BridgeCapability: Equatable, Codable, Sendable {
    public let protocolVersion: Int
    public let token: String
    public let role: BridgeClientRole
    public let expiresAt: Date
    public init(protocolVersion: Int = 2, token: String, role: BridgeClientRole, expiresAt: Date) { self.protocolVersion = protocolVersion; self.token = token; self.role = role; self.expiresAt = expiresAt }
}

public enum BridgeCommand: Equatable, Codable, Sendable {
    case registerClient(role: BridgeClientRole)
    case requestQuestion(sessionID: String, prompt: QuestionPrompt)
    case resolvePermission(sessionID: String, resolution: PermissionResolution)
    case answerQuestion(sessionID: String, response: QuestionPromptResponse)
    case processCodexHook(CodexHookPayload)
    case processClaudeHook(ClaudeHookPayload)
    case processOpenCodeHook(OpenCodeHookPayload)
    case processCursorHook(CursorHookPayload)
    case processGeminiHook(GeminiHookPayload)

    private enum CodingKeys: String, CodingKey {
        case type
        case role
        case sessionID
        case prompt
        case resolution
        case response
        case codexHook
        case claudeHook
        case openCodeHook
        case cursorHook
        case geminiHook
    }

    private enum CommandType: String, Codable {
        case registerClient
        case requestQuestion
        case resolvePermission
        case answerQuestion
        case processCodexHook
        case processClaudeHook
        case processOpenCodeHook
        case processCursorHook
        case processGeminiHook
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CommandType.self, forKey: .type)

        switch type {
        case .registerClient:
            self = .registerClient(role: try container.decode(BridgeClientRole.self, forKey: .role))
        case .requestQuestion:
            self = .requestQuestion(
                sessionID: try container.decode(String.self, forKey: .sessionID),
                prompt: try container.decode(QuestionPrompt.self, forKey: .prompt)
            )
        case .resolvePermission:
            self = .resolvePermission(
                sessionID: try container.decode(String.self, forKey: .sessionID),
                resolution: try container.decode(PermissionResolution.self, forKey: .resolution)
            )
        case .answerQuestion:
            self = .answerQuestion(
                sessionID: try container.decode(String.self, forKey: .sessionID),
                response: try container.decode(QuestionPromptResponse.self, forKey: .response)
            )
        case .processCodexHook:
            self = .processCodexHook(try container.decode(CodexHookPayload.self, forKey: .codexHook))
        case .processClaudeHook:
            self = .processClaudeHook(try container.decode(ClaudeHookPayload.self, forKey: .claudeHook))
        case .processOpenCodeHook:
            self = .processOpenCodeHook(try container.decode(OpenCodeHookPayload.self, forKey: .openCodeHook))
        case .processCursorHook:
            self = .processCursorHook(try container.decode(CursorHookPayload.self, forKey: .cursorHook))
        case .processGeminiHook:
            self = .processGeminiHook(try container.decode(GeminiHookPayload.self, forKey: .geminiHook))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .registerClient(role):
            try container.encode(CommandType.registerClient, forKey: .type)
            try container.encode(role, forKey: .role)
        case let .requestQuestion(sessionID, prompt):
            try container.encode(CommandType.requestQuestion, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(prompt, forKey: .prompt)
        case let .resolvePermission(sessionID, resolution):
            try container.encode(CommandType.resolvePermission, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(resolution, forKey: .resolution)
        case let .answerQuestion(sessionID, response):
            try container.encode(CommandType.answerQuestion, forKey: .type)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(response, forKey: .response)
        case let .processCodexHook(payload):
            try container.encode(CommandType.processCodexHook, forKey: .type)
            try container.encode(payload, forKey: .codexHook)
        case let .processClaudeHook(payload):
            try container.encode(CommandType.processClaudeHook, forKey: .type)
            try container.encode(payload, forKey: .claudeHook)
        case let .processOpenCodeHook(payload):
            try container.encode(CommandType.processOpenCodeHook, forKey: .type)
            try container.encode(payload, forKey: .openCodeHook)
        case let .processCursorHook(payload):
            try container.encode(CommandType.processCursorHook, forKey: .type)
            try container.encode(payload, forKey: .cursorHook)
        case let .processGeminiHook(payload):
            try container.encode(CommandType.processGeminiHook, forKey: .type)
            try container.encode(payload, forKey: .geminiHook)
        }
    }
}

public enum BridgeResponse: Equatable, Codable, Sendable {
    case acknowledged
    case authenticated(BridgeCapability)
    case protocolUpgradeRequired
    case denied
    case codexHookDirective(CodexHookDirective)
    case claudeHookDirective(ClaudeHookDirective)
    case openCodeHookDirective(OpenCodeHookDirective)
    case cursorHookDirective(CursorHookDirective)

    private enum CodingKeys: String, CodingKey {
        case type
        case directive
        case capability
    }

    private enum ResponseType: String, Codable {
        case acknowledged
        case codexHookDirective
        case claudeHookDirective
        case openCodeHookDirective
        case cursorHookDirective
        case authenticated
        case protocolUpgradeRequired
        case denied
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ResponseType.self, forKey: .type)

        switch type {
        case .acknowledged:
            self = .acknowledged
        case .authenticated:
            self = .authenticated(try container.decode(BridgeCapability.self, forKey: .capability))
        case .protocolUpgradeRequired:
            self = .protocolUpgradeRequired
        case .denied:
            self = .denied
        case .codexHookDirective:
            self = .codexHookDirective(try container.decode(CodexHookDirective.self, forKey: .directive))
        case .claudeHookDirective:
            self = .claudeHookDirective(try container.decode(ClaudeHookDirective.self, forKey: .directive))
        case .openCodeHookDirective:
            self = .openCodeHookDirective(try container.decode(OpenCodeHookDirective.self, forKey: .directive))
        case .cursorHookDirective:
            self = .cursorHookDirective(try container.decode(CursorHookDirective.self, forKey: .directive))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .acknowledged:
            try container.encode(ResponseType.acknowledged, forKey: .type)
        case let .authenticated(capability):
            try container.encode(ResponseType.authenticated, forKey: .type)
            try container.encode(capability, forKey: .capability)
        case .protocolUpgradeRequired:
            try container.encode(ResponseType.protocolUpgradeRequired, forKey: .type)
        case .denied:
            try container.encode(ResponseType.denied, forKey: .type)
        case let .codexHookDirective(directive):
            try container.encode(ResponseType.codexHookDirective, forKey: .type)
            try container.encode(directive, forKey: .directive)
        case let .claudeHookDirective(directive):
            try container.encode(ResponseType.claudeHookDirective, forKey: .type)
            try container.encode(directive, forKey: .directive)
        case let .openCodeHookDirective(directive):
            try container.encode(ResponseType.openCodeHookDirective, forKey: .type)
            try container.encode(directive, forKey: .directive)
        case let .cursorHookDirective(directive):
            try container.encode(ResponseType.cursorHookDirective, forKey: .type)
            try container.encode(directive, forKey: .directive)
        }
    }
}

public enum BridgeEnvelope: Equatable, Codable, Sendable {
    case hello(BridgeHello)
    case authenticate(BridgeAuthentication)
    case event(AgentEvent)
    case command(BridgeCommand)
    case response(BridgeResponse)

    private enum CodingKeys: String, CodingKey {
        case type
        case hello
        case event
        case command
        case response
        case authentication
    }

    private enum EnvelopeType: String, Codable {
        case hello
        case event
        case command
        case response
        case authenticate
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EnvelopeType.self, forKey: .type)

        switch type {
        case .hello:
            self = .hello(try container.decode(BridgeHello.self, forKey: .hello))
        case .event:
            self = .event(try container.decode(AgentEvent.self, forKey: .event))
        case .command:
            self = .command(try container.decode(BridgeCommand.self, forKey: .command))
        case .response:
            self = .response(try container.decode(BridgeResponse.self, forKey: .response))
        case .authenticate:
            self = .authenticate(try container.decode(BridgeAuthentication.self, forKey: .authentication))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .hello(payload):
            try container.encode(EnvelopeType.hello, forKey: .type)
            try container.encode(payload, forKey: .hello)
        case let .authenticate(payload):
            try container.encode(EnvelopeType.authenticate, forKey: .type)
            try container.encode(payload, forKey: .authentication)
        case let .event(payload):
            try container.encode(EnvelopeType.event, forKey: .type)
            try container.encode(payload, forKey: .event)
        case let .command(payload):
            try container.encode(EnvelopeType.command, forKey: .type)
            try container.encode(payload, forKey: .command)
        case let .response(payload):
            try container.encode(EnvelopeType.response, forKey: .type)
            try container.encode(payload, forKey: .response)
        }
    }
}

public enum BridgeCodec {
    private static let newline = UInt8(ascii: "\n")
    public static let maximumFrameBytes = 256 * 1024
    public static let maximumJSONDepth = 64

    public static func encodeLine(_ envelope: BridgeEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970

        var data = try encoder.encode(envelope)
        guard data.count <= maximumFrameBytes else { throw BridgeTransportError.frameTooLarge }
        data.append(newline)
        return data
    }

    public static func decodeLines(from buffer: inout Data) throws -> [BridgeEnvelope] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        var messages: [BridgeEnvelope] = []

        while let newlineIndex = buffer.firstIndex(of: newline) {
            let line = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)

            guard line.count <= maximumFrameBytes else { throw BridgeTransportError.frameTooLarge }

            guard !line.isEmpty else {
                continue
            }

            guard jsonDepth(of: line) <= maximumJSONDepth else {
                throw BridgeTransportError.malformedEnvelope
            }

            do {
                let message = try decoder.decode(BridgeEnvelope.self, from: Data(line))
                messages.append(message)
            } catch {
                throw BridgeTransportError.malformedEnvelope
            }
        }

        guard buffer.count <= maximumFrameBytes else { throw BridgeTransportError.frameTooLarge }

        return messages
    }

    /// JSONDecoder has no public nesting limit.  Preflight the framed bytes so
    /// a tiny, deeply nested document cannot consume unbounded decoder stack.
    private static func jsonDepth(of bytes: Data) -> Int {
        var depth = 0
        var maximum = 0
        var inString = false
        var escaped = false
        for byte in bytes {
            if inString {
                if escaped { escaped = false }
                else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1; maximum = max(maximum, depth)
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                if depth < 0 { return maximumJSONDepth + 1 }
            default: break
            }
        }
        return inString || depth != 0 ? maximumJSONDepth + 1 : maximum
    }
}

func withUnixSocketAddress<T>(
    path: String,
    _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
) throws -> T {
    var address = sockaddr_un()
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = Array(path.utf8)
    let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)

    guard pathBytes.count < maxPathLength else {
        throw BridgeTransportError.socketPathTooLong
    }

    withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
        rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)

        for (index, byte) in pathBytes.enumerated() {
            rawBuffer[index] = byte
        }
    }

    let length = socklen_t(
        MemoryLayout.size(ofValue: address.sun_len) +
        MemoryLayout.size(ofValue: address.sun_family) +
        pathBytes.count + 1
    )

    return try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            try body(sockaddrPointer, length)
        }
    }
}

func makeSocketNonBlocking(_ fileDescriptor: Int32) throws {
    let currentFlags = fcntl(fileDescriptor, F_GETFL)
    guard currentFlags != -1 else {
        throw BridgeTransportError.systemCallFailed("fcntl(F_GETFL)", errno)
    }

    guard fcntl(fileDescriptor, F_SETFL, currentFlags | O_NONBLOCK) != -1 else {
        throw BridgeTransportError.systemCallFailed("fcntl(F_SETFL)", errno)
    }
}

func disableSocketSigPipe(_ fileDescriptor: Int32) throws {
    var enabled: Int32 = 1
    guard setsockopt(
        fileDescriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &enabled,
        socklen_t(MemoryLayout<Int32>.size)
    ) != -1 else {
        throw BridgeTransportError.systemCallFailed("setsockopt(SO_NOSIGPIPE)", errno)
    }
}

func writeAll(_ data: Data, to fileDescriptor: Int32) throws {
    var remaining = data[...]

    while !remaining.isEmpty {
        let bytesWritten = remaining.withUnsafeBytes { rawBuffer -> Int in
            let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return write(fileDescriptor, baseAddress, rawBuffer.count)
        }

        if bytesWritten > 0 {
            remaining.removeFirst(bytesWritten)
            continue
        }

        if bytesWritten == -1 && (errno == EAGAIN || errno == EWOULDBLOCK) {
            usleep(1_000)
            continue
        }

        throw BridgeTransportError.systemCallFailed("write", errno)
    }
}
