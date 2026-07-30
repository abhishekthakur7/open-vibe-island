#if HALO_PARITY_TESTING
import CryptoKit
import Foundation
import OpenIslandCore

enum HaloParityFixtureBase: String, Codable, Sendable {
    case emptyClosed
    case emptyOpened
    case oneRunningClosed
    case threeRunningClosed
    case permissionClosed
    case questionClosed
    case successClosed
    case interruptedClosed
    case failedClosed
    case permissionPeek
    case subagentsClosed
    case criticalUsageClosed
    case stateGroupedList
    case expandedSubagents
    case permissionCommand
    case permissionDiff
    case terminalApproval
    case questionPageOne
    case questionPageTwo
    case compactQuestion
    case successDetail
    case interruptedDetail
    case failedDetail
    case usageMeters
    case duplicates
    case longContent
    case overflow
}

/// Codable description of the exact deterministic payload used by a native
/// scenario. It deliberately records semantic state separately from its base
/// fixture: meta/motion/profile scenarios may share pixels at a checkpoint,
/// but never alias without provenance.
struct HaloParityFixtureRecord: Codable, Equatable, Sendable {
    let scenario: HaloParityScenarioID
    let base: HaloParityFixtureBase
    let variant: String
    let fixtureSeed: UInt64
    let sessionCount: Int
    let phaseCounts: [String: Int]
    let grouping: [String]
    let order: [String]
    let visibleCopy: [String]
    let state: [String: String]
    let provenance: [String]
    let dataHash: String

