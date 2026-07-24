import Foundation
import OpenIslandCore

enum SpotlightActivityTone {
    case live
    case idle
    case ready
    case attention
}

enum IslandSessionPresence: Equatable {
    case running
    case active
    case inactive
}

extension AgentSession {
    private static let collapsedDetailAgeThreshold: TimeInterval = 20 * 60
    private static let islandActivityThreshold: TimeInterval = 20 * 60
    static let staleCompletedDisplayThreshold: TimeInterval = 5 * 60

    /// Whether this session represents a subagent (worktree agent) that should
    /// not appear as a separate entry in the session list.  The parent session
    /// already tracks subagents via `claudeMetadata.activeSubagents`.
    ///
    /// Note: `claudeMetadata.agentID` is NOT a reliable signal here because
    /// SubagentStart hooks set `agent_id` on the *parent* session's metadata.
    var isSubagentSession: Bool {
        if let path = claudeMetadata?.transcriptPath, path.contains("/subagents/") {
            return true
        }
        return false
    }

    var islandActivityDate: Date {
        updatedAt
    }

    var spotlightPrimaryText: String {
        if let request = permissionRequest {
            return request.summary
        }

        if let prompt = questionPrompt {
            return prompt.title
        }

        if let assistantMessage = lastAssistantMessageText?.trimmedForSurface,
           !assistantMessage.isEmpty {
            return assistantMessage
        }

        return summary
    }

    var spotlightSecondaryText: String? {
        if let request = permissionRequest {
            return request.affectedPath.isEmpty ? nil : request.affectedPath
        }

        if let currentTool = displayCurrentToolName {
            return phase == .completed
                ? summary
                : "Running \(currentTool)"
        }

        let normalizedPrimary = spotlightPrimaryText.trimmedForSurface
        let normalizedSummary = summary.trimmedForSurface
        guard normalizedSummary != normalizedPrimary else {
            return nil
        }

        return summary
    }

    var spotlightCurrentToolLabel: String? {
        displayCurrentToolName
    }

    var spotlightStatusLabel: String {
        switch phase {
        case .running:
            if let currentTool = spotlightCurrentToolLabel {
                return "Live · \(currentTool)"
            }
            return "Live"
        case .waitingForApproval:
            return "Approval"
        case .waitingForAnswer:
            return "Question"
        case .completed:
            return jumpTarget != nil ? "Idle" : "Completed"
        }
    }

    var spotlightTerminalLabel: String? {
        guard let jumpTarget else {
            return nil
        }

        return "\(jumpTarget.terminalApp) · \(jumpTarget.workspaceName)"
    }

    var spotlightTerminalBadge: String? {
        guard let terminalApp = jumpTarget?.terminalApp,
              terminalApp != JumpTarget.unknownTerminalApp else {
            return nil
        }

        return terminalApp
    }

    var spotlightWorkspaceName: String {
        if let workspaceName = jumpTarget?.workspaceName.trimmedForSurface,
           !workspaceName.isEmpty {
            return workspaceName
        }

        let trimmedTitle = title.trimmedForSurface
        let pieces = trimmedTitle.split(separator: "·", maxSplits: 1).map {
            String($0).trimmedForSurface
        }
        if pieces.count == 2, !pieces[1].isEmpty {
            return pieces[1]
        }

        return trimmedTitle
    }

    var spotlightWorktreeBranch: String? {
        // This is a SwiftUI computed property read on every layout
        // pass. It MUST stay free of filesystem IO. Calling
        // `WorkspaceNameResolver.gitBranch` here previously walked
        // parent directories every layout, which combined with
        // SwiftUI's measure/layout convergence cycle pinned the
        // process at 99 % CPU during session-list rendering even
        // with the resolver result cached.
        //
        // Read order: hook-supplied metadata wins (already resolved
        // by `BridgeServer` from the hook payload), then the pure
        // string-based worktree-path detector (no IO). Other
        // sessions surface the workspace name without a branch
        // suffix; for branch info on arbitrary `cwd` values to
        // come back, it has to be resolved when the session is
        // created or updated, not from the view body.
        if let branch = claudeMetadata?.worktreeBranch?.trimmedForSurface,
           !branch.isEmpty {
            return branch
        }

        guard let workingDirectory = jumpTarget?.workingDirectory?.trimmedForSurface,
              !workingDirectory.isEmpty else {
            return nil
        }

        return WorkspaceNameResolver.worktreeBranch(for: workingDirectory)
    }

    var spotlightSubagentLabel: String? {
        guard let subagents = claudeMetadata?.activeSubagents, !subagents.isEmpty else {
            return nil
        }
        return "Subagents (\(subagents.count))"
    }

    var spotlightHeadlineText: String {
        var headline = spotlightWorkspaceName

        if let branch = spotlightWorktreeBranch {
            headline += " (\(branch))"
        }

        guard let prompt = spotlightHeadlinePromptText else {
            return headline
        }

        return "\(headline) · \(prompt)"
    }

    var spotlightHeadlinePromptText: String? {
        // Headline shows the initial prompt (session topic), not the latest.
        // The latest prompt is shown separately in the "You:" line.
        initialPromptText ?? latestPromptText
    }

