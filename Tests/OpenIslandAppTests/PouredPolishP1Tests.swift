import Foundation
import SwiftUI
import Testing
import OpenIslandCore
@testable import OpenIslandApp

/// P1 board-conformance polish (R14): where native diverged from the rendered
/// board `01-poured-island.html` on pure look, the board wins. Pure source /
/// value pins in the `PouredSlice5CorrectionsTests` style — no view mounting.
struct PouredPolishP1Tests {

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
    private static let headerSource = "Sources/OpenIslandApp/Views/Island/PouredHeaderControls.swift"
    private static let panelSource = "Sources/OpenIslandApp/Views/IslandPanelView.swift"
    private static let markdownSource = "Sources/OpenIslandApp/Views/LocalMarkdownText.swift"

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - P1 · §E hero interior bloom

    /// The `.amber-hero` interior is the board's near-black warm well
    /// `linear-gradient(180deg, rgba(58,42,20,.55), rgba(30,22,12,.6))` (`:303`),
    /// not the bright-amber-at-low-alpha fill that read ~3× lighter.
    @Test
    func heroInteriorUsesTheBoardsDarkWarmWell() throws {
        let row = try Self.source(Self.rowSource)
        #expect(row.contains("shape.fill(heroWellGradient)"))
        #expect(row.contains("static let heroWellTop = Color(red: 0x3A/255, green: 0x2A/255, blue: 0x14/255).opacity(0.55)"))
        #expect(row.contains("static let heroWellBottom = Color(red: 0x1E/255, green: 0x16/255, blue: 0x0C/255).opacity(0.6)"))
        // E3's blue `.amber-hero` override (`:1089`).
        #expect(row.contains("static let heroWellBlueTop = Color(red: 0x18/255, green: 0x28/255, blue: 0x36/255).opacity(0.5)"))
        #expect(row.contains("static let heroWellBlueBottom = Color(red: 0x0E/255, green: 0x18/255, blue: 0x22/255).opacity(0.55)"))
        // The shipped bright-amber gradient fill is gone (the `.hero-icon` chip's
        // own `accent.opacity(0.16)` at `:311` is a different element and stays).
        #expect(!row.contains("colors: [accent.opacity(0.16), accent.opacity(0.08)]"))
    }

    // MARK: - P2 · F″ compact question is bare glass

    /// The board's F″ compact single (`:1245-1256`) is bare glass — no `.q-hero`
    /// gradient card, no inset ring — so the Poured compact variant drops the
    /// wrapper (the gold comes from the row's own radial wash).
    @Test
    func compactQuestionDropsTheGoldHeroWrapper() throws {
        let row = try Self.source(Self.rowSource)
        #expect(row.contains("if isCompactQuestion {"))
        #expect(row.contains("PouredCompactQuestionLayout.applies(to: session.questionPrompt?.questions ?? [])"))

        // The F4 fixture is exactly the compact shape the wrapper is dropped for.
        let compact = AppearancePreviewFixtures.pouredCompactQuestion(now: Self.now)
        #expect(PouredCompactQuestionLayout.applies(to: compact.questionPrompt?.questions ?? []))
    }

    // MARK: - P3 · opened-panel header control glyphs

    /// Board §C header (`:791-796`) draws stroked speaker-x / gear / X, not the
    /// filled `speaker.wave.2.fill` / `gearshape.fill` / `power` set.
    @Test
    func openedHeaderControlsUseStrokedBoardGlyphs() throws {
        let header = try Self.source(Self.headerSource)
        #expect(header.contains("isSoundMuted ? \"speaker.slash\" : \"speaker.wave.2\""))
        #expect(header.contains("systemName: \"gearshape\","))
        #expect(header.contains("systemName: \"xmark\","))
        #expect(!header.contains("speaker.wave.2.fill"))
        #expect(!header.contains("gearshape.fill"))
        #expect(!header.contains("systemName: \"power\""))
    }

    // MARK: - P4 · no far-left header state-glyph

