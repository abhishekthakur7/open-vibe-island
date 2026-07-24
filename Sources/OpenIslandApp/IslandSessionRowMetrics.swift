import CoreGraphics

/// Fixed lanes for the trailing cluster of a session row (agent pill, age,
/// detail chevron, dismiss) so those columns land on the same x across every
/// row, whatever optional badges — model, permission mode, SSH, terminal —
/// the row happens to carry.
///
/// The widths are literal points and deliberately not type-scaled: every
/// label and glyph they wrap uses a hard-coded font size for the reasons
/// spelled out in `IslandSessionRow`'s AB-244 note on compact badges, so a
/// scaled lane would only add slack at larger text sizes.
enum IslandSessionRowMetrics {
    /// Constant gap between neighbouring items in the trailing cluster, and
    /// therefore between the variable badge group and the age column.
    static let badgeSpacing: CGFloat = 6

    /// Width of the agent title inside its pill. Sized to the six-character
    /// titles (`claude`, `gemini`, `cursor`) at 10.5pt monospaced; shorter
    /// ones pad up to the same lane so the pill edge holds still between
    /// rows running different agents.
    static let agentTitleWidth: CGFloat = 39

    /// Widest label `ageBadgeText` produces short of a hundred-day run
    /// (`23h 59m`, `99d 23h`) at 10.5pt monospaced. A longer label widens
    /// the lane rather than truncating the time.
    static let ageColumnWidth: CGFloat = 46

    static let detailToggleColumnWidth: CGFloat = 28
    static let dismissColumnWidth: CGFloat = 16

    /// Shared height for the two trailing controls, so the chevron and the
    /// dismiss glyph share a centre line and an equally tall hit target.
    static let trailingControlHeight: CGFloat = 28
}
