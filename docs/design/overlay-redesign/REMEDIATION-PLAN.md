# Overlay visual-fidelity remediation — plan

**Status**: COMPLETE — implementation and Phase 8 evidence are recorded below. The static matrix is
complete; live interaction pixels/states that the available tooling could not observe remain
explicitly **UNMEASURED**.
**Source of findings**: `shots/REPORT.md` (20 ranked findings, each adversarially verified).
**Branch**: `fix/overlay-fidelity-remediation` · **Worktree**: `.claude/worktrees/overlay-remediation`
**Baseline**: `main` @ c5fbd53.

A phase is **not** done because the code compiles. It is done when the pixels match and every
acceptance criterion below reports PASS with a number.

---

## 0. Operating rules (apply to every phase)

### Scale rule
App captures are **@2x** (1px = 0.5pt). Mockup crops are **@1x** (1px = 1pt).
**Halve every app pixel measurement before comparing.** This was the #1 source of false findings in
the review that produced `REPORT.md`.

### Surface scope
`IslandDebugScenario` renders **two** surfaces today; the mockups depict **three**:

| Surface | How it is configured | Scenarios |
|---|---|---|
| Notification card | `notchOpenReason:.notification` + `islandSurface:.sessionList(actionableSessionID:)` | `approvalCard`, `questionCard`, `completionCard`, `longCompletionCard`, `diffApprovalCard`, `codexApprovalCard`, `multiQuestionCard`, `completedInterrupted`, `completedFailed` |
| Plain session list | `notchOpenReason:.click` + `islandSurface:.sessionList()` | `sessionList`, `subagentsCard`, `usageMeters` |
| **Expanded row** (mockup §D/§H, §G engine cluster) | **not currently reachable from any scenario** | — (Phase 1 adds it) |

Comparing a notification card against §H produces false "missing action" findings. **Every capture
must state its surface before being compared to a mockup frame.**

### Capture is a strictly serial resource
There is one overlay panel, one `defaults` theme key, and **one shared dev bundle**
(`~/Applications/Open Island Dev.app`). Never run two capture agents at once.

`scripts/launch-dev-app.sh` derives `repo_root` from **its own location** — capture agents must
invoke the **worktree's** copy so the bundle is built from the fixes under test. Always pass
`--skip-setup`: without it the script runs `OpenIslandSetup install`, which rewrites the user's real
agent hook configs.

### Toolchain
`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` on every `swift build` / `swift
test` — the CLT default lacks the SwiftUI macro plugin and fails inside NetworkImage.

### Known-red tests — do not chase
`islandSessionSectionsGroupStaleCompletedIntoIdle`,
`islandSessionSectionsKeepCompletedInDoneWhenStaleThresholdIsNever`,
`islandSessionListCanSortByLastUpdate`, `cellStateReflectsSessionPhase`,
`bulkFirstObservationOrdersByHistoricalFirstSeenAt`, plus two Poured session-list snapshot goldens
that drift environmentally. Confirm the count is unchanged and move on.

### Known harness artifacts — never file, never "fix"
- Install-hint banner ("No agent hooks installed — SETUP") — the bundled binary's hooks probe reads
  false. It clips short panels. Phase 1 adds a **harness-only** suppression.
- `appearance.island.v8.notch.sessionGroup = none` is the user's setting.
- Notch↔top-bar metric deltas (pill 38↔24pt, panel 540↔520pt, insets 46↔16pt, ring 30↔22pt) are
  SPEC-sanctioned.

### Environment state to restore on completion
`appearance.island.v8.theme` → `halo` · `overlay.display.preference` →
`F3BDCAC0-1700-415E-817D-AC4E69D405BC` · `appearance.island.v8.notch.sessionGroup` → `none`.
Forced-notch captures use built-in display UUID `37D8832A-2D66-02CA-B9F7-8F30A301B230`; confirm
notch mode by panel width **540pt** (vs top-bar 520pt).

---

## 1. ⛔ Out of scope — investigated, correct as-is

Copied verbatim from the review brief. Every implementation agent reads this before touching code.

| Apparent problem | Reality |
|---|---|
| Completion card has no **Dismiss** | Deliberate. `notificationRowActions` (`IslandPanelView.swift:937-945`) omits `dismiss:` with an explicit comment — the notification card isn't dismissible. Row wiring is correct and is handed `nil` on this surface. **Do not add a Dismiss button here.** |
| Completion card has no **Reply** | Feature flag `model.completionReplyEnabled`, default `false` (`AppModel.swift:298,758`), matching BRIEF §6 "narrow support". Not a rendering bug. |
| Halo/Poured completion card has no **Transcript** | **RESOLVED.** Completion and long-completion fixtures now carry nonempty transcript paths; all three themes expose **Transcript** where the contract requires it. |
| Poured's A3 attention glyph "is malformed" (2 bars, no dot) | REFUTED. Matches `UnifiedBars(mode:.waiting)` exactly — the capture legitimately shows **A4 question**, not A3 permission. Poured's ringed dot is fine. |
| Halo's Failed outcome "uses a different template" | Fixture bug, not a template bug. `completedFailed.updatedAt` is 9 min old, exceeding the 5-min stale threshold → `presence:.inactive` → idle template. **Fix the fixture, not the badge/dot code.** |
| Halo session list "missing section headers" | User setting: `appearance.island.v8.notch.sessionGroup = none`. |
| Attention pills have a "huge banded glow" | REFUTED by measurement. Bleed within spec (Poured 5.0pt, FD 1.5pt, Halo 9.5pt). The apparent drama is the harness capturing against pure black vs the mockup's grey desktop. |
| Halo's row edge-rail "is missing" | Present at 2.0pt with the correct cyan→violet gradient, correctly gated to live/actionable rows. |
| Flight Deck hero "drops the whole identity block" | Partly refuted — the agent name IS rendered, relocated above the card (defensible). Only **Model and Branch** are genuinely absent. Fix only those. |
| Notch vs top-bar metric differences | SPEC-sanctioned. Not defects. |
| Flight Deck's flat/opaque body, no gradients, no specular | **Correct by design** (tintOpacity 1.0). Its signature is phosphor glow bleed on lamps. Do not add gradients. |
| Halo's pure-black void, no fills/cards/vibrancy | **Correct by design.** Its only chrome is the 1.5pt edge-light. Do not add card fills. |

Only **Poured** owes layered glass (3-stop body gradient + two specular layers + inner hairline),
and it already has it — verified present and smooth.

⚠️ The SPEC files' ✅ conformance markers are **not trustworthy** — `SPEC-flight-deck.md:158` marks
the MASTER placard ✅ while the code ships 10.5/700. Verify against code, never the checkmark.
Phase 8 audits them all.

---

## 2. Per-finding analysis

> Filled in from the parallel analysis pass. Each block: current behaviour → target → root cause →
> blast radius → regression risk → acceptance criterion → fix → file set.

### F1 — The shared question card is unthemed · MAJOR · CONFIRMED (blast radius RESCOPED wider)
- **Surface**: notification card **and** plain session list — identical exposure. Both hosts call the
  same `theme.sessionRow(…, isActionable: true, …)` factory and land in the same
  `questionActionBody`. Notification path `IslandNotificationCard.swift:74-78`; list path via each
  `*SessionListScaffold.swift`. **All three conformance-snapshot suites exercise the LIST path**
  (`ThemeSnapshotting.swift:200-243`), not the notification-card path.
- **Current — six call sites, not three.** The brief listed `PouredSessionRow.swift:872-877`,
  `FlightDeckSessionRow.swift:2250-2255`, `HaloSessionRow.swift:1997-2002`; also unthemed:
  `IslandPanelView.swift:1876` (Classic), `AnnualSessionRow.swift:1250`, `InstrumentSessionRow.swift:1011`
  — the same 4-parameter signature (`prompt/lang/keyboardCoordinator/onAnswer`) at all six.
  Comments verbatim: Halo `:1994` *"**Not restyled**…"*; Flight Deck `:2247` *"…interior is *wrapped*…
  **never modified**"*; Poured `:864-865` *"The interior's semantics are **untouched**."*

  | Element | file:line | Hardcoded | Should map to |
  |---|---|---|---|
  | Question text | `2383-2386` | `.system(size:12,.medium)`, colour hardcoded `.white.opacity(0.88)` | `questionText` (Poured 14.5/560, Halo 14.5) |
  | Multi-Q header | `2378-2381` | `.system(size:10,.bold)`, hardcoded `.white.opacity(0.5)` | theme secondary-text token |
  | Progress readout | `2371-2374` | `.system(size:10,.bold)` mono-digit | `metaChip`/`qProgress` equivalent |
  | Option digit | `2416-2427` | `.system(size:10.5,.semibold,.monospaced)`, box 22×20 r5 | `optionNumber` (11/700 tabular) |
  | Option label | `2430-2432` | `.system(size:12.2,.medium)`, hardcoded `.white` | `optionLabel` (13/600) |
  | Option desc | `2434-2438` | `.system(size:10.5)` implicit `.regular`, hardcoded `.white` | `optionDesc` (11.5/400) |
  | Selection marker | `2487-2514` | Circle/square, `lineWidth:1.2`, 16×16, checkmark 9/heavy | shape is theme-swappable; tint already token |
  | Card bg/border | `2345-2355` | `RoundedRectangle(r10)`, flat `.white.opacity(0.03/0.05)` | wrong for FD (opaque) and Halo (no fills) |
  | Submit button | `2953-3032`, used `:2338`,`:2543` | `11.8/.semibold`, pad h13/v8, **always** `RoundedRectangle(r10)`, `expands:true` → `maxWidth:.infinity` | the highest-visibility break |

- **⚠️ Precision on the measured "flat grey CTA"**: `selections`/`typedReply` (`:2301-2303`) start
  empty and **no fixture can pre-populate them**, so `canSubmit` (`:2647-2649`) is **always false at
  capture time** → `.disabled(true)` → the button renders through the `guard !isEnabled` branches
  (`:2988-2989, 3003-3004, 3018-3019`), which are 100% theme-blind literals. Even the *enabled*
  `.primary` state would still be a flat pill — `IslandActionButtonStyle` fills with a `Color`
  (`:3017-3031`) and **cannot express a gradient at all**.
  **Verification consequence: the enabled CTA is not reachable from a still. Phase 2 must verify it
  by driving a selection via computer-use, or by adding a fixture/harness hook that pre-populates
  `selections`.** This is a Phase 1 tooling requirement.
- **Target**: none of the three boards want a full-width flat button.
  Poured `01-poured-island.html:1192-1196` — `.btn.primary` is `display:inline-flex` (**intrinsic
  width**), `linear-gradient(180deg,#ffe0a8,#ffd58a)`, in `.q-foot{display:flex;gap:8px}`.
  Halo `06-halo.html:371-372,421` — `linear-gradient(135deg,#ffce8a,#ffab54)`, `padding:8px 13px`.
  Flight Deck `02-flight-deck.html:1233` — a **translucent outlined chip**
  (`rgba(230,170,66,.14)`, border `rgba(230,170,66,.5)`), not a filled pill.
- **Root cause — two independent gaps**: (1) typographic — the view reads `\.islandTokens` (`:2306`)
  for a few colours only, never typography; (2) structural — `IslandActionButtonStyle` has three
  `Kind`s, none read `\.islandTheme`, none support a gradient or a non-rounded shape.
- **Role-table reality — corrects the brief's premise**:

  | Role | Poured (`PouredTypography.swift`) | Halo (`HaloTheme.swift`) | Flight Deck |
  |---|---|---|---|
  | `questionText` | `:203` 14.5 / 560 / −0.01em | `:85,164` 14.5 sans | **does not exist** |
  | `optionLabel` | `:204` 13 / 600 | `:87,165` 13 sans | **does not exist** |
  | `optionDesc` | `:205` 11.5 / 400 | `:89,166` 11.5 sans | **does not exist** |
  | `optionNumber` | `:206` 11 / 700 tabular | `:92,167` 11 sans | **does not exist** |

  - **Flight Deck has none of these roles** — its `roleFamilies` (`:78-90`) has 9 entries, none
    question-related. This is *"never authored"*, not *"defined but unused"* — materially more work
    than Poured/Halo's "start reading the table".
  - **Halo's role table structurally cannot express weight**: `roleFamilies: [(name, family, size)]`
    (`:141`). The "600/560" figures in its doc comments are prose, not enforced data, and there is no
    `.font` accessor like Poured's `Role.font` (`PouredTypography.swift:162`).
  - **"Zero call sites" is right for 8 of 9 dormant sizes but not `optionDesc`** — it has one call
    site, `PouredSessionRow.swift:1692`, on the unrelated Codex-approval note.
- **Architecture — RECOMMENDED: a narrow new protocol seam (option b)**, mirroring the existing
  optional-hook precedent `closedSurfaceGlow`/`closedGlyphTint`/`usageMeterCard`/`surfaceEdgeOverlay`
  (`Theme/IslandTheme.swift:271-313`) — protocol members with **defaults that reproduce current
  Classic behaviour**, so Classic/Annual/Instrument stay byte-identical and **zero call sites change**
  (`\.islandTheme` already propagates to this subtree; injected once at `IslandPanelView.swift:316`).
  - *(a) environment-read alone* is insufficient — there is nothing on the protocol to call, so it
    degenerates into `if theme.id == "halo"` conditionals, exactly what the theme-arch series removed.
  - *(c) style struct per call site* touches all six row files for no benefit.
  - **Strong supporting evidence**: every theme already owns a bespoke primary-action button, just
    never wired to the question card — `PouredJumpButtonStyle`/`PouredGhostButtonStyle`
    (`PouredSessionRow.swift:2326,2368`), `FlightDeckApprovalButton` (already built on
    `FlightDeckChamferedRectangle`), `HaloHeroButton` (`HaloSessionRow.swift:1867-1943`).
    **The fix is exposing existing components through a new seam, not building new chrome.**
  - **Typography needs no protocol change at all** — lowest-risk, land it first and independently.
- **Blast radius**: 6 call sites across 6 `IslandTheme` conformances. `IslandActionButtonStyle` is
  also used by Classic's own approval/completion buttons (`IslandPanelView.swift:1786,1794,1819,1832,1858`)
  — untouched by a scoped seam, but in scope for any edit to the style itself.
- **Regression risk**: med. **Covering tests**: `PouredConformanceSnapshotTests.testQuestionHero`
  (`:69-70`), `HaloConformanceSnapshotTests.testQuestionHero` (`:91-93`),
  `ThemeSnapshotHarnessTests.testFlightDeckQuestionMasterCautionNotch` (`:69-76`, **notch only** — no
  FD topbar golden exists). **5 goldens re-record.** `QuestionPromptFormatTests.swift` (27 funcs)
  covers pure logic — safe under restyle, **in scope if pagination changes progress/hint semantics**.
  Classic/Annual/Instrument call sites have **zero snapshot coverage anywhere**.
- **Acceptance criterion**: (1) grep for Poured's four `PouredType.Role` question roles and Halo's
  four sizes inside `IslandPanelView.swift` returns ≥1 hit each; (2) Halo/Poured submit in the
  **enabled** state samples non-achromatic RGB (max−min channel > 15); (3) submit width < card width
  on Poured/Halo (no `maxWidth:.infinity` on the enabled path); (4) FD's submit clip-shape is
  `FlightDeckChamferedRectangle`, not `RoundedRectangle`.
- **File set**: `IslandPanelView.swift`, `Theme/IslandTheme.swift`, `PouredIslandTheme.swift`,
  `FlightDeckTheme.swift`, `HaloTheme.swift`. Classic/Annual/Instrument: none if defaults preserve
  current rendering.

### F1a — ⚠️ Pagination: the approved boards CONTRADICT each other (product decision required)
The brief prescribed "add question pagination" uniformly. **Flight Deck's own approved board rejects it.**
- **No pagination state exists**: `@State` (`IslandPanelView.swift:2301-2304`) has no page index;
  `ForEach` over all questions (`:2321-2323`), each `ForEach`ing all options (`:2389-2394`), one
  shared Submit (`:2335-2339`). **Correction to REPORT.md**: there is **no `ScrollView`** anywhere
  near this view — VStacks only, unbounded height.
- **Fixture**: `conformanceQuestions()` (`AppearancePreviewFixtures.swift:535-575`) — 2 questions,
  7 options total.
- **Poured** `01-poured-island.html:1154-1205`: one frame, one question, `.q-progress` "Question 1 of 2",
  footer "**Submit & next** ⏎" — **paginated**.
- **Halo** `06-halo.html:1067-1156`: **two separate frames** — F1 "1 of 2" / button "**Next** ↵";
  F2 "2 of 2" / button "**Submit** ↵" — **paginated**.
- **Flight Deck** `02-flight-deck.html:1194-1265`: **both questions stacked in one card** — `Q 1 / 2`
  then `Q 2 / 2` headers, **continuous flat digit numbering across both** (Q1 → digits 1-3, Q2 →
  digits 4-7), **one shared submit** ("Digits 1–9 select · Enter submits"). **The opposite pattern** —
  plausibly deliberate, matching FD's MASTER-CAUTION identity (show every active caution at once).
- **Keyboard impact**: `registerKeyboardHandlersIfNeeded` (`:2813-2850`) **disables 1-9/Enter entirely**
  when `structuredQuestions.count > 1` (guard `:2821`, reason: "each question restarts at 1").
  Paginating Poured/Halo removes that premise and lets shortcuts be **re-enabled** per page. FD's board
  wants the opposite: a running digit offset across stacked questions. **Two different code paths.**
- **See §5 Open decisions.**

### F1b — Persistent hollow selection marker · CONFIRMED for Poured/Halo, RESCOPED for Flight Deck
- **Code**: `selectionMarker` (`IslandPanelView.swift:2487-2514`) is called unconditionally per row
  (`:2444-2447`) — always strokes a ring; only fill + checkmark vary by `isSelected`.
- **Poured** (`01-poured-island.html:1178-1188`) and **Halo** (`06-halo.html:1090-1092`): selected rows
  get a trailing `<svg class="ck">`; **unselected rows emit no trailing element at all**. Confirmed defect.
