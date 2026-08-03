import Foundation
import SwiftUI
import Testing
import OpenIslandCore
@testable import OpenIslandApp

/// Slice 5, correction round 2 (dual-FAIL at `2f54a2ea`).
///
/// One pin per corrected behaviour, kept in its own suite so the round's contract
/// items map to assertions one-to-one and a later round can see what each one was
/// defending. Everything here is either a pure function or a source pin — no
/// assertion mounts a view, in keeping with the rest of the Poured suites.
struct PouredSlice5CorrectionsTests {

    private static func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static let rowSource = "Sources/OpenIslandApp/Views/Island/PouredSessionRow.swift"

    /// An English-pinned lookup instance. `LanguageManager.language` persists to
    /// the shared `appLanguage` default on every set, and several suites cycle
    /// zh-Hans/zh-Hant on parallel instances — a bare `LanguageManager()` (or
    /// `.shared`) can therefore resolve a Chinese bundle mid-run. The instance's
    /// bundle is fixed at set-time, so restoring the persisted key immediately
    /// keeps the default as this test found it.
    private static func englishLanguage() -> LanguageManager {
        let key = "appLanguage"
        let saved = UserDefaults.standard.string(forKey: key)
        let lang = LanguageManager()
        lang.language = .en
        if let saved {
            UserDefaults.standard.set(saved, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return lang
    }

    // MARK: - §D detail hero

    /// D1: the §D assistant block renders through the Poured markdown style, not
    /// `.completionCard`'s 13.5/medium borrow, and that style carries the board's
    /// own numbers.
    @Test
    func detailAssistantProseTakesThePouredMarkdownStyle() throws {
        let source = try Self.source(Self.rowSource)
        // X12: the renderer is handed a Poured-local token copy whose
        // `surfaceText` IS paper — the board's `.assistant` ink is
        // `rgba(242,245,251,.66)`, not white at .66.
        #expect(source.contains("LocalMarkdownText(message, style: .pouredAssistant, colors: assistantInkColors)"))
        #expect(source.contains("colors.surfaceText = colors.paper"))
        #expect(!source.contains("LocalMarkdownText(message, colors: tokens.colors)"))

        // `.assistant{font-size:12.5px}` at the body weight, and inline `code` at
        // 11px mono — the two roles the style binds.
        #expect(PouredType.Role.assistantBody.spec.size == 12.5)
        #expect(PouredType.Role.assistantBody.spec.weight == 400)
        #expect(PouredType.Role.assistantInlineCode.spec.size == 11)
        #expect(PouredType.Role.assistantInlineCode.spec.isMono)

        // The new case is additive: the three shipped styles are untouched.
        let markdown = try Self.source("Sources/OpenIslandApp/Views/LocalMarkdownText.swift")
        for existing in ["case completionCard", "case flightDeckAssistant", "case haloAssistant"] {
            #expect(markdown.contains(existing))
        }
        #expect(markdown.contains("case pouredAssistant"))
        // Halo's chip values must not have drifted while Poured's were added.
        #expect(markdown.contains("0xC8 / 255.0, green: 0xD2 / 255.0, blue: 0xE6 / 255.0"))
        #expect(markdown.contains("0xC9 / 255.0, green: 0xD3 / 255.0, blue: 0xE6 / 255.0"))
    }

    /// D2: an open row drops the trailing identity set entirely — the board's §D
    /// `.body` is the full content width and states those facts in the
    /// `.meta-grid` below — and its `.act` drops the elapsed tail.
    @Test
    func openRowGivesTheActivityLineTheFullDetailWidth() throws {
        let source = try Self.source(Self.rowSource)

        // The four trailing chips are gone from the row entirely (their helpers
        // with them), so nothing can quietly re-add them to the open header.
        #expect(!source.contains("private func sideBadge("))
        #expect(!source.contains("private func permissionModeChip("))
        // `.age` renders only while collapsed — "There is no `.age` element in §D".
        #expect(source.contains("if !showsDetail {\n                    Text(ageBadgeText(at: referenceDate))"))
        // And the elapsed tail is suppressed on the open row.
        #expect(source.contains("liveSuffix: showsDetail ? nil : liveElapsedSuffix(at: referenceDate)"))
    }

    /// D3: the LIVE metadata cell reads the board's second-precision `1m 42s`,
    /// not the age column's floored `1m`.
    @Test
    func liveMetadataCellCarriesBoardSecondPrecision() throws {
        // The board's own value, from the same formatter the §C `· live …` tail
        // uses. `elapsedRunningLabel` — what the cell used to read — floors to
        // whole minutes and returns "1m" for the identical duration.
        #expect(PouredLiveElapsed.text(seconds: 102) == "1m 42s")
        #expect(PouredLiveElapsed.text(seconds: 42) == "42s")
        #expect(PouredLiveElapsed.text(seconds: 120) == "2m")

        let source = try Self.source(Self.rowSource)
        #expect(source.contains("value: PouredLiveElapsed.text("))
        #expect(!source.contains("value: session.elapsedRunningLabel(at: referenceDate)"))
    }

    /// D4: §D's Transcript is the board's filled `.btn.ghost`, and only §D's —
    /// the footnote form under an actionable hero is unchanged.
    @Test
    func detailTranscriptTakesTheBoardGhostFill() throws {
        let row = try Self.source(Self.rowSource)
        #expect(row.components(separatedBy: "pouredGhost: true").count - 1 == 1)

        let panel = try Self.source("Sources/OpenIslandApp/Views/IslandPanelView.swift")
        #expect(panel.contains("var pouredGhost: Bool = false"))
        // `.btn.ghost{background:rgba(242,245,251,.08)}` → `:hover{.14}`, r11.
        #expect(panel.contains(".opacity(isHovered ? 0.14 : 0.08)"))
        #expect(panel.contains("in: RoundedRectangle(cornerRadius: 11, style: .continuous)"))
        // Halo's chip branch survives untouched.
        #expect(panel.contains("} else if haloChip {"))
    }

    /// D5: the branch stays on the title line when the row expands, whether or
    /// not the list needed it to disambiguate.
    @Test
    func openRowKeepsTheBranchOnTheTitleLine() throws {
        let source = try Self.source(Self.rowSource)
        #expect(source.contains("if base == nil, showsDetail, let branch = SessionDisambiguation.branch(for: session)"))
        #expect(source.contains("titleLine(presence: presence, showsDetail: showsDetail)"))
    }

    /// D6: one accessibility element per `.mcell`, reading `"<key>, <value>"`.
    @Test
    func metadataCellIsOneAccessibilityElement() throws {
        #expect(PouredMetadataCellCopy.accessibilityLabel(key: "Agent", value: "Claude Code")
            == "Agent, Claude Code")
        // The key is spoken in its authored case — never the `.uppercased()`
        // chrome the cell draws.
        #expect(!PouredMetadataCellCopy.accessibilityLabel(key: "Agent", value: "Claude Code").contains("AGENT"))
        #expect(PouredMetadataCellCopy.accessibilityLabel(key: "  Live  ", value: " 1m 42s ") == "Live, 1m 42s")
        #expect(PouredMetadataCellCopy.accessibilityLabel(key: "", value: "Opus 4.8") == "Opus 4.8")
        #expect(PouredMetadataCellCopy.accessibilityLabel(key: "Model", value: "  ") == "Model")

        let source = try Self.source(Self.rowSource)
        #expect(source.contains(".accessibilityLabel(PouredMetadataCellCopy.accessibilityLabel(key: key, value: spokenValue))"))
    }

    // MARK: - §E permission heroes

    /// E1: the hero diff is clamped to whole rows with an explicit remainder,
    /// never sliced mid-glyph by the shared renderer's flat 180pt scroll cap.
    @Test
    func heroDiffClampsToWholeRowsWithAnExplicitRemainder() {
        func line(_ text: String, _ kind: PermissionDiffLine.Kind) -> PermissionDiffLine {
            PermissionDiffLine(kind: kind, text: text)
        }
        let short = PermissionDiffResult(
            lines: (0..<4).map { line("line \($0)", .unchanged) },
            addedCount: 0,
            removedCount: 0
        )
        let shortClamped = PouredHeroDiff.clamp(short)
        #expect(shortClamped.hiddenLineCount == 0)
        #expect(shortClamped.result.lines.count == 4)

        let long = PermissionDiffResult(
            lines: (0..<20).map { line("line \($0)", .added) },
            addedCount: 20,
            removedCount: 0
        )
        let longClamped = PouredHeroDiff.clamp(long)
        #expect(longClamped.result.lines.count == PouredHeroDiff.maxRows)
        #expect(longClamped.hiddenLineCount == 20 - PouredHeroDiff.maxRows)
        // Whole rows only — the last kept line is a complete one, and the counts
        // that head the block still describe the real change.
        #expect(longClamped.result.lines.last?.text == "line \(PouredHeroDiff.maxRows - 1)")
        #expect(longClamped.result.addedCount == 20)
        // The board's E2 renders four rows; the cap must never fall below that.
        #expect(PouredHeroDiff.maxRows >= 4)
    }

    /// E2: E1 and E3 take the board's terminal chevron, E2 the pencil — a shape
    /// fork, not one glyph for all three.
    @Test
    func heroIconForksByVariant() throws {
        let source = try Self.source(Self.rowSource)
        #expect(source.contains("PouredTerminalChevron()"))
        #expect(source.contains("Image(systemName: \"pencil\")"))
        // The `</>` code mark the card used to draw for E1/E2 is gone from the
        // render (it survives only as the comment naming what was replaced).
        #expect(!source.contains("Image(systemName: requiresTerminalApproval ? \"arrow.up.forward.app.fill\" : \"chevron.left.forwardslash.chevron.right\")"))
        // The chevron is the board's own SVG path pair, in its 24-unit viewBox.
        #expect(source.contains("path.move(to: point(4, 17))"))
        #expect(source.contains("path.addLine(to: point(10, 11))"))
        #expect(source.contains("path.move(to: point(12, 19))"))
        #expect(source.contains("path.addLine(to: point(20, 19))"))
        // The fork is the intent classification, so title and icon can't disagree.
        #expect(source.contains("hasCommand: commandText != nil\n        ) == .editFile"))
    }

    /// E3: the effect line is E1-only and never restates the ask.
    @Test
    func effectLineIsE1OnlyAndNeverRestatesTheAsk() {
        // E1: a genuine effect survives.
        #expect(PouredApprovalHeroCopy.effect(
            summary: "Compiles the OpenIsland package. No files are modified.",
            command: "swift build",
            intentTitle: "Run a shell command?",
            hasFileDiff: false,
            requiresTerminalApproval: false
        ) == "Compiles the OpenIsland package. No files are modified.")

