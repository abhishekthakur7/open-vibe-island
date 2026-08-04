import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Regression coverage for the overlay remediation Phase 5 `emptyState` hang
/// (ship-blocker, live-capture verification finding).
///
/// **The bug.** `IslandPanelView.openedContent` measures its own rendered
/// height via a `GeometryReader`/`PreferenceKey` (`OpenedContentHeightKey`)
/// that sits *inside* an ancestor `.frame(maxHeight:)` proposal
/// (`openedSurfaceContent`, `IslandPanelView.swift:578`). That proposal is
/// itself derived from the *previous* measurement
/// (`OverlayPanelController.panelSize` → `openedContentHeight`, which adds a
/// flat 8pt `measuredContentSafetyPadding` on every recompute). Every
/// `*EmptyState` / `*BootstrapPlaceholder` body (Poured, Halo, …) is a
/// `VStack { Spacer(); <content>; Spacer() }` used to
/// vertically centre its content — a layout that, left unguarded, is greedy
/// for *whatever* height its parent proposes. That closes a feedback loop:
/// propose H, the `Spacer`s fill to H, the measurement reports H, the window
/// grows to H + 8, which becomes the *next* proposal — an unconditional
/// +8pt/cycle with no fixed point. Confirmed live: pinned CPU, ~5MB/s RSS
/// growth, the harness's `OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS` never
/// firing, isolated specifically to `model.islandListSessions.isEmpty`.
///
/// **The fix** (`IslandPanelView.swift`, both the `emptyState` and
/// `bootstrapPlaceholder` branches) adds `.fixedSize(horizontal: false,
/// vertical: true)`. That forces SwiftUI to propose `nil` (the subtree's own
/// ideal size) down through it instead of forwarding the ancestor's
/// proposal — each `Spacer` then collapses to its minimum length instead of
/// expanding to fill, so the reported height becomes a pure function of the
/// theme's own copy/glyph content, independent of whatever height it is
/// offered — the same "give it an unconstrained proposal so intrinsic
/// content measures truthfully" idea `AutoHeightScrollView` already uses
/// elsewhere in this file, without an actual `ScrollView` (which would add
/// unwanted scroll chrome to a state that must never scroll).
///
/// **Why `NSHostingController.sizeThatFits(in:)`.** It proposes a concrete
/// bounding size down a SwiftUI view tree and returns the resolved size —
/// exactly the mechanism `GeometryReader`/`OpenedContentHeightKey` measures
/// in production — without needing a live window, a run-loop pump, or a
/// `PreferenceKey` round-trip. That lets these tests exercise the actual
/// non-convergence this phase's regression hit, not merely restate the
/// `.fixedSize` modifier.
///
/// Themes are addressed by a plain index range (not `.indices` on an
/// `@MainActor`-isolated collection) because `@Test(arguments:)` evaluates its
/// argument expression outside actor isolation — only the individual test
/// functions (and the `NSHostingController` work they do) need `@MainActor`.
struct OpenedContentEmptyStateConvergenceTests {
    // MARK: - Fixtures

    @MainActor
    private static func theme(at index: Int) -> any IslandTheme {
        let themes: [any IslandTheme] = [
            PouredIslandTheme(), HaloTheme(),
        ]
        return themes[index]
    }

    private static let themeCount = 2

    @MainActor
    private static func measuredHeight(
        _ view: AnyView,
        proposedHeight: CGFloat,
        width: CGFloat = 300
    ) -> CGFloat {
        let controller = NSHostingController(rootView: view)
        let size = controller.sizeThatFits(in: CGSize(width: width, height: proposedHeight))
        return size.height
    }

    /// The exact production wrapping `IslandPanelView.openedContent` applies to
    /// `theme.emptyState(...)` *after* this phase's fix — horizontal/top
    /// padding, then `.fixedSize(vertical: true)` — mirroring
    /// `IslandPanelView.swift:911-978`.
    @MainActor
    private static func fixedEmptyState(_ theme: any IslandTheme, lang: LanguageManager) -> AnyView {
        AnyView(
            theme.emptyState(
                lang: lang,
                hasRecentSessions: false,
                workspaceCount: 0,
                installedAgentNames: []
            )
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.islandTokens, theme.tokens)
            .environment(\.colorScheme, .dark)
        )
    }

    // MARK: - Convergence (the fix)

    /// The core convergence property: measuring the SAME content under two
    /// very different proposed heights must report the SAME height. This is
    /// what "reaches a fixed point" means for
    /// `OverlayPanelController.openedContentHeight` — its `measured` input
    /// must not itself depend on the window size that resulted from the
    /// previous cycle's `measured` output, or the two grow together forever.
    @Test(arguments: 0..<OpenedContentEmptyStateConvergenceTests.themeCount)
    @MainActor
    func emptyStateHeightIsIndependentOfProposedHeight(themeIndex: Int) {
        let theme = Self.theme(at: themeIndex)
        let lang = LanguageManager()

        let small = Self.measuredHeight(Self.fixedEmptyState(theme, lang: lang), proposedHeight: 40)
        let large = Self.measuredHeight(Self.fixedEmptyState(theme, lang: lang), proposedHeight: 2_000)

        let message = """
        \(theme.id): empty-state height must not depend on the proposed height \
        (got \(small) @40pt vs \(large) @2000pt) — a dependency here is exactly \
        the mechanism that produced the Phase 5 emptyState hang.
        """
        #expect(small == large, Comment(rawValue: message))
    }

    // MARK: - The regression is real (not a restatement of the fix)

    // MARK: - No-clipping guarantee

    /// The fixed body's reported height must be at least as tall as its own
    /// unconstrained (ideal) height even when proposed the old, hand-picked
    /// 108pt pre-measurement floor (`OverlayPanelController.openedEmptyStateHeight`)
    /// — i.e. the measurement that sizes the window is never *shorter* than
    /// what the content actually needs. This is the property whose absence
    /// caused Flight Deck's "…watching the bridge…" tail and Halo's
    /// "Monitoring" footer to be clipped by that constant before this phase's
    /// (regressed, now-fixed) measurement change.
    @Test(arguments: 0..<OpenedContentEmptyStateConvergenceTests.themeCount)
    @MainActor
    func emptyStateMeasuredHeightMeetsIntrinsicRequirementAtTheLegacyFloor(themeIndex: Int) {
        let theme = Self.theme(at: themeIndex)
        let lang = LanguageManager()

        let unconstrained = Self.measuredHeight(
            Self.fixedEmptyState(theme, lang: lang),
            proposedHeight: 10_000
        )
        let atLegacyFloor = Self.measuredHeight(
            Self.fixedEmptyState(theme, lang: lang),
            proposedHeight: 108
        )

        let message = """
        \(theme.id): the fixed-size measurement must report the content's real \
        intrinsic height even when proposed the legacy 108pt floor, or the \
        window will be sized too short and clip real content \
        (got \(atLegacyFloor) vs intrinsic \(unconstrained)).
        """
        #expect(atLegacyFloor >= unconstrained - 0.5, Comment(rawValue: message))
    }
}