- **Flight Deck** (`02-flight-deck.html:1219-1221,1227-1229`): **every** `.qopt` emits
  `<span class="check oct">`; base CSS `.qopt .check{width:15px;height:15px;border:1px solid var(--hair3)}`
  (`:560`) is a **persistent hollow ring by design**. FD's defect is the **shape** — `.oct` (`:64-68`)
  is a `clip-path` chamfered octagon, not a circle. **For FD the fix is "swap Circle for chamfer",
  not "hide when unselected".**

### F7 — Notch header silently drops an entire usage provider · MAJOR · CONFIRMED (scope corrected)
- **Surface**: header lane, **notch only** (invisible to default top-bar captures).
- **Current**: fixture supplies Claude(5h 34%, 7d 78%) + Codex(7d 92%)
  (`AppModel.swift:1234-1238` → `AppearancePreviewFixtures.swift:669-702`). `splitUsageProviders`
  puts Claude whole in the left lane, Codex whole in the right (`HaloHeaderControls.swift:136-137`).
  When `proposedRightUsageWidth < minimumRightUsageLaneWidth (58)`, `rightUsageWidth` snaps to
  **exactly 0** (`:196-198`), and the guard `if metrics.rightUsageWidth > 0, !providerGroups.right.isEmpty`
  (`:67-70`) then skips the lane entirely. **Codex isn't shrunk — it is deleted from the render tree.**
- **Target**: mockup §C puts exactly **one window per lane**, never a whole provider — verified in
  board source: `02-flight-deck.html:888-909` (left "Claude · 5H", right "Claude · 7D" + controls),
  `06-halo.html:767-780` (identical pattern with filaments).
- **Root cause**: two stacked bugs in one shared body — provider-granularity split (one provider's
  windows can never balance across the cutout) **plus** a width-starved fallback that drops instead
  of reflowing.
- **Blast radius — SCOPE CORRECTED**: `splitUsageProviders` / `openedHeaderMetrics` /
  `minimumRightUsageLaneWidth=58` are **byte-identical in SIX files**, not the three `REPORT.md`
  claimed (only the returned struct name differs): `IslandHeaderControls.swift:23,138-155,171-222`
  (Classic) · `AnnualHeaderControls.swift:25,121-138,154-205` ·
  `InstrumentHeaderControls.swift:23,124-141,157-208` · `PouredHeaderControls.swift:23,124-141,157-208` ·
  `FlightDeckHeaderControls.swift:24,120-137,153-204` · `HaloHeaderControls.swift:26,128-145,161-212`.
  **All six shipped themes reproduce the identical drop.** Each copy has exactly one caller (its own
  `body`).
- **Regression risk**: low (isolated pure layout function) — but coverage is **zero**: grep of
  `Tests/` for `splitUsageProviders` / `minimumRightUsageLaneWidth` / `rightUsageWidth` returns
  nothing. **Covering tests: NONE.**
- **Acceptance criterion**: forced-notch capture (confirm 540pt panel) with the `usageMeters` fixture
  shows all three window percentages — **"34%", "78%", "92%"** — present in the header pixels;
  and `openedHeaderMetrics` never yields `rightUsageWidth == 0` while `providerGroups.right` is
  non-empty. Add a unit test for the second half — it needs no capture.
- **Fix**: split at flattened `(provider, window)` granularity; on width starvation reflow overflow
  windows into the other lane (or force the short-title `ViewThatFits` branch) rather than zeroing;
  deduplicate into one shared function.
