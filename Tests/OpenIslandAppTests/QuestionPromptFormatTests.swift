import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-325 stage 1 — the pure `QuestionPromptFormat` presentation logic for the
/// shared `StructuredQuestionPromptView` interior: marker shape, "Other"-last
/// display ordering with digit remapping, the contiguous-digit-run keyboard
/// hint (single question, or — since overlay remediation Phase 2C — an
/// all-questions page numbered with a running offset), the multi-select
/// running submit label, and the `Question N of M` progress readout.
///
/// The suite is `.serialized` and snapshots `appLanguage` because the localized
/// assertions pin a `LanguageManager` to a concrete language (whose `didSet`
/// writes `UserDefaults.standard`), mirroring the other theme suites.
@Suite(.serialized)
final class QuestionPromptFormatTests {
    private let savedLanguage: String?

    init() {
        savedLanguage = UserDefaults.standard.string(forKey: "appLanguage")
    }

    deinit {
        if let savedLanguage {
            UserDefaults.standard.set(savedLanguage, forKey: "appLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "appLanguage")
        }
    }

    private func manager(_ language: LanguageManager.AppLanguage) -> LanguageManager {
        let manager = LanguageManager()
        manager.language = language
        return manager
    }

    // MARK: - Marker shape

    @Test
    func multiSelectMarkerIsSquareWithTicketRadius() {
        #expect(QuestionPromptFormat.markerShape(multiSelect: true) == .square(cornerRadius: 4))
        #expect(QuestionPromptFormat.multiSelectMarkerCornerRadius == 4)
    }

    // MARK: - Option ordering ("Other" pinned last)

    @Test
    func freeformOtherAuthoredMidListMovesLastAndRemapsDigits() {
        // "Other" authored in the MIDDLE (authored index 1) must render last, and
        // digit N must still select the option the user sees numbered N.
        let options = [
            QuestionOption(label: "A"),
            QuestionOption(label: "Other", allowsFreeform: true),
            QuestionOption(label: "B"),
            QuestionOption(label: "C"),
        ]

        let ordered = QuestionPromptFormat.orderedOptions(options)

        #expect(ordered.map(\.option.label) == ["A", "B", "C", "Other"])
        // Display-index → original-option mapping survives the reorder.
        #expect(ordered.map(\.originalIndex) == [0, 2, 3, 1])
        // Digit 2 (display index 1) selects "B", not the authored-2nd "Other".
        #expect(ordered[1].option.label == "B")
        #expect(ordered[1].originalIndex == 2)
    }

    // MARK: - Page digit contiguity (keyboard hint gate)

    /// Overlay remediation Phase 2C: `IslandPanelView.keyboardHintCaption`'s
    /// gate, extracted here because no snapshot fixture wires a live
    /// `keyboardCoordinator` (`ThemeSnapshotting.swift:507` always passes
    /// `nil`) — so this predicate has no golden-level coverage to fall back
    /// on, and needs its own direct pin. Each test below names the theme
    /// bucket it stands in for.
    @Test
    func pageDigitsRestartForAnUnpaginatedMultiQuestionPrompt() {
        // Classic with several structured questions: no
        // pagination and more than one question on the page means
        // `currentPageDigitBases` is all-zero — each question's options
        // restart at 1, so this must be the one `false` case.
        #expect(!QuestionPromptFormat.pageDigitsAreContiguous(pageSize: nil, pageQuestionCount: 2))
    }

    // MARK: - Keyboard hint caption

    @Test
    func hintCapsDigitRangeAtNine() {
        let en = manager(.en)
        // Only 1…9 are keyboard-selectable, so 12 options still reads "1–9".
        #expect(
            QuestionPromptFormat.keyboardHint(optionCount: 12, lang: en)
                == "1–9 select · Enter submits · Esc closes"
        )
    }

    // MARK: - Progress readout

    @Test
    func progressIsNilForSingleQuestion() {
        let en = manager(.en)
        #expect(QuestionPromptFormat.progressReadout(questionIndex: 0, questionCount: 1, lang: en) == nil)
    }

    // MARK: - Localization coverage (every new key resolves in all 3 languages)

    /// Every AB-325 string resolves to a real translation — not the bare key — in
    /// English and both Chinese scripts (the shared theme-suite pattern).
    ///
    /// Overlay remediation Phase 2C added `question.submitAndNext` /
    /// `question.next` (D1 pagination's per-page advance label, routed
    /// through `lang.t(…)` in `IslandPanelView.nonFinalPageLabel` — Phase 2B
    /// had shipped them as plain English literals since
    /// `Resources/*.lproj/Localizable.strings` was outside its file set).
    /// Folded into this same coverage sweep rather than a separate test,
    /// since a key missing from `zh-Hans`/`zh-Hant` is exactly the failure
    /// mode this test exists to catch.
    @Test
    func allNewKeysLocalizeInEveryLanguage() {
        let keys = [
            "question.progress",
            "question.hint.keyboard.single",
            "question.hint.keyboard.range",
            "question.submit.multiSelect",
            "question.submitAndNext",
            "question.next",
        ]

        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = manager(language)
            for key in keys {
                let resolved = manager.t(key)
                #expect(resolved != key, "\(key) is unlocalized in \(language)")
                #expect(!resolved.isEmpty)
            }
        }
    }

    /// Poured Slice 5 (§F″). The board never flags the compact single — it is
    /// derived from the question's own shape — so this pins the derivation
    /// against the three §F frames themselves: F″'s fixture takes it, and F′
    /// (multi-select, three options) and F (three described options plus the
    /// freeform `Other`) do not. The four one-condition mutations below each
    /// break it individually, so no single condition can be dropped silently.
    @Test
    func compactQuestionLayoutIsDerivedFromTheBoardsOwnFFrames() throws {
        let now = Date()
        let compact = AppearancePreviewFixtures.pouredCompactQuestion(now: now)
        let multiSelect = AppearancePreviewFixtures.pouredMultiSelectQuestion(now: now)
        let multiQuestion = AppearancePreviewFixtures.questionMulti(now: now)

        #expect(PouredCompactQuestionLayout.applies(to: compact.questionPrompt?.questions ?? []))
        #expect(!PouredCompactQuestionLayout.applies(to: multiSelect.questionPrompt?.questions ?? []))
        #expect(!PouredCompactQuestionLayout.applies(to: multiQuestion.questionPrompt?.questions ?? []))
        #expect(!PouredCompactQuestionLayout.applies(to: []))

        let base = try #require(compact.questionPrompt?.questions.first)

        var multi = base
        multi.multiSelect = true
        #expect(!PouredCompactQuestionLayout.applies(to: [multi]))

        var three = base
        three.options.append(QuestionOption(label: "Roll back"))
        #expect(!PouredCompactQuestionLayout.applies(to: [three]))

        var described = base
        described.options[0].description = "Ship the build to prod."
        #expect(!PouredCompactQuestionLayout.applies(to: [described]))

        var freeform = base
        freeform.options[1].allowsFreeform = true
        #expect(!PouredCompactQuestionLayout.applies(to: [freeform]))
    }
}