    var spotlightPromptText: String? {
        latestPromptText
    }

    var spotlightPromptLineText: String? {
        guard spotlightShowsDetailLines,
              let prompt = spotlightPromptText else {
            return nil
        }

        return "You: \(prompt)"
    }

    var completionReplyRecipientName: String {
        switch tool {
        case .claudeCode:
            return "Claude"
        case .codex:
            return "Codex"
        case .geminiCLI:
            return "Gemini"
        case .openCode:
            return "OpenCode"
        case .qoder:
            return "Qoder"
        case .qwenCode:
            return "Qwen Code"
        case .factory:
            return "Factory"
        case .codebuddy:
            return "CodeBuddy"
        case .cursor:
            return "Cursor"
        case .kimiCLI:
            return "Kimi"
        }
    }

    var notificationHeaderPromptLineText: String? {
        guard phase != .completed else {
            return nil
        }

        return spotlightPromptLineText
    }

    var spotlightActivityLineText: String? {
        guard spotlightShowsDetailLines else {
            return nil
        }

        if let request = permissionRequest?.summary.trimmedForSurface,
           !request.isEmpty {
            return request
        }

        if let prompt = questionPrompt?.title.trimmedForSurface,
           !prompt.isEmpty {
            return prompt
        }

        switch phase {
        case .running:
            if let activity = spotlightRunningActivityText {
                return activity
            }
            return spotlightPromptLineText == nil ? "Running" : "Thinking"
        case .waitingForApproval:
            return permissionRequest?.summary.trimmedForSurface ?? "Approval needed"
        case .waitingForAnswer:
            return questionPrompt?.title.trimmedForSurface ?? "Answer needed"
        case .completed:
            if let assistantMessage = lastAssistantMessageText?.trimmedForSurface,
               !assistantMessage.isEmpty {
                return assistantMessage
            }

            switch outcome {
            case .success:
                return jumpTarget != nil ? "Ready" : "Completed"
            case .interrupted:
                return "Interrupted"
            case .failed:
                return "Failed"
            }
        }
    }

    var spotlightActivityTone: SpotlightActivityTone {
        if phase.requiresAttention {
            return .attention
        }

        switch phase {
        case .running:
            return .live
        case .completed:
            if lastAssistantMessageText?.trimmedForSurface.isEmpty == false {
                return .idle
            }
            return .ready
        case .waitingForApproval, .waitingForAnswer:
            return .attention
        }
    }

    var spotlightShowsDetailLines: Bool {
        spotlightShowsDetailLines(at: .now)
    }

    func spotlightShowsDetailLines(at referenceDate: Date) -> Bool {
        if phase == .running || phase.requiresAttention {
            return true
        }

        if referenceDate.timeIntervalSince(islandActivityDate) >= Self.collapsedDetailAgeThreshold {
            return false
        }

        return spotlightPromptText != nil || lastAssistantMessageText?.trimmedForSurface.isEmpty == false
    }

    var spotlightAgeBadge: String {
        let age = max(0, Int(Date.now.timeIntervalSince(islandActivityDate)))

        if age < 60 {
            return "<1m"
        }

        if age < 3_600 {
            return "\(max(1, age / 60))m"
        }

        if age < 86_400 {
            return "\(max(1, age / 3_600))h"
        }

        return "\(max(1, age / 86_400))d"
    }

