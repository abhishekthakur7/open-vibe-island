import CoreGraphics
import Foundation
import OpenIslandCore

/// Motion + pure presentation vocabulary for the Poured 2.0 **session row**
/// list state (AB-332, `SPEC-poured-island` §3.3 / §4C · mockup §C).
///
/// A sibling of `PouredPillMotion`: the pill owns the closed-pill ambient
/// states, this owns the row. Like the pill table it is a pure, `Equatable`-
/// friendly vector of geometry / timing (colours come from the token layer at
/// the view site), so `PouredRowMotionTests` can pin every number and drift
/// fails the build instead of the eye.
///
/// The `PouredPulsingStatusDot` "never acquire the clock under Reduce Motion"
/// precedent governs the entrance: with motion a freshly-inserted row rises and
/// fades once into its settled frame; under Reduce Motion the row is *born*
/// settled — no offset, no fade, and crucially no clock is ever touched
/// (`SPEC` §K "gated under Reduce Motion", ticket "row appears with no entrance
/// animation — never acquire the clock").
enum PouredRowMotion {

    // MARK: Row entrance — `rowin` (mockup §K motion strip)

    /// The one-shot rise+fade a row plays when it is inserted into the list.
    ///
    /// Mockup keyframe `rowin`:
    /// `0% { opacity:0; transform: translateY(10px) scale(.98) }` settling to
    /// `opacity:1; translateY(0) scale(1)`. The demo loops for the motion
    /// strip; the real row plays it **once** on appear, spring-settled.
    enum Entrance {
        /// Starting vertical offset (mockup `translateY(10px)`), eased to `0`.
        static let riseOffset: CGFloat = 10
        /// Starting scale (mockup `scale(.98)`), eased to `1`.
        static let initialScale: CGFloat = 0.98
        /// Starting opacity (mockup `opacity:0`), eased to `1`.
        static let initialOpacity: Double = 0

        /// Settle spring — deliberately the Poured **morph** spring
        /// (`SPEC` §1c open = `spring(response:0.5, damping:0.84)`) so a row
        /// arriving reads with the same liquid, overshoot-free settle as the
        /// surface itself, rather than the bouncier new-event `pop`.
        static let springResponse: TimeInterval = 0.5
        static let springDamping: Double = 0.84
    }

    // MARK: Hover-reveal dismiss (mockup §C `.row:hover .dismiss`)

    /// The trailing dismiss glyph is hidden at rest and fades in on row hover
    /// (`SPEC` §D "Dismiss hover-reveal only (opacity 0→1 on row hover)"). The
    /// fade rides the row's existing `isHighlighted` animation; these are the
    /// endpoint opacities the view interpolates between.
    enum Dismiss {
        static let hiddenOpacity: Double = 0
        static let revealedOpacity: Double = 1
    }

    // MARK: Compact ⇄ hero disclosure (Slice 5 · `PI-A11Y-001`)

    /// The in-place open/close of a row's detail — the §D quiet detail and the
    /// §E/§F heroes alike (R9: the hero grows **inside** the list, it is not a
    /// replacing panel).
    ///
    /// The board renders no open/close transition at all for this (the §D note
    /// "Tap a row to expand in place" is prose; `mapper-reference.md` §4.6
    /// classifies it `specified-invariant`), so the duration is native-authored
    /// and deliberately left at the value the row already shipped — this entry
    /// exists to make it **pinnable** and, above all, to make it Reduce-Motion
    /// gated. Before Slice 5 `toggleDetail` animated unconditionally, the one
    /// un-gated motion left on the Poured row (`mapper-native.md` §4.2 GAP).
    ///
    /// Under Reduce Motion the disclosure is not slowed or softened — it is
    /// removed: the row is *born* open, exactly as `Entrance` treats a row
    /// insertion, and no clock is involved either way.
    enum HeroDisclosure {
        /// The animated open/close duration (`.easeInOut`), unchanged from the
        /// shipped value.
        static let duration: TimeInterval = 0.2

        /// The duration to animate the disclosure over, or `nil` when the change
        /// must be applied instantly. Pure so the Reduce-Motion contract is
        /// testable without a view.
        static func duration(reduceMotion: Bool) -> TimeInterval? {
            reduceMotion ? nil : duration
        }
    }

    // MARK: Identity tick (mockup §C `.row .tick` · `SPEC` §1b "identity tick")

    /// The 2×13 brand-coloured tick that replaces the capsule agent badge in the
    /// collapsed row — "identity stays a whisper" (`SPEC` §1.5).
    enum IdentityTick {
        static let width: CGFloat = 2
        static let height: CGFloat = 13
        static let cornerRadius: CGFloat = 1
    }
}

// MARK: - Narrated activity tone split (mockup §C `.act` / `.act .live`)