        // E2 — the diff is the statement of effect; the board draws no line.
        #expect(PouredApprovalHeroCopy.effect(
            summary: "Claude wants to edit AGENTS.md.",
            command: nil,
            intentTitle: "Edit a file?",
            hasFileDiff: true,
            requiresTerminalApproval: false
        ) == nil)

        // E3 — the blue `.codex-note` owns that slot, and nothing amber may sit
        // inside the blue card.
        #expect(PouredApprovalHeroCopy.effect(
            summary: "Codex wants to run: git push origin main",
            command: "git push origin main",
            intentTitle: "Approval needed in Codex",
            hasFileDiff: false,
            requiresTerminalApproval: true
        ) == nil)

        // Restatements of the ask, in all three shapes seen in the wild.
        #expect(PouredApprovalHeroCopy.effect(
            summary: "swift build",
            command: "swift build",
            intentTitle: "Run a shell command?",
            hasFileDiff: false,
            requiresTerminalApproval: false
        ) == nil)
        #expect(PouredApprovalHeroCopy.effect(
            summary: "Claude wants to run swift build",
            command: "swift build",
            intentTitle: "Run a shell command?",
            hasFileDiff: false,
            requiresTerminalApproval: false
        ) == nil)
        #expect(PouredApprovalHeroCopy.effect(
            summary: "Run a shell command?",
            command: "swift build",
            intentTitle: "Run a shell command?",
            hasFileDiff: false,
            requiresTerminalApproval: false
        ) == nil)

        // Empty / absent summaries never print an empty line.
        #expect(PouredApprovalHeroCopy.effect(
            summary: "   ",
            command: "swift build",
            intentTitle: nil,
            hasFileDiff: false,
            requiresTerminalApproval: false
        ) == nil)
    }

    /// E3 (round 2): the §E1 **fixture** has to state an effect too.
    ///
    /// `effect(…)` can only suppress the echoes it can see, and the debug
    /// fixture's old summary — "Allow exec_command to rewrite SettingsView.swift?"
    /// — cleared every one of them while being a question-form restatement of the
    /// ask carrying a raw tool name. The board's E1 reads
    /// "Compiles the OpenIsland package. No files are modified."
    /// (`01-poured-island.html:1010`): a declarative sentence plus its side effect.
    @Test
    func e1DebugFixtureSummaryIsADeclarativeEffect() throws {
        let snapshot = IslandDebugScenario.approvalCard.snapshot(
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let session = try #require(snapshot.sessions.first { $0.id == snapshot.selectedSessionID })
        let summary = try #require(session.permissionRequest?.summary)

        // The card reads the request's summary; the row falls back to the
        // session's. They narrate the same pending change, so they must agree.
        #expect(summary == session.summary)
        #expect(summary == "Renames AppearanceSection to AppearanceSettingsSection in SettingsView.swift. One file is modified.")
        // Declarative, not the ask restated…
        #expect(!summary.contains("?"))
        #expect(!summary.lowercased().contains("wants to"))
        #expect(!summary.lowercased().hasPrefix("allow "))
        // …and no raw internals: the tool name never reaches rendered copy.
        #expect(!summary.lowercased().contains("exec_command"))
        // States the side effect, the way the board's second sentence does.
        #expect(summary.contains("One file is modified."))

        // And it still survives the echo heuristic, so E1 really prints a line.
        #expect(PouredApprovalHeroCopy.effect(
            summary: summary,
            command: session.currentCommandPreviewText,
            intentTitle: nil,
            hasFileDiff: session.permissionRequest?.fileDiffSource != nil,
            requiresTerminalApproval: false
        ) == summary)
    }

    /// E4/E5: E3's head carries the agent tag (brand name when there is no model)
    /// and its primary prints the board's `⌘Y`.
    @Test
    func codexHeroCarriesItsAgentTagAndKeycap() throws {
        let source = try Self.source(Self.rowSource)
        #expect(source.contains("guard requiresTerminalApproval else { return nil }"))
        #expect(source.contains("return name.isEmpty ? nil : name.lowercased()"))
        // X9: E3's blue primary carries the board's Y4 `.btn.primary .kc kbd`
        // recipe — brown glyphs on a darkened chip — exactly as E1's amber and
        // F2's gold primaries do. `.btn.primary .kc kbd` is never overridden per
        // variant on the board (L360), so the cap pair is one rule, not three.
        #expect(source.contains("PouredKeycapRow(glyphs: PouredApprovalShortcut.allowOnce.glyphs, onAmber: true)"))
        #expect(PouredApprovalShortcut.allowOnce.glyphs == ["\u{2318}", "Y"])

        // E4's rendered state really is *no* tag, so the fallback must stay
        // scoped to the terminal-approval variant.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let codex = AppearancePreviewFixtures.codexTerminalApproval(now: now)
        #expect(codex.displayModelName == nil)
        #expect(codex.permissionRequest?.requiresTerminalApproval == true)
        #expect(codex.tool == .codex)
    }

    /// E6: scope rows are the board's sentence-plus-code-chip, not the shipped
    /// `Yes, allow running …` dump or `Always Allow (Bash)`.
    @Test
    func scopeRowsAreHumanisedWithACodeChip() {
        let projectRule = ClaudePermissionUpdate.addRules(
            destination: .projectSettings,
            rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "swift build")],
            behavior: .allow
        )
        let shape = PouredScopeCopy.shape(for: projectRule)
        #expect(shape?.key == "poured.approval.scope.fromProject")
        #expect(shape?.code == "swift build")

        let toolWide = ClaudePermissionUpdate.addRules(
            destination: .session,
            rules: [ClaudePermissionRuleValue(toolName: "swift")],
            behavior: .allow
        )
        #expect(PouredScopeCopy.shape(for: toolWide)?.key == "poured.approval.scope.allCommands")
        #expect(PouredScopeCopy.shape(for: toolWide)?.code == "swift")

        let edit = ClaudePermissionUpdate.addRules(
            destination: .projectSettings,
            rules: [ClaudePermissionRuleValue(toolName: "Edit", ruleContent: "README.md")],
            behavior: .allow
        )
        #expect(PouredScopeCopy.shape(for: edit)?.key == "poured.approval.scope.edits")
        #expect(PouredScopeCopy.shape(for: edit)?.code == "README.md")

        // Update kinds the board never draws as a scope row keep `displayLabel`.
        #expect(PouredScopeCopy.shape(for: .setMode(destination: .session, mode: .acceptEdits)) == nil)

        // The chip lands where the localized sentence puts its `%@`.
        let parts = PouredScopeCopy.parts(format: "Always allow %@ from this project", code: "swift build")
        #expect(parts.prefix == "Always allow ")
        #expect(parts.code == "swift build")
        #expect(parts.suffix == " from this project")
        // A format with no marker degrades to a plain sentence rather than losing it.
        let bare = PouredScopeCopy.parts(format: "Always allow", code: "swift")
        #expect(bare.prefix == "Always allow")
        #expect(bare.suffix.isEmpty)

        // The English copy really is the board's, and the raw-tool-name form is
        // no longer what Poured reads.
        let lang = Self.englishLanguage()
        #expect(lang.t("poured.approval.scope.fromProject") == "Always allow %@ from this project")
        #expect(lang.t("poured.approval.scope.allCommands") == "Always allow all %@ commands")
        #expect(lang.t("poured.approval.scope.edits") == "Always allow edits to %@")
        #expect(!lang.t("poured.approval.scope.allCommands").contains("("))
    }

    /// E7: the hero radius is the board's 18, in one place.
    @Test
    func heroCornerRadiusIsEighteen() throws {
        let source = try Self.source(Self.rowSource)
        #expect(source.contains("static let cornerRadius: CGFloat = 18"))
        // Both the fill and the stroke read the one constant.
        #expect(source.components(separatedBy: "cornerRadius: Self.cornerRadius").count - 1 == 2)
    }

    /// E8: the accessible name of every approval CTA is its **visible** label;
    /// the agent-supplied verb moves to the hint.
    @Test
    func approvalButtonsNameThemselvesByWhatTheyShow() throws {
        let source = try Self.source(Self.rowSource)
        // No CTA routes an agent title into `accessibilityLabel` any more.
        #expect(!source.contains(".accessibilityLabel(session.permissionRequest?.primaryActionTitle"))
        #expect(!source.contains(".accessibilityLabel(session.permissionRequest?.secondaryActionTitle"))
        // Four CTAs — hero Allow once / Deny, compact Approve / Deny — each with
        // the visible label as its name and the agent verb as its hint.
        #expect(source.components(separatedBy: "PouredOptionalAccessibilityHint(session.permissionRequest?").count - 1 == 4)
        #expect(source.contains(".accessibilityLabel(lang.t(\"poured.approval.allowOnce\"))"))
        #expect(source.contains(".accessibilityLabel(lang.t(\"poured.approval.approve\"))"))
        #expect(source.components(separatedBy: ".accessibilityLabel(lang.t(\"poured.approval.deny\"))").count - 1 == 2)
        // E3's CTA names itself too.
        #expect(source.contains(".accessibilityLabel(terminalApprovalCTATitle)"))
    }

    /// E9 (verify): the `.actions` gap constant is the board's 8px. Recorded as a
    /// pin because the reviewer's ≈13.5pt reading was low-confidence and is not
    /// reproducible from the candidate's own crop — see the round report.
    @Test
    func heroActionsGapIsTheBoardsEight() throws {
        let source = try Self.source(Self.rowSource)
        #expect(source.contains("private var actionButtons: some View {\n        HStack(spacing: 8) {"))
        #expect(source.contains("private var compactApprovalActions: some View {\n        HStack(spacing: 8) {"))
    }

    // MARK: - §F question surfaces

    /// F1: a Poured question frame with no freeform option draws no freeform
    /// field; every other theme's rule is untouched.
    @Test
    func pouredQuestionFramesDropTheUnaskedForReplyField() {
        let plain = QuestionPromptItem(
            question: "Which agents ship?",
            header: "Targets",
            options: [
                QuestionOption(label: "OpenCode"),
                QuestionOption(label: "Kimi CLI"),
            ],
            multiSelect: true
        )
        let withOther = QuestionPromptItem(
            question: "Which auth?",
            header: "Auth",
            options: [
                QuestionOption(label: "Unix socket"),
                QuestionOption(label: "Other", allowsFreeform: true),
            ],
            multiSelect: false
        )

        // F′/F″ shape: no freeform option, and Poured draws no field.
        #expect(!PouredQuestionFieldPolicy.showsGlobalReplyField(isPoured: true, questions: [plain]))
        // The shipped rule for every other theme is unchanged — it shows the
        // field precisely because nothing is freeform.
        #expect(PouredQuestionFieldPolicy.showsGlobalReplyField(isPoured: false, questions: [plain]))
        // A prompt that already has an inline freeform row never showed one.
        #expect(!PouredQuestionFieldPolicy.showsGlobalReplyField(isPoured: false, questions: [withOther]))
        #expect(!PouredQuestionFieldPolicy.showsGlobalReplyField(isPoured: true, questions: [withOther]))
        // A genuinely freeform prompt keeps its field on every theme.
        #expect(PouredQuestionFieldPolicy.showsGlobalReplyField(isPoured: true, questions: []))
        #expect(PouredQuestionFieldPolicy.showsGlobalReplyField(isPoured: false, questions: []))
    }

    /// F1: whatever field survives names itself.
    @Test
    func everySurvivingReplyFieldCarriesAnAccessibleName() throws {
        let panel = try Self.source("Sources/OpenIslandApp/Views/IslandPanelView.swift")
        #expect(panel.contains(".accessibilityLabel(Text(option.label))"))
        #expect(panel.contains(".accessibilityLabel(Text(lang.t(\"question.otherPlaceholder\")))"))
    }

    /// F2: the digit hint is F-only, and it is the board's copy — no
    /// `Enter submits · Esc closes` tail.
    @Test
    func questionHintIsTheBoardsDigitRangeAndOnlyOnF() {
        #expect(PouredQuestionHint.digitRange(optionCount: 3, isMultiSelect: false) == "1\u{2013}3")
        #expect(PouredQuestionHint.digitRange(optionCount: 4, isMultiSelect: false) == "1\u{2013}4")
        #expect(PouredQuestionHint.digitRange(optionCount: 1, isMultiSelect: false) == "1")
        // F′ renders no `.q-hint` at all.
        #expect(PouredQuestionHint.digitRange(optionCount: 3, isMultiSelect: true) == nil)
        #expect(PouredQuestionHint.digitRange(optionCount: 0, isMultiSelect: false) == nil)
        // The digit keys stop at 9, so the advertised range must too.
        #expect(PouredQuestionHint.digitRange(optionCount: 12, isMultiSelect: false) == "1\u{2013}9")
        // En dash, not a hyphen (`&#8211;`).
        #expect(PouredQuestionHint.digitRange(optionCount: 3, isMultiSelect: false)?.contains("-") == false)

        let lang = Self.englishLanguage()
        #expect(lang.t("poured.question.hint.pick") == "Press %@ to pick")
        #expect(!lang.t("poured.question.hint.pick").contains("Esc"))
        // The shared string every other theme still reads is untouched.
        #expect(lang.t("question.hint.keyboard.range").contains("Esc closes"))
    }

    /// F3: the `.opt-other` row says what it does, and F's own fixture has one.
    @Test
    func freeformEscapeHatchCarriesTheBoardCopyAndAppearsOnF() throws {
        let lang = Self.englishLanguage()
        #expect(lang.t("poured.question.optionOther") == "Other — type a different approach")

        let panel = try Self.source("Sources/OpenIslandApp/Views/IslandPanelView.swift")
        // Display-only: the submitted answer is still `option.label`.
        #expect(panel.contains("Text(isPoured && isOther ? lang.t(\"poured.question.optionOther\") : option.label)"))

        // F's fixture now renders the row the board draws.
        let auth = AppearancePreviewFixtures.conformanceQuestions()[0]
        #expect(auth.options.count == 4)
        #expect(auth.options.last?.allowsFreeform == true)
        #expect(auth.options.last?.label == "Other")
        #expect(Set(auth.options.map(\.id)).count == 4)
    }

    /// F4: the preselection seam is a set of indices, and the three §F scenarios
    /// pin the board's own selected states.
    @Test
    func questionScenariosPinTheBoardsSelectedStates() {
        #expect(IslandQuestionPromptPreselection.firstOption.optionIndices == [0])

        #expect(IslandDebugScenario.multiQuestionCard.snapshot().questionPreselection?.optionIndices == [0])
        #expect(IslandDebugScenario.pouredMultiSelectQuestion.snapshot().questionPreselection?.optionIndices == [0, 1])
        #expect(IslandDebugScenario.pouredCompactQuestion.snapshot().questionPreselection?.optionIndices == [0])

        // Scenario-scoped: nothing else opts in, so no other capture and no real
        // question card starts from a seeded selection.
        let seeded = IslandDebugScenario.allCases.filter { $0.snapshot().questionPreselection != nil }
        #expect(Set(seeded) == [.multiQuestionCard, .pouredMultiSelectQuestion, .pouredCompactQuestion])

        // The Bool spelling of the old seam still means exactly `[0]`.
        var environment = EnvironmentValues()
        #expect(!environment.islandQuestionPromptPreselectsFirstOption)
        environment.islandQuestionPromptPreselectsFirstOption = true
        #expect(environment.islandQuestionPromptPreselection?.optionIndices == [0])
        environment.islandQuestionPromptPreselection = IslandQuestionPromptPreselection(optionIndices: [1, 2])
        // `[1,2]` does not contain 0, so the legacy Bool correctly reads `false`.
        #expect(!environment.islandQuestionPromptPreselectsFirstOption)
    }

    /// F4: F′'s submit reads the board's `Submit 2 selected` — no em dash — and
    /// every other theme keeps the shipped label.
    @Test
    func multiSelectSubmitDropsTheEmDashOnPoured() {
        let lang = Self.englishLanguage()
        #expect(lang.t("poured.question.submit.multiSelect", 2) == "Submit 2 selected")
        #expect(!lang.t("poured.question.submit.multiSelect", 2).contains("—"))
        #expect(QuestionPromptFormat.multiSelectSubmitLabel(selectedCount: 2, lang: lang).contains("—"))
    }

    /// §E capture seam: E1/E2/E3 draw no auto-collapse countdown (the board puts
    /// one on E4 alone), and E4's scenario keeps it.
    @Test
    func onlyTheNotificationScenarioKeepsTheAutoCollapseCountdown() {
        let suppressed = IslandDebugScenario.allCases.filter { $0.snapshot().suppressesNotificationCountdown }
        #expect(Set(suppressed) == [.approvalCard, .diffApprovalCard, .codexApprovalCard])

        var environment = EnvironmentValues()
        #expect(!environment.islandSuppressesNotificationCountdown)
        environment.islandSuppressesNotificationCountdown = true
        #expect(environment.islandSuppressesNotificationCountdown)
    }

    // MARK: - Rotation (PI-A-002)

    /// R1: the traveling glyph forks by ambient shape, so A3's permission and
    /// A4's question can never be told apart by hue alone.
    @Test
    func travelingGlyphForksBetweenA3AndA4() throws {
        let pill = try Self.source("Sources/OpenIslandApp/Views/Island/PouredClosedPill.swift")
        #expect(pill.contains("struct PouredClosedTravelingGlyph: View"))
        // A3 is the ringed dot; A4 and the working/idle states are the bars.
        #expect(pill.contains("case .permission:\n            PouredPillRingedDot("))
        // X2: and A4's bars are the board's three, not the shipped two.
        #expect(pill.contains("case .idle, .working, .question:\n            //"))
        #expect(pill.contains("UnifiedBars(mode: unifiedMode, size: size, tint: tint, showsMiddleWaitBar: true)"))
        // The resting pill and the traveling overlay are the same leaf.
        #expect(pill.contains("PouredClosedTravelingGlyph(ambient: ambient, size: Self.glyphSize, tint: restingGlyphTint)"))

        let panel = try Self.source("Sources/OpenIslandApp/Views/IslandPanelView.swift")
        #expect(panel.contains("if theme.id == \"poured\" {\n                PouredClosedTravelingGlyph("))
        // Every other theme still takes the protocol default.
        #expect(panel.contains("theme.closedTravelingGlyph("))
    }

    /// R1: A3's label sets its command in mono — `Approve ` + `<mono>` + `?`.
    @Test
    func permissionPillSetsItsCommandInMono() {
        let span = PouredClosedPillCommandSpan.split(label: "Approve swift build?", format: "Approve %@?")
        #expect(span?.prefix == "Approve ")
        #expect(span?.command == "swift build")
        #expect(span?.suffix == "?")

        // A locale that moves the command still resolves.
        let moved = PouredClosedPillCommandSpan.split(label: "需要批准 swift build", format: "需要批准 %@")
        #expect(moved?.command == "swift build")

        // Anything that is not that sentence falls back to the two-tone split.
        #expect(PouredClosedPillCommandSpan.split(label: "Answer needed", format: "Approve %@?") == nil)
        #expect(PouredClosedPillCommandSpan.split(label: "Approve ?", format: "Approve %@?") == nil)
        #expect(PouredClosedPillCommandSpan.split(label: "Approve swift build?", format: "no marker") == nil)
    }

    /// R1: the attention badge follows the spotlighted item's kind, so a cycle
    /// that holds a permission and a question does not paint both amber.
    @Test
    func rotationRetagsTheAttentionBadgeToTheSpotlightedItem() throws {
        let model = try Self.source("Sources/OpenIslandApp/AppModel.swift")
        #expect(model.contains("private func pouredRotationRetaggedBadge("))
        // Kind only — the value stays the aggregate total the adjudication pinned.
        #expect(model.contains("return .attentionCount(count: count, kind: spotlightKind)"))
        #expect(model.contains("guard case let .attentionCount(count, kind) = content,\n              pouredSpotlightRotationIsLive,"))
    }

    /// R2: the pill holds one silhouette across the cycle, sized to the widest
    /// rotating item.
    @Test
    func rotatingPillSizesToTheWidestItem() {
        let widest = PouredSpotlightRotation.widthReferenceLabel(
            ["Answer needed", "Approve swift build?", "Approve ls?"],
            measuredBy: { CGFloat($0.count) }
        )
        #expect(widest == "Approve swift build?")

        // Deterministic tie-break, so a capture at any phase sizes identically.
        let tied = PouredSpotlightRotation.widthReferenceLabel(
            ["bbb", "aaa"],
            measuredBy: { CGFloat($0.count) }
        )
        #expect(tied == "bbb")

        #expect(PouredSpotlightRotation.widthReferenceLabel([], measuredBy: { _ in 0 }) == nil)
        #expect(PouredSpotlightRotation.widthReferenceLabel(["only"], measuredBy: { _ in 0 }) == "only")
        #expect(PouredSpotlightRotation.widthReferenceLabel(["", ""], measuredBy: { _ in 0 }) == nil)
    }

    /// R2: the reference reaches the *surface* width, not only the pill's inner
    /// label box, so the morph frame and the glow seam hold still too.
    @Test
    func rotationWidthReferenceReachesTheSurfaceSilhouette() throws {
        let panel = try Self.source("Sources/OpenIslandApp/Views/IslandPanelView.swift")
        #expect(panel.contains("label: model.islandClosedPillRotation()?.widthReferenceLabel ?? model.islandClosedLabel()"))
        #expect(panel.contains(".environment(\\.islandClosedPillRotation, model.islandClosedPillRotation())"))

        let pill = try Self.source("Sources/OpenIslandApp/Views/Island/PouredClosedPill.swift")
        #expect(pill.contains("label: widthLabel,"))
        #expect(pill.contains("guard let reference = rotation?.widthReferenceLabel, !reference.isEmpty else { return label }"))
    }

    /// R3: the swap is sequential and inside the ruled budget; Reduce Motion
    /// keeps the instant swap while the cycle itself keeps running.
    @Test
    func rotationSwapNeverShowsTwoLabelsAtOnce() throws {
        #expect(PouredSpotlightRotation.swapFadeSeconds == 0.2)
        #expect(PouredSpotlightRotation.swapSeconds <= 0.45)
        #expect(PouredSpotlightRotation.swapFadeSeconds(reduceMotion: false) == 0.2)
        #expect(PouredSpotlightRotation.swapFadeSeconds(reduceMotion: true) == nil)
        // The cycle is informational: Reduce Motion drops the animation, never
        // the rotation.
        #expect(PouredSpotlightRotation.isActive(waitingCount: 2))
        #expect(PouredSpotlightRotation.holdMilliseconds == 3_500)

        // X1: the swap has ONE driver, and it is not in the view.
        let clockSource = try Self.source("Sources/OpenIslandApp/PouredSpotlightRotation.swift")
        // Fade out, then commit, then fade in — never a crossfade of the two.
        #expect(clockSource.contains("withAnimation(PouredSpotlightRotation.swapAnimation(fadingOut: true)) { contentOpacity = 0 }"))
        #expect(clockSource.contains("withAnimation(PouredSpotlightRotation.swapAnimation(fadingOut: false)) { self.contentOpacity = 1 }"))

        let pill = try Self.source("Sources/OpenIslandApp/Views/Island/PouredClosedPill.swift")
        // The pill owns no swap state of its own any more — it applies the one
        // shared opacity to the whole rotating payload.
        #expect(pill.contains("private var swapOpacity: Double { rotation?.contentOpacity ?? 1 }"))
        #expect(pill.contains(".pouredRotationSwapFade(opacity: swapOpacity, isRotating: rotation != nil)"))
        #expect(!pill.contains("labelOpacity"))
        #expect(!pill.contains("displayedLabel"))
        // And the shipped 0.45s layout crossfade — the second driver that made
        // the incoming leg run at 0.45s instead of 0.2s — stands down for the
        // duration of a cycle.
        #expect(pill.contains("rotation == nil ? .timingCurve(0.4, 0, 0.2, 1, duration: 0.45) : nil"))
    }

    // MARK: - Correction round 3

    /// X1: the swap schedule is a pure state machine, so "outgoing reaches zero
    /// and STAYS zero before incoming starts" is an assertion rather than a
    /// frame-by-frame video measurement.
    @Test
    func rotationSwapSchedulesOneFadeOutThenOneAtomicCommit() {
        // A settled pill has nothing to do, at any phase.
        #expect(PouredSpotlightRotation.swapStep(
            displayedIndex: 1, targetIndex: 1, isSwapping: false, reduceMotion: false
        ) == .settled)

        // The target moved: begin the outgoing leg.
        #expect(PouredSpotlightRotation.swapStep(
            displayedIndex: 0, targetIndex: 1, isSwapping: false, reduceMotion: false
        ) == .fadeOut)

        // A second tick inside the same 0.4s swap must NOT restart the fade —
        // the 4Hz clock fires twice per swap window.
        #expect(PouredSpotlightRotation.swapStep(
            displayedIndex: 0, targetIndex: 1, isSwapping: true, reduceMotion: false
        ) == .settled)

        // R3: Reduce Motion keeps the cycle and drops only the animation.
        #expect(PouredSpotlightRotation.swapStep(
            displayedIndex: 0, targetIndex: 1, isSwapping: false, reduceMotion: true
        ) == .snap)
        #expect(PouredSpotlightRotation.swapStep(
            displayedIndex: 0, targetIndex: 1, isSwapping: true, reduceMotion: true
        ) == .snap)

        // The whole swap fits the adjudicated budget with the legs stated apart.
        #expect(PouredSpotlightRotation.swapSeconds == PouredSpotlightRotation.swapFadeSeconds * 2)
        #expect(PouredSpotlightRotation.swapSeconds <= PouredSpotlightRotation.swapBudgetSeconds)
        #expect(PouredSpotlightRotation.swapBudgetSeconds == 0.45)
    }

    /// X1: the clock's displayed index lags the phase across a swap and lands on
    /// the phase's answer when it commits, so every consumer changes at once.
    @Test @MainActor
    func rotationClockHoldsTheOutgoingItemUntilTheFadeOutFinishes() async {
        let clock = PouredSpotlightRotationClock()
        clock.waitingCount = 2
        // Pinned, so the assertion below does not depend on the host machine's
        // Reduce Motion setting.
        clock.reduceMotionOverride = false

        // Phase 0: nothing has moved.
        clock.advance(to: 0)
        #expect(clock.displayedIndex == 0)
        #expect(clock.contentOpacity == 1)
        #expect(!clock.isSwapping)

        // Cross the first boundary: the item on screen is STILL item 0 while the
        // outgoing leg runs. This is the whole point — item 1's marker/badge
        // cannot appear beside item 0's label because item 1 is not displayed yet.
        clock.advance(to: 3_500)
        #expect(clock.isSwapping)
        #expect(clock.displayedIndex == 0)

        // After the fade-out leg the commit lands, in one step.
        try? await Task.sleep(nanoseconds: UInt64(PouredSpotlightRotation.swapFadeSeconds * 1_600_000_000))
        #expect(clock.displayedIndex == 1)
        #expect(!clock.isSwapping)

        // Reduce Motion swaps instantly and never acquires the fade.
        let reduced = PouredSpotlightRotationClock()
        reduced.waitingCount = 2
        reduced.reduceMotionOverride = true
        reduced.advance(to: 3_500)
        #expect(reduced.displayedIndex == 1)
        #expect(reduced.contentOpacity == 1)
        #expect(!reduced.isSwapping)
    }

    /// X1: the single opacity really is shared — the model publishes one value
    /// and it is `1` (a no-op) on every non-rotating path, including a
    /// deterministic parity phase, so stills capture full-opacity frames.
    @Test @MainActor
    func rotationContentOpacityIsOneOutsideALiveAnimatedCycle() throws {
        let model = AppModel()
        model.islandThemeID = "poured"
        model.loadDebugSnapshot(
            IslandDebugScenario.closedAttentionQueue.snapshot(at: Date(timeIntervalSince1970: 1_700_000_000)),
            presentOverlay: false
        )
        #expect(model.pouredSpotlightRotationIsLive)

        // A deterministic phase (parity driver / tests) is never mid-swap.
        model.pouredSpotlightRotationPhaseOverride = 3_500
        #expect(model.pouredClosedRotationContentOpacity == 1)
        #expect(model.islandClosedPillRotation()?.contentOpacity == 1)

        // Neither is any theme without a cycle.
        model.pouredSpotlightRotationPhaseOverride = nil
        model.islandThemeID = "classic"
        #expect(!model.pouredSpotlightRotationIsLive)
        #expect(model.pouredClosedRotationContentOpacity == 1)

        // The three collapsed-surface consumers all read that one value.
        // The three collapsed-surface consumers all read that one value through
        // the one fade modifier, so their curves cannot drift apart.
        let panel = try Self.source("Sources/OpenIslandApp/Views/IslandPanelView.swift")
        #expect(panel.components(separatedBy: "opacity: model.pouredClosedRotationContentOpacity").count == 3)
        #expect(panel.contains("glow.pouredRotationSwapFade("))
        let pillSource = try Self.source("Sources/OpenIslandApp/Views/Island/PouredClosedPill.swift")
        #expect(pillSource.contains("PouredSpotlightRotation.swapAnimation(fadingOut: opacity == 0)"))
    }

    /// X2: Poured's A4 wait lead is the board's THREE-bar `.glyph.wait`; every
    /// other theme keeps the shipped two-bar pause mark byte-identical.
    @Test @MainActor
    func pouredWaitGlyphDrawsThreeBarsAndOtherThemesKeepTwo() throws {
        #expect(UnifiedBars.waitBarHeights(showsMiddleWaitBar: false) == [10, 0, 10])
        #expect(UnifiedBars.waitBarHeights(showsMiddleWaitBar: true) == [10, 10, 10])

        // The Poured leaf is the only opt-in; the shared default is unchanged.
        let pill = try Self.source("Sources/OpenIslandApp/Views/Island/PouredClosedPill.swift")
        #expect(pill.contains("UnifiedBars(mode: unifiedMode, size: size, tint: tint, showsMiddleWaitBar: true)"))
        let bars = try Self.source("Sources/OpenIslandApp/Views/UnifiedBars.swift")
        #expect(bars.contains("var showsMiddleWaitBar: Bool = false"))
        for other in [
            "Sources/OpenIslandApp/Views/V6NotchContent.swift",
            "Sources/OpenIslandApp/Views/Island/FlightDeckClosedPill.swift",
            "Sources/OpenIslandApp/Theme/IslandTheme.swift",
        ] {
            #expect(!(try Self.source(other)).contains("showsMiddleWaitBar"))
        }
    }

    /// X3: the right-slot attention badge is the board's 20pt circle
    /// (`.count{min-width:20px;height:20px;border-radius:10px}`), not an r6 chip.
    @Test
    func attentionBadgeIsTheBoardsTwentyPointCircle() throws {
        #expect(PouredPillMotion.RightSlot.badgeMinDiameter == 20)
        #expect(PouredPillMotion.RightSlot.badgeCornerRadius == 10)
        #expect(PouredPillMotion.RightSlot.badgeHPadding == 6)

        let pill = try Self.source("Sources/OpenIslandApp/Views/Island/PouredClosedPill.swift")
        #expect(pill.contains("minWidth: PouredPillMotion.RightSlot.badgeMinDiameter,"))
        #expect(pill.contains("minHeight: PouredPillMotion.RightSlot.badgeMinDiameter"))
    }

    /// X4 / R12: the ruling is transcribed, and the two comments that claimed the
    /// badge value stays the aggregate total through both holds are corrected.
    @Test
    func ruling12IsTranscribedAndTheStaleBadgeCommentsAreGone() throws {
        let rulings = try Self.source("docs/design/overlay-redesign/poured-owner-rulings.md")
        #expect(rulings.contains("## R12 — Rotation question-phase badge"))
        #expect(rulings.contains("Version 5 — 2026-08-03"))

        let rotation = try Self.source("Sources/OpenIslandApp/PouredSpotlightRotation.swift")
        #expect(!rotation.contains("the badge keeps showing the **total** waiting count"))
        #expect(rotation.contains("owner ruling **R12**"))

        let model = try Self.source("Sources/OpenIslandApp/AppModel.swift")
        #expect(!model.contains("the value stays the aggregate\n    /// total the adjudication pinned"))
        #expect(model.contains("X4 / **R12**"))
    }

    /// X5: the collapsed pill's badge cannot claim a mixed set is all one kind.
    @Test
    func rotatingAttentionBadgeSpeaksTheAggregateNotTheKind() throws {
        let lang = Self.englishLanguage()
        // The per-kind sentences survive for the single-kind (non-rotating) case.
        #expect(lang.t("a11y.rightSlot.attention.permission", 2) == "2 waiting for approval")
        #expect(lang.t("a11y.rightSlot.attention.question", 2) == "2 waiting for an answer")
        // The rotating one names neither kind, so it is true of 1+1.
        let mixed = lang.t("poured.a11y.rightSlot.attention.mixed", 2)
        #expect(mixed == "2 waiting for you")
        #expect(!mixed.contains("approval"))
        #expect(!mixed.contains("answer"))

        let pill = try Self.source("Sources/OpenIslandApp/Views/Island/PouredClosedPill.swift")
        #expect(pill.contains("guard isRotating else { return content.fallbackBadgeAccessibilityLabel(lang) }"))
        #expect(pill.contains("PouredRightSlotView(content: rightSlot, isRotating: rotation != nil)"))
    }

    /// X6: the disabled §F Submit must be legible — ≥ 3:1 label-on-fill against
    /// **its own** fill, measured off the literals the view paints.
    @Test
    func disabledSubmitClearsThreeToOneAgainstItsOwnFill() throws {
        let ink = PouredQuestionColors.submitDisabledInkRGB
        for fill in [PouredQuestionColors.submitDisabledTopRGB, PouredQuestionColors.submitDisabledBottomRGB] {
            let ratio = Self.contrastRatio(ink, fill)
            #expect(ratio >= 3.0, "disabled Submit contrast \(ratio) < 3:1")
        }

        // The shared dim recipe (which composited both to 1.18:1 on the panel) is
        // no longer applied by the Poured label, and the shared constants — which
        // Halo and Flight Deck still use — are untouched.
        let row = try Self.source(Self.rowSource)
        #expect(!row.contains("IslandQuestionSubmitDisabledStyle.saturation"))
        #expect(!row.contains("IslandQuestionSubmitDisabledStyle.opacity"))
        #expect(IslandQuestionSubmitDisabledStyle.saturation == 0.35)
        #expect(IslandQuestionSubmitDisabledStyle.opacity == 0.5)
    }

    /// WCAG 2.x relative-luminance contrast, on plain sRGB components.
    private static func contrastRatio(
        _ a: (Double, Double, Double),
        _ b: (Double, Double, Double)
    ) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func relativeLuminance(_ rgb: (Double, Double, Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }

    /// X7: E1's fixture renders the board's TWO scope rows, and no generic
    /// fallback ever prints a raw tool identifier inside the gold chip.
    @Test
    func e1FixtureRendersTwoScopeRowsAndTheChipIsNeverAToolIdentifier() {
        // Reached through the scenario the E1 still is captured from
        // (`Validation/PouredParity/scenarios-v1.json` maps `E1-command-permission`
        // → `IslandDebugScenario.approvalCard`), so the pin follows the artifact.
        let snapshot = IslandDebugScenario.approvalCard.snapshot(
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let approval = snapshot.sessions.first { $0.id == "session-approval" }
        let updates = approval?.permissionRequest?.suggestedUpdates ?? []
        #expect(updates.count == 2)

        // Row 1 — the command-prefix grant scoped to the project. It is the row
        // that carries the `⌘⇧Y` cap (board: first row only), which the view
        // decides by index, so order is part of the contract.
        let first = PouredScopeCopy.shape(for: updates[0])
        #expect(first?.key == "poured.approval.scope.fromProject")
        #expect(first?.code == "sed -i ''")

        // Row 2 — the whole-tool grant, chip = the executable, no cap.
        let second = PouredScopeCopy.shape(for: updates[1])
        #expect(second?.key == "poured.approval.scope.allCommands")
        #expect(second?.code == "sed")

        // The generic fallback resolves the executable, never the harness id.
        #expect(PouredScopeCopy.genericScopeChip(
            toolName: "exec_command",
            commandPreview: "sed -i '' -e 's/a/b/g' /tmp/x.swift"
        ) == "sed")
        #expect(PouredScopeCopy.genericScopeChip(
            toolName: "Bash",
            commandPreview: "/usr/bin/swift build"
        ) == "swift")
        #expect(PouredScopeCopy.genericScopeChip(
            toolName: "run_terminal_cmd",
            commandPreview: "FOO=1 git status"
        ) == "git")
        // Nothing honest to print → no row at all, rather than `exec_command`.
        #expect(PouredScopeCopy.genericScopeChip(toolName: "exec_command", commandPreview: nil) == nil)
        #expect(PouredScopeCopy.genericScopeChip(toolName: "some_internal_tool", commandPreview: "  ") == nil)
        // A presentable tool name still stands on its own.
        #expect(PouredScopeCopy.genericScopeChip(toolName: "Edit", commandPreview: nil) == "Edit")
    }

    /// X10: the same control keeps one verb family across disabled and enabled.
    @Test
    func pouredSingleQuestionSubmitReadsSendAnswerInBothStates() throws {
        let panel = try Self.source("Sources/OpenIslandApp/Views/IslandPanelView.swift")
        #expect(panel.contains("if isPoured, structuredQuestions.count == 1 {\n            return lang.t(\"question.sendAnswer\")"))

        // The two controls that legitimately read differently are different
        // actions / different controls, and keep their own copy.
        let lang = Self.englishLanguage()
        #expect(lang.t("question.sendAnswer") == "Send answer")
        #expect(lang.t("question.submitAndNext") == "Submit & next")
        #expect(lang.t("poured.question.submit.multiSelect", 2) == "Submit 2 selected")
    }

    /// X11: §D's `.act` carries the board's narration clause, and the row's
    /// VoiceOver line no longer speaks an elapsed tail the board moved into the
    /// `LIVE` metadata cell.
    @Test
    func detailNarrationGainsTheBoardClauseAndTheAxLabelDropsTheLiveTail() throws {
        let fixture = AppearancePreviewFixtures.pouredSessionDetail(
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(fixture.summary == "narrating the bridge lifecycle change")
        #expect(fixture.narratedActivityLineText == "Editing AppModel.swift")

        // The composed §D object is the board's, verbatim.
        #expect(PouredDetailNarration.object(
            base: fixture.narratedActivity?.object,
            summary: fixture.summary,
            narratedLine: fixture.narratedActivityLineText
        ) == "AppModel.swift \u{00B7} narrating the bridge lifecycle change")

        // An echoing summary adds nothing and is dropped — the §C runner's
        // `"Editing AppModel.swift."` must never become
        // `AppModel.swift · Editing AppModel.swift`.
        #expect(PouredDetailNarration.object(
            base: "AppModel.swift",
            summary: "Editing AppModel.swift.",
            narratedLine: "Editing AppModel.swift"
        ) == "AppModel.swift")
        #expect(PouredDetailNarration.object(base: "AppModel.swift", summary: "  ", narratedLine: nil) == "AppModel.swift")
        #expect(PouredDetailNarration.object(base: nil, summary: "reading the registry", narratedLine: nil) == "reading the registry")

        // The §C runner is deliberately NOT changed — a collapsed row has no room
        // for the clause and the board gives it none.
        let runner = AppearancePreviewFixtures.pouredGroupedSix(
            now: Date(timeIntervalSince1970: 1_700_000_000)
        ).first { $0.id == "fixture-poured-c1-running" }
        #expect(runner?.summary == "Editing AppModel.swift.")

        let row = try Self.source(Self.rowSource)
        #expect(row.contains("object: detailNarrationObject(base: narrated.object, showsDetail: showsDetail)"))
        #expect(row.contains("private func accessibilityActivityNarrative(referenceDate: Date, showsDetail: Bool) -> String?"))
        #expect(row.contains("activitySegments(referenceDate: referenceDate, showsDetail: showsDetail)"))
        #expect(!row.contains("accessibilityActivityNarrative(referenceDate: referenceDate)\n"))
    }

    /// X13: `.amber-hero{padding:14px 16px 15px}` — the two axes differ, and the
    /// horizontal one is the board's 16, not the uniform 14 the card shipped.
    @Test
    func heroHorizontalPaddingIsTheBoardsSixteen() throws {
        let row = try Self.source(Self.rowSource)
        #expect(row.contains("static let horizontalPadding: CGFloat = 16"))
        #expect(row.contains("static let verticalPadding: CGFloat = 14"))
        #expect(row.contains(".padding(.horizontal, Self.horizontalPadding)"))
        #expect(row.contains(".padding(.vertical, Self.verticalPadding)"))
    }

    /// X8 (reviewer D's F-05): E2's `.fname` renders the board's
    /// `<file> · <hunk description>` shape, not the shipped `Updated +N −N`.
    /// Reached through the scenario `scenarios-v1.json` maps E2 to
    /// (`E2-diff-permission → IslandDebugScenario.diffApprovalCard`), so the pin
    /// follows the artifact rather than a private factory.
    @Test @MainActor
    func e2DiffHeaderRendersFileAndHunkAndFallsBackWithoutAHunk() {
        let lang = Self.englishLanguage()
        let snapshot = IslandDebugScenario.diffApprovalCard.snapshot(
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let session = snapshot.sessions.first { $0.id == "fixture-permission-diff" }
        let request = session?.permissionRequest
        // The fixture carries the file *and* the hunk clause the board's `.fname`
        // second segment states.
        #expect(request?.affectedPath == "AGENTS.md")
        #expect(request?.diffHunkDescription == "verification section")

        let source = request?.fileDiffSource
        let result = PermissionDiff.compute(
            oldText: source?.oldText ?? "",
            newText: source?.newText ?? ""
        )

        // The E2 artifact path: header reads `<file> · <hunk>`.
        let style = IslandDiffStyle.poured(
            tokens: .poured,
            reduceTransparency: false,
            fileName: request?.affectedPath,
            hunk: request?.diffHunkDescription
        )
        #expect(
            IslandDiffRenderer.resolvedHeader(style: style, result: result, lang: lang)
                == .fileName("AGENTS.md · verification section")
        )

        // A request WITHOUT a hunk keeps the shipped `Updated +N −N` header —
        // a header-less style — rather than emitting a dangling separator.
        let noHunk = IslandDiffStyle.poured(
            tokens: .poured,
            reduceTransparency: false,
            fileName: request?.affectedPath,
            hunk: nil
        )
        #expect(noHunk.header == nil)
        let fallback = IslandDiffRenderer.resolvedHeader(style: noHunk, result: result, lang: lang)
        #expect(fallback == .updatedCounts(
            title: "Updated",
            added: result.addedCount,
            removed: result.removedCount
        ))
        if case let .fileName(title) = fallback {
            Issue.record("fallback should not render a filename title, got \(title)")
        }
    }
}