    /// The board's §C `.p-head` (`:782-798`) opens on the usage meter with no
    /// lead-marker cluster, so Poured's traveling glyph fades out on open rather
    /// than persisting at far left.
    @Test
    func pouredGlyphDoesNotPersistInTheOpenedHeader() throws {
        let panel = try Self.source(Self.panelSource)
        #expect(panel.contains("private var travelsGlyphOnOpen: Bool { usesNotchAwareOpenedHeader && theme.id != \"poured\" }"))
    }

    // MARK: - P5 · E2 `.fname` header chrome

    /// The board's `.fname` (`:342`) carries `padding:6px 10px` and a
    /// `border-bottom:1px solid rgba(242,245,251,.09)`.
    @Test
    func diffHeaderGainsTheFnameBorderAndPadding() {
        let style = IslandDiffStyle.poured(
            tokens: .poured,
            reduceTransparency: false,
            fileName: "README.md",
            hunk: "support matrix"
        )
        #expect(style.header?.horizontalPadding == 10)
        #expect(style.header?.verticalPadding == 6)
        #expect(style.header?.bottomBorder != nil)
        #expect(style.header?.bottomBorder?.width == 1)
    }

    // MARK: - P6a · `.amber-hero` bottom padding 15

    @Test
    func heroBottomPaddingIsFifteen() throws {
        let row = try Self.source(Self.rowSource)
        #expect(row.contains("static let bottomPadding: CGFloat = 15"))
        #expect(row.contains(".padding(.bottom, Self.bottomPadding)"))
    }

    // MARK: - P6b · E3 codex-note glyph

    /// The board's E3 `.codex-note` glyph (`:1100-1101`) is a down arrow into a
    /// tray, not the external-link box `arrow.up.forward.app`.
    @Test
    func codexNoteUsesTheTrayDownGlyph() throws {
        let row = try Self.source(Self.rowSource)
        #expect(row.contains("Image(systemName: \"tray.and.arrow.down\")"))
    }

    // MARK: - P6c · "+N more lines" inside the diff well

    /// The board keeps its "+N more" compression inside the surface it summarizes
    /// (`:729`), so the clamped remainder rides inside the diff well via
    /// `additionalHiddenLines`, not as a floating line below it.
    @Test
    func moreLinesRidesInsideTheDiffWell() throws {
        let row = try Self.source(Self.rowSource)
        #expect(row.contains("additionalHiddenLines: clamped.hiddenLineCount"))
        #expect(!row.contains("Text(lang.t(\"approval.diffMoreLines\", clamped.hiddenLineCount))"))

        let style = IslandDiffStyle.poured(
            tokens: .poured,
            reduceTransparency: false,
            fileName: "README.md",
            hunk: "x",
            additionalHiddenLines: 4
        )
        #expect(style.additionalHiddenLines == 4)
        // A non-clamping caller stays at the renderer default.
        #expect(IslandDiffStyle.standard(tokens: .poured).additionalHiddenLines == 0)
    }

    // MARK: - P6d · §D bullet rhythm

    /// The board's `.assistant li{margin:3px 0}` (`:441`) sets list items looser
    /// than paragraph lines; SwiftUI (no margin collapse) reproduces it as a 6pt
    /// inter-item gap, Poured only.
    @Test
    func pouredAssistantListItemsAreLooser() throws {
        let markdown = try Self.source(Self.markdownSource)
        #expect(markdown.contains("self == .pouredAssistant ? 6 : 3"))
        #expect(markdown.contains("VStack(alignment: .leading, spacing: style.listItemSpacing)"))
    }

    // MARK: - P6e · `.amh` concise vendor name

    /// The board's `.amh` byline reads `Last message · Claude` (`:953`) — the
    /// concise vendor name, not the full `Claude Code` product name.
    @Test
    func lastMessageBylineUsesTheConciseVendorName() throws {
        let row = try Self.source(Self.rowSource)
        #expect(row.contains("lang.t(\"poured.detail.lastMessage\", session.tool.shortName)"))
        #expect(!row.contains("lang.t(\"poured.detail.lastMessage\", session.tool.displayName)"))
        #expect(AgentTool.claudeCode.shortName == "CLAUDE")
    }
}