/// Splits the row's narrated activity line into tone runs for the mockup's
/// `.act` treatment: the **verb** reads at secondary opacity and the **object**
/// (the file / command / host — the data half a human scans for) reads at
/// primary. A verb with no object is the whole line, so it takes primary. When
/// there is no narration to speak (a completed / interrupted / idle row, or a
/// running row with no active tool yet) the human fallback line renders wholly
/// secondary — exactly the mockup's `.act{color:var(--t2)}` for those rows.
///
/// Pure and view-free (it takes already-resolved, already-localized strings) so
/// `PouredRowMotionTests` can pin the split without standing up a view or a
/// `LanguageManager`. This is the row analogue of the pill's
/// `PouredPillLabelTone`, but it works off the structured `NarratedActivity`
/// verb/object directly instead of re-parsing a joined string.
enum PouredRowActivityTone {

    /// The ink a run of the activity line takes.
    ///
    /// R2/C3 (`01-poured-island.html:852`, `:868`): the board paints **only the
    /// verb** in the run-blue `.live` tone; the object and the trailing
    /// `· live 1m 42s` segment both stay at the base `.act` colour (`--t2`).
    enum Tone: Equatable, Sendable {
        /// `.act .live` — the run-blue verb span.
        case live
        /// Base `.act` ink (`--t2`).
        case secondary
    }

    /// One tone run of the activity line.
    struct Segment: Equatable {
        var text: String
        var tone: Tone
    }

    /// Tone-segments the activity line.
    ///
    /// - Parameters:
    ///   - verb: the narrated verb, already localized. `nil`/empty → no narration.
    ///   - object: the narrated object (file / command / host), never localized.
    ///   - fallback: the human activity line to speak when there is no narration.
    ///   - liveSuffix: the board's `· live 1m 42s` tail, already formatted, or
    ///     `nil` when the row's own age column already answers "for how long".
    static func segments(
        verb: String?,
        object: String?,
        fallback: String?,
        liveSuffix: String? = nil
    ) -> [Segment] {
        var runs: [Segment] = []
        if let verb = verb?.pouredTrimmed, !verb.isEmpty {
            runs.append(Segment(text: verb, tone: .live))
            if let object = object?.pouredTrimmed, !object.isEmpty {
                runs.append(Segment(text: " " + object, tone: .secondary))
            }
        } else if let fallback = fallback?.pouredTrimmed, !fallback.isEmpty {
            runs.append(Segment(text: fallback, tone: .secondary))
        }
        guard !runs.isEmpty else { return [] }
        if let liveSuffix = liveSuffix?.pouredTrimmed, !liveSuffix.isEmpty {
            runs.append(Segment(text: " \u{00B7} " + liveSuffix, tone: .secondary))
        }
        return runs
    }
}

// MARK: - Live run duration (mockup §C row 3 — `live 1m 42s`)

