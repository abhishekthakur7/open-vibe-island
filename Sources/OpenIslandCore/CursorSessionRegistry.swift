import Foundation

public struct CursorTrackedSessionRecord: Equatable, Codable, Sendable {
    public var sessionID: String
    public var title: String
    public var origin: SessionOrigin?
    public var attachmentState: SessionAttachmentState
    public var summary: String
    public var phase: SessionPhase
    /// Optional so legacy records (saved before `AgentSession.outcome`
    /// existed) decode cleanly; `session` falls back to `.success`.
    public var outcome: SessionOutcome?
    public var updatedAt: Date
    public var jumpTarget: JumpTarget?
    public var cursorMetadata: CursorSessionMetadata?

    public init(
        sessionID: String,
        title: String,
        origin: SessionOrigin? = nil,
        attachmentState: SessionAttachmentState = .stale,
        summary: String,
        phase: SessionPhase,
        outcome: SessionOutcome? = nil,
        updatedAt: Date,
        jumpTarget: JumpTarget? = nil,
        cursorMetadata: CursorSessionMetadata? = nil
    ) {
        self.sessionID = sessionID
        self.title = title
        self.origin = origin
        self.attachmentState = attachmentState
        self.summary = summary
        self.phase = phase
        self.outcome = outcome
        self.updatedAt = updatedAt
        self.jumpTarget = jumpTarget
        self.cursorMetadata = cursorMetadata
    }

    public init(session: AgentSession) {
        self.init(
            sessionID: session.id,
            title: session.title,
            origin: session.origin,
            attachmentState: session.attachmentState,
            summary: session.summary,
            phase: session.phase,
            outcome: session.outcome,
            updatedAt: session.updatedAt,
            jumpTarget: session.jumpTarget,
            cursorMetadata: session.cursorMetadata
        )
    }

    public var session: AgentSession {
        AgentSession(
            id: sessionID,
            title: title,
            tool: .cursor,
            origin: origin,
            attachmentState: attachmentState,
            phase: phase,
            outcome: outcome ?? .success,
            summary: summary,
            updatedAt: updatedAt,
            jumpTarget: jumpTarget,
            cursorMetadata: cursorMetadata
        )
    }

    public var restorableSession: AgentSession {
        var session = session
        session.attachmentState = .stale
        return session
    }
}

public extension CursorTrackedSessionRecord {
    var shouldRestoreToLiveState: Bool {
        origin != .demo
    }
}

public final class CursorSessionRegistry: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public static var defaultDirectoryURL: URL {
        CodexSessionStore.defaultDirectoryURL
    }

    public static var defaultFileURL: URL {
        defaultDirectoryURL.appendingPathComponent("cursor-session-registry.json")
    }

    public init(
        fileURL: URL = CursorSessionRegistry.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load(referenceDate: Date = .now) throws -> [CursorTrackedSessionRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        if let metadata = try LocalDataLifecycle.readMetadata(from: fileURL, fileManager: fileManager, referenceDate: referenceDate) {
            let active = metadata.filter { !$0.isExpired(referenceDate: referenceDate) }
            if active.count != metadata.count {
                try LocalDataLifecycle.writeMetadata(active, to: fileURL, fileManager: fileManager, referenceDate: referenceDate)
            }
            return active.map(Self.record(from:))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode([CursorTrackedSessionRecord].self, from: Data(contentsOf: fileURL))
        let metadata = legacy.map(Self.metadata(from:)).filter { !$0.isExpired(referenceDate: referenceDate) }
        try LocalDataLifecycle.writeMetadata(metadata, to: fileURL, fileManager: fileManager, referenceDate: referenceDate)
        return metadata.map(Self.record(from:))
    }

    public func save(_ records: [CursorTrackedSessionRecord], referenceDate: Date = .now) throws {
        try LocalDataLifecycle.writeMetadata(records.map(Self.metadata(from:)), to: fileURL, fileManager: fileManager, referenceDate: referenceDate)
    }

    private static func metadata(from record: CursorTrackedSessionRecord) -> PersistedSessionMetadata {
        PersistedSessionMetadata(sessionID: record.sessionID, origin: record.origin, attachmentState: record.attachmentState, phase: record.phase, outcome: record.outcome, updatedAt: record.updatedAt)
    }

    private static func record(from metadata: PersistedSessionMetadata) -> CursorTrackedSessionRecord {
        CursorTrackedSessionRecord(sessionID: metadata.sessionID, title: "Recent Cursor session", origin: metadata.origin, attachmentState: metadata.attachmentState, summary: "", phase: metadata.phase, outcome: metadata.outcome, updatedAt: metadata.updatedAt)
    }
}