    /// How long the main session has actually been running, derived from
    /// `firstSeenAt` — distinct from `spotlightAgeBadge`, which measures time
    /// since the *last update* and reads as "<1m" for most running sessions.
    /// Minute granularity (AB-230); callers re-derive this from their own
    /// periodic tick rather than a dedicated high-frequency timer.
    func elapsedRunningLabel(at referenceDate: Date) -> String {
        let totalSeconds = max(0, Int(referenceDate.timeIntervalSince(firstSeenAt)))
        let totalMinutes = totalSeconds / 60

        if totalMinutes < 1 {
            return "<1m"
        }

        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours < 24 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }

        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours == 0 ? "\(days)d" : "\(days)d \(remainingHours)h"
    }

    /// Short display form of the session's model metadata, e.g.
    /// `"claude-sonnet-4-5"` → `"Sonnet 4.5"`, `"gpt-5-codex"` → `"GPT-5"`.
    /// `nil` when no model metadata is present (AB-230) — the model badge is
    /// hidden entirely in that case.
    var displayModelName: String? {
        let rawModel = claudeMetadata?.model ?? openCodeMetadata?.model ?? cursorMetadata?.model
        guard let trimmed = rawModel?.trimmedForSurface, !trimmed.isEmpty else {
            return nil
        }

        return Self.shortModelDisplayName(for: trimmed)
    }

    /// Family keywords recognized regardless of where they appear in the raw
    /// model string (e.g. both `"claude-opus-4-6"` and `"claude-4.6-opus"`).
    private static let modelFamilyDisplayNames: [String: String] = [
        "opus": "Opus",
        "sonnet": "Sonnet",
        "haiku": "Haiku",
        "fable": "Fable",
        "mythos": "Mythos",
        "gemini": "Gemini",
        "grok": "Grok",
        "llama": "Llama",
        "mistral": "Mistral",
        "qwen": "Qwen",
        "kimi": "Kimi",
        "deepseek": "DeepSeek",
        "glm": "GLM",
    ]

    static func shortModelDisplayName(for rawModel: String) -> String {
        var value = rawModel.trimmedForSurface
        guard !value.isEmpty else { return rawModel }

        // Drop a leading provider namespace, e.g. "anthropic/claude-opus-4-6".
        if let slashIndex = value.lastIndex(of: "/") {
            value = String(value[value.index(after: slashIndex)...])
        }

        let tokens = value
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !tokens.isEmpty else { return value }

        var family: String?
        var isGPTFamily = false

        for token in tokens {
            if let mapped = modelFamilyDisplayNames[token] {
                family = mapped
                break
            }
            if token == "gpt" {
                family = "GPT"
                isGPTFamily = true
                break
            }
            if token.count == 2, token.hasPrefix("o"), token.dropFirst().allSatisfy(\.isNumber) {
                family = token.uppercased()
                break
            }
        }

        guard let resolvedFamily = family else {
            return humanizedModelName(from: tokens)
        }

        // Version = the numeric tokens, in original order — but drop
        // date-like tokens (e.g. the "20260101" trailing a Claude model id).
        let version = tokens
            .filter { $0.allSatisfy(\.isNumber) && $0.count < 6 }
            .joined(separator: ".")

        if version.isEmpty {
            return resolvedFamily
        }

        return isGPTFamily ? "\(resolvedFamily)-\(version)" : "\(resolvedFamily) \(version)"
    }

    private static func humanizedModelName(from tokens: [String]) -> String {
        let filtered = tokens.filter { !($0.allSatisfy(\.isNumber) && $0.count >= 6) }
        let source = filtered.isEmpty ? tokens : filtered
        return source
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    func islandPresence(at referenceDate: Date) -> IslandSessionPresence {
        if phase == .running {
            return .running
        }

        if phase.requiresAttention {
            return .active
        }

        if referenceDate.timeIntervalSince(islandActivityDate) <= Self.islandActivityThreshold {
            return .active
        }

        return .inactive
    }

    /// v8 UI-only staleness: keep `SessionPhase.completed` unchanged, but
    /// visually fold older completed rows into the low-priority presentation.
    func isStaleCompletedForIsland(
        at referenceDate: Date,
        threshold: TimeInterval = Self.staleCompletedDisplayThreshold
    ) -> Bool {
        phase == .completed
            && referenceDate.timeIntervalSince(islandActivityDate) >= threshold
    }

    private var spotlightRunningActivityText: String? {
        guard let currentTool = currentToolName?.trimmedForSurface,
              !currentTool.isEmpty else {
            return nil
        }

        let label = Self.currentToolDisplayName(for: currentTool)
        guard let preview = currentCommandPreviewText?.trimmedForSurface,
              !preview.isEmpty else {
            return label
        }

        return "\(label) \(preview)"
    }

    var displayCurrentToolName: String? {
        guard let currentTool = currentToolName?.trimmedForSurface,
              !currentTool.isEmpty else {
            return nil
        }

        return Self.currentToolDisplayName(for: currentTool)
    }

    static func currentToolDisplayName(for toolName: String) -> String {
        switch toolName {
        case "exec_command":
            return "Bash"
        case "Bash":
            return "Bash"
        case "AskUserQuestion":
            return "Question"
        case "ExitPlanMode":
            return "Plan"
        case "apply_patch":
            return "Patch"
        case "write_stdin":
            return "Input"
        case "web_search", "tool_search":
            return "Search"
        case "image_generation", "view_image":
            return "Image"
        case "context_compaction":
            return "Compact"
        case "update_plan":
            return "Plan"
        case "request_user_input":
            return "Question"
        case "spawn_agent":
            return "Subagent"
        default:
            return humanizedToolName(toolName)
        }
    }

    private static func humanizedToolName(_ toolName: String) -> String {
        let trimmed = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrivatePrefix = String(trimmed.drop(while: { $0 == "_" }))
        let pieces = withoutPrivatePrefix
            .split(separator: "_", omittingEmptySubsequences: true)
            .map { piece -> String in
                let upper = piece.uppercased()
                if ["API", "CI", "ID", "PR", "URL"].contains(upper) {
                    return upper
                }
                return piece.prefix(1).uppercased() + piece.dropFirst().lowercased()
            }
        let label = pieces.joined(separator: " ")
        return label.isEmpty ? toolName : label
    }

    private var initialPromptText: String? {
        let prompt = initialUserPromptText?.trimmedForSurface
        guard let prompt, !prompt.isEmpty else {
            return nil
        }

        return prompt
    }

    private var latestPromptText: String? {
        let prompt = latestUserPromptText?.trimmedForSurface
        guard let prompt, !prompt.isEmpty else {
            return nil
        }

        return prompt
    }

    private var prefersLivePromptHeadline: Bool {
        isProcessAlive || phase == .running || phase.requiresAttention
    }
}

private extension String {
    var trimmedForSurface: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