/// The `1m 42s` clock the board hangs off a just-refreshed running row's `.act`
/// line (`01-poured-island.html:852`). Distinct from the row's `.age` column,
/// which reads *recency*: the board's row 3 is `now` in the age column **and**
/// `live 1m 42s` in the narration, so the two can never be the same reading.
///
/// Seconds survive under an hour — a run that has been going 102 seconds reads
/// `1m 42s`, not the age badge's coarser `1m` — and roll up to `Xh Ym` beyond
/// it. Pure so `PouredRowMotionTests` can pin it without a `TimelineView`.
enum PouredLiveElapsed {
    static func text(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return "\(total)s" }
        if total < 3_600 {
            let minutes = total / 60
            let remainder = total % 60
            return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
        }
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

// MARK: - Disambiguator suffix styling input (mockup §C `.disamb`)

/// The bare branch / recency phrase rendered after the workspace name in the
/// title line (`SPEC` §C "`feat/bridge-auth`, `main`, `12m ago`").
///
/// The mockup draws the disambiguator as its own mono span — **not** a
/// parenthesised suffix on the headline the way the old `spotlightHeadlineText`
/// did. This pure helper is the single formatting decision the row makes about
/// that span (trim, drop-if-empty, no parentheses), pinned so it can't silently
/// regain the `(…)` wrapper.
enum PouredRowDisambiguation {
    static func suffix(_ raw: String?) -> String? {
        guard let trimmed = raw?.pouredTrimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - Subagent live timer (mockup §G `.sa-time` — `0:42`)

/// The `M:SS` clock the expanded subagent list ticks against `startedAt`
/// (mockup §G `.sa-time` renders `0:42` / `1:15` / `0:08`, not the shipped
/// row's `42s` / `1m 15s`). Pure and view-free so `PouredRowMotionTests` can
/// pin the padding without a `TimelineView`.
///
/// Minutes are **not** rolled into hours: a subagent that has run 83 minutes
/// reads `83:20`, an honest live count rather than a truncated `1:23:20` the
/// tabular column can't align. Negative intervals (a `startedAt` in the future
/// after a clock nudge) clamp to `0:00`.
enum PouredSubagentTiming {
    static func clockLabel(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let secs = clamped % 60
        return "\(minutes):" + String(format: "%02d", secs)
    }
}

// MARK: - Run-glyph metrics (mockup `.glyph.run` at its four rendered sizes)

/// The three-bar `.glyph.run` measured off the board (`01-poured-island.html:160-166`)
/// plus the two §G sizes Slice 6 adopts.
///
/// The board keeps `.glyph i` at a literal `2.5px` wide / `5px` tall while
/// shrinking only the *box* (`10×11` for `.nest-h` at `:1289`, `8×9` for
/// `.todo.doing .tk` at `:1313`), so its bars overflow every reduced instance
/// (mapper contradiction C-7). Native scales the bars with the box off a single
/// `height / 15` factor, which is what these helpers compute — pinned so the two
/// swapped §G sites can never drift apart or away from the board's sizes.
enum PouredRunGlyphMetrics {
    /// The board's unscaled `.glyph` box.
    static let referenceHeight: CGFloat = 15
    static let barWidth: CGFloat = 2.5
    static let barHeights: [CGFloat] = [14, 14, 11]

    /// `.nest-h > .glyph.run{width:10px;height:11px}` (`:1289`).
    static let nestHeaderHeight: CGFloat = 11
    /// `.todo.doing .tk > .glyph.run{width:8px;height:9px}` (`:1313`).
    static let todoTickHeight: CGFloat = 9

    static func scale(height: CGFloat) -> CGFloat { height / referenceHeight }

    static func barWidth(height: CGFloat) -> CGFloat { barWidth * scale(height: height) }

    static func barHeights(height: CGFloat) -> [CGFloat] {
        barHeights.map { $0 * scale(height: height) }
    }
}

// MARK: - Live subagent rollup (mockup §G `· 3 subagents live`)

/// How many subagents are still running, for the **expanded** row's `.act`
/// suffix (`01-poured-island.html:1286`).
///
/// A subagent that has reported a `summary` has handed its work back, so it is
/// no longer live. Returns `nil` — not `0` — for every case that must render no
/// suffix at all: a collapsed row (where the fan-out is identity and rides the
/// disambiguator per R2/C4), and an expanded row whose subagents have all
/// finished.
enum PouredLiveSubagents {
    nonisolated static func liveCount(_ subagents: [ClaudeSubagentInfo], isExpanded: Bool) -> Int? {
        guard isExpanded else { return nil }
        let live = subagents.filter { $0.summary == nil }.count
        return live > 0 ? live : nil
    }
}

// MARK: - Task rollup (mockup §G nest header + §G′ compressed chip)

/// The done / total split the todo list rolls up to — the nest header
/// `Tasks · 2 of 5 done` when expanded and the `2/5 tasks` chip when
/// compressed both read from this. Pure count arithmetic, pinned so the two
/// surfaces can never disagree about what "done" means (completed only, never
/// in-progress).
struct PouredTaskRollup: Equatable {
    var done: Int
    var total: Int

    init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    init(statuses: [ClaudeTaskInfo.Status]) {
        self.total = statuses.count
        self.done = statuses.filter { $0 == .completed }.count
    }
}

// MARK: - Completion hero sub-line (mockup §H `Fable 5 · finished 12m ago`)

/// The §H hero's identity sub-line (`01-poured-island.html:1399`): the model
/// name and the finished-ago reading, joined by the board's own middot.
///
/// A session with no model metadata (`AgentSession.displayModelName == nil` —
/// every Codex.app / MCP session, and any agent that never reported one) drops
/// the model segment **and** the separator, so the line never renders as a
/// dangling `· finished 12m ago`. Pure so the composition is pinnable without
/// building the card.
enum PouredCompletionSubline {
    nonisolated static func text(model: String?, finishedAgo: String) -> String {
        let finished = finishedAgo.pouredTrimmed
        guard let model = model?.pouredTrimmed, !model.isEmpty else { return finished }
        guard !finished.isEmpty else { return model }
        return model + " \u{00B7} " + finished
    }
}

// MARK: - Pane attachment chip (mockup §D `.chip` — first surfacing of the field)

/// The attachment chip in the expanded detail (mockup §D
/// `Pane attached` / `Pane stale` / `Detached`). AB-332 is the first surface
/// to render `SessionAttachmentState` anywhere, so the state→(copy-key, live)
/// mapping lives here as one pinnable decision rather than a `switch` buried in
/// the view. `isLive` drives the green status dot; only `.attached` is live.
enum PouredAttachmentChip {
    case attached
    case stale
    case detached

    init(_ state: SessionAttachmentState) {
        switch state {
        case .attached: self = .attached
        case .stale: self = .stale
        case .detached: self = .detached
        }
    }

    /// Localization key for the chip label — resolved ×3 (en / zh-Hans /
    /// zh-Hant) in `Localizable.strings`.
    var localizationKey: String {
        switch self {
        case .attached: "poured.detail.attachment.attached"
        case .stale: "poured.detail.attachment.stale"
        case .detached: "poured.detail.attachment.detached"
        }
    }

    /// Only an attached pane reads as live (green dot); stale/detached recede.
    var isLive: Bool { self == .attached }
}

private extension String {
    var pouredTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