    fileprivate init(
        scenario: HaloParityScenarioID,
        base: HaloParityFixtureBase,
        variant: String,
        fixtureSeed: UInt64,
        sessionCount: Int,
        phaseCounts: [String: Int],
        grouping: [String],
        order: [String],
        visibleCopy: [String],
        state: [String: String],
        provenance: [String]
    ) {
        self.scenario = scenario
        self.base = base
        self.variant = variant
        self.fixtureSeed = fixtureSeed
        self.sessionCount = sessionCount
        self.phaseCounts = phaseCounts
        self.grouping = grouping
        self.order = order
        self.visibleCopy = visibleCopy
        self.state = state
        self.provenance = provenance

        struct HashInput: Encodable {
            let scenario: HaloParityScenarioID
            let base: HaloParityFixtureBase
            let variant: String
            let fixtureSeed: UInt64
            let sessionCount: Int
            let phaseCounts: [String: Int]
            let grouping: [String]
            let order: [String]
            let visibleCopy: [String]
            let state: [String: String]
            let provenance: [String]
        }
        let input = HashInput(
            scenario: scenario,
            base: base,
            variant: variant,
            fixtureSeed: fixtureSeed,
            sessionCount: sessionCount,
            phaseCounts: phaseCounts,
            grouping: grouping,
            order: order,
            visibleCopy: visibleCopy,
            state: state,
            provenance: provenance
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(input)) ?? Data()
        self.dataHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct HaloParityResolvedFixture {
    let record: HaloParityFixtureRecord
    let snapshot: IslandDebugSnapshot
}

enum HaloParityFixtureCatalog {
    static let schemaVersion = "gate-0a-native-fixtures-v1"
    static let fixedEpoch = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z

    static func record(for scenario: HaloParityScenarioID, seed: UInt64) -> HaloParityFixtureRecord {
        let specification = specification(for: scenario)
        return HaloParityFixtureRecord(
            scenario: scenario,
            base: specification.base,
            variant: specification.variant,
            fixtureSeed: seed,
            sessionCount: specification.sessionCount,
            phaseCounts: specification.phaseCounts,
            grouping: specification.grouping,
            order: specification.order,
            visibleCopy: specification.copy,
            state: specification.state,
            provenance: specification.provenance
        )
    }

    static func resolve(
        configuration: HaloParityConfiguration,
        language: LanguageManager = .shared
    ) -> HaloParityResolvedFixture {
        let record = record(for: configuration.scenario, seed: configuration.seed)
        let now = fixedEpoch.addingTimeInterval(TimeInterval(configuration.seed % 86_400))
        return HaloParityResolvedFixture(
            record: record,
            snapshot: snapshot(
                base: record.base,
                scenario: configuration.scenario,
                now: now,
                language: language
            )
        )
    }

    private struct Specification {
        var base: HaloParityFixtureBase
        var variant: String
        var sessionCount: Int
        var phaseCounts: [String: Int]
        var grouping: [String] = []
        var order: [String] = []
        var copy: [String] = []
        var state: [String: String] = [:]
        var provenance: [String] = []
    }

    private static func specification(for id: HaloParityScenarioID) -> Specification {
        var spec = Specification(
            base: .stateGroupedList,
            variant: id.rawValue,
            sessionCount: 6,
            phaseCounts: ["waiting": 2, "running": 2, "done": 2],
            provenance: ["typed-manifest:\(id.rawValue)", schemaVersion]
        )

        switch id {
        case .a1, .jPrime, .kIdle, .stressCount0:
            spec.base = .emptyClosed
            spec.sessionCount = 0
            spec.phaseCounts = [:]
            spec.order = ["idle glyph", "camera dead-zone", "idle dot"]
            spec.state = ["ambient": "idle", "presentation": "closed"]
        case .a2, .kOrbit, .kGlyph, .stressCount1:
            spec.base = .oneRunningClosed
            spec.sessionCount = 1
            spec.phaseCounts = ["running": 1]
            spec.copy = ["Editing AppModel.swift"]
            spec.order = ["running glyph", "Editing", "AppModel.swift"]
            spec.state = ["ambient": "working", "workingCount": "1"]
        case .a2Prime, .stressCountMany:
            spec.base = .threeRunningClosed
            spec.sessionCount = 3
            spec.phaseCounts = ["running": 3]
            spec.copy = ["3 working"]
            spec.order = ["running glyph", "3 working", "six-cell agents grid"]
            spec.state = ["gridOnMap": "1,1,0,1,0,0"]
        case .a3, .kCondense:
            spec.base = .permissionClosed
            spec.sessionCount = 1
            spec.phaseCounts = ["waitingForApproval": 1]
            spec.copy = ["Approve swift build?", "1"]
            spec.state = ["ambient": "permission"]
        case .a4:
            spec.base = .questionClosed
            spec.sessionCount = 1
            spec.phaseCounts = ["waitingForAnswer": 1]
            spec.copy = ["Answer needed", "?"]
            spec.state = ["ambient": "question"]
        case .a5, .kSuccess:
            spec.base = .successClosed
            spec.sessionCount = 1
            spec.phaseCounts = ["success": 1]
            spec.copy = ["Done · the-automator"]
            spec.state = ["event": "fresh-success", "settlesTo": "idle"]
        case .a6Interrupted:
            spec.base = .interruptedClosed
            spec.sessionCount = 1
            spec.phaseCounts = ["interrupted": 1]
            spec.copy = ["Interrupted · niche-radar"]
            spec.state = ["ambient": "idle", "motion": "static"]
        case .a6Failed, .kFailure:
            spec.base = .failedClosed
            spec.sessionCount = 1
            spec.phaseCounts = ["failed": 1]
            spec.copy = ["Failed · open-vibe-island"]
            spec.state = ["ambient": "failure", "motion": "static"]
        case .b, .bPrime, .kMorph:
            spec.base = .permissionPeek
            spec.sessionCount = 3
            spec.phaseCounts = ["waitingForApproval": 1, "running": 2]
            spec.copy = ["the-automator wants to run a command", "swift build", "+2 more sessions"]
            spec.state = ["presentation": "closed-to-open", "variant": id.rawValue]
        case .c:
            spec.grouping = ["Needs you 2", "Running 2", "Done 2"]
            spec.order = ["Needs you", "Running", "Done"]
            spec.copy = ["6 total", "2 waiting", "2 running", "2 done", "Needs you", "Running", "Done"]
            spec.state = ["group": "state", "sort": "attention"]
        case .d:
            spec.base = .expandedSubagents
            spec.sessionCount = 1
            spec.phaseCounts = ["running": 1]
            spec.grouping = ["metadata grid", "assistant message", "actions"]
            spec.copy = ["Agent", "Model", "Permission", "Branch", "Duration", "Terminal", "Last message · Claude"]
            spec.state = ["expanded": "true"]
        case .eTravel, .e1:
            spec.base = .permissionCommand
            spec.sessionCount = 1
            spec.phaseCounts = ["waitingForApproval": 1]
            spec.copy = ["Permission needed", "Allow once ⌘Y", "Deny ⌘N"]
            spec.state = ["hero": "command", "event": id == .eTravel ? "light-travel" : "settled"]
        case .e2:
            spec.base = .permissionDiff
            spec.sessionCount = 1
            spec.phaseCounts = ["waitingForApproval": 1]
            spec.copy = ["Approve file edit", "AGENTS.md · 2 changed", "Allow once ⌘Y", "Deny ⌘N"]
            spec.state = ["hero": "file-diff"]
        case .e3:
            spec.base = .terminalApproval
            spec.sessionCount = 1
            spec.phaseCounts = ["waitingForApproval": 1]
            spec.copy = ["Approval waiting", "Codex needs a decision — in-app only", "Jump to Codex"]
            spec.state = ["hero": "terminal-only", "fakeApprovalButtons": "false"]
        case .f1:
            spec.base = .questionPageOne
            spec.sessionCount = 1
            spec.phaseCounts = ["waitingForAnswer": 1]
            spec.copy = ["1 of 2", "Auth", "Which auth method should the bridge use?", "Next ↵"]
            spec.state = ["page": "1", "pageCount": "2", "multiSelect": "false"]
        case .f2:
            spec.base = .questionPageTwo
            spec.sessionCount = 1
            spec.phaseCounts = ["waitingForAnswer": 1]
            spec.copy = ["2 of 2", "Platforms", "multi-select", "Other… (type a freeform answer)", "Submit ↵"]
            spec.state = [
                "page": "2", "pageCount": "2", "multiSelect": "true",
                "selected": "1,2", "freeform": "", "submission": "pending",
            ]
        case .f3:
            spec.base = .compactQuestion
            spec.sessionCount = 1
            spec.phaseCounts = ["waitingForAnswer": 1]
            spec.copy = ["Continue past the failing test?", "Yes, skip it for now", "No, stop and let me look"]
            spec.state = ["questionChrome": "compact"]
        case .g, .gPrime:
            spec.base = id == .g ? .expandedSubagents : .subagentsClosed
            spec.sessionCount = 1
            spec.phaseCounts = ["running": 1]
            spec.copy = ["the-automator", "3 subagents", "Subagents", "3 active"]
            spec.state = [
                "subagents": "3", "tasksDone": "2", "tasksTotal": "5",
                "presentation": id == .g ? "opened" : "closed",
            ]
        case .hSuccess:
            spec.base = .successDetail
            spec.sessionCount = 1
            spec.phaseCounts = ["success": 1]
            spec.copy = ["Success", "Result", "Outcome", "Duration", "Model", "Finished", "Dismiss"]
            spec.state = ["outcome": "success", "presentation": "detail"]
        case .hInterrupted:
            spec.base = .interruptedDetail
            spec.sessionCount = 1
            spec.phaseCounts = ["interrupted": 1]
            spec.copy = ["Interrupted"]
            spec.state = ["outcome": "interrupted", "presentation": "detail"]
        case .hFailed:
            spec.base = .failedDetail
            spec.sessionCount = 1
            spec.phaseCounts = ["failed": 1]
            spec.copy = ["Failed"]
            spec.state = ["outcome": "failed", "presentation": "detail"]
        case .i, .iPrime:
            spec.base = id == .i ? .usageMeters : .criticalUsageClosed
            spec.sessionCount = id == .i ? 6 : 0
            spec.phaseCounts = id == .i ? ["waiting": 2, "running": 2, "done": 2] : [:]
            spec.copy = ["Claude · 5h", "34%", "Claude · 7d", "78%", "Codex · 7d · Pro", "94%"]
            spec.state = ["usage": id == .i ? "full" : "critical-compact", "reset": "19h"]
        case .j:
            spec.base = .emptyOpened
            spec.sessionCount = 0
            spec.phaseCounts = [:]
            spec.copy = ["All quiet", "Monitoring · 4 workspaces"]
            spec.state = ["presentation": "opened", "ambient": "idle"]
        case .kRow:
            spec.base = .stateGroupedList
            spec.state = ["event": "row-entrance", "motion": "one-shot"]
        case .stressLong:
            spec.base = .longContent
            spec.sessionCount = 1
            spec.phaseCounts = ["success": 1]
            spec.state = ["stress": "long-copy"]
        case .stressDuplicate:
            spec.base = .duplicates
            spec.sessionCount = 3
            spec.phaseCounts = ["running": 2, "done": 1]
            spec.state = ["workspace": "the-automator", "disambiguation": "branch-recency"]
        case .stressMissing:
            spec.base = .stateGroupedList
            spec.state = ["stress": "missing-metadata", "missing": "branch,model,terminal"]
        case .stressOverflow:
            spec.base = .overflow
            spec.sessionCount = 9
            spec.phaseCounts = ["waiting": 2, "running": 3, "done": 4]
            spec.state = ["stress": "overflow", "visible": "6", "overflow": "3"]
        case .stressUsage0:
            spec.base = .emptyOpened
            spec.sessionCount = 0
            spec.phaseCounts = [:]
            spec.state = ["usage": "zero"]
        case .stressUsageMissing:
            spec.base = .usageMeters
            spec.state = ["usage": "missing-reset"]
        case .stressAttentionRunning:
            spec.base = .stateGroupedList
            spec.state = ["priority": "permission>question>running"]
        case .stressQuestionPermission:
            spec.base = .stateGroupedList
            spec.state = ["priority": "permission>question"]
        case .stressIPrimeAttention:
            spec.base = .permissionClosed
            spec.sessionCount = 1
            spec.phaseCounts = ["waitingForApproval": 1]
            spec.state = ["priority": "attention>critical-usage"]
        case .accessibilityReduceMotion:
            spec.base = .stateGroupedList
            spec.state = ["accessibility": "reduce-motion"]
        case .accessibilityIncreaseContrast:
            spec.base = .stateGroupedList
            spec.state = ["accessibility": "increase-contrast"]
        case .accessibilityReduceTransparency:
            spec.base = .stateGroupedList
            spec.state = ["accessibility": "reduce-transparency"]
        case .accessibilityKeyboard:
            spec.base = .permissionCommand
            spec.sessionCount = 1
            spec.phaseCounts = ["waitingForApproval": 1]
            spec.state = ["accessibility": "keyboard", "focus": "allow-once"]
        case .accessibilityVoiceOver:
            spec.state = ["accessibility": "voiceover", "order": "header,rows,footer"]
        case .accessibilityText:
            spec.state = ["accessibility": "text-scale", "scale": "accessibility3"]
        case .displayNotch:
            spec.state = ["profile": "notch"]
        case .displayTopBar:
            spec.state = ["profile": "topbar"]
        case .responsive560:
            spec.state = ["width": "560", "overflowPolicy": "production"]
        }
        return spec
    }

    private static func snapshot(
        base: HaloParityFixtureBase,
        scenario: HaloParityScenarioID,
        now: Date,
        language: LanguageManager
    ) -> IslandDebugSnapshot {
        let preview = AppearancePreviewFixtures.sessions(now: now, lang: language)
        let running = preview.first { $0.phase == .running }!
        let trio = AppearancePreviewFixtures.duplicateWorkspaceTrio(now: now)
        var command = AppearancePreviewFixtures.permissionCommand(now: now)
        if scenario == .e1 || scenario == .eTravel {
            command.summary = "the-automator wants to run a command"
            command.title = "Claude · the-automator"
            command.jumpTarget?.workspaceName = "the-automator"
            command.claudeMetadata?.currentToolInputPreview = #"rtk grep -rn "fetch(" packages/ui/src"#
        }
        var question = AppearancePreviewFixtures.questionMulti(now: now)
        if scenario == .f1 || scenario == .f2 {
            question.title = "OpenCode · niche-radar"
            question.jumpTarget?.workspaceName = "niche-radar"
            question.questionPrompt = QuestionPrompt(
                id: AppearancePreviewFixtures.stableID("halo-parity-f1-f2"),
                title: "A question for you",
                questions: [
                    QuestionPromptItem(
                        question: "Which auth method should the bridge use?",
                        header: "Auth",
                        options: [
                            QuestionOption(label: "OAuth 2.0"),
                            QuestionOption(label: "API key"),
                            QuestionOption(label: "mTLS"),
                        ]
                    ),
                    QuestionPromptItem(
                        question: "Which platforms should CI test against?",
                        header: "Platforms",
                        options: [
                            QuestionOption(label: "macOS"),
                            QuestionOption(label: "Linux"),
                            QuestionOption(label: "Windows"),
                            QuestionOption(label: "Other", allowsFreeform: true),
                        ],
                        multiSelect: true
                    ),
                ]
            )
        }
        var success = AppearancePreviewFixtures.completedSuccess(now: now)
        if scenario == .hSuccess {
            success.title = "Claude · open-vibe-island"
            success.jumpTarget?.workspaceName = "open-vibe-island"
        }
        let interrupted = AppearancePreviewFixtures.completedInterrupted(now: now)
        let failed = AppearancePreviewFixtures.completedFailed(now: now)

        func make(
            title: String,
            opened: Bool,
            sessions: [AgentSession],
            actionable: String? = nil,
            expanded: Bool = false,
            usage: [UsageProviderPresentation]? = nil
        ) -> IslandDebugSnapshot {
            IslandDebugSnapshot(
                title: title,
                summary: "Deterministic Halo parity fixture",
                previewHeight: opened ? 520 : 78,
                notchStatus: opened ? .opened : .closed,
                notchOpenReason: opened ? (actionable == nil ? .click : .notification) : nil,
                islandSurface: .sessionList(actionableSessionID: actionable),
                sessions: sessions,
                selectedSessionID: actionable ?? sessions.first?.id,
                usageProviders: usage,
                forcesRowExpansion: expanded
            )
        }

        switch base {
        case .emptyClosed: return make(title: base.rawValue, opened: false, sessions: [])
        case .emptyOpened: return make(title: base.rawValue, opened: true, sessions: [])
        case .oneRunningClosed: return make(title: base.rawValue, opened: false, sessions: [running])
        case .threeRunningClosed:
            let sessions = trio.map { original in
                var session = original
                session.phase = .running
                session.outcome = .success
                return session
            }
            return make(title: base.rawValue, opened: false, sessions: sessions)
        case .permissionClosed: return make(title: base.rawValue, opened: false, sessions: [command])
        case .questionClosed: return make(title: base.rawValue, opened: false, sessions: [question])
        case .successClosed: return make(title: base.rawValue, opened: false, sessions: [success])
        case .interruptedClosed: return make(title: base.rawValue, opened: false, sessions: [interrupted])
        case .failedClosed: return make(title: base.rawValue, opened: false, sessions: [failed])
        case .permissionPeek:
            return make(title: base.rawValue, opened: false, sessions: [command, trio[0], trio[1]])
        case .subagentsClosed:
            var session = AppearancePreviewFixtures.subagentsAndTasks(now: now)
            session.title = "Claude · the-automator"
            session.jumpTarget?.workspaceName = "the-automator"
            return make(title: base.rawValue, opened: false, sessions: [session])
        case .criticalUsageClosed:
            return make(
                title: base.rawValue,
                opened: false,
                sessions: [],
                usage: exactUsageProviders(now: now)
            )
        case .stateGroupedList:
            var sessions = [command, question, trio[0], trio[1], success, interrupted]
            if scenario == .stressMissing {
                sessions = sessions.map { original in
                    var session = original
                    session.jumpTarget = nil
                    session.codexMetadata = nil
                    session.claudeMetadata = nil
                    session.cursorMetadata = nil
                    return session
                }
            }
            return make(title: base.rawValue, opened: true, sessions: sessions)
        case .expandedSubagents:
            var session = AppearancePreviewFixtures.subagentsAndTasks(now: now)
            session.title = "Claude · the-automator"
            session.jumpTarget?.workspaceName = "the-automator"
            session.summary = "Orchestrating the bridge-auth migration"
            return make(title: base.rawValue, opened: true, sessions: [session], expanded: true)
        case .permissionCommand:
            return make(title: base.rawValue, opened: true, sessions: [command], actionable: command.id)
        case .permissionDiff:
            let session = AppearancePreviewFixtures.permissionDiff(now: now)
            return make(title: base.rawValue, opened: true, sessions: [session], actionable: session.id)
        case .terminalApproval:
            var session = AppearancePreviewFixtures.codexTerminalApproval(now: now)
            session.codexMetadata?.currentCommandPreview = "git push --force-with-lease origin main"
            return make(title: base.rawValue, opened: true, sessions: [session], actionable: session.id)
        case .questionPageOne, .questionPageTwo:
            return make(title: base.rawValue, opened: true, sessions: [question], actionable: question.id)
        case .compactQuestion:
            var session = IslandDebugScenario.questionCard.snapshot(at: now).sessions[0]
            session.summary = "Continue past the failing test?"
            session.questionPrompt = QuestionPrompt(
                id: AppearancePreviewFixtures.stableID("halo-parity-f3"),
                title: "Continue past the failing test?",
                questions: [
                    QuestionPromptItem(
                        question: "Continue past the failing test?",
                        header: "",
                        options: [
                            QuestionOption(label: "Yes, skip it for now"),
                            QuestionOption(label: "No, stop and let me look"),
                        ]
                    )
                ]
            )
            return make(title: base.rawValue, opened: true, sessions: [session], actionable: session.id)
        case .successDetail:
            return make(title: base.rawValue, opened: true, sessions: [success], actionable: success.id)
        case .interruptedDetail:
            return make(title: base.rawValue, opened: true, sessions: [interrupted], actionable: interrupted.id)
        case .failedDetail:
            return make(title: base.rawValue, opened: true, sessions: [failed], actionable: failed.id)
        case .usageMeters:
            let sessions = [command, question, trio[0], trio[1], success, interrupted]
            return make(
                title: base.rawValue,
                opened: true,
                sessions: sessions,
                usage: exactUsageProviders(now: now, missingReset: scenario == .stressUsageMissing)
            )
        case .duplicates:
            return make(title: base.rawValue, opened: true, sessions: trio)
        case .longContent:
            var session = success
            session.id = "halo-parity-long-content"
            session.summary = String(repeating: "Deterministic long completion copy. ", count: 32)
            session.claudeMetadata?.lastAssistantMessage = String(
                repeating: "Verified the isolated fixture without reading user session data. ",
                count: 40
            )
            return make(title: base.rawValue, opened: true, sessions: [session], actionable: session.id)
        case .overflow:
            let sessions = [
                command, question, trio[0], trio[1], trio[2], running,
                success, interrupted, failed,
            ]
            return make(title: base.rawValue, opened: true, sessions: sessions)
        }
    }

    private static func exactUsageProviders(
        now: Date,
        missingReset: Bool = false
    ) -> [UsageProviderPresentation] {
        [
            UsageProviderPresentation(
                id: "claude",
                title: "Claude",
                windows: [
                    UsageWindowPresentation(
                        id: "claude-5h",
                        label: "5h",
                        usedPercentage: 34,
                        resetsAt: missingReset ? nil : now.addingTimeInterval(2 * 3_600 + 10 * 60)
                    ),
                    UsageWindowPresentation(
                        id: "claude-7d",
                        label: "7d",
                        usedPercentage: 78,
                        resetsAt: missingReset ? nil : now.addingTimeInterval(3 * 86_400 + 4 * 3_600)
                    ),
                ]
            ),
            UsageProviderPresentation(
                id: "codex-pro",
                title: "Codex · Pro",
                windows: [
                    UsageWindowPresentation(
                        id: "codex-7d-pro",
                        label: "7d",
                        usedPercentage: 94,
                        resetsAt: missingReset ? nil : now.addingTimeInterval(19 * 3_600)
                    ),
                ]
            ),
        ]
    }
}
#endif