- **Home for the shared function**: `IslandUsageSummary.swift`, beside
  `UsageProviderPresentation`/`UsageWindowPresentation`. **Not** `OpenIslandCore` (no SwiftUI/layout
  concerns there, and it doesn't own the type). **Not** the `IslandTheme` protocol — the geometry is
  proven byte-identical across all six themes, so putting it on the per-theme protocol would invite
  exactly the drift this review just caught.
- **File set**: the six `*HeaderControls.swift`; `IslandUsageSummary.swift`.
- **⚠️ Open decision**: whether to fix Annual / Instrument / Classic too — see §5 Open decisions.

### F8 — Flight Deck usage gauges overflow the header band · MAJOR · CONFIRMED
- **Surface**: header lane.
- **Current**: `FlightDeckUsageProviderChip.body` stacks a provider's windows in
  `VStack(alignment:.leading, spacing:9)` (`FlightDeckUsageSummary.swift:61-65`),
  height-unconstrained. A 2-window chip is ~75–83pt (2×(head ~14pt + track 8pt) + 9pt gap + 14pt
  padding) against a reserved band of `closedNotchHeight` (~24pt top-bar,
  `IslandPanelView.swift:844-846` ← `NSScreen.islandClosedHeight` /
  `OverlayPanelController.swift:846-870`). That band is applied as a **fixed, non-clipping**
  `.frame(height: closedNotchHeight)` on `openedHeaderContent` (`IslandPanelView.swift:535-536`)
  with **no `.clipped()` anywhere** — so the oversized chip bleeds symmetrically past both edges:
  up past panel y=0, and down into the control-button row in the same `VStack(spacing:0)`
  (`:534-549`), producing the reported "SE TOP" glyph collision.
- **Target**: mockup §C never stacks two windows in one gauge box — each `.gauge` div is one window
  (`02-flight-deck.html:888-909`). **Both sibling themes already lay windows out horizontally**:
  `HaloUsageProviderGroup` = `HStack(spacing:12)` (`HaloUsageSummary.swift:237-247`),
  `PouredUsageProviderGroup` = `HStack(spacing:12)` (`PouredUsageSummary.swift:159-169`). FD's chip
  is the only `VStack` of the three.
- **Root cause**: FD's per-window layout axis is vertical/unconstrained where the reserved band and
  both siblings are horizontal/self-limiting. **Independent of F7** (F7 = silent drop; F8 = renders
  but too tall); they compound only when a wide *and* tall condition co-occur.
- **Blast radius**: `FlightDeckUsageProviderChip` has one call site,
  `FlightDeckUsageSummary.summaryRow:34-40`, reached only via `FlightDeckHeaderControls.swift:114,148`.
- **Regression risk**: medium — switching to HStack moves growth from height to width, interacting
  with the `ViewThatFits` short-title fallback (`:26-29`) and F7's lane-width math. **Verify together
  with F7.** **Covering tests: NONE.**
- **Acceptance criterion**: in the re-captured `flightDeck-usageMeters` notch frame (@2x → halve):
  no gauge pixel at panel-local y < 0pt, and `gaugeBBox.maxY <= controlBBox.minY` where the control
  buttons are 22×22pt (`FlightDeckHeaderControls.swift:18`).
- **Fix**: `VStack(alignment:.leading, spacing:9)` → `HStack(alignment:.top, spacing:9)`, mirroring
  Halo/Poured; re-check `gaugeWidth:150 × N` still fits the lane width after F7.
- **File set**: `FlightDeckUsageSummary.swift`; possibly `FlightDeckHeaderControls.swift`.

### F15 — Flight Deck's usage gauge uses raw SwiftUI system colours · MAJOR · CONFIRMED
- **Surface**: header lane **and** closed pill.
- **Current**: `usageColor(for:)` returns `.red / .orange / .green.opacity(0.95)` for ≥90 / 70–89 /
  <70 (`FlightDeckUsageSummary.swift:193-202`). Sampled caution fill **#E39244** (227,146,68) vs the
  FD caution token **#E6AA42** (230,170,66) — ΔG = −24.
- **Target**: per `SPEC-flight-deck.md:56-58` + `IslandColorTokens.swift:286-315` —
  ≥90 → `statusWaitingForApproval` = `flightDeckWarning` **#E04A42**;
  70–89 → `statusWaitingForAnswer` = `flightDeckCaution` **#E6AA42**;
  <70 → `statusRunning` = `flightDeckNominal` **#4AC99E**.
- **Root cause**: written against the shared base-theme reference `IslandUsageSummary.usageColor`
  (`:137-146`, itself still raw) and never swapped onto FD's token palette.
- **Sibling check — REFUTED for Poured and Halo**: both already fixed this exact defect.
  `PouredUsageThreshold.color(_:)` → `statusCompleted/statusWaitingForAnswer/statusFailed`
  (`PouredUsageSummary.swift:65-77`); `HaloUsageThreshold.filamentColor` → `HaloEdge.usageFine/
  usageWarn/usageCrit` (`HaloUsageSummary.swift:71-81`). Both doc comments explicitly say they
  replace "the shipped raw `.red/.orange/.green`". **Not a shared root cause — FD is the one theme
  that never got the treatment.**
- **Blast radius**: second call site is `FlightDeckUsageMiniTape.tint` on the **closed pill**
  (`FlightDeckClosedPill.swift:583`), which per its own comment only renders in production at the
  ≥90 red band. ⚠️ **`tickGaugeColoursBandOnTheExactUsageCutoffs` (`FlightDeckThemeTests.swift:231-242`)
  currently pins the WRONG (raw) values** and must be updated in the same commit.
- **Regression risk**: low visually; the test update is non-optional and atomic.
- **Acceptance criterion**: `usageColor(for:92) == tokens.colors.statusWaitingForApproval` (#E04A42);
  `usageColor(for:78) == tokens.colors.statusWaitingForAnswer` (#E6AA42);
  `usageColor(for:34) == tokens.colors.statusRunning` (#4AC99E) — exact, not `.red/.orange/.green`.
- **Fix**: make `usageColor` take `IslandColorTokens` (mirroring `PouredUsageThreshold.color(_:)`),
  threading the already-present `@Environment(\.islandTokens)` (`:127`, `FlightDeckClosedPill.swift:581`).
- **File set**: `FlightDeckUsageSummary.swift`, `FlightDeckClosedPill.swift`, `FlightDeckThemeTests.swift`.

### F18 — Flight Deck's usage `%` renders at 9pt · MINOR · CONFIRMED
- **Current**: `.font(.system(size: FlightDeckTypography.countSize - 2, ...))`
  (`FlightDeckUsageSummary.swift:161`); `countSize = 11` (`FlightDeckTheme.swift:46`) → **9pt** vs
  `floor = 10` (`:30`). Not in `roleFamilies` (9 entries, `:78-90`), so invisible to
  `everyReadableTypographyRoleHoldsTheTenPointFloor` (`FlightDeckThemeTests.swift:118-125`) —
  verified: the test walks only the nine pinned roles.
- **Doc-comment claim verified**: `FlightDeckTheme.swift:23-25` reads *"The one intentional exception
  is the closed-grid overflow `+N`…"* — confirmed **not** this usage `%`. Independent corroboration:
  `SPEC-flight-deck.md:166` lists `Unit tag (.gval u "%") | 9px | mono | ❌ → lift to 10`, the same
  treatment given to five sibling sub-floor roles the code *did* lift. This is the one that was missed.
- **Blast radius**: sole call site. **Covering tests: NONE** (the fix should add the role so the
  existing floor test starts catching it).
- **Acceptance criterion**: the `%` glyph renders ≥10pt **and** is a named `roleFamilies` entry
  exercised by `everyReadableTypographyRoleHoldsTheTenPointFloor`.
- **Fix**: add `FlightDeckTypography.gaugeUnitSize = 10`, register `("gaugeUnit", .mono, gaugeUnitSize)`
  in `roleFamilies`, use it at `:161`.
- **File set**: `FlightDeckUsageSummary.swift`, `FlightDeckTheme.swift`.
- **Ordering**: land **before or with F8**, so F8's height budget is computed against the corrected
  10pt size and its capture doesn't need re-verification.

### F5 — Approve/Deny order is REVERSED in Flight Deck · MAJOR · CONFIRMED
- **Surface**: notification card (`approvalCard`/`diffApprovalCard`/`codexApprovalCard`).
- **Current**, verified by direct read — no `layoutDirection`/mirroring trick anywhere:
  Poured `allowOnce` (`PouredSessionRow.swift:1613-1624`) → `deny` (`:1625-1636`) — **Allow LEFT**.
  Halo `allowOnce` (`HaloSessionRow.swift:1867-1873`) → `deny` (`:1874-1880`) — **Allow LEFT**.
  Flight Deck `deny` (`FlightDeckSessionRow.swift:2804-2811`) → `allowOnce` (`:2812-2819`) inside
  `FlightDeckApprovalCard.body`'s `HStack(spacing:8)` (`:2803-2820`) — **Deny LEFT, reversed**.
- **Board confirmation**: `02-flight-deck.html:1113-1115` — literal DOM order `ALLOW ONCE ⌘Y` →
  `ALLOW ALWAYS ⌘⇧Y` → `DENY ⌘N`. Allow-family leads, Deny trails, matching both siblings.
- **Risk is mouse/trackpad muscle memory, not keyboard**: each button's `shortcut:` stays bound to
  its own action and the ⌘Y/⌘N keydown handler is a single global handler independent of visual
  layout. BRIEF §6 treats row verbs as a shared contract and fixes ⌘Y (Allow) before ⌘N (Deny).
- **No other verb-order divergence exists**: scoped "always allow" rows follow the same structure in
  all three (Poured `:1647+`, Halo `:1889+`, FD `:2940-2974`), first row carries ⌘⇧Y in all three.
  Completion rails: Poured (`:1016-1053`) and Halo (`:958-983`) both render Jump → Transcript →
  spacer → Dismiss, identically ordered. FD has no rail at all — that is F13, not a reordering.
- **Blast radius**: one render call site; no protocol conformance, no other theme.
- **Regression risk**: low — pure reorder of two already-correct closures. **Covering tests: NONE.**
- **Acceptance criterion**: in `FlightDeckApprovalCard.body`'s primary `HStack`, the `allowOnce`
  declaration precedes `deny`. Pin it with a per-theme order test so it cannot silently flip again.
- **Fix**: swap the two `FlightDeckApprovalButton` blocks at `:2804-2819`, and extract the order into
  a pure array/enum (mirroring the existing `FlightDeckSessionRowFormat`/`HaloSessionRowFormat`
  split, which exists precisely so `*Tests.swift` can pin pure logic).
- **File set**: `FlightDeckSessionRow.swift`; `Tests/OpenIslandAppTests/FlightDeckSessionRowTests.swift`
  (+ Poured/Halo equivalents for the new order test).

### F9 — Flight Deck's §C annunciator strip is ~2.4× too small · MAJOR · CONFIRMED
- **Surface**: plain session list (`sessionList`/`subagentsCard`/`usageMeters`).
- **Current**: `FlightDeckAnnunciatorTileView` (`FlightDeckSessionListScaffold.swift:335-408`) is an
  `HStack(spacing:5)` — 6×6pt `Rectangle` lamp + glow, count (11pt bold mono), caption (10pt
  semibold mono), padding h7/v4, `RoundedRectangle(cornerRadius:3)`. Intrinsic height ≈ 21pt,
  matching the measured 21.5pt. **Confirmed not misled by the outer container**: `.frame(height:40)`
  (`:141`) is the outer row holding `Text("SESSION LIST")` *and* the tile row via `ViewThatFits`.
- **Target** (`02-flight-deck.html:321-334` CSS + `:913-919` markup; `shots/mockup/flightDeck-BOARD-C-4.png`):
  `.sumtile` is `flex-direction:column` — count over caption, **not** inline with a lamp. Count `.sn`
  17px/700/mono, line-height 1; caption `.sl` 9px/600/0.13em/uppercase; `gap:3px`; padding `9px 12px`.
  A lit tile's marker is a **2px-wide, full-height** (`top:0;bottom:0`) accent bar on the left edge
  (`::before`), not a small square lamp. Computed box height ≈ 9+17+3+11+9 ≈ **49–51pt**, corroborating
  the measured 51–52pt. Tiles are `flex:1`, edge-to-edge, 1px hairline separators, no per-tile radius.
- **⚠️ Structural nuance beyond REPORT**: in the mockup the annunciator strip is its **own full-width
  band**, entirely separate from the brand/usage header (`.phead`, `:889-911`) — there is **no mockup
  equivalent of a "SESSION LIST" title sharing a row with the tiles**. The app fuses title + tile row
  into one `HStack` inside one `.frame(height:40)`. Growing the tile's internal geometry inside that
  constrained HStack will **not** reproduce the mockup. The fix must restructure `sessionPanelHeader`,
  not just resize the leaf view.
- **Blast radius**: the literal `40` at `:141` is used nowhere else. Panel content height is measured
  **dynamically** at runtime via `GeometryReader`/`PreferenceKey` (`OverlayPanelController.swift:589-604`)
  — which replaced an older hand-estimated-constants approach precisely because it drifted. So growing
  the tile **does not** break the header band or push rows below the fold; it grows the panel by the
  delta (~+11–15pt on a ~650pt budget, under 3%).
- **Regression risk**: low structurally, but scope is larger than one leaf view. **Covering tests: NONE.**
- **Acceptance criterion**: tile height 49–55pt @1x (halve @2x captures); a ≥2pt accent mark spanning
  full tile height when lit; count ≥15pt stacked **above** a ≤10pt uppercase caption.
- **Fix**: rewrite `FlightDeckAnnunciatorTileView.body` (`:364-407`) to `VStack(spacing:3)`, replace
  the 6×6 lamp with a leading full-height 2pt accent `Rectangle` (keep the existing `phosphorGlow`),
  padding v9/h12, and give the count a **new dedicated typography role** — do **not** bump the shared
  `FlightDeckTypography.countSize` in place, it is also the closed-pill count badge. Separately
  restructure `sessionPanelHeader` to give the tile row its own full-width band.
- **File set**: `FlightDeckSessionListScaffold.swift`; `FlightDeckTheme.swift` (new 17pt count role).
- **Open copy decision**: whether to keep a "SESSION LIST" title at all — the mockup shows none.

### F12 — Three forked diff implementations · MAJOR · CONFIRMED (axis refined)
- **Surface**: notification card (`diffApprovalCard`).
- **⚠️ REPORT's "gutter width 10/26/22" conflates two different columns that do not all exist**:
  - **Shared** `PermissionDiffPreview`/`PermissionDiffLineRow` (`IslandPanelView.swift:68-178`) —
    used verbatim by Flight Deck (`FlightDeckSessionRow.swift:2792`, inside its chamfer-5 well),
    Annual, Instrument. Has a dedicated **marker column** (w10, glyphs `+`/`−`/blank, `:134-136`)
    but **no line-number gutter at all**. Font 10pt mono (`:141`). Only the scroll area is boxed
    (`RoundedRectangle(r7)`, `:119-122`); the "Updated (+N −N)" header floats above it, unboxed.
    Colours are token-driven, not theme-hardcoded.
  - **Poured** `PouredPermissionDiff` (`PouredSessionRow.swift:1943-2141`) — numbered gutter w26
    trailing-aligned (`:2041`); marker is **string-concatenated into the content cell**
    (`"+ "`/`"− "`/`"  "`, `:2044,2057-2063`), not a separate node. Font 11.5/regular/mono. Whole
    card in ONE `RoundedRectangle(r10)`, 1pt stroke white@0.06.
  - **Halo** `HaloHeroDiff` (`HaloSessionRow.swift:2096-2230`) — numbered gutter w22 (`:2186`).
    **No marker anywhere**: `diffRow` (`:2182-2198`) renders exactly two `Text` children. Font
    11.5/regular/mono — **identical to Poured**. Whole card in ONE `RoundedRectangle(r9)`.
  - **Already-shared invariants — do not touch**: `maxRenderedLines=500` and `maxHeight=180` are
    byte-identical across all three (`:78-79`, `:1950-1951`, `:2103-2104`).
- **Target**: not one pixel-identical look — one renderer with a themed style token. Flight Deck's
  SPEC defines **no typographic `.diff` role at all** (only structural prose at
  `SPEC-flight-deck.md:335`), confirming FD was never meant to have bespoke diff type — only a
  chamfer-native container. Candidate shared font: **11.5/regular/mono** (Poured and Halo already
  agree; the shared view's 10pt reads as unreconciled legacy).
- **Root cause**: no parameterised diff component ever existed. Poured and Halo each forked-and-themed
  reasonably but reinvented gutter width, marker treatment and card enclosure independently; the
  still-shared view has a third, older geometry nobody reconciled — and it is the **only one with a
  marker**, while the two "fully re-themed" forks are 1-for-2 on keeping it.
- **Blast radius**: `PermissionDiffPreview` — 4 callers (Annual, FlightDeck, Instrument,
  IslandPanelView); `PouredPermissionDiff`/`HaloHeroDiff` — 1 caller each, file-contained.
  **Zero tests cover any of the three renderers** — `PermissionDiffTests.swift` covers only the pure
  `PermissionDiff.compute` classification, not presentation.
- **Regression risk**: med for full unification (3 live hero frames, no rendering-test net), but each
  migration step is independently low–med and revertable.
- **Acceptance criterion**: (1) every theme's diff row renders a marker as a **dedicated child view**
  (not string concatenation) whose text is `+`/`−`(U+2212)/blank, distinct from gutter and content;
  (2) a line-number gutter is present in all three (today absent from the shared view); (3) verified
  against a fixture line that does **not** start with `-`/`+`; (4) FD's diff card shows one continuous
  chamfer edge with no nested `RoundedRectangle(r7)`.
- **Fix**: new `IslandDiffRenderer(result:lang:style:)` + `IslandDiffStyle` (gutterWidth, font,
  colours, `ContainerShape`). Marker and gutter become **structural, always-rendered** parts of the
  component — not per-theme options.
- **File set**: `IslandPanelView.swift`, `PouredSessionRow.swift`, `HaloSessionRow.swift`,
  `FlightDeckSessionRow.swift`, `AnnualSessionRow.swift`, `InstrumentSessionRow.swift`,
  `AppearancePreviewFixtures.swift`, new `IslandDiffRenderer.swift`.
- **Migration order**: (1) fix the fixture + build the component net-new, no call sites touched;
  (2) Poured (pure consolidation, near-zero behaviour delta); (3) Halo (carries in the already-shipped
  F4 marker); (4) Flight Deck onto `.chamfered(5)`, dropping its outer well-wrap — **resolves F14**,
  highest design risk; (5) Annual/Instrument (open decision); (6) delete the legacy view once callerless.

### F3 — Halo's closed-pill glyph is achromatic; A3 ringed-dot unreachable · MAJOR · CONFIRMED (root cause RESCOPED)
- **Surface**: closed pill. The symptom lives in the **shared traveling-glyph overlay**, not a
  pill-specific view — this is the rescope.
- **Current — tint**: `closedGlyphTint` is a genuine **protocol requirement**
  (`IslandTheme.swift:233-237` — deliberately not extension-only; its doc comment says so, "for the
  same dynamic-dispatch reason as `closedSurfaceGlow`"), defaulted to `nil` by the extension
  (`:282-286`). `HaloTheme.swift` has **zero** references (grep-confirmed) → inherits `nil`. The sole
  consumer `islandGlyphOverlay` (`IslandPanelView.swift:626-646`) builds `UnifiedBars(mode:, tint:
  theme.closedGlyphTint(...))`; `nil` falls back to `tokens.colors.paper` (`UnifiedBars.swift:51`) →
  the sampled RGB(255,255,255) / RGB(143,141,141). Poured's override is at `PouredIslandTheme.swift:132-154`.
- **Current — shape. REPORT.md's framing was wrong about *why*.** `PouredPillAmbientState.resolve`
  **does** have a `.permission` case (`PouredPillAmbientState.swift:56-58`, reached via
  `activity.phase == .waitingForApproval`). `HaloClosedPill` **does** have correct ringed-dot code:
  `indicator` (`:63-68`) → `HaloSessionRowFormat.pillIndicator` (`:271-326`) → `.permissionDot` →
  `HaloPillRingedDot` (`:112-116, 486-503`), an 8pt filled circle correctly fed
  `statusWaitingForApproval`. **It is dead because** `leadingIndicator` (`:96-104`) only renders
  `indicatorContent` `if showsGlyph`, and the one production call site in the default animated path,
  `morphingIslandSurface`, always passes `v6ClosedSurface(showsGlyph: false)`
  (`IslandPanelView.swift:804`). The visible glyph is exclusively `islandGlyphOverlay`'s
  `UnifiedBars`, whose `Mode` (`UnifiedBars.swift:11-27`) has only 3 bar shapes and **structurally
  cannot draw a dot**, regardless of tint.
  ⚠️ **Under Reduce Motion**, `legacyCrossfadeSurface` calls `v6ClosedSurface()` with the default
  `showsGlyph: true` (`:687`) — Halo's indicator **renders correctly there**. The bug is specific to
  the default/animated path.
- **Target**: `06-halo.html:619-650` captions A4 *"Distinct from permission by hue **and**
  shape/label — never color alone"* — shape differentiation is the intended contract, which Halo's
  dead code already implements correctly. Crops `halo-A3.png` (perm dot) vs `halo-A4.png` (3 bars).
- **Root cause**: tint = missing `HaloTheme.closedGlyphTint` override. Shape = `islandGlyphOverlay`
  hardcodes theme-agnostic `UnifiedBars` as the sole traveling-glyph renderer and unconditionally
  suppresses each theme's richer indicator via `showsGlyph:false`. `UnifiedBars.Mode` lacking a
  permission case is real but **secondary**.
- **Blast radius**: *Tint* — isolated to `HaloTheme.swift`, zero other themes. *Shape via extending
  `UnifiedBars.Mode`* — exhaustive switches needing a new arm: `UnifiedBars.swift` (`Mode.usesLayerAnimation`
  ~`:21-27`, plus **three internal CAShapeLayer configs at `:252,272,291` that need actual new
  geometry**), `PouredPillAmbientState.swift:49-53`, `HaloClosedPill.swift:353-357`,
  `AppearanceSettingsPane.swift:764-768`.
  **Verified NOT affected** (grep false positive): the similar `case .running/.idle/.waiting`
  switches in `PouredClosedPill.swift:745-757`, `FlightDeckClosedPill.swift:707-721`,
  `AnnualClosedPill.swift:299-307`, `InstrumentClosedPill.swift:275-285`, `HaloClosedPill.swift:742-751`,
  `V6NotchContent.swift:265-273` all switch over **`AgentGridCellState`**, a different type.
- **Regression risk**: tint override **low** (additive, Halo-only, no covering tests). Shape via
  `UnifiedBars.Mode` **high**. Shape via a new theme-pluggable glyph seam **med** (additive, mirrors
  the existing `closedSurfaceGlow`/`closedGlyphTint` precedent).
- **Acceptance criterion**: closed pill in the A3/permission scenario, Reduce Motion off, sampled
  @1x: left-indicator glyph is non-achromatic (R,G,B not within 5 of each other) and matches
  `statusWaitingForApproval` hue (~255,177,77); and the indicator is geometrically **a filled circle,
  not three bars**, when the spotlight session's phase is `.waitingForApproval`.
- **Fix**: (1) add `HaloTheme.closedGlyphTint`, extracting the existing
  `HaloClosedPill.livenessTint`/`outcomeTint` mapping (`:123-138`) into a shared static both call —
  **share, do not duplicate** (duplicating literals is exactly the drift this review catalogues).
  (2) Shape gap needs an explicit decision — see §5.
- **File set** (tint only, ready now): `HaloTheme.swift`, `HaloClosedPill.swift`.
- **⚠️ Open question**: confirm the capture harness runs with system **Reduce Motion OFF** — no
  toggle was found under `scripts/`, so this is inferred. It determines whether the observed symptom
  is this bug or something else.

### F4 — Halo's permission diff conveys added/removed by COLOUR ALONE · MAJOR · CONFIRMED
- **Surface**: notification card (hero permission/diff frame).
- **Current**: `HaloHeroDiff.diffRow` (`HaloSessionRow.swift:2182-2198`) renders exactly two `Text`
  children — gutter number (`:2184-2187`) and `row.line.text` (`:2188-2191`) — styled only by
  `gutterColor`/`textColor`/`rowBackground` (`:2200-2222`), all keyed on `PermissionDiffLine.Kind`
  but expressed **purely as colour**. No marker glyph exists anywhere in the type.
- **Target**: the shared `PermissionDiffLineRow` marker column — `Text(marker)` at fixed
  `.frame(width:10, alignment:.leading)` (`IslandPanelView.swift:134-136`), where `marker` (`:148-154`)
  is computed **purely from `line.kind`, never from `line.text`**. Poured concatenates the same
  kind-only `markerPrefix(_:)` (`PouredSessionRow.swift:2057-2063`). Both are trap-proof by
  construction — marker existence is decoupled from content.
- **Blast radius**: none beyond `HaloSessionRow.swift` — `diffRow` and `HaloHeroDiff` are both
  private, single-caller.
- **Regression risk**: **low** — additive change to one private view. **Covering tests: NONE.**
- **Acceptance criterion** (trap-proof): `diffRow` renders a **third, dedicated leading-column
  element** whose content is a pure function of `row.line.kind` only — verifiable by code inspection
  independent of any fixture text — **and** verified on a fixture line whose content does not start
  with `-` (requires the Phase 1 fixture fix, §3a). Row remains distinguishable added-vs-removed
  with colour desaturated to greyscale.
- **Fix**: add a marker column rendering `"+ " / "− " / "  "` keyed off `row.line.kind`, mirroring
  `PermissionDiffLineRow.marker`. 2–4 lines.
- **File set**: `HaloSessionRow.swift` (~`:2182-2198`).

### F19 — Halo `nestHeader` caption at two weights · MINOR · CONFIRMED exactly as rescoped
- **Current**: five sites use `HaloTypography.nestHeaderSize`; only two are true captions.
  `:622` "SUBAGENTS" — `weight:.bold`, `.tracking(×0.09)`, uppercased. `:1102` assistant/completion
  label — `weight:.semibold`, same tracking, same uppercasing. **Identical pattern except weight.**
- **Correctly excluded, as the brief warned**: `:625` and `:720` are `.semibold.monospacedDigit()`
  numeric readouts with **no tracking and no uppercasing**; `:2019` (`HaloQuestionTag`) is `.bold`
  with **0.05** tracking (not 0.09) on a solid qgold capsule — a separately-specified `qChip` role
  (`HaloTheme.swift:93-94`) that merely aliases the same numeric size.
- **Target**: `SPEC-halo.md:264` — *"Nest header (.nest-h) | 10 | sans | **700** / 0.09em UPPER"*.
  700 = `.bold`, so **`:1102` is the deviant**.
- **Root cause**: `HaloTypography` exposes only the raw `nestHeaderSize: CGFloat`, no pre-built
  `Font` constant — every call site hand-reconstructs weight+tracking, structurally inviting drift.
- **Regression risk**: low, one word. **Covering tests: NONE.**
- **Acceptance criterion**: `:1102` reads `.bold`, matching `:622`.
- **Fix**: `.semibold` → `.bold` at `:1102`; additionally add `HaloTypography.nestHeader: Font` +
  tracking constant (mirroring `FlightDeckTypography.count`) so both sites construct identically.
- **File set**: `HaloSessionRow.swift:622,1102`, `HaloTheme.swift`.

### F20 — Halo completion grid omits Model · MINOR-MEDIUM · CONFIRMED (root cause DEEPER than REPORT)
- **Current**: `displayModelName` (`AgentSession+Presentation.swift:373-380`) is
  `claudeMetadata?.model ?? openCodeMetadata?.model ?? cursorMetadata?.model` — **`codexMetadata` is
  never in the union**, and `CodexSessionMetadata` (`CodexSessionTracking.swift:4-36`) has no `model`
  field. §H's fixture is `longCompletionSession` (`IslandDebugScenario.swift:582-609`), `tool:.codex`
  — so `metadataCell` (`HaloSessionRow.swift:1069-1078`, which "emit[s] nothing rather than an
  em-dash" per SPEC §0 honesty) structurally never draws the cell. **This much matches REPORT.md.**
- **⚠️ Deeper finding not in REPORT.md — Codex DOES carry a model at the wire level.**
  `CodexHookPayload.model: String` is a **required, non-optional** field (`CodexHooks.swift:123`,
  decoded non-optionally at `:216` — a payload omitting it fails to decode). Every real Codex CLI
  hook event reports a model. The value is **dropped in translation**: `defaultCodexMetadata`
  (`CodexHooks.swift:400-409`) and `mergedCodexMetadata` (`BridgeServer.swift:2026-2047`) copy six
  fields but never `model`. Corroborating: `shortModelDisplayName` (`AgentSession+Presentation.swift:400+`)
  **already has explicit GPT-family handling** (`:423-427`) and its doc comment gives
  `"gpt-5-codex" → "GPT-5"` as a worked example — the display pipeline was written expecting Codex
  models to flow through; the plumbing was never finished.
- **Root cause**: two layers — the display union gap REPORT identified, **plus** a real,
  previously-unflagged data-plumbing gap.
- **Regression risk**: low-med — additive `Optional` field, synthesized `Codable` with no custom
  `CodingKeys` (confirmed), so old persisted JSON decodes fine. **Covering tests**:
  `CodexSessionTrackingTests.swift`, `AgentSessionPresentationTests.swift` — both need extending,
  neither should break.
- **Acceptance criterion**: a Codex session with a hook-reported model produces a non-nil
  `displayModelName`, and §H renders 4 cells including Model via the existing GPT-family path.
- **Fix — add the field, not a fixture swap or placeholder.** A placeholder would violate the
  documented SPEC §0 honesty principle; a fixture swap would hide the gap for production Codex users.
  (1) `public var model: String?` on `CodexSessionMetadata`; (2) thread it through
  `defaultCodexMetadata` + `mergedCodexMetadata`; (3) add `?? codexMetadata?.model` to the union;
  (4) set a `model:` on the fixture so §H actually exercises the fixed path.
- **File set**: `CodexSessionTracking.swift`, `CodexHooks.swift`, `BridgeServer.swift`,
  `AgentSession+Presentation.swift`, `IslandDebugScenario.swift`.
- **Caveat**: the Codex.app/MCP path (`CodexAppServerCoordinator.swift:280`) shows no model-equivalent
  field. The fix definitely closes the gap for CLI-hook Codex sessions; Codex.app-sourced sessions
  need a follow-up look.

### F17 — Flight Deck's `count` role in four weight/design combos · MAJOR · RESCOPED file confirmed
- **Surface**: closed pill (all four sites are closed-pill right-slot content).
- **Current**, all verified verbatim at `FlightDeckClosedPill.swift` — and
  `FlightDeckSessionRow.swift` has **zero** matches for `countSize`/`.count`, confirming REPORT's
  file correction:
  `:536` bold+sans (attention segment) · `:601` bold+mono (usage mini-tape "%") ·
  `:633` medium+sans (task counter "N subagents") · `:638` semibold+mono (canonical, matches
  `FlightDeckTypography.count` at `:112`).
- **Root cause**: `FlightDeckTypography.count` — a pre-built canonical `Font` — already exists, but
  **3 of 4 sites construct their own `Font.system(...)` reusing only the `countSize` *number*, not
  the *font***.
- **Regression risk**: low. **Covering tests: NONE** — `readableRoleSizes` checks only the number 11
  and is blind to weight/design.
- **Acceptance criterion**: zero raw `Font.system(size: FlightDeckTypography.countSize, …)`
  constructions outside a named, tested role; each new role has a weight+design assertion.
- **Fix**: three named sub-roles — `countGlyph` (bold/sans), `countLabel` (medium/sans), and the
  existing `count` (semibold/mono) for both value sites, converging `:601`'s bold+mono onto canonical
  semibold+mono (reads as copy-paste, not intent). **This is a judgement call, not a SPEC citation** —
  see §5.
- **File set**: `FlightDeckTheme.swift`, `FlightDeckClosedPill.swift`, `FlightDeckThemeTests.swift`.

### F11 (role slice) — Poured `sideBadge` mono + dead `monoChip` · MAJOR · CONFIRMED
- **Current**: `sideBadge` (`PouredSessionRow.swift:1181-1188`) hardcodes
  `.system(size:10.5, weight:.medium, design:.monospaced)`, never calling `PouredType`. **Six call
  sites**: `:214,226,229,233,236,1210`. The bypass-permissions chip (`:1213`) repeats the pattern at
  `.semibold`. `PouredType.Role.monoChip` (`PouredTypography.swift:109,183`) has **confirmed zero
  call sites** in `Sources/` (the other `monoChip` hits are an unrelated same-named private func in
  `AppearanceSettingsPane.swift`).
- **Target**: `SPEC-poured-island.md:189` "drop mono". The right role is
  `PouredType.Role.metaChip` (10.5/500/**sans**, `PouredTypography.swift:182`).
- **🔑 This is the load-bearing proof for the Phase 6 mechanism**: `monoIsReservedForCodeShapedRoles`
  (`PouredThemeTests.swift:358-373`) **already asserts `.metaChip` must be sans, and passes today** —
  because the table has never been asked about `sideBadge`. **Extending the role table cannot fix
  this. The table was never wrong.**
- **Recommendation**: retire `monoChip` (dead, and SPEC drops mono for chips); wire `sideBadge` and
  the bypass chip to `PouredType.font(for: .metaChip)`.
- **File set**: `PouredSessionRow.swift:1181-1188,1213-1218`, `PouredTypography.swift:109,183`.

### F11b — Poured hero-frame button labels have no role at all · CONFIRMED
- **Current**: `.system(size:13, weight:.semibold)` hardcoded at `PouredApprovalButtonLabel`
  (`PouredSessionRow.swift:1872`) and `terminalApprovalCTA` (`:1721`). (`:1688` is an SF Symbol icon,
  **not** a text role — noted to correct the count, not a defect.)
- **Root cause**: **a different class from F11** — this is FD's disease (missing vocabulary) inside
  Poured. No role in the 42-entry table covers "button label". **Poured has both failure modes.**
- **Fix**: add `PouredType.Role.heroButtonLabel` (13/600/sans — matches shipped values, **zero visual
  change**) and consume at both sites.
- **File set**: `PouredTypography.swift`, `PouredSessionRow.swift:1721,1872`.

### F2 — Flight Deck's hero frame does not read as an EVENT · MAJOR · CONFIRMED
Four sub-findings. **F2.1 and F2.2 are the same bug** — see the shared cause below.

**F2.1 — zero glow bleed. Root cause traced to a shared clip.**
`FlightDeckApprovalCard.body` (`FlightDeckSessionRow.swift:2762-2839`) chains `.background(cardFill)`
(`:2827`) → `.overlay(border)` (`:2829-2832`) → `.background(FlightDeckCautionGlow)` (`:2835-2837`).
`FlightDeckCautionGlow`/`FlightDeckPulsingGlow` (`:3019-3065`) build
`FlightDeckPhosphorGlow(shape:radius:9,…)` — **structurally identical to working sites** like
`FlightDeckEngineLamp` (`:1797-1828`). `FlightDeckPhosphorGlow.body`
(`FlightDeckPhosphorGlow.swift:44-51`) paints outside its frame via `.padding(-bleed)` **without
inflating its measured size**.
**The clip**: the entire opened panel content is wrapped in `.clipShape(shape)` in both render paths
— `IslandPanelView.swift:797`+`815` (default morph) and `:575`+`580` (Reduce Motion). Per the AB-228
comment (`:540-547`) the panel's bounds are the content's **tightly measured** layout size — zero
slack for anything painting outside its own frame.
**Decisive precedent — this exact bug class is already solved once**: `closedAmbientGlow`
(`IslandPanelView.swift:456-474`, wired `:782`) is **already hoisted outside this same clip** via the
`theme.closedSurfaceGlow(...)` hook, with the comment *"cast… as a sibling… OUTSIDE the content clip…
so it bleeds past the silhouette instead of being truncated."* **No equivalent hook exists for the
opened/actionable side.** Small lamps never reach the clip boundary (generous surrounding chrome);
the near-full-width MASTER card does.
- **Acceptance criterion**: horizontal scan across the card's left edge shows a fading alpha ramp
  ≥4–8pt (the in-strip lamp's is ~2pt @1x) instead of today's 0px cut. Halve @2x.
- **Fix**: either (a) widen the card's margin from the clipped bounds so existing bleed fits, or
  (b) mirror AB-330 — add a `theme.actionableCardGlow(…)`-style hook rendered as a ZStack sibling
  **outside** `openedSurfaceContent`'s clip. (b) is straightforward for the notification card; an
  actionable row scrolled inside the plain list would need scroll-position tracking — see §5.
- **Blast radius**: `FlightDeckCautionGlow` has 1 real call site, FD-only. **The clip is shared by
  every theme — do not edit those calls directly.** Extend via the hook pattern.

**F2.2 — card fill ~3× too light. Not a token, and not independently fixable.**
`cardFill` (`:2932-2934`) is `alarm.opacity(0.08)` where `alarm = statusWaitingForApproval =
flightDeckWarning` **#E04A42** (`IslandColorTokens.swift:315`). **It does not route through
`FlightDeckSurfaces` at all** — contrary to the ruler's pointer.
**The arithmetic proves F2.1 is the cause**: forward-computing 8% alpha over the confirmed base
`surfaceInk` #08090A gives ≈(25,14,14) — **darker** than measured, not lighter. The residual
brightness is explained by the un-bled glow: `FlightDeckApprovalFormat.glowOpacity(phase:0,
reduceMotion:true)` (`:453-458`) hardcodes `restingLevel = 0.5`. Composing base → glow(0.5) →
cardFill(0.08) gives ≈**#7D2C28**, within ~1–20 RGB units per channel of the measured **#682E27**.
**The glow is rendering at full strength under the card because it can't escape the clip.**
- **Acceptance criterion**: sampled interior = **#231718** ± a few units; beacon/card luminance ratio
  ≥ 2.3× (today 1.29×, mockup 2.58×).
- **Fix**: land F2.1 first, then re-tune. Replace `alarm.opacity(0.08)` with an FD-hero-local hex
  constant, mirroring `PouredApprovalColors` (`PouredSessionRow.swift:2094-2141` — *"exact hero hexes
  live beside the view rather than on the token layer"*), rather than chasing an opacity tied to one
  base/glow combination.

**F2.3 — MASTER placard smaller than its kicker.**
Placard `.system(size:10.5, weight:.bold, design:.monospaced).tracking(1.2)` (`:2625-2627`) vs kicker
`.system(size:11, weight:.semibold, …).tracking(0.6)` (`:2634-2636`), both in
`FlightDeckAnnunciatorHeader` (`:2608-2646`). Target per `SPEC-flight-deck.md:158`: 12px/800/0.12em.
- **`FlightDeckAnnunciatorHeader` has exactly 2 call sites** — `FlightDeckApprovalCard.annunciatorHeader`
  (red) and `FlightDeckQuestionAnnunciator` (amber) — **one fix covers both MASTER WARNING and
  MASTER CAUTION.**
- **Fix**: `:2626` size 10.5→12, weight `.bold`→`.heavy`; `:2627` tracking 1.2→1.44 (0.12×12).
- **Acceptance criterion**: cap-height ratio vs kicker > 1.0.

**F2.4 — Model and Branch unreachable, including via VoiceOver.**
Exhaustive check of `FlightDeckActionableRowContent` (`:2052-2511`): **zero** references to
`displayModelName` or branch. `accessibilityRowSummaryText` (`:2483-2491`) interpolates only tool
name / workspace / phase / elapsed. `.accessibilityElement(children:.contain)` (`:2838`) lets
VoiceOver descend, but no child ever renders one. FD **does** have the data and component — expanded-row
`metagrid()` (`:887-931`, model at `:902-903`, branch at `:910-911`) — but that is the **expanded
surface**, not the alarm card.
- **Sibling precedent**: **Halo puts Model *inside* the hero card** — `HaloPermissionHero`/
  `HaloQuestionHero` pass `modelName:` into `HaloHeroShell` (`HaloSessionRow.swift:1821`), whose
  `head` (`:1678-1724`) renders a dedicated who-line (`:1712-1721`). Halo's row-level `metaLine`
  explicitly suppresses itself for `.permission`/`.question` — it relies entirely on that who-line.
  **Poured** calls `rowSummary` unconditionally (`PouredSessionRow.swift:190`, `:121-123`).
  Halo passes **Model only, not branch**.
- **Root cause**: `FlightDeckAnnunciatorHeader`'s only extension point is `trailing:` (consumed by
  `heldReadout`) — no slot for identity data.
- **Fix**: add a compact secondary-opacity context run to `FlightDeckAnnunciatorHeader`, mirroring
  Halo's who-line. **Do not touch `agentCell`** (defensible per DO-NOT-FIX).

### F10 — Flight Deck's E3 CTA reads as a decision · MAJOR · CONFIRMED (mechanism RESCOPED)
- **Current**: `terminalApprovalCTA` (`FlightDeckSessionRow.swift:2976-2986`) is a direct child of
  `FlightDeckApprovalCard.body`'s outer VStack (`:2800-2802`) — **fully inside the alarm-red
  `cardFill` field**. It is `FlightDeckApprovalButton(kind:.ghost)`, and `.ghost`'s tokens
  (`:3129-3158`) are **confirmed fully neutral** (`foreground paper@0.7`, `background paper@0.03`,
  `border paper@0.18`) — no red anywhere. Every button carries `.frame(maxWidth:.infinity)` (`:3106`).
  So: correct colours, but 3% fill lets the alarm-red behind it dominate, and forced full width
  borrows the ALLOW/DENY pair's decision weight.
- **⚠️ Target corrects the review**: the mockup's `.codexbar` (`02-flight-deck.html:1161-1189`) is
  **not neutral grey** — it is `rgba(99,146,196,.06)` with `.btn.jump` at `rgba(99,146,196,.16)`,
  border `.5`, colour `#a9c4e8`. **`rgba(99,146,196,…)` is FD's own `statusCompleted` advisory-blue
  token** (`flightDeckComplete`, `IslandColorTokens.swift:311`) — a **differently-hued** sub-panel,
  hairline-separated, with explanatory copy and a ~27–30%-width button.
- **⚠️ Blast radius trap**: `FlightDeckApprovalButton(kind:.ghost)` has **2 conceptually different
  callers** — `alwaysAllowOptions` (`:2940-2973`, which **should stay full-width** per the mockup)
  and `terminalApprovalCTA`. **Restyling `.ghost` globally would wrongly change the always-allow
  rows.** The fix must be at the call site.
- **Regression risk**: high (unverified) — **`.codexApproval` is wired into NO Flight Deck golden.**
- **Acceptance criterion**: sub-panel background reads blue-grey (~99,146,196 family), not
  alarm-red-adjacent; button width ≤ ~35% of card content width (today 94–95%); hairline above.

### F13 — Flight Deck's completion card genuinely lacks Transcript · MAJOR · CONFIRMED
- **Current**: `completionBody` (`FlightDeckSessionRow.swift:2281-2323`, read in full) — badge/banner
  → optional markdown → optional donestats → optional reply input. **Zero** Transcript references in
  `FlightDeckActionableRowContent`. The only `TranscriptAffordance` use in the file is `:868-871`,
  inside `expandedDetails` — a **different struct** (`FlightDeckRowContent`'s non-actionable path).
- **Mirror pattern**: `RowActions` has **no `transcript` field at all** — both siblings read the
  session directly. Poured `completionActionRail` (`PouredSessionRow.swift:1013-1044`) and Halo
  (`HaloSessionRow.swift:954-980`) are identically shaped, both gating on
  `session.trackingTranscriptPath?.trimmed` — exactly FD's own `:868-869` idiom.
- **Fix**: add to `completionBody` after donestats:
  `if let p = session.trackingTranscriptPath?.trimmingCharacters(in:.whitespacesAndNewlines), !p.isEmpty { TranscriptAffordance(path:p, workspace:…, lang:lang) }`.
  **Do NOT add Dismiss or Reply.**
- **⚠️** `testFlightDeckCompletionSuccessNotch` exists, but its fixture likely doesn't set
  `trackingTranscriptPath` either — **the new branch renders nothing unless Phase 1's fixture fix
  also covers `.completedSuccess`.**

### F14 — Rounded shared view nested in a chamfered well · MAJOR · CONFIRMED
- **Current**: `FlightDeckApprovalCard.body` (`:2789-2798`) wraps unmodified `PermissionDiffPreview`
  in `.background(FlightDeckChamferedRectangle(chamfer:5).fill(FlightDeckSurfaces.well))`, and
  `PermissionDiffPreview` (`IslandPanelView.swift:68-125`) hardcodes
  `RoundedRectangle(cornerRadius:7)` (`:119-122`) — confirmed only 2 stored properties, **no shape
  parameter exists**.
- **Note**: FD is the *only* theme reusing the shared view verbatim. Poured/Halo forked their own —
  so they have a *duplication* problem, not a *corner-mismatch* problem (their forks are internally
  consistent, rounded-in-rounded).
- **⚠️ DO NOT FIX F14 INDEPENDENTLY OF F12.** Two incompatible directions exist: (1) parameterise
  `PermissionDiffPreview`'s shape → fixes F14 **and** reduces forks 3→1; (2) write an FD-only fork →
  fixes F14 alone but moves fork count **3→4, the wrong way**. Sequence F12 first or merge them.
- **Covering tests**: NONE for FD — `.permissionDiff` is in no FD golden.

### F6 — Poured's session list buries the list under expanded rows · MAJOR · CONFIRMED (cause NARROWED further)
- **Surface**: plain session list.
- **Current**: `PouredRowContent.rowBody` (`PouredSessionRow.swift:110-117`):
  `defaultShowsDetail = !isStaleCompleted && (rawPresence != .inactive || isActionable)`.
  When true, the row branches: `if shouldShowEmbeddedDetailBody { embeddedDetailBody }` **`else {
  sessionDetailBody(…) }`** (`:131`, `:145-150`) — **unconditionally**.
  `shouldShowEmbeddedDetailBody` (`:828-836`) is true only for `phase.requiresAttention` or
  `(completed && isActionable)` — **false for a merely-running row by explicit design** (comment
  `:822-827`: *"A running row no longer earns an embedded body"*). So every running/recently-active
  non-actionable row falls through to `sessionDetailBody` (`:562-578` — metadata grid + assistant
  card + Jump/Transcript rail): **the ~251pt culprit.**
  **→ The precise defect is the `else` branch at `:145-150`, not the `showsDetail` predicate itself.**
- **Verified against the real fixture** (`DebugSessionFactory.listSessions`,
  `IslandDebugScenario.swift:319-386`, `previewHeight:430` at `:151`): 1 running + 1 completed-3-min-ago
  (under the 5-min threshold) + 7 inactive aged 27–130min. `.sessionList` sets no `actionableSessionID`
  → all 9 have `isActionable=false` → both the running and recently-completed rows hit
  `sessionDetailBody` (~251pt each). **2×251 = 502pt alone exceeds the 430pt budget** — mechanically
  why only 2 of 9 fit.
- **Target — decisive**: mockup §C (`01-poured-island.html:768-919`) — **zero rows carry a
  `.meta-grid`. That class appears exactly once in the entire document, inside §D (`:942`).** All six
  §C rows render only `title-line` + one `.act` line + one compact actions/meta line, uniform
  regardless of state (the measured 86–98pt). §D is an explicitly separate, **user-initiated** frame:
  *"Tap a row to expand in place"* (`:925-927`). **No row is auto-expanded in the plain list — not
  even actionable ones**, which use a short inline treatment (amber `.act` + mini Approve/Deny,
  `:819-824`).
- **Arithmetic** (*M* = measured, *D* = derived): scroll cap `maxSessionListHeight = 560pt`
  (`PouredSessionListScaffold.swift:21`) *M*; header 36pt (`:128`) *M*; footer ≈32pt (`:142-166`) *M*.
  Post-fix running-row height ≈ **62pt** *D* (49pt collapsed + 16 content − 3 padding).
  **9 rows post-fix = 2×62 + 7×49 = 467pt ≤ 560pt — all 9 fit** (vs 845pt / 2-of-9 today).
  Against the 430pt preview budget (−36 −32 = 360pt): cumulative 62,124,173,222,271,320 → **rows 1–6
  fit**; worst case with three 30pt section headers (270pt budget) → **rows 1–5**. **The ≥5-row bar
  is met in every scenario tested.**
- **⚠️ `testExpandedDetailAndSubagents`'s golden exists ONLY because of this bug.**
  `ThemeSnapshotting.swift:224` forces `actionableSessionID = nil` for `.subagents`, so its
  "expanded running row" golden is a product of ambient expansion. Fixing F6 makes that render path
  unreachable from static snapshots — **a testability seam is required**, see §5.
- **Fix**: change the unconditional `else { sessionDetailBody(…) }` to
  `else if detailOverride == true { … }`. The row already has the plumbing —
  `@State private var detailOverride: Bool?` (`:82`) plus a working chevron `detailToggleButton`
  (`:1231+`). `shouldShowEmbeddedDetailBody`'s hero path is untouched, so the notification card's
  actionable row is **provably unaffected** (that branch never reads `detailOverride`).
- **Note**: near-identical logic exists in the shared `IslandSessionRow.rowBody`
  (`IslandPanelView.swift:1152-1159`) and in Halo's own `sessionDetailBody`
  (`HaloSessionRow.swift:795`) — both untouched by a Poured-scoped fix. See §5.

### F16 — Poured's button family disagrees with itself · MAJOR · CONFIRMED (all four verified byte-exact)

| Kind | Radius | Pad H/V | Border | Glow | Font | Location |
|---|---|---|---|---|---|---|
| Jump | **10** | 14/8 | white@0.4 1pt `.blendMode(.overlay)` | yes `.shadow(r10,y4)` | `jumpChip` 11.5/600 | `PouredJumpButtonStyle:2326-2360`; calls `:759`, `:1028` |
| Allow/Deny | 11 | 14/8 | none | **none** | hardcoded `.system(13,.semibold)` `:1872` | `PouredApprovalButtonLabel:1862-1899`; calls `:1616`,`:1628` |
| Ghost | 11 | **12**/8 | none | none | hardcoded `.system(12,.medium)` `:1044` | `PouredGhostButtonStyle:2368-2405`; call `:1047` |
| Codex CTA | 11 | 14/**9** | none | **none** | hardcoded `.system(13,.semibold)` `:1721` | `terminalApprovalCTA:1712-1739`; call `:1523` |

- **Target — the mockup has ONE `.btn` base** (`01-poured-island.html:347-348`):
  `padding:8px 14px; border-radius:11px; font-size:13px; font-weight:600; border:none`. Kind
  modifiers change **only fill/colour**: `.btn.primary` adds gradient + glow (`:349-350`);
  `.btn.ghost`/`.btn.deny` add a flat translucent fill with **no shadow** (`:352-355`).
- **Two corrections**: (1) the small `.jump` inline chip (`:280-283`, 11.5px/600, r8) is a
  **separate, smaller affordance**, not the same component as the "Jump to terminal" primary CTA,
  which the mockup renders as `.btn.primary` at the **13px/600 base size** in both §D (`:963-966`)
  and §H (`:1422-1425`). The code reuses `jumpChip` (11.5/600) for what the mockup treats as a full
  `.btn.primary` — a **role-context mismatch**. (2) Jump's white@0.4 border is a **Jump-specific
  addition, not spec'd** — the mockup's `.btn.primary` has no stroke.
- **Additional observation**: `PouredApprovalButtonLabel` has **no `.shadow(…)` of its own** — Allow's
  amber gradient never gets the button-level glow Jump's blue one does, though both map to
  `.btn.primary`.
- **Do NOT flatten**: primary/amber/blue keep gradient + glow; ghost/deny stay flat and glowless.
  That is a real semantic distinction (event vs wayfinding vs decision), not drift.
- **Acceptance criterion**: one shared style with a `kind` enum; all 6 call sites migrated; radius
  literals {10,11,11,11} → {11}; padH {14,14,12,14} → {14}; zero remaining `.system(size:13…)` /
  `.system(size:12…)` literals in these regions.
- **Blast radius**: all four structs are private/fileprivate to `PouredSessionRow.swift`; 6 call
  sites; zero protocol or cross-theme impact.

### Phase 1 infrastructure findings (harness + fixtures)

**⚠️ P1.a — REPORT-methodology.md is WRONG about Poured's expanded row.** It claims *"all three
agents independently confirmed the expanded state never appears."* **Empirically refuted**:
`shots/app/poured-subagentsCard.png` **already shows** the full "3 SUBAGENTS" nest + "TASKS · 2 OF 5
DONE" checklist. Only **Flight Deck and Halo** are broken. Poured's §D/§G renders correctly today —
because Poured's expansion is presence-derived (the F6 bug!), while Halo/FD read
`@Environment(\.islandRowExpandedByDefault)` (`HaloSessionRow.swift:123`, `FlightDeckSessionRow.swift:551`),
which defaults false and the harness never sets.
**→ Fixing F6 will collapse Poured's currently-working §D capture. F6 and P1.a must be sequenced
together.**
- **The seam already exists**: `IslandRowExpandedByDefaultKey` (`IslandThemeEnvironment.swift:107-127`),
  doc-commented *"lets the harness pin the expanded frame without a real gesture; it is a preview/test
  seam only"* — built for AB-339's snapshot goldens, **never wired into `IslandDebugScenario`**.
- **Fix**: add `forcesRowExpansion: Bool = false` to `IslandDebugSnapshot`; set it on a **new**
  scenario (`subagentsExpanded`) so the existing `subagentsCard` keeps documenting the collapsed
  state; thread through `AppModel.loadDebugSnapshot` → `.environment(\.islandRowExpandedByDefault, …)`
  at `OverlayPanelController.swift:134`.
- **Acceptance criterion**: `overlay.ax.json` for the new FD/Halo captures contains the fixture's task
  titles (e.g. `"Header + meters + scaffold"`) — currently absent, and already present for Poured.

**⚠️ P1.b — §I's usage-meter card is a Settings-only surface by design.**
`theme.usageMeterCard(providers:lang:)` has **exactly one call site in the whole app target**:
`AppearanceSettingsPane.swift:1101`, inside `AppearanceSessionListPreview`. The live overlay's
`openedHeaderContent` (`IslandPanelView.swift:848-863`) calls only `theme.openedHeader(…)`.
**The live overlay never shows §I to a real user either** — both theme files' doc comments say so
("Hosted by the `meters` preview scenario; the compact header filament stays in `openedHeader`").
**→ This is not a harness gap; making §I capturable means either adding a live-overlay surface
(production composition change) or capturing the Settings window. See §5.**

**P1.c — `completedFailed.updatedAt`**: `-9 * 60` at `AppearancePreviewFixtures.swift:217` vs
`AgentSession.staleCompletedDisplayThreshold = 5*60` (`AgentSession+Presentation.swift:20`) →
`isStaleCompletedForIsland` true (`:477-483`) → every theme forces `presence = .inactive`
(`PouredSessionRow.swift:118-120`, `HaloSessionRow.swift:136,140`) → the idle template wins.
**Fix**: change to `-3*60 - 30` (210s) — under 300s, off a 60s boundary, distinct from
`completedInterrupted`'s −240s.

**P1.d — `stableID` truncation, mechanism confirmed by character count.**
`stableID(_:)` (`AppearancePreviewFixtures.swift:29-40`) copies only the **first 16 UTF-8 bytes** of
the seed directly into the UUID — **no hashing, no mixing**. `conformanceQuestions()` (`:536-575`)
seeds `"conformance-auth-oauth"`, `"conformance-auth-apikey"`, `"conformance-auth-mtls"` — all share
the 16-character prefix `"conformance-auth"` → **byte-identical UUIDs**. Same for the four
`"conformance-scop"` Scope options.
- **Acceptance criterion** (a plain unit assertion, no capture needed):
  `Set(conformanceQuestions()[0].options.map(\.id)).count == 3` and `[1]…count == 4` — today both 1.
- **Fix**: hash the seed (e.g. a 16-byte digest) instead of truncating. **Caveat stated honestly**:
  this changes the UUID value for *every* seed. All other seeds were checked for collisions (none)
  and no UUID is rendered as visible text, so no further goldens are predicted to move — but treat
  any extra golden diff as a signal to investigate, not to approve.

**P1.e — `transcriptPath`**: the gate is a **pure non-empty-string check** —
`AgentSession.swift:629-631`, consumed identically across all themes. **No `FileManager` check at
render time**, so the path need not exist on disk. Add one to `completedInterrupted`'s
`claudeMetadata:` (`:197-202`), and to `.completedSuccess` if F13's FD branch is to be exercised.

**P1.f — install-hint banner**: gated by a single theme-agnostic condition
`if !model.hasAnyInstalledAgent { theme.installHint(…) }` (`IslandPanelView.swift:867-870`).
**Fix**: add `OPEN_ISLAND_HARNESS_SUPPRESS_INSTALL_HINT` to `HarnessLaunchConfiguration`, set a
`model.debugSuppressesInstallHint` in `OpenIslandApp.swift` alongside the existing
`ignoresPointerExitDuringHarness` pattern, and change `:867` to `&& !model.debugSuppressesInstallHint`.
**The real probe is untouched** — it cannot reach the shipping app because the flag only ever
originates from an env var no real user sets.
- **Acceptance criterion**: with the var set, `overlay.ax.json` no longer contains "No agent hooks
  installed"; **with it unset the string is still present** (proves opt-in, not a default change).

**P1.g — batch capture already 90% exists.** `scripts/smoke-all-scenarios.sh` already loops all 15
scenarios for the currently-persisted theme, calling `smoke-dev-app.sh` and validating via
`scripts/validate-harness-artifacts.py`. **It has no theme axis.** Adding an outer loop that writes
`defaults write <bundle> appearance.island.v8.theme <id>` gives the fixed **3 themes × 15 scenarios
= 45** matrix (including `subagentsExpanded`, excluding `closedAttention`) — **a pure shell change,
no Swift required.** Theme is a persisted `UserDefaults` choice, not an env var, so one run cannot
capture multiple themes.

**⚠️ P1.h — `overlay.ax.json` has NO per-element bounds.** `AccessibilityNode`
(`HarnessArtifactRecorder.swift:12-19`) carries `typeName/role/subrole/label/value/children` only.
`axFrame(for:)` exists but is used internally for window matching and never persisted per node. Only
the **window-level** frame is captured, in `report.json`. **Every acceptance criterion in this plan
must therefore be satisfiable from pixels, label text, or window-height deltas — not from element
geometry in the AX dump.**

**P1.i — bonus gap**: `AppearancePreviewFixtures.completedSuccess` has **no harness scenario at all**
— reachable only from the Settings preview. Relevant to F13's verification.

---

## 2a. The type-scale mechanism — two diseases, one cure

**Headline correction to the brief's framing: there are two distinct failure modes, needing
different fixes.**

| Theme | Roles enrolled | Enforcement | Raw `.system(size:` escapees | Non-icon est. |
|---|---|---|---|---|
| Flight Deck | **9** (`FlightDeckTheme.swift:78-90`, manual array, no enum) | floor + mono/sans family tests — **neither exhaustive**: a new size constant can exist without ever entering `roleFamilies` and no test fails | 71 | ~56 |
| Poured | **42** (`PouredTypography.swift:175-227`, `enum Role: CaseIterable`) | **compiler + test-enforced exhaustiveness** (`everyRoleHasExactlyOneTableEntry`), exact-mono-set test — strongest of the three | 44 | ~22 |
| Halo | **39** (`HaloTheme.swift:141-185`, manual array, no enum) — **corrects `ruler-halo.md` and `audit-type-scale.md`, which both say 35** | same shape as FD: name/family only, not exhaustiveness | 93 | ~69 |

- **FD's disease**: the vocabulary is incomplete — most call sites have no role to consume.
- **Poured's disease**: the vocabulary is complete and airtight — **and views bypass it anyway**.
- **Halo sits structurally with FD** (manual array, no compiler-enforced exhaustiveness) but
  currently behaves like Poured — it simply hasn't been around long enough to rot.

**Therefore Option A (extend enrollment) cannot be the mechanism.** Only a **call-site** check
catches Poured's failure mode. Recommend **Option C, sequenced**:

1. **Ship now — the lint in seed/allowlist mode.** It must be a **Swift Testing `@Test`**, not a
   shell script: `.github/` workflows are disabled, `.git/hooks/` has only `.sample` files, and the
   two existing grep lints (`scripts/lint-strings.sh`, `scripts/check-docs.sh`) are **wired into
   nothing** (grep-confirmed: zero references in `Tests/` or `.github/`). The repo's only real gate
   is `swift test`. Implementation: `#filePath` → repo root (a pattern `ThemeSnapshotting.swift`
   already uses) → scan `Sources/OpenIslandApp/Views/Island/*.swift` for `.system(size:`,
   `Font.system(size:` and the positional form `.system(<digit>` (this form exists, e.g.
   `PouredClosedPill:557`) → compare against a committed allowlist. **~40–60 lines, no new
   dependencies, green on day one, and every brand-new escapee fails the build from then on.**
2. **Same round**: fix the ~16–19 sites identified with certainty (F17 ×4, F18 ×1, F11 ×7,
   F11b ×2, F19 ×2), each removing its own allowlist entries.
3. **Follow-up per-theme chore tickets** to pay down the remaining ~130.

**Migration size, stated honestly**: 208 raw sites, ~147 non-icon. **Turning the lint on repo-wide
and blocking today is too big for this remediation** — the seed/allowlist form is the shippable win.

**False positives**: SF Symbol sizing (`Image(systemName:).font(.system(size:))`) is legitimate —
~61 of the 208. A regex cannot reliably tell `Text` from `Image` across multi-line HStacks.
Recommend the blunt approach: flag everything, classify **once** by hand during allowlist seeding.
The documented `+N` overflow exemptions get permanent allowlist entries.

**Correction to the brief**: `BRIEF.md` never states "10pt" or "floor" (grep → zero hits). The real
authority is `docs/design/overlay-redesign/README.md:62-64`, which frames it as a WCAG correction —
*"0.42 on black is 3.9:1 and fails the 4.5:1 body-text floor, and lifts every sub-10pt caps role to
a 10pt floor"* — then operationalised independently by each theme's `Typography.floor = 10`.

---

## 2b. SPEC ✅ marker audit — the markers never claimed what we assumed

**Mechanically verified**: in both `SPEC-flight-deck.md` and `SPEC-halo.md` the ✅/❌ column is
literally headed **"Floor"**. Every ✅ row's mockup value is ≥10pt and every ❌ row's is <10pt — a
1:1 correlation across all rows. **The marker's literal claim is "this target value clears the 10pt
readability floor". It is never a claim that shipped code matches the target.** No "shipped" column
exists in either table.

This is more structurally damning than "one stale checkmark": **the SPEC's entire typography-
conformance apparatus has never once compared against shipped code.**

| SPEC | Claim | Reality | Justified? |
|---|---|---|---|
| `SPEC-flight-deck.md:147-161` (15 rows) | ✅ = target clears floor | Floor claim **true on all 15**. But **3 of 15 contradicted** on the printed-yet-ungraded weight/tracking columns: MASTER placard (`:158` target 12/800/0.12em → ships 10.5/`.bold`/1.2pt, `FlightDeckSessionRow.swift:2626`), Button (`:160` target 11/600/0.04em → ships 11.5/`.semibold`/≈0.07em, `:3098-3099`), option label/desc (`:150-151` → shared view hardcodes 12.2/10.5) | Technically yes; **misleading in practice** |
| `SPEC-halo.md:237-271,274,280` (37 rows) | Same "Floor" pattern | Floor claim **true on all 37**. 2 known mono/sans deviations are **openly acknowledged in Swift doc comments**; **1 undocumented contradiction** — `nestHeader` (`:264` spec'd 700) ships `.bold` at one site, `.semibold` at another (F19) | Yes for the floor axis; 1/37 undocumented drift |
| `SPEC-poured-island.md:181-247` | **No ✅ markers at all** — uses "✓", only 2 in the typography table | Predates the Poured 2.0 migration; its "Shipped now" column holds **pre-migration** values annotated "change to X". A to-do list never revisited post-ship | **N/A** — the only SPEC making no post-hoc conformance claim. **This is the pattern to imitate**: add a real "shipped" column with measured values |

**Coverage, stated honestly**: 100% of typography-tagged markers audited — 15 (FD) + 37 (Halo) + 0
(Poured) = **52**, all true on the narrow floor basis, with confirmed drift on **4 of 52** against
independently-known shipped values. The other 48 were not re-derived line-by-line from scratch. For
non-typography markers, **2 spot-checks** out of an **uncounted** population across ~1,929 SPEC
lines — no defensible sample rate can be stated, so none is claimed.

**Phase 8 action**: rather than re-ticking markers, **add a "shipped" column** to the FD and Halo
typography tables, populated with measured values — the Poured pattern.

---

## 2c. Regression & snapshot map (empirical)

### ⚠️ Operational landmark — the cloned `.build` breaks the first build
`scripts/agent-worktree.sh`'s APFS clone bakes the **Clang module-cache path** into the copied
artefacts. The first build in a fresh worktree fails with:

> `error: precompiled file '…/ModuleCache/…/_Builtin_stdbool-*.pcm' was compiled with module cache
> path '…/open-vibe-island/.build/…', but the path is currently '…/worktrees/…/.build/…'`

**This is not a code bug. Fix**: `rm -rf .build/arm64-apple-macosx/{debug,release}/ModuleCache` and
rebuild — cheap, not a cold dependency build. **Every phase agent must be told this** or it will
chase a phantom.

### Baseline test state — measured, not assumed
Command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (full, unfiltered).

**967 tests total · 6 failures across 5 distinct tests · 1 skipped.**
Swift Testing: 909 tests / 72 suites, 4 issues (all `AppModelSessionListTests`).
XCTest: 58 tests / 7 classes, 2 failures (both `ThemeSnapshotHarnessTests`), 1 unrelated skip.

| Known-red test | Failed in baseline? |
|---|---|
| `islandSessionSectionsGroupStaleCompletedIntoIdle` | **yes** (2 issues) |
| `islandSessionSectionsKeepCompletedInDoneWhenStaleThresholdIsNever` | **yes** |
| `islandSessionListCanSortByLastUpdate` | **yes** |
| `cellStateReflectsSessionPhase` | **no — passed** (genuinely intermittent) |
| `bulkFirstObservationOrdersByHistoricalFirstSeenAt` | **no — passed** (genuinely intermittent) |
| `testPouredSessionListBaselineNotch` / `TopBar` | **yes** — "Snapshot does not match reference" |

**Any phase whose full-suite run shows more than these must stop and investigate.**

**The 3 `AppModelSessionListTests` failures have a diagnosed, non-mysterious root cause.**
`islandSessionGroup`/`islandSessionSort`/`completedStaleThreshold` (`AppModel.swift:521-534`)
get/set through `appearancePreferences(for: activeAppearanceProfile)`, and `activeAppearanceProfile`
(`:497-498`) resolves to `.notch` only if `overlayPlacementDiagnostics?.mode == .notch`, **defaulting
to `.topBar`**. The tests write the preference once with no both-buckets pin, so a placement arriving
mid-test flips the profile and the getter falls back to the other bucket's default. Mechanically
confirmed by the failure output: `islandSessionSections.map(\.id)` → `["all"]`, exactly
`IslandSessionSectioning`'s `.none`-group fallback. **`AgentsGridRightSlotTests.swift:184-193`
already documents and fixes this same race (AB-322) via a `pinAgentsGridPreference(on:)` helper that
writes both buckets** — it was simply never back-ported. Out of scope, but see §5.

### Snapshot harness — mechanism confirmed
- Harness: `Tests/OpenIslandAppTests/Support/ThemeSnapshotting.swift`. Goldens:
  `Tests/OpenIslandAppTests/__Snapshots__/<TestClass>/<method>.<name>.png`. **57 project-owned
  goldens** (the 400+ PNGs under `.build/…/swift-markdown-ui` are a vendored dependency's fixtures).
- **`OPEN_ISLAND_RECORD_SNAPSHOTS=1` is correctly scoped** — `record:` is a **per-call default
  parameter** on `assertSnapshot`, so only tests that actually execute re-record. `--filter`ing to
  one suite genuinely leaves the others untouched. **The playbook's "never blanket re-record" rule
  is mechanically sound.** Recording also rewrites `environment-fingerprint.txt`.
- **Snapshots are @2x unconditionally** — `rasterize(_:width:)` hardcodes `let scale: CGFloat = 2`
  (`:252`), independent of host backing scale. Confirms the SCALE RULE.
- **Environment gate**: each golden dir carries `environment-fingerprint.txt` (currently
  `macos=Version 27.0 (Build 26A5388g) arch=arm64 scale=2x`). On a mismatch the compare is
  **`XCTSkip`ped, not failed** — the image still renders first, so a crash or build break fails
  everywhere.

### The two drifting goldens — named, root-caused, and FIXABLE
`testPouredSessionListBaselineNotch` / `TopBar` → `poured-session-list-baseline-{notch,topbar}.png`
(`ThemeSnapshotHarnessTests.swift:31-48`).

**Precise cause**: `AppearancePreviewFixtures.sessions(now:lang:)` (`:53-166`) sets four rows'
`updatedAt` within 15–30s of a 60-second age-badge rounding boundary — `preview-approval` −90s,
`preview-answer` −150s, `preview-running` −30s, and `preview-done` **−45s, only 15s of margin**
before `spotlightAgeBadge(at:)`'s `age < 60 → "<1m"` bucketing (`AgentSession+Presentation.swift:322-338`)
flips the string. The badge reads a **fresh `Date()` at draw time** — `ThemeSnapshotting.swift:25-32`
documents that it cannot inject that clock — so any rendering latency past the margin flips the label.
The harness's own later rule (`ThemeSnapshotHarnessTests.swift:87-88`) says *"never within ~30s of a
60s boundary"*; these four offsets predate it (AB-305) and violate it.

**→ Phase 1 should re-centre these offsets mid-bucket, retiring two of the five known-red tests.**

**⚠️ Unflagged risk**: `.meters` (`testUsageMeters` in both Poured and Halo conformance suites)
reuses the **identical** `sessions(now:lang:)` fixture. **Flight Deck explicitly declined to pin
`.meters`** citing this exact drift class (`ThemeSnapshotHarnessTests.swift:175-183`). So
`poured-I-usage-meters-*` and `halo-I-usage-meters-*` are equally susceptible despite not being on
the playbook's known-drift list. They passed in the baseline run, but one green run doesn't prove
non-intermittency. **Fixing the fixture offsets fixes these too.**

### Coverage gaps that change how phases must be verified

| Gap | Consequence |
|---|---|
| **No button-order test exists for any theme.** `FlightDeckSessionRowTests` asserts only shortcut glyph strings; `HaloPermissionHeroTests` only glyphs + layout enum; Halo's row body has **no dedicated test file at all** | F5 is caught **only** by pixel-diff. Phase 3 must add the order test it proposes. |
| **FD hero fill is not a literal** — it is the computed `alarm.opacity(0.08)` where `alarm = statusWaitingForApproval` (`FlightDeckSessionRow.swift:2760,2933`) | Phase 4's `#682E27 → #231718` is an **opacity/compositing change, not a hex swap**. No unit test asserts it. |
| **`showsDetail` is defined TWICE, identically** — `PouredSessionRow.swift:116` **and** `IslandPanelView.swift:1158` (the shared row every other theme uses). Zero tests reference it by name | Phase 5 must explicitly decide whether both copies change, or Poured silently diverges from every other theme. |
| **`UnifiedBars.Mode` is not `CaseIterable`**, but all **7** consumers switch exhaustively with no `default:` (`UnifiedBars.swift:21,252,272,291`, `AppearanceSettingsPane.swift:764`, `PouredPillAmbientState.swift:49`, `HaloClosedPill.swift:353`) | Adding a case is a **compile error at all 7**, caught by `swift build` — stronger than any test. Confirms F3's high blast-radius estimate. |
| **No `.waiting`-mode closed-pill golden exists** in either conformance suite (only A1 `.idle` / A2 `.running`) | F3's attention-state fix has no snapshot net. |
| **Flight Deck has no golden for `permissionDiff`, `codexApproval`, or `completedVariants`**; FD pins notch-only for several scenarios and has **no topBar golden** for the permission/question heroes | Phases 4 and 7 have **no snapshot safety net on FD**; a topBar-only regression is invisible. Eye-check against the mockup is mandatory there. |
| Weight changes are invisible to **every** unit test in all three themes (only Poured pins weight, and only for 10 named roles) | Phase 6's real backstop is the snapshot diff, not the theme tests. |

### Per-phase test filters

| Phase | `swift test --filter` | Goldens expected to move |
|---|---|---|
| P1 | `'AppearancePreviewFixturesTests\|IslandDebugScenarioTests\|HaloConformanceSnapshotTests\|PouredConformanceSnapshotTests\|ThemeSnapshotHarnessTests'` | Only the changed scenario's goldens — **or all 57** if a shared helper (`sessions`, `stableID`) changes. Diff before assuming correct. |
| P2 | `'QuestionPromptFormatTests\|HaloConformanceSnapshotTests\|PouredConformanceSnapshotTests\|ThemeSnapshotHarnessTests'` | `{halo,poured}-F-question-*`, `flightdeck-question-master-caution-notch` |
| P3 | `'PermissionDiffTests\|FlightDeckSessionRowTests\|HaloConformanceSnapshotTests\|ThemeSnapshotHarnessTests'` | `halo-E2-permission-diff-*`, `flightdeck-permission-master-warning-notch` |
| P4 | `'FlightDeckThemeTests\|FlightDeckSessionRowTests\|FlightDeckMotionTests\|ThemeSnapshotHarnessTests'` | `flightdeck-permission-master-warning-notch`, `flightdeck-question-master-caution-notch` |
| P5 | `'PouredThemeTests\|PouredRowMotionTests\|FlightDeckThemeTests\|FlightDeckSessionRowTests\|HaloUsageTests\|IslandChromeLayoutTests\|HaloConformanceSnapshotTests\|PouredConformanceSnapshotTests\|ThemeSnapshotHarnessTests'` | `poured-D-G-subagents-*`, `poured-A6-completed-variants-*`, FD row goldens, `{halo,poured}-I-usage-meters-*` |
| P6 | `'ThemeTests\|ConformanceSnapshotTests\|ThemeSnapshotHarnessTests'` | Potentially **all 57** — type scale touches roles rendered in every scenario |
| P7 | `'PermissionDiffTests\|FlightDeckSessionRowTests\|PouredRowMotionTests\|HaloPermissionHeroTests\|HaloConformanceSnapshotTests\|PouredConformanceSnapshotTests\|ThemeSnapshotHarnessTests'` | `{halo,poured}-E1/E2-*`, `flightdeck-permission-master-warning-notch` |

Run the **full** suite once per phase before its commit, per the standing protocol.

---

## 3. Shared root causes

> Consolidation pass — findings that collapse into one fix.

- **F12 + F14 collapse into one fix surface**: the missing shape/corner parameter on a unified diff
  renderer. `FlightDeckChamferedRectangle` already conforms to `InsettableShape` exactly like
  `RoundedRectangle` (`FlightDeckSessionRow.swift:2016-2039`), so a
  `ContainerShape { rounded(CGFloat) | chamfered(CGFloat) }` resolved to `some InsettableShape` is a
  mechanical, low-risk parameter — **not** a redesign of FD's hero chrome.
- **F4 + F12 share one function** (`HaloHeroDiff.diffRow`) but at different scope. **Decision: ship
  F4 standalone FIRST (Phase 3), unification second (Phase 7).** F4 is a hard BRIEF §5 violation on
  red/green content — the worst pair for colour-vision deficiency — and its fix is a 1-file, 1-caller,
  ~2–5 line addition. Gating an accessibility bug behind a multi-file, test-free architecture refactor
  is the wrong risk trade. Nothing is wasted: Phase 7 step 3 carries the already-correct marker logic
  into the shared component instead of inventing it there.
- **F8 / F15 / F18** all edit `FlightDeckUsageSummary.swift` but are **three independent defects**
  (container axis `:61-65` · colour function `:193-202` · inline literal `:161`). No shared code —
  but package as **one ticket** to avoid triple-touching the same small file and triple-running its
  test/snapshot blast radius.
- **F7** is its own consolidation: one logic bug duplicated across six files.
- **F9 + F8** both grow the top-of-panel region (different files, no shared constant). No hard
  dependency, but land them in the same pass — two independent height-increasing changes compound
  visually even when they don't break each other structurally.

---

## 3a. ⚠️ The diff fixture blocks its own acceptance criteria — Phase 1 must fix it

`AppearancePreviewFixtures.permissionDiff` (`AppearancePreviewFixtures.swift:433-448`): **every line
of both `oldText` and `newText` is a markdown bullet literally starting with `"- "`** (e.g.
`"- Run swift build after each change."`).

Consequence: Poured's concatenated marker for a removed line renders `"− "` (U+2212) plus the
content's own literal `"-"` — the "double dash" the review spotted is coincidence, not design. **Any
acceptance criterion that regexes for a leading `-`/`+` glyph in a rendered row is unfalsifiable
against this fixture**, which is exactly how F4 nearly escaped detection.

Fix in Phase 1: edit the fixture so no line starts with `-` or `+` (prose instead of bullets).
Verified safe against the one existing test —
`AppearancePreviewFixturesTests.permissionDiffProducesARealMultiLineDiff`
(`Tests/OpenIslandAppTests/AppearancePreviewFixturesTests.swift:131-141`) asserts only
`affectedPath == "AGENTS.md"` and `addedCount + removedCount >= 3`, with no literal-content pin.

---

## 4. Phases

> Ordered by dependency, not severity. One commit per phase. Every phase ends with its verification
> loop green before the next begins.

### Phase 1 — Verification infrastructure ⟵ must be first
Without it, later phases cannot be verified at all, and three acceptance criteria in this plan are
literally unfalsifiable.

| # | Item | Why first |
|---|---|---|
| 1.1 | **Install-hint suppression** (P1.f) | Cheapest, zero risk, unblocks clean `emptyState`/`completedFailed` captures needed to verify 1.3 |
| 1.2 | **Diff fixture: remove leading-dash bullets** (§3a) | **F4 and F12's marker criteria are unfalsifiable until this lands** |
| 1.3 | **`completedFailed.updatedAt` −9min → −3m30s** (P1.c) | Unmasks the failed-outcome template |
| 1.4 | **`stableID` hashing** (P1.d) | Every multi-question option currently renders as option[0] |
| 1.5 | **`transcriptPath` on `completedInterrupted`** (+ `.completedSuccess` for F13) (P1.e) | Makes the Transcript affordance testable |
| 1.6 | **Re-centre the four `sessions()` age offsets mid-bucket** | **Retires 2 of the 5 known-red tests** and de-risks the 4 `.meters` goldens carrying the same latent flaw |
| 1.7 | **New `subagentsExpanded` scenario** (P1.a) | The only way §D/§G becomes regression-testable for FD and Halo |
| 1.8 | **Theme axis on `smoke-all-scenarios.sh`** (P1.g) | Turns the fixed 15-scenario loop (`subagentsExpanded`, not `closedAttention`) into the 3×15=45 matrix; pure shell |

**Cancelled**: §I usage-meter card (P1.b) — per D4, §I is a Settings surface.
**Filter**: `'AppearancePreviewFixturesTests|IslandDebugScenarioTests|HaloConformanceSnapshotTests|PouredConformanceSnapshotTests|ThemeSnapshotHarnessTests'`

**Goldens — predicted 15, actual 19.** The prediction undercounted; both extra pairs were investigated
before recording and are correct consequences of mandatory items:

| Golden | Cause | Predicted? |
|---|---|---|
| `{poured,halo}-A6-completed-variants-{notch,topbar}` (4) | 1.3 + 1.5 | ✅ |
| `{poured,halo}-F-question-{notch,topbar}` + `flightdeck-question-master-caution-notch` (5) | 1.4 | ✅ |
| `poured-session-list-baseline-{notch,topbar}` (2) | 1.6 | ✅ |
| `{poured,halo}-H-completed-success-{notch,topbar}` (4) | **1.5** — `completedSuccess.transcriptPath` opens the `TranscriptAffordance` gate in both `completionActionRail`s (`PouredSessionRow.swift:1031-1037`, `HaloSessionRow.swift:962-968`). Previously always nil, so this exercises code that was untestable | ❌ **1.5's blast radius was credited only against A6** |
| `{poured,halo}-E2-permission-diff-{notch,topbar}` (4) | **1.2** — `testPermissionDiffHero` renders the very fixture that was rewritten | ❌ **1.2's blast radius was recorded as zero — an error in this plan** |
| `{poured,halo}-I-usage-meters-{notch,topbar}` | predicted to move, **did not** — only `preview-done` needed re-centring; the other three offsets were already at bucket midpoints | over-predicted |

**Lesson carried into later phases**: predict goldens from the *fixture→scenario→golden* chain, not
from the finding that motivated the change. Any fixture edit moves **every** golden rendering that
fixture.

**Retired from known-red**: `testPouredSessionListBaselineNotch` / `TopBar` now **pass**. The baseline
is now **4 failures across 3 tests** (all `AppModelSessionListTests`). Later phases must compare
against that, not the original 6/5.

**Corrections found during implementation**:
- The transcript-path gate is `Sources/OpenIsland**Core**/AgentSession.swift:629-631`, not
  `Sources/OpenIslandApp/`. Watch for other App-vs-Core slips in this plan's citations.
- `stableID` uses an inline FNV-1a 128-bit digest — no `Crypto`/`CryptoKit` dependency was added.
- Only `preview-done` (−45s → −32s) was genuinely inside the 60s-boundary margin; the other three
  offsets were already mid-bucket and were left alone, with the invariant now documented on all four.

### Phase 1 — OUTCOME (verified 2026-07-27)

**All six acceptance criteria PASS.** 24 live captures in `shots/after/` (72 artifacts). Full suite
**912 tests / 4 issues, all `AppModelSessionListTests`**; snapshot suites **34/34**. Theme restored to
`halo`; `shots/app/` and `shots/notch/` untouched.

Evidence the fixes are real, not just green — the verifier captured the **pre-fix** state too:
- **AC4**: baseline ax.json showed `'1, OAuth 2.0…'` **repeated 3×** and `'1, Local socket'`
  **repeated 4×** — every option collapsed to option[0]. Now distinct.
- **AC6**: baseline rendered `'− - Run swift build after each change.'` (UI marker **plus** the
  fixture's own authored `"- "`), and an unchanged context line read literally
  `'- Commit on the feature branch.'`. Now clean prose.
- **AC3**: baseline `completedFailed` showed only `'…failed, 9 minutes ago'` with no badge and no
  message — the idle template, confirmed. Now shows `'Failed'`, `'finished 3m ago'`, the failure
  message and Jump.

#### ⚠️ NEW — Halo's AX tree is structurally blind to row detail
`HaloSessionRow` applies `.accessibilityElement(children: .ignore)`
(`Sources/OpenIslandApp/Views/Island/HaloSessionRow.swift:206-208`), collapsing every row's children
into one combined VoiceOver label **regardless of expansion state**. `overlay.ax.json` therefore
**cannot see Halo's expanded/hero content at all** — AC2, AC4, AC5 and AC6 all had to be settled by
pixel inspection for Halo.

**This changes the verification protocol for every remaining phase**: any Halo criterion phrased
against `overlay.ax.json` is unfalsifiable and will silently pass. **Halo must be verified from
pixels.** It is also a genuine accessibility question in its own right — a VoiceOver user gets one
flat label where Poured and Flight Deck expose structure — worth a follow-up ticket, out of scope here.

#### ⚠️ NEW finding — `emptyState` still clips on Flight Deck and Halo
Suppressing the install hint **does not resize the panel** (height identical in both states, all
themes). It un-clips content at the *same* window height. Poured is fully fixed — its
`"No open terminal sessions"` text becomes visible. But **Flight Deck and Halo still cut off
secondary body copy at the bottom edge even with the hint suppressed** (FD's "…watching the bridge…"
tail, Halo's "Monitoring" footer). This is a **real panel-height defect, not a harness artifact**, and
Phase 1 is only a partial mitigation. → **Added to Phase 5 (Layout).**

#### Landmarks for later phases
- **Phase 2 (D1)**: question digits currently **reset per question** — measured `1,2,3` then
  `1,2,3,4` on all three themes. D1 requires **Flight Deck to run continuously 1–7** across its
  stacked page. That is a behaviour change, not just a layout one.
- **Phase 5**: Flight Deck's expanded row grows the panel (**693 → 787pt, +94**) but **Halo's does
  not (789 → 789)** despite rendering far more content — Halo appears to have an internally-scrolled
  region under a capped outer height. Confirm this is intended before measuring Halo row pitch.
- **Phase 7**: Poured's diff markers are **charset-inconsistent** — the minus is U+2212 MINUS SIGN
  but the plus is ASCII U+002B. The unified renderer should pin both deliberately.
- **Not verified anywhere yet**: scroll reachability of rows 3–9 once a row is expanded,
  click-to-toggle, and keyboard digit selection. All need computer-use, not stills.

### Phase 2 — Shared question view (closes F1 across all three themes)
Sub-staged by risk, because the typography half needs no protocol change:
- **2.1 Typography consumption** — wire the dormant `questionText`/`optionLabel`/`optionDesc`/
  `optionNumber` roles. Zero protocol change, lowest risk. **FD has none of these roles — they must
  be authored, not merely wired.** Halo's table cannot express weight; extend the tuple or pick
  weights at the call site (see §5 note).
- **2.2 The theme seam** — narrow optional protocol members with Classic-preserving defaults,
  mirroring `closedGlyphTint`. **Zero call-site changes.** Then expose each theme's *existing*
  button component (`PouredJumpButtonStyle`, `FlightDeckApprovalButton`, `HaloHeroButton`) through it.
- **2.3 Selection marker** — hide when unselected for **Poured/Halo only**; for **Flight Deck, swap
  `Circle()` for its chamfered octagon and keep it always-visible** (its board is explicit).
- **2.4 Pagination** — resolved by §5 D1.
- **⚠️ Verification note**: `canSubmit` is always false at capture time, so the enabled CTA is
  **not reachable from a still**. Verify it by driving a selection via computer-use.

### Phase 2 — OUTCOME (verified 2026-07-27)

Closes finding **F1** (+F1a, F1b) across all three themes from **one** fix surface. Full suite
**921 tests / 4 issues, all `AppModelSessionListTests`**; snapshot suites 37/37; 16 goldens
(11 re-recorded, 5 new enabled-Submit).

| Criterion | Result |
|---|---|
| S1 question/option type hierarchy | **PASS** — Poured 10.5 vs 9.5pt cap-height, Halo 11 vs 9.5–10pt (was 0pt gap) |
| S2 marker asymmetry | **PASS** — no marker on unselected rows (Poured/Halo); FD an 8-sided octagon on every row, verified at 6× zoom |
| S3 Halo has no card fill | **PASS** — sampled RGB **(0,0,0)–(7,7,7)**. FD opaque **(17,21,25)** vs `#101519` expected, chamfered corner confirmed |
| S4 digit sequences | **PASS** — Poured/Halo `1,2,3`; **FD `1,2,3,4,5,6,7` continuous**, one shared submit |
| S5 enabled Submit fill | **PASS** Poured `#FAE0AD→#F8D897`, width **26.4%** of card · **PASS** FD `(46,42,33)` ≈ the 14%-blend of `#E6AA42`, width 27.4%, chamfered · **Halo not verified** (tooling) |
| S6 pagination advance | **PASS** Poured — "Question 2 of 2", digits restart `1,2,3,4`, hint "1–4 select…", label → "Submit Answers" · **Halo not verified** · FD N/A |
| S7 keyboard digit + Enter | **NOT VERIFIED — architecturally blocked**, see below |
| S8 keyboard hint caption | **PASS** all three — Poured/Halo `"1–3 select · Enter submits · Esc closes"`, **FD `"1–7 …"`** (was `nil`) |
| S9 regressions | **PASS** — none; Classic spot-checked unaffected |

**Baseline captures independently confirm two Phase 1 fixes were real**: all three
`shots/app/*-multiQuestionCard.png` baselines show every option row duplicating the *first* option's
label and digit "1" — the `stableID` collision, visible. And Halo's baseline shows a nested lighter
secondary box (double chrome) that is **gone** in the fresh capture, directly confirming S3.

#### ⚠️ NEW blocker — the harness can never exercise real keyboard input
`OverlayPanelController.startEventMonitoring()` (`:219-229`) **never installs `keyCommandMonitor`**
when `model.disablesOverlayEventMonitoringDuringHarness == true`, and `OpenIslandApp.swift:24-25`
sets that flag `true` for **any** harness scenario launch, unconditionally — independent of
`AUTO_EXIT_SECONDS`. So the interactive launch mode the verification protocol prescribes **cannot
test keyboard handling at all**, for any theme or phase. Pressing `1`/Enter had zero effect;
confirmed by source read, not inferred from the failure.
**This blocks Phase 3's ⌘Y/⌘N ordering work and Phase 8's motion/focus pass. → Fix before Phase 3.**

#### ⚠️ Halo is hard to drive interactively
Halo's AX tree exposes the entire question hero as **one opaque element** (the
`.accessibilityElement(children:.ignore)` consequence from Phase 1) — clicking it *collapses* the
row rather than selecting an option. Coordinate-clicks also fail: `orca computer capabilities`
reports `"windows":{"focus":false}` for this provider, and the overlay is a non-activating panel, so
synthetic clicks don't register without key-window status. Poured and Flight Deck, with richer AX
trees, responded instantly.
**Halo's S5/S6 rest on shared-code inference**: the Submit seam and pagination are the same code
Poured exercises live, and Halo's `questionPageSize` is `1` exactly as Poured's. Recorded as
inference, **not** claimed as measured.

#### ⚠️ Do not route synthetic bridge events during verification
A live production `/Applications/Open Island.app` is bound to the single bridge socket
(`~/Library/Application Support/OpenIsland/bridge.sock`), and **the app does not honour
`OPEN_ISLAND_SOCKET_PATH`** — only the hooks CLI does (`BridgeTransport.swift:15-33`,
`AppModel.swift:685`). `scripts/replay-bridge-scenarios.py` would therefore drive **the user's real
app**, not the worktree build. The verifier correctly declined.

#### Known deliberate deviations from the boards (documented in source, not defects)
The "AUTH"/"SCOPE" question header stays plain text rather than the mockup's pill badge
(`IslandPanelView.swift:2514-2525` scopes that fix to colour only), and FD's progress line omits the
mockup's "SINGLE/MULTI" suffix. Candidates for a later polish pass.

### Phase 3 — Safety and semantics (small, high-value, low-risk)
- **F5** Allow-before-Deny + extract the order into pure logic + **add an order-pinning test for all
  three themes** (none exists today; the golden is currently the only gate).
- **F4** Halo diff `+`/`−` markers — standalone, ahead of F12, because it is a live accessibility
  violation with a 2–4 line, zero-blast-radius fix.
- **F3 tint** — `HaloTheme.closedGlyphTint` override, sharing (not duplicating) the existing
  `HaloClosedPill` colour mapping.
- **F3 shape** — resolved by §5 D3.
- **F19** `nestHeader` `.semibold` → `.bold` at `HaloSessionRow.swift:1102`.
- **F20** Codex model plumbing — thread `CodexHookPayload.model` through to `displayModelName`.

### Phase 3A — OUTCOME (2026-07-27)

- **Harness keyboard blocker resolved.** `OPEN_ISLAND_HARNESS_ENABLE_KEY_MONITOR` (default off) lets
  `keyCommandMonitor` install under a harness launch. Scoped to the **key monitor only** — the mouse
  monitors stay disabled under any harness scenario, unchanged. Provably inert outside a harness run:
  a normal launch has `scenario == nil` → `disablesForHarness == false` → the new flag is
  short-circuited and never consulted. **Phase 8 can now verify keyboard behaviour.**
- **F5 fixed and pinned.** Flight Deck now renders `ALLOW ⌘Y` left / `DENY ⌘N` right, matching both
  siblings and its own board. The agent went further than the plan asked: rather than swapping two
  literals and adding a parallel array, it made the view **render from** the array
  (`FlightDeckApprovalFormat.primaryDecisionOrder`) via the `ForEach(Array(...enumerated()))` idiom
  already used at `alwaysAllowOptions`. A pure array the view doesn't consume can't stop a future
  edit from silently re-reversing the buttons — which is the entire point of pinning it.
- **F20 plumbed.** `CodexHookPayload.model` → `defaultCodexMetadata` → `mergedCodexMetadata` →
  `displayModelName` → every theme's model cell. Backward compatibility proven **empirically**, not
  just by source read: a hand-written pre-F20 JSON blob with no `"model"` key decodes with
  `model == nil`.

#### ⚠️ NEW production bug — F20's fix is clobbered every 3 seconds by a second metadata source
`CodexRolloutWatcher`/`CodexRolloutReducer` (`CodexSessionTracking.swift:595-739,1425+`) is an
**independent** metadata path: it polls a session's rollout JSONL every ~3s (via
`SessionDiscoveryCoordinator.refreshCodexRolloutTracking()`, called on every applied event —
`AppModel.swift:1935`) for essentially every hook-driven Codex session. `CodexRolloutSnapshot` has
**no `model` field**, and its `.sessionMetadataUpdated` is applied by **blind overwrite** at
`SessionState.swift:173` — *not* merged the way `BridgeServer.mergedCodexMetadata` merges hook
updates.

**So a live Codex CLI session's hook-reported model is set, then reset to `nil` on the next poll
tick.** F20 works in fixtures and snapshots (demo sessions never enter this pipeline) and **does not
work in production**. Pinned with a test rather than left as prose.

**Fix direction (Phase 3C)**: make the rollout emission **merge against existing metadata before
emitting**, mirroring the convention `BridgeServer.mergedCodexMetadata` / `mergedOpenCodeMetadata`
already follow. Prefer that over changing `SessionState.apply(_:)`'s overwrite semantics —
CLAUDE.md names that reducer the single source of truth for session mutations, and broadening it to
merge would change behaviour for every agent, not just Codex.

#### Landmarks
- The Allow-before-Deny order test exists **only for Flight Deck**. Poured and Halo are already
  correct but unpinned; extending the same shape to `PouredApprovalShortcut` and `HaloSessionRowFormat`
  is a natural follow-up.
- `longCompletionSession`'s new `model: "gpt-5-codex"` has **no** golden consumer — §H's
  golden-backed fixture (`AppearancePreviewFixtures.completedSuccess`) is a **Claude** session.
  Phase 8's full-matrix recapture is the first point anyone sees that Model cell render.
- `OverlayPanelController.startEventMonitoring()`'s new branch has no direct unit test (private,
  `NSEvent`-coupled); verified structurally plus by all 12 `ThemeSnapshotHarnessTests` staying green.

### Phase 3 — OUTCOME (verified 2026-07-27) — 13/13 criteria PASS

Full suite **929 tests / 4 issues, all `AppModelSessionListTests`**.

| Criterion | Result |
|---|---|
| T1 Allow-before-Deny (FD) | **PASS** — `Allow` x=124–568, `Deny` x=584–1027 @2x. Poured and Halo confirmed still Allow-first |
| T2 Halo diff markers | **PASS** — marker column x≈345–360, distinct from gutter (≈300–320) and text (≥375); **survives greyscale via glyph shape**, not colour |
| T3a Halo pill non-achromatic | **PASS** — sampled (244,180,96) raw Display-P3 → **exactly (255,177,77) sRGB** after ICC conversion = `0xFFB14D` `haloAmber`. Baseline was **(143,141,141)**, fully achromatic |
| T3b Halo pill is a ringed dot | **PASS** — glyph bbox **15×15px (1:1)**, zoomed crop shows filled dot + ring. Baseline crop shows **two grey bars** |
| T3 Poured pill unchanged | **PASS** — glyph colours within 3–4/255 of baseline (noise) |
| T4 nestHeader weight | **PASS** — "RESULT" glyph fill-ratio **0.514 → 0.556 (+8.3%)**, now matching "SUBAGENTS" at 0.596 |
| T5 Codex Model cell | **PASS** — renders **"GPT-5"** as a **new 4th grid cell**; baseline had only 3 and no Model at all |
| T6a–b keyboard (Poured) | **PASS** — `1` selects (Submit's `(disabled)` clears), Enter advances "Question 1 of 2" → "2 of 2" |
| T6c ⌘Y fires Allow (FD) | **PASS** — approval card collapses to the running pill |
| T6d opt-in control | **PASS** — same keys **delivered successfully** without the env var, **zero app-side effect** |

**T3a's measurement is the model to follow**: the raw sample (244,180,96) looks wrong against the
expected (255,177,77) until you account for **Display-P3 → sRGB** conversion. A less careful check
would have reported a false FAIL. Colour criteria in later phases must state their colour space.

#### ⚠️ Resolved: why Halo resisted synthetic clicks in Phase 2
Not an `orca` limitation. The overlay is a **`.nonactivatingPanel`** (`OverlayPanelController.swift:108`)
that calls `makeKeyAndOrderFront` **only when `notchOpenReason == .click`** — a `.notification`-opened
card deliberately does not steal key-window status. **Fix for future verification**: send one
synthetic click on a neutral non-interactive element first (exactly what a real user's first click
does), then keys land reliably. This is product behaviour, not a defect — and it made T6d's negative
control clean, since delivery succeeded in both runs and only the app-side gating differed.

#### Known measurement limit
Poured's pill baseline could not be byte-diffed: baseline and fresh captures differ in overlay pixel
size (1200×380 vs 1240×368) — pre-existing environmental drift, not introduced here. Substituted
direct glyph-pixel colour sampling.

### Phase 4 — Flight Deck hero frame (BRIEF §7's top-priority bar)
Strict internal order, because two of these are the same bug:
1. **F2.3 placard** (isolated, zero dependency — safe to land first; fixes MASTER WARNING **and**
   MASTER CAUTION in one edit).
2. **F2.4 Model + Branch** (same component as F2.3 — combine to avoid re-measuring the header twice).
3. **F2.1 glow hoist** — the clip fix.
4. **F2.2 card fill re-tune** — **only after 2.1**; tuning against today's glow-bleed-through
   baseline guarantees a second retune.
5. **F13 Transcript** (needs Phase 1's `.completedSuccess` fixture to be observable).
6. **F10 E3 CTA** — extract into an advisory-blue sub-panel at the **call site**, never by restyling
   `.ghost` globally.

⚠️ FD has **no golden** for `permissionDiff`, `codexApproval`, or `completedVariants`, and **no
topBar golden** for the permission/question heroes. Phase 4 and Phase 7 rely on eye-check against
the mockup for those.

### Phase 5 — Layout
- **F6** Poured `showsDetail` — change the `else` branch, add the testability seam, and **sequence
  with P1.a** (fixing F6 collapses Poured's currently-working §D capture).
- **F9** FD annunciator strip — requires restructuring `sessionPanelHeader` into a full-width band,
  not just resizing the leaf. Panel height is dynamic, so growth is safe.
- **F18 → F8** FD gauge unit size, then the `VStack`→`HStack` axis fix (in that order).
- **F15** FD usage colours — **atomic with its test update**, which currently pins the wrong values.
- **F7** notch usage lanes — per-window split + reflow-instead-of-drop, across all six themes (D2).
- **NEW — `emptyState` clipping on Flight Deck and Halo.** Found during Phase 1 verification: even
  with the install hint suppressed, both themes cut off secondary body copy at the panel's bottom
  edge (FD's "…watching the bridge…" tail, Halo's "Monitoring" footer). Poured is fixed. The panel
  does not resize when the hint is suppressed, so this is an independent height/layout defect.
  Acceptance criterion: every text run present in the AX tree for `emptyState` is fully within the
  captured frame, all three themes.

#### Phase 5 — OUTCOME (2026-07-27). Corrections recorded so later phases don't repeat them.

**Corrections to statements made above:**
1. **P1.a was already done** — wired in `b5afaac` (`IslandDebugSnapshot.forcesRowExpansion`, the
   `.subagentsExpanded` scenario, `IslandDebugScenarioTests.swift:18-40`). No work was needed.
2. **The expansion seam's wiring is at `IslandPanelView.swift:342`**, not `OverlayPanelController.swift:134`
   as §P1.a speculated.
3. **F6's golden blast radius includes `poured-A6-completed-variants`** (its `completedFailed` row is
   non-actionable *and* non-stale), which §F6 does not name. 17 goldens moved in total: 9 from F9,
   8 from F6 — both predicted exactly, zero strays.

**F7/F8 — the real root cause, which neither REPORT nor this plan had:**
The mockup panels are **520px — NARROWER than the real 540pt panel.** Panel width was never the problem.
The boards disagree with each other about lane arrangement, and the app implemented the wrong one:
- `02-flight-deck.html:282` **column-stacks** the lane (controls above gauge) → needs `max(82, gauge)`.
- `06-halo.html` **row-packs** it (controls beside gauge) → needs ~186-196px, and it under-models its
  own notch (draws 172px, reserves 96px).
- `IslandUsageSummary.swift:277-283` implemented **Halo's row-pack for all six themes**, subtracting
  `openedHeaderButtonsWidth`. On real notch hardware: `130 − 12 − 82 − 8 = 28pt < 58pt floor → right
  lane 0pt`, deleting the lane. Flight Deck never had this collision in its own design.

**F8 was never actually fixed by the `VStack`→`HStack` change.** It improved the chip from ~75-83pt to
~40-57pt against a **24pt top-bar / 34-38pt notch** band — still overflowing, unclipped. Resolved this
phase via a per-theme `openedHeaderHeight` (`IslandTheme.swift`, `nil` default; FD returns 96pt).
⚠️ `closedNotchHeight` is the **closed pill** geometry for all six themes and must never be grown for this.
**Verified in pixels: chip 57pt, band 96pt, ~9pt slack** — the assumed SF line heights were correct.

**Still open (deliberately not fixed this round):**
- **Halo's row-packed arrangement is unreachable at 540pt** — needs ~600pt for a bare 58pt sliver,
  ~676pt for a 96pt gauge. Panel growth is symmetric about the notch, so 1pt of lane costs 2pt of width.
- **At 3+ usage windows a window is necessarily hidden.** Capacity is ~1 gauge per lane; fitting two
  needs `g ≤ 46.25pt`, below legibility. Mitigated by the corner `+N` overlay (costs zero lane width
  because overlays don't participate in `HStack` layout), not eliminated.
- **Accessibility defect, pre-existing and independent of this phase**: the session row's
  `NSAccessibilityCustomAction`s (`expand session detail`, `collapse session detail`, `dismiss session`)
  are registered with **`target:0x0 selector:(null)`** — listed by VoiceOver, non-invocable. There is
  also **no keyboard focus loop** in the opened panel (Tab moves nothing; `focusedElementId` never
  leaves the root). Suspected at `PouredSessionRow.swift:1231-1267` and its per-theme siblings.
  The chevron itself was confirmed working **by hand, with a mouse** — visible, expands, collapses.

**A 4th structural harness blind spot** (add to the three already tracked): `SnapshotSessionListPanel`
hardcodes `usesNotchAwareLayout: false` (`ThemeSnapshotting.swift:467-468`), so **no golden in any theme
exercises the notch-aware header branch**, and no FD golden touches the usage lane at all. The entire
F7/F8 surface is invisible to `swift test`.

**⚠️ Operational hazard — add to `ANALYST-BRIEF.md`**: the user's production `/Applications/Open Island.app`
is signed with bundle id **`app.openisland.dev` — the same domain as the test target.** A bare
`pkill -f OpenIslandApp` kills the user's real app, and `orca computer --app app.openisland.dev` drives
its UI. Both happened during Phase 5 verification. **Capture agents must target `--app pid:<own pid>`
and kill only their own PIDs, by exact PID.**

**Lesson — the failure mode this phase kept hitting:** tests here repeatedly asserted *what the code does*
rather than *what a user should see*. Three instances: a test pinning the defective lane split as correct,
a test pinning "zero gauges rendered" as intended, and a width-only invariant that accepted an invisible
window. Two regressions — the FD lane overflow and the emptyState infinite layout loop — passed a fully
green suite and were caught only by driving the real app.

### Phase 6 — Type-scale hygiene (the structural root cause)
1. **The lint, in seed/allowlist mode, first** — as a Swift `@Test` so it inherits `swift test` as
   the gate. Green on day one; every new escapee fails the build from then on.
2. Then F17 (FD `count` sub-roles), F18's role registration, F11 (`sideBadge` → `metaChip`, delete
   `monoChip`), F11b (`heroButtonLabel`), F19's `nestHeader: Font` constant — each removing its own
   allowlist entries.
3. **Not attempted this round**: the remaining ~130 sites. Follow-up per-theme chore tickets.

**Outcome (2026-07-27): complete.** The Swift Testing lint seeded 288 exact raw-font constructions
and now holds 278 after the scoped migrations; it rejects both new and stale entries and includes a
synthetic negative proof. F17/F18 now use named, size/family/weight-tested `countGlyph`, `countLabel`,
`count`, `gaugeValue`, and `gaugeUnit` roles without changing the shared 11pt `count` role in place.
F11 migrated all seven rendered Poured chip sites to sans `metaChip` and deleted dead `monoChip`;
F11b registered the existing 13/600 hero-button treatment. F19's production role had already landed
in Phase 3, so this round added its missing 10pt bold/sans + 0.09em contract test.

The mono→sans Poured change moved exactly the predicted 20 goldens (18 conformance + 2 baseline),
with no fingerprint or cross-theme drift. Live repo-executable captures passed on the real 540pt
notch surface for Flight Deck, Poured, and Halo; the unavailable 520pt physical top-bar profile is
covered by the passing snapshot harness rather than claimed as a live pass. Adversarial review
initially refuted F17 for one allowlisted raw 11pt bold-mono usage value; the additive `gaugeValue`
role closed it, and re-review upheld both MAJOR fixes. The final full suite ran 970 tests with exactly
the four known `AppModelSessionListTests` baseline issues; standalone `swift build` passed.

### Phase 7 — Component unification
`IslandDiffRenderer` + `IslandDiffStyle` (gutter, font, colours, `ContainerShape`) — marker and
gutter **structural, always rendered**. Migration order: fixture + component net-new → Poured →
Halo → **Flight Deck on `.chamfered(5)`, which resolves F14** → Annual/Instrument (§5 Q2) → delete
the legacy view. Then **F16**: one Poured button contract (r11, pad 14/8, 13/600), preserving the
primary-vs-ghost glow distinction.

**Outcome (2026-07-27): complete.** `IslandDiffRenderer` now owns the shared 500-line/180pt render
path with separate line-number gutter, kind-only marker child, and content; Poured, Halo, and Flight
Deck use themed styles while Annual, Instrument, and Classic retain `PermissionDiffPreview` per D2.
The Poured/Halo forks were deleted. Flight Deck now renders the diff inside one renderer-owned
chamfer-5 container, closing F14 without a nested rounded well.

F16's six full-size Poured CTAs share one intrinsic inline-flex contract (r11, 14/8 padding, 13/600,
no border): event and wayfinding variants retain gradient + glow, while ghost and deny remain flat
and glowless. The compact inline jump chip remains separate. Sixteen exact goldens moved — Poured
E1/E2/E3/H/A6/I plus the baseline list across both profiles, and Halo E2 across both profiles — with
zero fingerprint or cross-theme drift. Live repo-executable captures passed at the real 540pt notch
surface for all three diff styles and the Poured CTA variants. Orca exposes no hold-duration
mouse-down, and AXPress plus three cancel-safe 60fps-recorded drags produced no observable depressed
frame, so pressed-state pixels remain explicitly **UNMEASURED** for the Phase 8 interaction audit.

Adversarial review initially refuted an unused Poured typography dependency in the shared renderer
and duplicate event/deny label ownership; both were removed, and final review upheld F12, F14, and
F16. The final full suite ran 980 tests with exactly the four known `AppModelSessionListTests`
baseline issues; standalone `swift build` passed.

### Phase 8 — Full-matrix recapture + SPEC audit
**Outcome: implementation and static evidence complete.** The authoritative matrix is the fixed
**3 themes × 15 scenarios = 45** contract at
`shots/after/matrix-20260728-121846-0D5A74A5-26B2-4CFD-BC14-E947B90169D8`: it includes
`subagentsExpanded` and excludes `closedAttention`. All 45 cells pass the current validator and
each has a complete report/PNG/native-AX/timeline/Orca/cell-manifest set, rendered at exact @2x.
The runner/validator's private staging directories are absent after finalization; production proof
is **NONE→NONE**; and the required defaults were restored to `halo` plus the required display.

Capture geometry is intentional: Poured and Halo are **620pt outer = 540pt + 2×40pt**, while
Flight Deck is **576pt outer = 540pt + 2×18pt**. The machine is notched-only. The 520pt top-bar
profile has snapshot evidence only and is never represented as a live pass.

**Phase 8 evidence boundary — Halo expanded subagent combined nodes.** For the fresh complete-run
capture `shots/after/matrix-20260728-121846-0D5A74A5-26B2-4CFD-BC14-E947B90169D8`, harness
`overlay.ax.json` is the authoritative native AX evidence: it exposes exactly the three
status/type/task/timer rows. Orca's `orca-app-state.json` is secondary window/PID/integration
evidence only; its `treeText` omits those SwiftUI combined nodes and its screenshot payload is
`dataOmitted`, so it neither corroborates this detail nor may be cited as doing so. The current
validator binds the native contract and rejects the preserved broken artifact. Record this tooling
boundary transparently, not as a PASS from Orca.

**Approved Flight Deck production deviation.** The FD mockup crops
(`flightDeck-E1.png`, `flightDeck-F1.png`) place the Model·Branch identity run in a **third column
beside** the placard/kicker; Phase 4 shipped it as a **second line below**, because the single-line
arrangement demonstrably collapses the kicker (measured 0.61 cap-height ratio, truncation, and a
wrapping `HELD` readout at both 520/540pt). The documented shipped form mirrors Halo's who-line;
it is the approved production layout rather than an unacknowledged board-conformance claim.

**Fixture adjudication is complete.** Ordinary approval/question fixtures are Claude-backed and
provide Model·Branch; `codexApproval` is Codex-only; and completion plus long-completion fixtures
have nonempty transcripts and expose **Transcript**. Theme contracts are covered in the matrix.
There is no remaining claim that these fixtures or transcripts are missing.

**Completed implementation.** The safe runner and validator now bind the matrix contract; named
typography roles include `completionJumpLabel` and the 10pt `microLabel`; Halo uses a sans
monogram; and Poured has an expansion resolver. Shared nested-work AX now distinguishes collapsed
and expanded content, with Halo's combined rows represented correctly. Usage reset semantics cover
all six themes (Poured/Halo show full provider names; Flight Deck groups `Cl`/`Cx`); Flight Deck has
a completion Jump affordance; and Flight Deck's empty state is uppercase. Multi-question actions
have stable identifiers and raw AX title/description/help/enabled provenance, including strict
CFBoolean handling.

**Interaction boundary — no overall interaction PASS.** Evidence roots
`shots/after/interactions-20260728-132309-F9F06E15-C90E-4C2A-B824-7DEFC86173B8` and
`shots/after/interactions-detached-20260728-080123-79086C7F-323A-472B-8F29-68124D80A5FC` record
no product FAIL, but leave §K motion **UNMEASURED** (no targetable persistent window or temporal
capture), §B hover **UNMEASURED** (no hover capability), and expand/collapse action/end-state and
morph **UNMEASURED** (the owned app exited before Orca could target it). Focus rings are
**UNMEASURED**; pressed pixels are **UNMEASURED** (no held down/up); and physical 520pt is
**UNMEASURED**. Production PID 75647 remained unchanged and defaults were restored.

**Snapshot/golden accounting.** Exactly 34 unique goldens changed: 20 Halo monogram files; 6 Poured
conformance files plus 2 Poured baseline files in `ThemeSnapshot`; and 5 Flight Deck
permission/question files plus 1 Flight Deck completion file in `ThemeSnapshot` (8 ThemeSnapshot
files total). The completion golden was re-recorded after the 9.5→10pt arrow lift, but remains the
same unique file.

**Final verification.** The full suite reported **1,013 tests / 81 suites** with exactly four known
baseline issues: stale completed→idle grouping (2), completed retained in the done threshold (1),
and last-update sorting (1). There were no unexpected issues; the `swift test` process exited 1
only because of those baseline issues. `swift build` and `git diff --check` pass. Targeted and final
adversarial review both **UPHELD** the remediation.

---

## 5. Decisions — RESOLVED 2026-07-27

**D1 — Pagination: one mechanism, per-theme page size.** ✅
Build a paginated container whose **page size is a theme property**: `1` for Poured and Halo, `.all`
for Flight Deck. This honours all three approved boards at near single-path cost, and **the two
keyboard models fall out of it rather than being written twice** — digits restart per page when a
page holds one question, and run continuously when a page holds all of them. So
`registerKeyboardHandlersIfNeeded`'s guard (`IslandPanelView.swift:2821`, currently disabling 1-9
whenever `structuredQuestions.count > 1`) becomes a function of **page** contents, not question
count, and Poured/Halo regain keyboard selection they don't have today.

**D2 — Scope: F7 across all six themes; diff migration for the three reviewed only.** ✅
F7 becomes one shared helper in `IslandUsageSummary.swift` consumed by all six `*HeaderControls.swift`
— it is a single function, and fixing only three guarantees the drift returns. But **only
Poured/FD/Halo migrate onto `IslandDiffRenderer`**; Annual/Instrument/Classic keep the legacy
`PermissionDiffPreview`, which therefore is **not** deleted in Phase 7. Retire-candidates don't earn
migration churn.

**D3 — Halo A3: a new theme-pluggable glyph seam.** ✅
Additive and isolated, mirroring the existing `closedSurfaceGlow`/`closedGlyphTint` precedent.
**`UnifiedBars.Mode` is not extended** — that would be a compile error at all 7 exhaustive switch
sites plus new CAShapeLayer geometry in the shared animation engine, for a Halo-only need.

**D4 — §I is a Settings surface, not an overlay surface.** ✅
`usageMeterCard`'s only call site is the Settings > Appearance preview, and the live overlay never
shows it to a real user by design. **Dropped from the overlay remediation**; verified through the
existing Settings preview and snapshot coverage. **No production composition change, and Phase 1
item P1.b is cancelled.**

**Decisions taken by the orchestrator** (low-stakes, reversible):
- **F6 testability**: add an injectable seed for `detailOverride` so the expanded-detail path keeps
  static snapshot coverage after the fix.
- **`monoChip`**: delete it. Its mockup counterpart `.chip.mono` is **never applied to any element in
  the design source either**, and every genuine mono need already has a dedicated role.
- **Poured's shared-row twin**: `IslandPanelView.swift:1158`'s duplicate `showsDetail` and Halo's own
  `sessionDetailBody` stay untouched — a Poured-scoped fix, flagged in the commit.
- **Known-red `AppModelSessionListTests`**: leave the four baseline issues alone. They have a diagnosed
  cause and a known fix pattern (back-porting AB-322's both-buckets pin), but that is not this
  remediation's job. Offered as a separate follow-up.

---

## 6. Per-phase verification protocol

1. **One** verification agent per phase — capture is a strictly serial resource. It receives: the
   phase's acceptance criteria, frames to capture, mockup crops, the scale rule, the surface-scope
   table, and the known-artifacts list.
2. It re-captures the affected frames in **all three themes** where the change is shared, and reports
   PASS/FAIL **per criterion with numbers**.
3. Motion, hover, morph, focus and pressed states are driven live via **computer-use** — stills
   cannot settle them.
4. **Any FAIL means the phase is not done.** Dispatch a fix agent with the measurement; re-verify;
   loop. Never carry a failure forward.
5. For every MAJOR fix, a second **adversarial verifier** tries to REFUTE the pass, defaulting to
   REFUTED when uncertain. This caught real mistakes during the review — a wrong file cited, a wrong
   frame measured, an "artifact" that was correct behaviour.
6. Before/after evidence pairs land in `shots/pairs-after/`; new captures in `shots/after/`.
   **`shots/app/` and `shots/notch/` are the baseline — never overwrite them.**
7. Update §7's status table before starting the next phase.

**Constraints every agent is handed**: the ModuleCache gotcha (§2c), `DEVELOPER_DIR`, the worktree's
own copy of `launch-dev-app.sh` with `--skip-setup`, the per-phase test filter, the known-red
baseline of 6 failures / 5 tests, and the DO-NOT-FIX table.

---

## 7. Status table

| Phase | Scope | State |
|---|---|---|
| 0 | Analysis + this plan | **complete** — 9 parallel analyses merged, 4 decisions resolved |
| 1 | Verification infrastructure | **complete** — 6/6 ACs pass, 24 live captures, 2 known-red tests retired |
| 2 | Shared question view | **complete** — F1/F1a/F1b closed in all 3 themes; 7/9 criteria measured, 2 blocked by tooling |
| 3 | Safety and semantics | **complete** — F3/F4/F5/F19/F20 closed; 13/13 criteria measured live |
| 4 | Flight Deck hero frame | **complete** — F2.1/F2.2/F2.3/F2.4/F10/F13 closed; all 4 MAJORs adversarially UPHELD on the real app |
| 5 | Layout | **complete** — F6/F7/F8/F9/F15/F18 + emptyState closed; 14/14 criteria measured live; 2 regressions caught by capture that the green suite missed |
| 6 | Type-scale hygiene | **complete** — seed lint 288→278; F17/F18/F11/F11b/F19 closed; 20 exact Poured goldens; both MAJOR fixes adversarially UPHELD |
| 7 | Component unification | **complete** — F12/F14/F16 closed; 16 exact goldens; all three MAJOR fixes adversarially UPHELD |
| 8 | Full-matrix recapture + SPEC audit | **complete** — implementation/evidence complete; authoritative 45/45 matrix PASS, with live interaction pixels/states explicitly **UNMEASURED** where tooling/app lifetime prevented measurement (no overall interaction PASS) |

---

## 8. What this plan corrects in the source review

Recorded so the plan is not read as a restatement of `REPORT.md`:

| Claim in the review | Corrected finding |
|---|---|
| `splitUsageProviders` is "triplicated across all three themes" | **Six** byte-identical copies — every shipped theme |
| The shared question view has 3 unthemed call sites | **Six** — Classic, Annual and Instrument too |
| "Every theme defines `questionText`/`optionLabel`/… roles that go unused" | **Flight Deck has none of them** — they were never authored. Halo's table structurally cannot express weight |
| "Add question pagination" (uniformly) | **Flight Deck's own board rejects pagination** |
| "Fix the persistent hollow radio circle" (uniformly) | FD's board makes it **persistent by design** — its defect is the *shape* (chamfered octagon, not circle) |
| FD hero card fill is a `FlightDeckSurfaces` token | It is `alarm.opacity(0.08)`, routed through no surface token — and the excess brightness is the **un-bled glow**, i.e. the same bug as the missing bleed |
| `SPEC-flight-deck.md:158` is "a stale checkmark asserting false conformance" | The ✅ column is literally headed **"Floor"** — it only ever claimed the target clears 10pt. **No SPEC typography table has ever compared against shipped code** |
| "Poured's `showsDetail` is an overly broad predicate" | The defect is the **`else` branch at `:145-150`**; `showsDetail` itself is fine |
| "§D/§G never render — all three agents confirmed" | **Refuted for Poured** — `shots/app/poured-subagentsCard.png` already shows the full nest. Only FD and Halo are broken |
| "§I's meter card never renders" | It is a **Settings-only surface by design**; the overlay never shows it to any user |
| `monoChip` should be wired up | The mockup's own `.chip.mono` class **is never applied to any element** — delete it |
| Diff gutter widths "10 / 26 / 22" | Conflates two different columns: the shared view has a **marker column and no gutter**; the forks have gutters |
| 5 known-red tests | **2 of them passed** in the measured baseline; the other 3 have a diagnosed cause and a known fix pattern. Two more (the Poured goldens) are **fixable in Phase 1** |

### Corrections made during Phase 4 (2026-07-27)

| Claim in this plan | Corrected finding |
|---|---|
| **F2.1's root cause is the shared `.clipShape` around `openedSurfaceContent`**, requiring an `actionableCardGlow` hook hoisted outside it (mirroring AB-330) | **Refuted by real-app measurement.** The approval card is **inset ~68pt** within the panel, so the clip is nowhere near its edges and never truncated the glow. The actual cause was simply **insufficient bleed** — `FlightDeckPhosphorGlow`'s implicit default of `2`. A local `bleed: 8` on `FlightDeckCautionGlow`/`FlightDeckPulsingGlow` yields a **17.5–28.5pt symmetric fading ramp** (baseline: a 4px hard cut) on all four edges, unchanged under Reduce Motion. **No hook was needed and none was built.** The clip sites still exist and still execute — their line numbers drifted to `IslandPanelView.swift:833` (default morph) and `:597` (Reduce Motion) |
| Snapshot goldens can evidence glow, bleed, or panel geometry | **They cannot.** The harness **never instantiates `IslandPanelView`** — `ThemeSnapshotting.swift:430-526` builds a private `SnapshotSessionListPanel` replica with its *own* hand-maintained clip, and its offscreen `NSHostingView` rasterizer does not render `.blur()` faithfully. Any glow/geometry claim must come from the real app (`swift run OpenIslandApp` + screenCaptureKit). Goldens remain sound for **layout and typography** |
| F2.3 passes at a cap-height ratio of 1.087 | True **only while `contextText` was nil**. Once fixtures supplied model/branch, F2.4's run competed for the same line and the header collapsed to **0.61**, with a truncated kicker ("PERMISSION R…") and a wrapping `HELD` readout — **at notch as well as top-bar**. Fixed by giving the context run **its own line** (mirroring Halo's who-line) plus `lineLimit(1)`/`fixedSize` guards on `heldReadout`. Final: **1.06–1.70** across all four permission/question × notch/top-bar cells |
| A criterion measured green is settled | **Only if the feature actually renders.** F2.4 passed review, compiled, and shipped for an entire round while rendering **nothing** — no fixture set `claudeMetadata.model` or `worktreeBranch`. Closing that fixture gap is what exposed the F2.3 collapse above. **Verify a feature is observable before verifying it is correct** |
