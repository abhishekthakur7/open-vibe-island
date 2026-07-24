import SwiftUI
import OpenIslandCore

/// Colour half of the island theme token layer.
///
/// Values are lifted verbatim from the pre-theme constants they will
/// eventually replace: `V6Palette` for the two surface tones, and
/// `IslandDesignPalette.Status` / `.Contrast` for status tints, body-text
/// opacities and hairline dividers.
///
/// Nothing consumes these yet — later tickets route views through the token
/// layer one region at a time, and the legacy constants stay in place until
/// their last call site is migrated. `IslandThemeTokensTests` pins every
/// `classic` value against the live constant so drift in either direction
/// fails the build.
struct IslandColorTokens: Equatable, Sendable {

    // MARK: - Surface

    /// Near-black island body. Mirrors `V6Palette.ink`.
    var surfaceInk: Color

    /// Warm off-white for text and glyphs drawn on `surfaceInk`.
    /// Mirrors `V6Palette.paper`.
    var paper: Color

    // MARK: - Status tints

    /// A session that is actively working.
    var statusRunning: Color

    /// A session that finished successfully.
    var statusCompleted: Color

    /// A session blocked on a permission request.
    var statusWaitingForApproval: Color

    /// A session blocked on a question.
    var statusWaitingForAnswer: Color

    /// Single tint for a collapsed "N sessions waiting" roll-up, where the
    /// individual approval/answer tints would be misleading.
    var statusWaitingAggregate: Color

    /// Shared "caution" amber — bypass-permissions chips and the interrupted
    /// completion outcome.
    var statusWarning: Color

    /// A session whose turn was interrupted. Same amber as `statusWarning`.
    var statusInterrupted: Color

    /// A session that finished with a failure outcome.
    var statusFailed: Color

    /// An idle session with no recent activity.
    var statusIdle: Color

    /// A session whose process is no longer running.
    var statusInactive: Color

    // MARK: - Text contrast

    /// Opacity for de-emphasised-but-informative body text.
    var secondaryTextOpacity: Double

    /// Opacity for the dimmest still-legible text tier.
    var tertiaryTextOpacity: Double

    /// Added to a text opacity (clamped at 1) when the user has the system's
    /// Increase Contrast setting enabled.
    var increasedContrastTextBoost: Double

    // MARK: - Hairline

    /// Opacity for row/section dividers at default contrast.
    var hairlineOpacity: Double

    /// Opacity for row/section dividers when Increase Contrast is enabled.
    var hairlineOpacityIncreasedContrast: Double
}

// MARK: - Derived contrast values

extension IslandColorTokens {
    /// Mirrors `IslandDesignPalette.Contrast.text(_:increaseContrast:)`.
    func text(_ base: Double, increaseContrast: Bool) -> Double {
        increaseContrast ? min(1, base + increasedContrastTextBoost) : base
    }

    /// Mirrors `IslandDesignPalette.Contrast.hairline(increaseContrast:)`.
    func hairline(increaseContrast: Bool) -> Double {
        increaseContrast ? hairlineOpacityIncreasedContrast : hairlineOpacity
    }

    /// `secondaryTextOpacity` with the Increase Contrast boost applied.
    var secondaryTextOpacityIncreasedContrast: Double {
        text(secondaryTextOpacity, increaseContrast: true)
    }

    /// `tertiaryTextOpacity` with the Increase Contrast boost applied.
    var tertiaryTextOpacityIncreasedContrast: Double {
        text(tertiaryTextOpacity, increaseContrast: true)
    }
}

// MARK: - Status tint resolution

extension IslandColorTokens {
    /// Mirrors `IslandDesignPalette.Status.tint(for:outcome:)`.
    func statusTint(for phase: SessionPhase, outcome: SessionOutcome = .success) -> Color {
        switch phase {
        case .waitingForApproval:
            statusWaitingForApproval
        case .waitingForAnswer:
            statusWaitingForAnswer
        case .running:
            statusRunning
        case .completed:
            switch outcome {
            case .success:
                statusCompleted
            case .interrupted:
                statusInterrupted
            case .failed:
                statusFailed
            }
        }
    }

    /// Mirrors `IslandDesignPalette.Status.tint(for:presence:outcome:)`.
    func statusTint(
        for phase: SessionPhase,
        presence: IslandSessionPresence,
        outcome: SessionOutcome = .success
    ) -> Color {
        if phase == .waitingForApproval || phase == .waitingForAnswer {
            return statusTint(for: phase)
        }

        switch presence {
        case .running:
            return statusRunning
        case .active:
            // Presence only resolves to `.active` here when the phase is
            // `.completed` (running/attention phases are handled above),
            // so it's safe to fold in the outcome tint.
            return statusTint(for: .completed, outcome: outcome)
        case .inactive:
            return statusInactive
        }
    }
}

// MARK: - Classic

extension IslandColorTokens {
    /// Today's shipping palette, expressed as literals so the token layer is
    /// self-contained once the legacy constants are retired.
    static let classic = IslandColorTokens(
        surfaceInk: classicInk,
        paper: classicPaper,
        statusRunning: Color(red: 110.0 / 255.0, green: 167.0 / 255.0, blue: 255.0 / 255.0),
        statusCompleted: Color(red: 111.0 / 255.0, green: 185.0 / 255.0, blue: 130.0 / 255.0),
        statusWaitingForApproval: Color(red: 244.0 / 255.0, green: 164.0 / 255.0, blue: 164.0 / 255.0),
        statusWaitingForAnswer: Color(red: 255.0 / 255.0, green: 213.0 / 255.0, blue: 138.0 / 255.0),
        statusWaitingAggregate: Color(red: 231.0 / 255.0, green: 167.0 / 255.0, blue: 98.0 / 255.0),
        statusWarning: classicWarning,
        statusInterrupted: classicWarning,
        statusFailed: Color(red: 0.86, green: 0.32, blue: 0.32),
        statusIdle: classicPaper.opacity(0.35),
        statusInactive: classicPaper.opacity(0.38),
        secondaryTextOpacity: 0.55,
        tertiaryTextOpacity: 0.48,
        increasedContrastTextBoost: 0.24,
        hairlineOpacity: 0.055,
        hairlineOpacityIncreasedContrast: 0.22
    )

    private static let classicInk = Color(red: 0x0d / 255.0, green: 0x0d / 255.0, blue: 0x0f / 255.0)
    private static let classicPaper = Color(red: 0xf1 / 255.0, green: 0xea / 255.0, blue: 0xd9 / 255.0)
    private static let classicWarning = Color(red: 0.85, green: 0.55, blue: 0.15)
}
