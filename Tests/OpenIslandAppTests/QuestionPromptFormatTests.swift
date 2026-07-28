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
/// writes `UserDefaults.standard`), mirroring `AnnualThemeTests`.
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

    @Test
    func singleSelectMarkerIsCircle() {
        #expect(QuestionPromptFormat.markerShape(multiSelect: false) == .circle)
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

    @Test
    func freeformAlreadyLastIsStable() {
        let options = [
            QuestionOption(label: "A"),
            QuestionOption(label: "B"),
            QuestionOption(label: "Other", allowsFreeform: true),
        ]

        let ordered = QuestionPromptFormat.orderedOptions(options)

        #expect(ordered.map(\.option.label) == ["A", "B", "Other"])
        #expect(ordered.map(\.originalIndex) == [0, 1, 2])
    }

    @Test
    func noFreeformPreservesAuthoredOrder() {
        let options = [
            QuestionOption(label: "A"),
            QuestionOption(label: "B"),
            QuestionOption(label: "C"),
        ]

        let ordered = QuestionPromptFormat.orderedOptions(options)

        #expect(ordered.map(\.option.label) == ["A", "B", "C"])
        #expect(ordered.map(\.originalIndex) == [0, 1, 2])
    }

    @Test
    func multipleFreeformOptionsKeepRelativeOrderAtEnd() {
        let options = [
            QuestionOption(label: "Other1", allowsFreeform: true),
            QuestionOption(label: "A"),
            QuestionOption(label: "Other2", allowsFreeform: true),
        ]

        let ordered = QuestionPromptFormat.orderedOptions(options)

        #expect(ordered.map(\.option.label) == ["A", "Other1", "Other2"])
        #expect(ordered.map(\.originalIndex) == [1, 0, 2])
    }

    @Test
    func emptyOptionsReturnEmpty() {
        #expect(QuestionPromptFormat.orderedOptions([]).isEmpty)
    }

    // MARK: - Page digit contiguity (keyboard hint gate)

    /// Overlay remediation Phase 2C: `IslandPanelView.keyboardHintCaption`'s
    /// gate, extracted here because no snapshot fixture wires a live
    /// `keyboardCoordinator` (`ThemeSnapshotting.swift:507` always passes
    /// `nil`) — so this predicate has no golden-level coverage to fall back
    /// on, and needs its own direct pin. Each test below names the theme
    /// bucket it stands in for.
    @Test
    func pageDigitsAreContiguousForAOneQuestionPage() {
        // Poured/Halo: `questionPageSize` 1, so every page holds exactly one
        // question — trivially contiguous.
        #expect(QuestionPromptFormat.pageDigitsAreContiguous(pageSize: 1, pageQuestionCount: 1))
    }

    @Test
    func pageDigitsAreContiguousForAnAllQuestionsPaginatedPage() {
        // Flight Deck: `questionPageSize` is `Int.max`, collapsing every
        // question onto one page — still contiguous, since pagination being
        // *engaged* (not the page's question count) is what drives
        // `currentPageDigitBases`'s running offset (F1a).
        #expect(QuestionPromptFormat.pageDigitsAreContiguous(pageSize: Int.max, pageQuestionCount: 2))
    }

    @Test
    func pageDigitsAreContiguousForAnUnpaginatedSingleQuestionPrompt() {
        // Classic/Annual/Instrument with exactly one structured question:
        // `questionPageSize` is `nil` (no pagination), but a single question
        // has nothing to restart against — contiguous regardless.
        #expect(QuestionPromptFormat.pageDigitsAreContiguous(pageSize: nil, pageQuestionCount: 1))
    }

    @Test
    func pageDigitsRestartForAnUnpaginatedMultiQuestionPrompt() {
        // Classic/Annual/Instrument with several structured questions: no
        // pagination and more than one question on the page means
        // `currentPageDigitBases` is all-zero — each question's options
        // restart at 1, so this must be the one `false` case.
        #expect(!QuestionPromptFormat.pageDigitsAreContiguous(pageSize: nil, pageQuestionCount: 2))
    }

    // MARK: - Keyboard hint caption

    @Test
    func hintForSingleQuestionRendersCappedRange() {
        let en = manager(.en)
        #expect(
            QuestionPromptFormat.keyboardHint(optionCount: 3, lang: en)
                == "1–3 select · Enter submits · Esc closes"
        )
    }

    @Test
    func hintForSingleOptionRendersJustOne() {
        let en = manager(.en)
        #expect(
            QuestionPromptFormat.keyboardHint(optionCount: 1, lang: en)
                == "1 select · Enter submits · Esc closes"
        )
    }

    @Test
    func hintCapsDigitRangeAtNine() {
        let en = manager(.en)
        // Only 1…9 are keyboard-selectable, so 12 options still reads "1–9".
        #expect(
            QuestionPromptFormat.keyboardHint(optionCount: 12, lang: en)
                == "1–9 select · Enter submits · Esc closes"
        )
    }

    /// Overlay remediation Phase 2C: `keyboardHint` dropped `questionCount` —
    /// the "is this page's numbering contiguous" gate it used to enforce
    /// (`questionCount == 1`) moved to the caller, `IslandPanelView
    /// .keyboardHintCaption`, which is the only place `theme.questionPageSize`
    /// and `currentPage` are both in scope (see that property's doc). This
    /// pure formatter no longer has a way to *be* "nil for multi-question" —
    /// it renders whatever contiguous count it's given, whether that count
    /// came from one question or several. Replaces the old
    /// `hintIsNilForMultiQuestionPrompt`, which asserted a parameter that no
    /// longer exists; the call-site gate it used to pin is now covered by
    /// `ThemeSnapshotHarnessTests` (Flight Deck gains a caption; Classic's
    /// unpaginated multi-question page still gets none).
    @Test
    func hintRendersCombinedRangeForAnAllQuestionsPage() {
        let en = manager(.en)
        // Flight Deck's page holds every question with a running digit
        // offset (F1a) — the conformance fixture's 3 + 4 = 7 options render
        // as one continuous "1–7", the same shape a single 7-option question
        // would, because the function can't tell (and doesn't need to) how
        // many questions the count came from.
        #expect(
            QuestionPromptFormat.keyboardHint(optionCount: 7, lang: en)
                == "1–7 select · Enter submits · Esc closes"
        )
    }

    /// D1 pagination (overlay remediation Phase 2B): `StructuredQuestionPromptView
    /// .keyboardHintCaption` calls this with `currentPageFlatOptions.count` —
    /// true whenever a page holds exactly one question, regardless of how many
    /// *other* questions exist on other pages (Poured/Halo's second page: 4
    /// options, one question). Distinct from `hintForSingleQuestionRendersCappedRange`
    /// above (3 options, an unpaginated single-question prompt) — same
    /// contract, a different call site now relies on it too.
    @Test
    func hintForSingleQuestionOnAPaginatedPageRendersCappedRange() {
        let en = manager(.en)
        #expect(
            QuestionPromptFormat.keyboardHint(optionCount: 4, lang: en)
                == "1–4 select · Enter submits · Esc closes"
        )
    }

    @Test
    func hintIsNilWhenNoOptions() {
        let en = manager(.en)
        #expect(QuestionPromptFormat.keyboardHint(optionCount: 0, lang: en) == nil)
    }

    // MARK: - Multi-select submit label (running count)

    @Test
    func multiSelectSubmitLabelReflectsCount() {
        let en = manager(.en)
        #expect(QuestionPromptFormat.multiSelectSubmitLabel(selectedCount: 0, lang: en) == "Submit — 0 selected")
        #expect(QuestionPromptFormat.multiSelectSubmitLabel(selectedCount: 1, lang: en) == "Submit — 1 selected")
        #expect(QuestionPromptFormat.multiSelectSubmitLabel(selectedCount: 3, lang: en) == "Submit — 3 selected")
    }

    // MARK: - Progress readout

    @Test
    func progressIsNilForSingleQuestion() {
        let en = manager(.en)
        #expect(QuestionPromptFormat.progressReadout(questionIndex: 0, questionCount: 1, lang: en) == nil)
    }

    @Test
    func progressRendersOneBasedForMultiQuestion() {
        let en = manager(.en)
        #expect(
            QuestionPromptFormat.progressReadout(questionIndex: 0, questionCount: 2, lang: en)
                == "Question 1 of 2"
        )
        #expect(
            QuestionPromptFormat.progressReadout(questionIndex: 1, questionCount: 3, lang: en)
                == "Question 2 of 3"
        )
    }

    /// D1 pagination (overlay remediation Phase 2B): `StructuredQuestionPromptView
    /// .currentPageStartIndex` feeds `questionIndex` as an *absolute* position into
    /// the full (unpaginated) `structuredQuestions` list, and `questionCount` stays
    /// the full list's count — never the current page's — so this exact pair is
    /// what Poured/Halo's *second* page (one question, page size 1) passes: the
    /// index has advanced but the total hasn't. `progressReadout`'s contract
    /// already generalizes to this (it takes an absolute index + a total, not two
    /// page-relative numbers), so pagination needed no production change here —
    /// this test pins that the reliance is sound, not merely assumed.
    @Test
    func progressReadoutIsAbsoluteAcrossPaginatedPages() {
        let en = manager(.en)
        #expect(
            QuestionPromptFormat.progressReadout(questionIndex: 1, questionCount: 2, lang: en)
                == "Question 2 of 2"
        )
    }

    // MARK: - Localization coverage (every new key resolves in all 3 languages)

    /// Every AB-325 string resolves to a real translation — not the bare key — in
    /// English and both Chinese scripts (the `AnnualThemeTests` pattern).
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
}
