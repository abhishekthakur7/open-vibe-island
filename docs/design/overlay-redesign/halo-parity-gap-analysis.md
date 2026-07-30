# Halo — visual parity gap analysis (2026-07-31)

Fast 80/20 visual gap inventory: **live Halo overlay** vs **`docs/design/overlay-redesign/06-halo.html`**.

Scope note: this is *not* a re-run of `halo-visual-parity-audit.md`. That document's gates,
masks, manifests and calibration harness are deliberately out of scope. This document is a
per-element styling / layout / animation delta list, ordered by visual impact, meant to be
implemented directly and verified by eye.

Method: mockup CSS read as ground truth (exact px / opacity / duration values cited);
live overlay driven through `OPEN_ISLAND_HARNESS_SCENARIO=<scenario>` with
`-appearance.island.v8.theme halo`, captured with `screencapture`; native token values read
from source with `file:line` citations.

---

## 1. Verdict summary

Ranked by how much each one costs the "does it look like the mockup?" read.

1. **The edge-light is a solid glowing outline instead of a travelling segment.**
   `HaloEdgeRing` paints a *second* full-perimeter 1.5pt stroke in the bloom colour
   (`HaloEdgeLight.swift:263-268`) underneath the masked angular gradient. The mockup's bloom
   is a pure *outer* drop shadow (`box-shadow:0 0 26px -10px rgba(96,150,255,.45)`, spread
   `-10px`) with **no** coloured stroke. Result: every state reads as a bright, uniform,
   fully-lit ring. The whole "95% of the time it's a bare hairline" thesis collapses, and
   nothing inside the panel can out-shout the border.

2. **The expanded panel is an ungrouped flat list.** The live list renders no
   `NEEDS YOU → RUNNING → DONE` headers, so attention does not float to the top (the code
   *has* `sessionSectionHeader`, `HaloSessionListScaffold.swift:185-210`, but it only fires
   when `group != .none`). The mockup's entire §C hierarchy — group header + colour dot +
   right-aligned count + rails only on actionable rows — is absent from the rendered result.

3. **The quota/usage UI is the weakest surface in the product.** The mockup ships a dedicated
   §I `.meterc` card: 52px filament rings, **22px** threshold-coloured numerals, an explicit
   `resets in …` line, and **FINE / WARN / CRITICAL** tinted pills. Native has a near-exact
   port of this (`HaloUsageMeterCard.swift`) that **is never shown in the overlay** — it is
   only reachable from the Appearance settings preview (`AppearanceSettingsPane.swift:1101-1105`).
   The overlay instead crams **three** 30pt rings with 10/11pt labels into the header's
   *left* lane, where the mockup puts **one per lane** split around the notch.

4. **Rows are content-starved, so density reads as emptiness, not calm.** Mockup rows carry
   branch disambiguation, a narrated activity line, and a meta row of chips
   (`Opus 4.8` / `acceptEdits` / `⏱ 1m 42s`). Live rows show title + one line + age +
   a chevron — a chevron the mockup does not have at all
   (`HaloSessionRow.swift:1505-1510`). Vertical rhythm is uniform, so no tier is legible.

5. **Every tertiary element is ~19% too bright.** `tertiaryTextOpacity = 0.50`
   (`HaloTheme.swift:778`) against the mockup's `--t3: rgba(255,255,255,.42)`. This affects
   ages, meta chips, section headers, usage kickers, footers, branch chips — i.e. most of the
   panel. It is a one-line change with an outsized "quietness" payoff.

6. **The type ramp's bottom two tiers are collapsed into one.** `HaloTypography.floor = 10`
   (`HaloTheme.swift:32`) lifts the mockup's 9px (`.fk`, `.mk`) and 9.5px (`.thl`, `.mono-tag`)
   roles to 10 (`HaloTheme.swift:118-132`), *and* renders them at `.semibold`/`0.50` where the
   mockup uses `600`/`.42`. Micro-labels therefore compete with body copy — the single biggest
   contributor to "inconsistent typography".

7. **Two loud things at once on every attention state.** In `approvalCard` / `questionCard`
   the outer perimeter *and* the hero ring both burn at near-full intensity. The mockup's §E
   filmstrip is explicit: light *travels* from the perimeter **into** the card, leaving the
   perimeter dark. Native only drops the perimeter to `perimeterOpenHandoffFloor = 0.55`
   (`HaloEdgeLight.swift:323`).

8. **The question card is un-themed.** Option number chips, labels and descriptions are
   hard-coded achromatic white in the shared `IslandPanelView` option row
   (`IslandPanelView.swift:2726-2745`) — no qgold. The disabled Submit CTA renders as a dead
   grey slab (`saturation 0.35 × opacity 0.5`, `IslandTheme.swift:450-452`) and is the loudest
   element in the card. The mockup has no disabled state; its CTA is always amber.

9. **The collapsed pill loses its narration and its agents-grid.** Observed working pill:
   glyph + `×9`, empty centre. Mockup A2′: glyph + **"3 working"** + a bloomed
   6-dot agents grid. Observed permission pill: dot + `1`, no text. Mockup A3:
   **"Approve `swift build`?"**. The label machinery exists
   (`HaloClosedPill.swift:570-637`) but the pill does not grow to make room for it — its
   height is pinned to the notch (`IslandPanelView.swift:874-876`, fallback 24) where the
   mockup's `.pill` is **38px** and hangs 12px below the 26px notch.

10. **Motion is mostly *correct* but almost entirely *absent from the list*.**
    Durations/easings for orbit (6s linear), edge pulse (1.9 / 2.6 / 2.2s), success bloom (3s),
    wave (1.05s), breathe (2.4s), grid-dot (2s) and all hovers match the CSS. But
    `HaloSessionListScaffold.swift` contains **zero** `.animation` / `.transition` /
    `withAnimation` — rows insert, reorder and leave with a hard cut, which is what reads as
    "missing animations".

---

## 2. Screenshot evidence

All under `artifacts/halo-parity/analysis-2026-07-31/`.

### Reference (mockup, Safari, isolated sections)

| File | Mockup section |
|---|---|
| `ref-A-pill-states.png` | §A — collapsed pill: idle / one working / many working / permission / question / just completed |
| `ref-C-expanded-panel.png` | §C — expanded panel, grouped mixed session list (the primary comparison frame) |
| `ref-E-permission-hero.png` | §E — permission hero + the "light travels" filmstrip + command & diff variants |
| `ref-F-question.png` | §F — question prompt (single-select, multi-select + Other, compact) |
| `ref-H-completed.png` | §H — completed session |
| `ref-I-usage-meters.png` | §I — usage meters card + I′ compressed-to-pill |
| `ref-J-empty.png` | §J — empty state |
| `ref-K-motion.png` | §K — motion spec strip |
| `ref-B-hoverpeek-morph.png` | §B — hover peek + B′ morph filmstrip *(added 2026-07-31 pass 2)* |
| `ref-D-rowdetail.png` | §D — row expanded, session detail *(pass 2)* |
| `ref-G-subagents.png` | §G — nested subagents/tasks + G′ pill compression *(pass 2)* |
| `ref-I-usage-pill.png` | §I + I′ — meters card and the critical-usage pill *(pass 2)* |

Pass-2 reference crops were rendered headless
(`Google Chrome --headless=new --force-device-scale-factor=1 --window-size=1500,14000
--screenshot`) and cropped, rather than photographed out of Safari.

### Native (live overlay, Halo active)

| File | State | Harness scenario |
|---|---|---|
| `native-closed.png` | collapsed pill, many working | `closed` |
| `native-closedAttention.png` | collapsed pill, permission | `closedAttention` |
| `native-sessionList.png` | expanded panel, mixed session list | `sessionList` |
| `native-sessionList-full.png` | same, full-desktop context | `sessionList` |
| `native-usageMeters.png` | expanded panel **with header usage filaments** | `usageMeters` |
| `native-approvalCard.png` | permission hero | `approvalCard` |
| `native-questionCard.png` | question card | `questionCard` |
| `native-completionCard.png` | completed session | `completionCard` |
| `native-emptyState.png` | empty state | `emptyState` |

Added by the 2026-07-31 pass 2 (the four previously-uncaptured states plus the
scenarios the first pass missed):

| File | State | Harness scenario |
|---|---|---|
| `native-subagentsExpanded.png` | **§D + §G** — running row pinned open: subagents nest, todo list, metadata grid, Jump | `subagentsExpanded` |
| `native-subagentsCard.png` | §G collapsed — subagent fan-out compressed into the row meta line | `subagentsCard` |
| `native-rowDetail-collapsed.png` | §D before — the same list, all rows collapsed | `sessionList` |
| `native-rowDetail-expanded.png` | **§D** — an idle row expanded **in place by a real click** (metadata, last-message block, Jump, cwd) | `sessionList` + pointer-enter, then click the chevron |
| `native-B-pill-rest.png` | **§B** — closed pill at rest (2× zoom) | `closed` |
| `native-B-hoverPeek.png` | **§B** — same pill after a >0.15 s pointer dwell (2× zoom) | `closed` |
| `native-B-morph-open-frames.png` | **§B′** — 6 frames of the pill→panel morph (f128/131/135/140/146/156 @60 fps) | real mode |
| `native-B-morph-close-frames.png` | **§B′** — 9 frames of the panel→pill morph | real mode |
| `halo-morph.mov` | the 9 s source recording for both strips (`screencapture -v -V 9 -D 2`) | real mode |
| `native-diffApprovalCard.png` | §E edit-permission variant with the inline diff **and** the scoped-allow row | `diffApprovalCard` |
| `native-codexApprovalCard.png` | §E respond-in-terminal variant | `codexApprovalCard` |
| `native-multiQuestionCard.png` | §F two-question prompt, question 1 of 2 | `multiQuestionCard` |
| `native-longCompletionCard.png` | §H long result, internal scroll, rich-text render | `longCompletionCard` |
| `native-completedInterrupted.png` | §H `Interrupted` outcome | `completedInterrupted` |
| `native-completedFailed.png` | §H `Failed` outcome | `completedFailed` |
| `native-usageHeader-zoom.png` | §I header filaments at 1.6× — the three-in-one-lane crowding, legible | `usageMeters` |
| `native-real-emptyState.png` | **real discovery mode** — no harness scenario at all | *(none)* |
| `native-real-sessionList.png` | real mode, wider frame, after a fresh `claude -p` turn | *(none)* |

Repro:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build --disable-automatic-resolution --disable-sandbox -c debug --product OpenIslandApp

OPEN_ISLAND_HARNESS_SCENARIO=sessionList \
OPEN_ISLAND_HARNESS_PRESENT_OVERLAY=1 \
OPEN_ISLAND_HARNESS_BOOT_ANIMATION=0 \
OPEN_ISLAND_HARNESS_START_BRIDGE=0 \
OPEN_ISLAND_HARNESS_SUPPRESS_INSTALL_HINT=1 \
OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS=20 \
  ./.build/arm64-apple-macosx/debug/OpenIslandApp -appearance.island.v8.theme halo
```

### Coverage after pass 2 (2026-07-31)

Three of the four previously-uncaptured states are now captured live; the fourth is
argued to be undrivable and analysed from code vs CSS.

- **§G nested subagents — captured.** `subagentsCard` / `subagentsExpanded` existed all
  along in `IslandDebugScenario.swift:41,46`; the first pass simply missed them. Also
  captured while there: `diffApprovalCard`, `codexApprovalCard`, `multiQuestionCard`,
  `longCompletionCard`, `completedInterrupted`, `completedFailed`.
- **§D row-expanded detail — captured, two ways.** `subagentsExpanded` pins the running
  row open via `forcesRowExpansion`; and a *real* click-to-expand works in `sessionList`
  once the pointer has first entered the surface (see **G-61**).
- **§B hover peek + morph — captured.** Hover was driven with `CGWarpMouseCursorPosition`
  (a bare `CGEvent(.mouseMoved)` post does **not** move the cursor and never fires
  SwiftUI `.onHover`; the first pass's tooling would have silently no-op'd here). The
  morph was recorded at 60 fps and judged frame-by-frame — see **M-12**, **M-23…M-26**.
- **I′ critical usage compressed into the pill — NOT captured; genuinely undrivable
  today.** What was tried, in order:
  1. Read all 16 `IslandDebugScenario` cases — none pairs a *closed* notch with critical
     usage. `closed` / `closedAttention` carry `usageProviders: nil`, so `worstUsage`
     is `nil`.
  2. `usageMeters` is the only scenario with a critical window
     (`AppearancePreviewFixtures.swift:790-799`, Codex 7d = **92 %**), but its snapshot
     pins `notchStatus: .opened` and `OPEN_ISLAND_HARNESS_PRESENT_OVERLAY=1` suppresses
     collapse: an outside click, a click inside, and a pointer enter→leave all failed to
     collapse it.
  3. Even if it *could* collapse, `IslandRightSlotResolver.content`
     (`IslandRightSlotResolver.swift:128-145`) ranks attention → **running task counter**
     → usage. `usageMeters` uses `DebugSessionFactory.listSessions`, which has a running
     session, so the pill would resolve to `.taskCounter`, never `.usage`.
  4. Real discovery mode reports Claude 5h 3 %, Claude 7d 59 %, Codex 7d 21 % — nothing
     ≥ 90, and no sessions at all.
  5. `AppearancePreviewFixtures` only reaches the Settings preview
     (`AppearancePreviewScenario.meters`), which renders the *expanded header*, not the pill.

  Driving I′ needs a new scenario (closed notch + zero running sessions + a ≥90 % fixture
  window). Gaps **G-63 / G-67 / G-68** below are therefore code-vs-CSS only, and
  explicitly marked as such.
- **Still not captured:** reduced-motion variants.

---

## 3. Gap inventory

Severity is **visual impact**, not risk.

### (a) Typography

| ID | Area / state | Mockup (exact CSS) | Native (observed / code) | Impact | Fix direction |
|---|---|---|---|---|---|
| G-01 | Global tertiary ink | `--t3: rgba(255,255,255,.42)` | `tertiaryTextOpacity: 0.50` — `HaloTheme.swift:778` | **High** | Change `0.50 → 0.42`; single token, affects age/meta/section-header/usage-kicker/footer/branch at once. |
| G-02 | Micro-type tier | 9px `.fk` usage kicker, 9px `.mk` metadata key, 9.5px `.thl` threshold, 9.5px `.mono-tag` | all lifted to **10** by `HaloTypography.floor = 10` — `HaloTheme.swift:32,118-132` | **High** | Either lower the floor to 9 for the four decorative label roles, or keep 10 and drop them to `.medium` @ `0.42` so optical weight matches. |
| G-03 | Usage kicker weight | `.fil .ft .fk{font-weight:600;color:var(--t3)}` | `.semibold` @ `tertiaryTextOpacity 0.50` — `HaloUsageSummary.swift:302-306` | Med | `.medium` @ `0.42`. |
| G-04 | Option label / desc | `.opt .ol` 13/600 @ `--t1 .95`; `.opt .od` 11.5 @ `--t2 .63`, `line-height:1.42`, wraps | label `.white.opacity(0.78)`; desc `.white.opacity(0.38)` (0.48 hovered) **and `.lineLimit(1)`** — `IslandPanelView.swift:2739-2747` | **High** | Raise to `0.95` / `0.63`, drop `lineLimit(1)` → `lineLimit(2)`. |
| G-05 | Meter label | `.meter .mx .ml{font-size:12px;font-weight:550}` | `metadataValueSize` **12.5** `.medium` — `HaloUsageMeterCard.swift:105-107` | Low | 12. |
| G-06 | Summary strip title | no such element in `.summary` | extra uppercased list title (`SESSIONS`) at 10/bold tracking 1.0 — `HaloSessionListScaffold.swift:132-135` | Med | Drop the title, or demote to `0.42` and let the buckets lead as the mockup does. |
| G-07 | Panel footer | `.p-foot{font-size:11px;color:var(--t3);padding:9px 16px;border-top:1px solid var(--hair)}`, left-aligned | "Show all 9 sessions" renders centred, semibold, ~13pt, no top hairline (observed `native-approvalCard.png`, `native-questionCard.png`) | Med | 11pt `.regular` @ `0.42`, left-aligned, 1pt `white@0.08` top hairline. |
| G-08 | Liveness glyph silhouette | `.gly i` all three bars 5px→14px, uniform | per-bar crests 12 / **16** / 10 — `HaloClosedPill.swift:404-406` | Low | Flatten to a uniform crest (14) so the stagger, not the baked height, creates the wave. |
| G-50 | §D/§H metadata cell type | `.mcell .mk` **9px**/700/`.07em`/`--t3`; `.mcell .mv` **12.5px**/560/`--t1` | key renders ≈11px semibold well above `.42`, value ≈14px semibold — observed `native-rowDetail-expanded.png`, `native-completedFailed.png` | **High** | The metadata grid currently out-shouts the row title it belongs to. 9/700@0.42 + 12.5/560@t1. Same root as G-02 (`HaloTypography.floor = 10`). |
| G-51 | §G nest header | `.nest-h` 10px/700/`.09em`/`--t3`; `.nest-h .nn` also `--t3` | `SUBAGENTS` + `3 active` render ≈11–12px and clearly brighter than `.42` — observed `native-subagentsExpanded.png` | Med | 10/700 @ `0.42` for both the label and the trailing count. |
| G-52 | §G subagent row type | `.suba .sty` 12/600 `--t1`; `.suba .stk` 11 `--t2`; `.suba .sti` 11 `--t3` | type ≈13 semibold, task ≈12, elapsed ≈12 and bright — observed | Med | 12 / 11 / 11. As shipped a nested child reads at the same weight as its parent session title, flattening the hierarchy the nest exists to create. |
| G-53 | §G todo "in progress" tag | `.todo .tsp{font-size:10px;color:var(--cyan)}` | ≈12px, full-saturation cyan — the loudest string in the nest — observed | Low | 10px, and let the clock icon carry the state (the mockup's point: icon, not colour). |
| G-54 | §I header filament value | `.fil .fv` is the **percent only** (11px `--t2`); the reset countdown lives in the meter card's `.mr` | value line packs both: `34% · 2h 9m`, ≈13px bold near-white — observed `native-usageHeader-zoom.png` | Med | Drop the countdown from the header lane (it moves to the meter card, G-28) and take the percent to 11 @ `--t2`. |

### (b) Layout & density

| ID | Area / state | Mockup (exact CSS) | Native (observed / code) | Impact | Fix direction |
|---|---|---|---|---|---|
| G-09 | Expanded list grouping | `.grp` headers `Needs you / Running / Done`, 10px, `letter-spacing:.1em`, uppercase, 700, `--t3`; 6px colour dot; `.gn{margin-left:auto}` right-aligned count | headers exist (`HaloSessionListScaffold.swift:185-210`) but **do not render** in the live list — observed flat list in `native-sessionList.png`; and the count is left-adjacent, not right-aligned (`:195-198`) | **High** | Force grouping on for Halo's list presentation, and move the count behind a `Spacer()` so it right-aligns. |
| G-10 | Active-row rail | `.rail` 2px, `top:8px;bottom:8px`, cyan→violet / amber→magenta / qgold + `box-shadow 0 0 8-10px` | implemented correctly (`HaloSessionRow.swift:1397-1441`) but **visually swallowed** by the over-bright perimeter — no rail readable in `native-sessionList.png` | **High** | No row change needed; fixing G-13 restores it. Verify by eye after G-13. |
| G-11 | Row meta chips | `.meta` row: `.chip.mn` model, `.chip` mode, `.pin` elapsed, all 10.5px `--t3`, `margin-top:7px` | absent on most live rows (only `Jump` / `Ghostty` chips on the done row) — observed | **High** | Populate the meta row for running rows (model, permission mode, elapsed) — the layout slot already exists at `HaloSessionRow.swift:425-439`. |
| G-12 | Row disclosure chevron | none | `HaloDetailToggle` chevron on every interactive list row — `HaloSessionRow.swift:459-462,1505-1510` | Med | Hide at rest, reveal on hover (same treatment as `HaloDismissButton`), or drop it and keep row-tap-to-expand. |
| G-14 | Panel header padding | `.p-head{padding:11px 16px 10px}` | `.padding(.top, 2)`; horizontal `46` on notch layout — `HaloHeaderControls.swift:81`, `IslandUsageSummary.swift:212` | Med | Top padding `2 → 10`; the header currently clings to the notch with no breathing room. |
| G-15 | Summary strip chrome | `.summary{padding:8px 16px;border-top:1px solid var(--hair);border-bottom:1px solid var(--hair)}` | fixed `.frame(height: 36)`, **bottom hairline only** — `HaloSessionListScaffold.swift:144-153` | Med | Add the top hairline; let height be intrinsic (8pt vertical padding). |
| G-16 | Summary bucket dot | `.summary .b .dot{width:6px;height:6px}` | `5.5 × 5.5` — `HaloSessionListScaffold.swift:161-163` | Low | 6. |
| G-17 | Panel width | `.panel{width:520px}` | notch **540**, non-notch 520 — `OverlayPanelController.swift:9-10` | Low | 520 on both, or accept 540 as a notch-clearance decision. |
| G-18 | Collapsed pill height | `.pill{height:38px}` over a 26px notch — the pill visibly hangs below | height = `safeAreaInsets.top` (notch height); observed ≈26pt in `native-closed.png` — `IslandPanelView.swift:874-876` | **High** | Add a fixed overhang (`notchHeight + 12`, floor 38) so the pill reads as a body, not a notch tint. `HaloClosedPill`'s own default is already 38 (`HaloClosedPill.swift:43`). |
| G-19 | Pill corner radius | `--pill-r: 19px` | square top corners + bottom radius `height/2` ≈ 13 — `V6ClosedPillShape.swift:9-34` | Low | Follows from G-18 (height 38 → bottom radius 19). |
| G-20 | Working pill width | `.pill.big{min-width:352px}` so narration fits in a wing | pill does not grow for the label; observed empty centre + `×9` — `IslandPanelView.swift:460` (`minWidth: 70`) | **High** | Raise the working/attention min-width so the narrated label has a wing to live in. |
| G-21 | Hero: scoped grants | `.scopes` — 1–2 rows, `padding:9px 11px`, 12px `--t2`, `inset 0 0 0 1px var(--hair2)`, `code` chip `#ffd6a4` on `rgba(255,160,80,.1)`, `⌘⇧Y` keycap | absent — observed `native-approvalCard.png` | Med | Render `suggestedUpdates` as the scoped-allow rows the mockup specifies. |
| G-22 | Hero: duplicated headline | hero *is* the whole panel body; head = title + narrated subtitle | the session row above the hero repeats the same sentence verbatim — observed | Med | Suppress the row's activity line while its hero is presented, or make the hero subtitle the narration ("the-automator wants to run a command") and the row the target. |
| G-23 | Question: progress + subtitle | `.hero-head` subtitle `niche-radar · OpenCode`; `.qprog` `1 of 2` right-aligned 11px `--t3` | neither present — observed `native-questionCard.png` | Med | Add the workspace·agent subtitle and the `n of m` progress to the question hero head. |
| G-24 | Question: tag row | `.q-tag` 10/700/.05em on qgold sits **inline** with an optional `multi-select` chip, directly above `.qtext` | `AUTH` chip on its own line, oversized, no companion chip — observed | Low | Inline the tag row; add the `multi-select` chip. |
| G-25 | Question: footer order | `.q-foot` = primary button **then** `.q-hint` to its right, 10.5px `--t3`, with `kbd` keycaps | hint text sits **above** a full-width grey button — observed | Med | Put the CTA first and the hint beside it; render keys as keycaps not prose. |
| G-26 | Empty state rhythm | `.et`→`.es` 6px; `.es`→`.ec` 15px | uniform `VStack(spacing: 10)` — `HaloEmptyState.swift:39` | Low | Use 6 / 15 so the ramp reads. |
| G-27 | Command block wrap | `.cmd{white-space:pre;overflow-x:auto}` — never wraps | wraps to 3 lines on a long path — observed `native-approvalCard.png` | Low | Truncate/scroll horizontally, or middle-truncate the path. |
| G-55 | **§D/§H metadata grid has no cell chrome** | `.mcell{padding:8px 11px;border-radius:9px;box-shadow:inset 0 0 0 1px var(--hair2);min-width:86px}` in a `flex-wrap` `.mgrid` with `gap:8px` — six discrete chips | rendered as a bare 2/3-column text grid: no fill, no hairline, no radius, no padding — observed `native-rowDetail-expanded.png`, `native-subagentsExpanded.png`, `native-completedFailed.png`, `native-longCompletionCard.png` | **High** | The single biggest reason the expanded row "looks nothing like the design". Wrap each pair in a `hair2` inset-stroked 9pt-radius chip and let them wrap. Note the *mockup's own* §H (visible behind the overlay in `native-codexApprovalCard.png`) shows the boxed treatment side-by-side with native's bare one. |
| G-56 | §D metadata field set incomplete | six fields: **Agent, Model, Permission, Branch, Duration, Terminal** | idle row: **Agent + Terminal** only; running row: **Agent + Duration + Terminal**; completed row: Outcome + Duration + Model + Finished — observed | **High** | Model / permission-mode / branch never appear in the detail body even though the mockup's caption insists every field is "something the app truly computes". Same data the row meta chips need (G-11). |
| G-57 | §D/§H action row incomplete | §D `.meta`: `Jump to Ghostty` (cyan wash) + `Transcript` + right-aligned mono cwd. §H adds `Reply` + right-aligned `Dismiss` | §D shows `Jump · Ghostty` + cwd only (no Transcript); §H shows `Jump · Ghostty` + a **disabled/dimmed** `Transcript`, no `Reply`, no `Dismiss` — observed `native-rowDetail-expanded.png`, `native-completedFailed.png`, `native-longCompletionCard.png` | Med | Render Transcript live, add Reply/Dismiss on completed rows. Also the copy is `Jump · Ghostty` vs the mockup's `Jump to Ghostty`. |
| G-58 | §G subagent separators | `.suba + .suba{border-top:1px solid var(--hair)}` | no separator between subagent rows — only one hairline, above the todo block — observed `native-subagentsExpanded.png` | Med | Add the 1pt `white@0.08` divider between adjacent subagent rows. |
| G-59 | §G nest vertical rhythm | `.suba{padding:8px 11px}`, `.todos{padding:7px 11px 9px}`, `.todo{padding:3px 0}` | subagent rows measure roughly **2×** the mockup's rhythm; the nest ends up taller than the session body that owns it — observed | Med | Tighten to the CSS values; the nest is a subordinate surface and should read as one. |
| G-60 | §G stray todo counter | `.todos` has **no** header; the only count is `.nest-h .nn` ("3 active"). "2 of 5" is *caption* prose, not UI | native renders a right-aligned **`2 of 5`** line of its own between the subagent list and the todos — observed | Low | Drop it, or fold it into the nest header alongside `3 active`. |
| G-61 | §D expansion is not reachable on first click | "Tap a row to expand it in place" | the **first** click into the panel dismisses the whole overlay; expansion only fires once the pointer has already entered the surface (`move → dwell → click`). Reproduced 3× with warped-cursor clicks on both the row body and the chevron | **High** | Interaction bug with a direct visual cost: from the user's point of view "clicking a row closes the island". Likely `acceptsFirstMouse` / pointer-inside bookkeeping on the overlay panel. |
| G-62 | **§B hover peek does not exist** | pointer dwell 0.15 s → the silhouette grows and surfaces the one actionable session inline (`width:408px`, dot + title + mono command + `S5` tag + `Click to review & approve` + `+2 more sessions` chip) | hover is **scale-only**: `.scaleEffect(isHovering ? closedHoverScale : 1)` — `IslandPanelView.swift:395-404`. Measured live: pill outer width 277.5 → 286.5 pt (×1.032). No dwell timer, no content, no growth — `native-B-pill-rest.png` vs `native-B-hoverPeek.png` are identical apart from the scale | **High** | Whole §B state is unimplemented. It is also the mockup's answer to "the pill says nothing" (G-46/G-47) without needing the pill to grow permanently. |
| G-63 | I′ pill filament geometry *(code vs CSS — see §2 coverage note)* | `<circle r=9 stroke-width=2.4 pathLength=100 stroke-dasharray="75 100" transform="rotate(135)">` in a **15×15** box — a 270° gauge starting bottom-left, track `rgba(255,255,255,.14)` | full **360°** `Circle().trim(from: 0, to: fraction)` rotated −90°, `lineWidth 1.5`, **14×14**, track `paper@0.12` — `HaloClosedPill.swift:952-963` | Med | Match the 270° gauge, 2.4pt stroke, 15pt box. The header/meter filaments elsewhere already use the 270° form, so the pill is the odd one out. |
| G-64 | Empty state vs install hint | §J is the whole panel body: glyph → `All quiet` → sentence → `Monitoring` chip | in real mode an amber `⚠ No agent hooks installed — sessions won't surface events. Tap to set up.` banner + `SETUP ›` sits between the header and the empty state, pushing §J down and adding a second amber attention source — observed `native-real-emptyState.png` | Med | Not in the mockup at all. Either demote it to the footer lane or give it a Halo-native hairline treatment; as shipped it is the loudest thing in the calmest state. |
| G-65 | Completed-row duration | `.mv tnum` `14m 08s` | renders **`0m 00s`** on `completedFailed`, `completedInterrupted` and `longCompletionCard` — observed | Low | Duration is 0 whenever the turn has no recorded start; suppress the cell rather than print a zero. |

#### (b.1) Usage / quota UI — the dedicated subsection

| ID | Area / state | Mockup (exact CSS) | Native (observed / code) | Impact | Fix direction |
|---|---|---|---|---|---|
| G-28 | **§I meters card never reaches the overlay** | `.meterc{width:520px;border-radius:20px;padding:16px 18px 18px}` with `.meter-title` "USAGE", three 52px rings, 22px numerals, `resets in …`, threshold pills | `HaloUsageMeterCard` is a near-exact port but is only wired to `HaloIslandTheme.usageMeterCard` → **Appearance preview only** (`HaloTheme.swift:1085-1088`, `AppearanceSettingsPane.swift:1101-1105`). Overlay shows only header filaments (`native-usageMeters.png`) | **High** | Surface the meter card in the expanded panel (e.g. below the list, or as the `usage` disclosure). Highest parity-per-line-changed in the whole document — the component already matches. |
| G-29 | Header filament lane split | `.p-head`: **one** `.fil` in the left lane (`Claude 5h`), **one** in the right lane (`Claude 7d`) before the three `.ctl` buttons; `.ngap{width:96px}` between | **three** filaments (`CLAUDE 5H`, `CLAUDE 7D`, `CODEX 7D`) all in the left lane, right lane is buttons only — observed `native-usageMeters.png`; `HaloHeaderControls.swift:64-80` | **High** | Split: first window left, second right; overflow (3rd+) goes to the meter card (G-28), not the header. |
| G-30 | Threshold pill | `.thl{padding:1px 7px;border-radius:20px;font-size:9.5px;font-weight:700}` with tinted bg `rgba(95,227,154,.12)` / `(255,207,122,.13)` / `(255,107,107,.14)` | rendered as **bare coloured text**, 10/bold, no pill background — `HaloUsageMeterCard.swift:132-138` | Med | Wrap in a `Capsule` with the tint at 12–14% and `padding(.horizontal, 7).padding(.vertical, 1)`. |
| G-31 | Meter card body | `.isle .meterc` — pure `#000` body with the 1.5px edge ring | explicitly chromeless: no fill, no stroke, no radius — `HaloUsageMeterCard.swift:15-17` | Low | Only matters if G-28 places it as a standalone surface. |
| G-32 | Pill usage compression (I′) | `.wing r` shows the **reset countdown** (`19h`) | shows the **window label** (`7d`) instead — documented deviation, `HaloClosedPill.swift:925-934,971-974` | Med | Plumb `resetsAt` into the pill payload so the third token is the countdown, matching I′ and the header filament. |
| G-33 | Header filament ring size | `.fil svg{width:30px;height:30px}`, `stroke-width:2.2` | 30 (notch) / **22** (top bar), 2.2 — `HaloUsageSummary.swift:23-27`, `HaloHeaderControls.swift:37-39` | Low | Top-bar variant at 22 is a deliberate fit choice; leave unless the top-bar layout is in scope. |
| G-34 | Usage value ramp | card `.mp` **22px/660** threshold-coloured is the hero numeral; header `.fv` 11px `--t2` is the quiet one | header path is the *only* path, so the product never shows the 22px numeral — consequence of G-28 | **High** | Resolved by G-28. |

### (c) Colour / material / premium effects

| ID | Area / state | Mockup (exact CSS) | Native (observed / code) | Impact | Fix direction |
|---|---|---|---|---|---|
| G-13 | **Edge-light bloom is a lit stroke** | `.isle.work{box-shadow:0 0 26px -10px rgba(96,150,255,.45)}` — an *outer* shadow, spread `-10px`, **no coloured stroke**; the only coloured ring is the masked conic | bloom is drawn as a **second full-perimeter 1.5pt stroke** in the bloom colour plus a shadow — `HaloEdgeLight.swift:263-268` | **High** | Make the bloom layer shadow-only (transparent/near-zero-opacity stroke used purely as a shadow caster), so the visible ring is only the masked angular gradient. This single change is what turns the ring back into a hairline. |
| G-35 | Working off-band | conic `rgba(255,255,255,.05)` for `0–176°` + `348–360°` (≈52% of the ring) | matches: `hair2 = white@0.05`, same stops — `HaloEdgeLight.swift:385-389` | — | No change. Correct once G-13 lands. |
| G-36 | Perimeter → hero handoff | §E filmstrip: perimeter goes dark, the card ring becomes the only light | perimeter only drops to `perimeterOpenHandoffFloor = 0.55` — `HaloEdgeLight.swift:323`; both rings loud in `native-approvalCard.png` / `native-questionCard.png` | **High** | Lower the floor to ≈0.12–0.18 (matching `successOpacityEnd = 0.12`) and suppress the perimeter bloom entirely while a hero is presented. |
| G-37 | Hero outer glow radius | `.hero{box-shadow: … , 0 0 48px -8px rgba(255,140,80,.5)}` | radius **20** — `HaloTheme.swift:649` | Low | Raise toward 30–34 to match the 48px-blur/-8-spread feel, once G-36 lets it be the only glow. |
| G-38 | Question option chrome | `.opt{background:rgba(255,255,255,.022);box-shadow:inset 0 0 0 1px var(--hair2)}`; `.opt .num{background:rgba(255,207,122,.13);color:var(--qgold)}`; `.opt.sel{background:rgba(255,207,122,.1);box-shadow:inset 0 0 0 1.5px rgba(255,207,122,.55)}`; `.opt.sel .num{background:var(--qgold);color:#2a2003}` | achromatic: chip fill `white@0.045` / selected `paper@0.88`, ink `white@0.42` / `black@0.82`, border `white@0.08` — `IslandPanelView.swift:2726-2737` | **High** | Theme the option chip through the Halo seam: qgold @13% fill + qgold ink unselected; solid qgold + `#2a2003` ink selected; selected row gets a 1.5pt qgold@55% inset stroke. |
| G-39 | Question option hover | `.opt:hover{background:rgba(255,207,122,.07)}` | only the description opacity changes (0.38→0.48) — `IslandPanelView.swift:2745` | Med | Add the qgold@7% row wash on hover. |
| G-40 | Submit CTA disabled look | no disabled state; `.btn.primary` is always `linear-gradient(135deg,#ffce8a,#ffab54)` on `#3a2205` | `saturation 0.35 × opacity 0.5` → reads as a dead grey slab, the loudest element in the card — `IslandTheme.swift:450-452`, observed `native-questionCard.png` | **High** | Raise the disabled floors (e.g. `saturation 0.75`, `opacity 0.8`) or pre-select the first option so the CTA is live, so it never reads grey. |
| G-41 | "Other" option | `.opt-other{font-style:italic;font-size:12px;color:var(--t3)}`, achromatic dimmer number chip | renders identical to a normal option (13/600 white) — observed | Low | Italicise, drop to 12 @ `0.42`, keep the chip achromatic. |
| G-42 | Attention badge | `.cnt.hot{background:linear-gradient(135deg,var(--amber),var(--magenta));box-shadow:0 0 16px rgba(255,150,90,.6);min-width:20px;height:20px;font:12/700}` | matches exactly — `HaloClosedPill.swift:856-879` | — | No change. |
| G-43 | Status dot bloom | `.dot::after{inset:-3px;opacity:.55;filter:blur(2px)}` → 14px halo | matches: `dot+6 = 14`, `blur(2)`, opacity 0.55 / 0.35 failed / 0 idle — `HaloSessionRow.swift:1360-1364` | — | No change. |
| G-44 | Meta / jump chip fill | `.chip{background:rgba(255,255,255,.05)}`; `.jump:hover{background:rgba(80,170,255,.16)}` | fill matches (`hair2 = white@0.05`, `HaloSessionRow.swift:490,519`); jump hover tint unverified | Low | Verify the jump-chip hover picks up the cyan@16% wash. |
| G-66 | **§G subagent liveness is a static dot** | `.gly run sg` — the same three-bar wave as the pill, `width:15px`, `height:12px`, running colour | a plain filled cyan dot per subagent, no bars, no motion — observed `native-subagentsExpanded.png` | **High** | Three concurrently-running subagents render as three identical dead dots. Reuse the existing glyph (`HaloClosedPill.swift:404-406,484-488`) at 15×12. Highest-value single change in §G. |
| G-67 | I′ pill label tint *(code vs CSS)* | `<span class="dim">Codex</span> <b style="color:var(--crit)">94%</b>` — provider name **dim**, only the percent in crit | one `Text("\(providerTitle) \(percent)%")` painted entirely in `tint` — `HaloClosedPill.swift:966-969` | Med | Split into two runs so the red is spent on the number, not the vendor. Same "one loud thing" thesis as G-36. |
| G-68 | I′ pill filament glow *(code vs CSS)* | the 15px pill SVG has **no** filter; only the §I card's 52px ring gets `drop-shadow(0 0 5px rgba(255,107,107,.6))` | `.shadow(color: tint.opacity(0.6), radius: 3)` on the pill arc — `HaloClosedPill.swift:960` | Low | Drop the shadow on the pill-sized filament. |
| G-69 | `.assistant` / RESULT block tone | `.assistant{font-size:12.5px;line-height:1.55;color:var(--t2);box-shadow:inset 0 0 0 1px var(--hair2)}`, `code` chips `rgba(255,255,255,.07)` bg / `#c8d2e6` ink / 11px | body renders ≈14px near-`--t1` on a **filled** surface with no inset hairline; inline mono spans (e.g. `f196316` in `native-longCompletionCard.png`) render without the chip background | Med | Rich text itself works (markdown links + mono are rendered — `native-longCompletionCard.png`), so this is purely tone: 12.5 @ `--t2`, hairline instead of fill, and give inline code the 7 % chip. As shipped the last message is the loudest text in the row. |

### (d) Animation & motion

Every mockup animation, with its native status.

| ID | Mockup animation | Mockup spec | Native | Status |
|---|---|---|---|---|
| M-01 | `orbit` — working edge | `6s linear infinite`, conic `from var(--a)` | `.linear(6).repeatForever(autoreverses:false)` — `HaloEdgeLight.swift:159`, `HaloTheme.swift:333` | **Correct** (but invisible under G-13) |
| M-02 | `edgepulse` — permission | `1.9s ease-in-out infinite`, opacity `.55↔1` | `PulseClock` sine, period ≈1.963s, `0.55↔1.0` — `HaloEdgeLight.swift:175`, `PulseClock.swift:27,66` | **Correct** |
| M-03 | `edgepulse` — question | `2.6s ease-in-out infinite` | `.easeInOut(2.6).repeatForever(autoreverses:true)` — `HaloEdgeLight.swift:209` | **Correct** |
| M-04 | `edgepulse` — hero ring | `2.2s ease-in-out infinite` | `.easeInOut(2.2).repeatForever(autoreverses:true)` — `HaloSessionRow.swift:1789-1791` | **Correct** |
| M-05 | `bloompulse` — permission halo | box-shadow `20px -8` → `46px -4`, `rgba(255,140,80,.5)` → `rgba(255,120,90,.85)`, 1.9s | radius `lerp(8,21)`, opacity `lerp(0.50,0.85)` — `HaloEdgeLight.swift:481-485` | **Wrong magnitude** — radius peak 21 vs an effective ~42px blur; and it is applied to a *stroke* (G-13) |
| M-06 | `okedge` — success | `3s ease-out`, opacity `1 → .12` at 70% | `.easeOut(3)`, `lerp(1.0, 0.12)` — `HaloEdgeLight.swift:234`, `:448-450` | **Correct** |
| M-07 | `okbloom` — success bloom | `3s ease-out`, 40px→0, `rgba(95,227,154,.7)`→0 | opacity `lerp(0.70,0)`, radius `lerp(20,0)` — `HaloEdgeLight.swift:487-493` | **Correct** |
| M-08 | `wave` — liveness bars | `1.05s ease-in-out infinite`, 5px↔14px, delays `0 / .13 / .26` | `.easeInOut(0.525).repeatForever(autoreverses:true)`, delays `[0,0.13,0.26]` — `HaloClosedPill.swift:484-488`, `HaloTheme.swift:345,350` | **Correct** timing; wrong crest heights (see G-08) |
| M-09 | `breathe` — waiting glyph | `2.4s ease-in-out infinite`, height 6↔12, opacity `.5↔1`, **all three bars** | `.easeInOut(1.2).repeatForever(autoreverses:true)`, opacity `0.45↔1.0`, **middle bar dropped** (`waitH = 0`) — `HaloClosedPill.swift:405,489-494` | **Partly wrong** — restore the middle bar |
| M-10 | `breathe-dot` — waiting grid cell | `2s ease-in-out infinite`, opacity `.4↔1` | `.easeInOut(1.0).repeatForever(autoreverses:true)`, `0.4↔1.0` — `HaloClosedPill.swift:802-827` | **Correct** |
| M-11 | `rowsweep` — row entrance | `linear-gradient(100deg,transparent 34%,rgba(120,180,255,.14) 50%,transparent 66%)`, `translateX(-100%→100%)` | same stops/colour; `.easeOut(0.7)` one-shot — `HaloSessionRow.swift:1588-1619`, `HaloTheme.swift:341` | **Correct** (mockup's 3.4s is a looping demo) |
| M-12 | `morph` — pill↔panel container | demo: `3.6s cubic-bezier(.2,.7,.2,1)`, width/height/radius; B′ caption: "top radius 0→20, bottom radius pillHeight/2→20 as the frame grows; the orbiting edge-light never breaks — **one liquid black body, never a crossfade**" | `.spring(response:0.46, dampingFraction:0.86)` — `HaloTheme.swift:838` | **WRONG — resolved 2026-07-31.** Recorded at 60 fps (`halo-morph.mov`) and read frame-by-frame (`native-B-morph-open-frames.png`, `native-B-morph-close-frames.png`). The timing envelope is fine (~0.30 s to settle, no bounce); the *continuity* is not. Three independent breaks, split out as M-23/M-24/M-25 below. Net: it does not read as one black body — it reads as a translucent sheet inflating while its contents fade up. |
| M-23 | morph body opacity | "never a crossfade" — the silhouette is opaque `#000` throughout | the panel body is **translucent for the entire growth**: the desktop behind it (Safari address bar, page text) is legibly readable *through* the panel from the first morph frame until it settles — `native-B-morph-open-frames.png` frames 128–146 | **Wrong** — **the single most damaging morph defect.** Drive the body fill to full opacity *before* the geometry animation starts, or animate the geometry on an already-opaque layer. |
| M-24 | morph width continuity | width interpolates from the pill's width to the panel's | width **jumps** from the ≈278 pt pill to ≈430 pt in a single 16 ms frame, then animates 430 → 520 over the remaining ~0.28 s. The pill silhouette never visually becomes the panel — `native-B-morph-open-frames.png` frames 126→128 | **Wrong** | Start the width interpolation at the measured closed-pill width, not at an intermediate layout width. |
| M-25 | morph content entrance | filmstrip grows an **empty** silhouette (frames 1·pill → 2·peek → 3·panel carry no content) | all panel content — usage filaments, install hint, empty-state block — is laid out at its **final** position from the first morph frame and simply fades its opacity up | **Wrong** | Gate the content on the geometry settling (or fade it in after ~0.6 of the spring), so the container reads as a growing object rather than a dissolving one. |
| M-26 | close morph | the reverse of the open — same body, same continuity | height collapses over ≈8 frames (~0.13 s — noticeably faster than the ~0.30 s open, so the pair is asymmetric); content stays at **full size** and fades rather than compressing; the body is translucent throughout, same as M-23 — `native-B-morph-close-frames.png` | **Wrong** | Match the open envelope and fix the opacity with M-23. |
| M-27 | `.pill` hover-peek transition | 0.15 s dwell → the pill grows into the peek surface | no dwell timer and no peek at all (G-62); the only hover motion is `.spring(response:0.38, dampingFraction:0.8)` on the 1.03 scale — `IslandPanelView.swift:400-404` | **Absent** — the scale itself is correct (M-16), the state it is supposed to introduce is missing |
| M-28 | §G subagent liveness | `.gly run sg` waves at `1.05s ease-in-out infinite` per subagent | static dot, no animation (G-66) | **Absent** — three running subagents render as three still dots |
| M-13 | `.row:hover` wash | `background rgba(255,255,255,.026)`, `transition .15s` | `white@0.026`, `.easeInOut(0.14)` — `HaloSessionListScaffold.swift:35`, `HaloSessionRow.swift:211` | **Correct** |
| M-14 | `.dismiss` hover reveal | `opacity 0→1`, `scale .82→1`, `transition .14s` | identical — `HaloSessionRow.swift:468-470` | **Correct** |
| M-15 | `.ctl` hover | bg `.06→.14`, `transition .15s` | identical — `HaloHeaderControls.swift:175-176,199` | **Correct** |
| M-16 | `.pill.hoverlift` | `transform: scale(1.03)` | `closedHoverScale = 1.03` — `HaloTheme.swift:826`, `IslandPanelView.swift:395` | **Correct** |
| M-17 | `.opt:hover` | `background rgba(255,207,122,.07)`, `.14s` | **missing** (see G-39) | **Absent** |
| M-18 | `.btn.primary:hover` | `filter: brightness(1.06)` | not found | **Absent** (Low) |
| M-19 | `.scope:hover` | `background rgba(255,160,80,.08)`, icon → amber, `.14s` | **the whole element is missing** (G-21) | **Absent** |
| M-20 | Attention light *travels* (§E filmstrip) | perimeter → silhouette → card ring; perimeter goes dark | perimeter floors at 0.55, no directional handoff — `HaloEdgeLight.swift:323` | **Wrong** (see G-36) |
| M-21 | List insert / reorder / removal | implied by §C grouping + §K "content is still, light moves" | `HaloSessionListScaffold.swift` has **zero** `.animation` / `.transition` / `withAnimation` | **Absent** — **this is the "missing animations" complaint.** Add an `.animation(.easeInOut(0.22), value: sessionIDs)` + `.transition(.opacity.combined(with:.move(edge:.top)))` on rows. |
| M-22 | Usage arc reveal | none (static SVG) | `.easeOut(0.6)` appear sweep + `.easeInOut(1.6).repeatForever` critical breathe — `HaloUsageSummary.swift:157,161` | **Native addition** — keep, it is on-thesis |

### (e) Copy / content presentation (visual read only)

| ID | Area | Mockup | Native (observed) | Impact | Fix direction |
|---|---|---|---|---|---|
| G-45 | Working pill right wing | `.agrid` — 3×2 grid of 6px dots, running ones cyan with `box-shadow 0 0 5px rgba(80,180,255,.7)` | `×9` count badge (11pt mono) — the agents grid exists (`HaloClosedPill.swift:728-796`) but the default right-slot preference resolves to `.count` | **High** | Make the agents grid the default right-slot content for Halo when >1 session is running. |
| G-46 | Working pill label | "3 working" / "Editing `AppModel.swift`" | no label rendered — centre is empty | **High** | Consequence of G-20 (pill too narrow); the resolver already produces the strings (`IslandClosedLabelResolver.swift:190,196`). |
| G-47 | Permission pill label | "Approve `swift build`?" | no label — dot + `1` badge only | **High** | Same as G-46. |
| G-48 | Hero subtitle | narrated: "the-automator wants to run a command" | verbatim repeat of the row line above it | Med | See G-22. |
| G-49 | Done-row activity | narrated summary: "Updated `AGENTS.md` & `CLAUDE.md` with the new worktree workflow" | raw last-assistant-message text (fixture-dependent) | Low → **Med** | **Not a fixture artifact** — see the real-data addendum below. Every non-lead row in every scenario prints the raw last assistant message verbatim, truncated with `…`. |
| G-70 | §G collapsed-row title | `.tl` = `.ws` *the-automator* + a `.disamb` chip reading **`3 subagents`** | workspace title alone; "3 subagents" is folded into the *activity* sentence ("Orchestrating 3 subagents") and the disamb slot is left empty — observed `native-subagentsCard.png`, `native-subagentsExpanded.png` | Low | Put the fan-out count in the disamb chip and let the activity line narrate the actual work. |
| G-71 | Row `.disamb` prints the age, not the branch | `.disamb` = branch glyph + branch **name** (`main`), and the age lives in the right-hand `.age` slot | rows render branch-glyph + **`3m ago`** next to the title *and* a separate `3m` at the row's right edge — the age is printed twice and the branch name never appears in the collapsed row — observed `native-subagentsCard.png`, `native-rowDetail-collapsed.png` | Med | The branch name *is* available (the expanded row shows `feat/theme-halo`). Put it in the disamb chip and drop the duplicate age. |
| G-72 | Question hero head stacking | `.hero-head`: title + `niche-radar · OpenCode` subtitle, with `.qprog` `1 of 2` **right-aligned on the same line**; `.q-tag` inline with an optional `multi-select` chip | four stacked left-aligned lines before the question text: gold title, bold `Question 1 of 2`, bold `Auth`, then the question — plus the `AUTH` tag on its own oversized line — observed `native-multiQuestionCard.png` | Med | Sharpens G-23/G-24 with the multi-question capture: the vertical bloat is the visible symptom, not just the missing progress token. |
| G-73 | Codex approval CTA is un-themed | `.btn.primary{background:linear-gradient(135deg,#ffce8a,#ffab54);color:#3a2205}` — amber, always | `Jump to Codex` renders as a solid **light-blue** gradient slab inside an amber attention hero — observed `native-codexApprovalCard.png` | Med | Two competing accent hues in the one card the user must act on. Route the CTA through the Halo amber seam (same fix family as G-40). |
| G-74 | Completed-row copy duplication | row line narrates; the RESULT block carries the message | the row's one-line summary and the RESULT block print the **same string verbatim** on `completedFailed` / `completedInterrupted`; on `longCompletionCard` the row line is raw markdown source (`[README.md](/Users/…/open-island/R…`) — observed | Med | Same shape as G-22/G-48. The row should narrate, the block should quote — and the row must render (or strip) markdown rather than showing its source. |

#### (e.1) Real-data addendum (2026-07-31)

The owner asked for a pass with the app in real discovery mode (no
`OPEN_ISLAND_HARNESS_SCENARIO`, just `-appearance.island.v8.theme halo`).

**What real mode actually showed.** After ~50 s, and again after driving a fresh
`claude -p "say hi"` turn from `/tmp`, the panel stayed on **`All quiet — No active
agent sessions`** (`native-real-emptyState.png`, `native-real-sessionList.png`). The
panel itself explains why: `⚠ No agent hooks installed — sessions won't surface events.`
Discovery in this build is hook-driven, and this checkout's binary has no hooks
installed. Installing them is a change to the user's config, so per the brief the
pipeline was **not** debugged further.

Two things real mode *did* settle:

- **Real usage data reaches the header, and it reproduces G-29 exactly.** Three live
  filaments — `CLAUDE 5H 3% · 3h 42m`, `CLAUDE 7D 59% · 2d 5h`, `CODEX 7D 21% · 5d 10h` —
  all crammed into the **left** lane, right lane buttons only. The mockup splits one per
  lane. Real data also confirms G-54: the value line carries percent *and* countdown.
  Hovering a filament pops a native tooltip (`Claude 7d 59%, resets in 2d 5h`) that the
  mockup expresses as the meter card's `resets in …` line — more evidence for G-28.
- **Real usage is nowhere near the I′ threshold** (max 59 %), which is the fourth
  independent reason I′ could not be captured.

**G-49 is a real gap, not a fixture artifact.** `DebugSessionFactory`
(`IslandDebugScenario.swift:353-421`) is not synthetic filler — it is a transcript-shaped
fixture set (real workspaces, real bilingual last-assistant messages). Native renders
those messages **verbatim and truncated** as the row's activity line in every state:
`整理完了，已经提炼出和 autoreserach 相关的几段…`, `PR 已经提好了：`,
`[README.md](/Users/wangruobing/Personal/open-island/R…`. The mockup's rows never show a
raw message — they show a *narration* ("Updated `AGENTS.md` & `CLAUDE.md` with the new
worktree workflow"). Nothing about that changes with live data, so G-49 is upgraded from
Low to **Med** and G-74 records the duplication it causes.

**Layout consequences of real-shaped content** (visible across every capture):

- Rows carry **no meta chips at all** (model / permission mode / elapsed) unless the
  session is the actionable lead — confirming G-11 against realistic data, not just the
  three hand-authored rows the first pass saw.
- Workspace titles fall back to the bare directory name (`Personal`, `hooks`, `agents`,
  `claude-code`) with no branch disambiguation (G-71), so the mockup's "duplicate
  the-automator disambiguated by branch" story never appears.
- The expanded row's working-directory readout can be another machine's home
  (`/Users/wangruobing/…nal/claude-research`) middle-truncated — the mockup's
  right-aligned mono `~/Developer/open-vibe-island` assumes a tilde-relative path.
- CJK last-message text sets the row's line height, so real rows are visibly taller than
  the mockup's Latin-only §C rhythm.

---

## 4. Quick-win ordering

Ranked by visual-parity gain per unit of change.

1. **G-13** — make the edge bloom shadow-only. One layer in `HaloEdgeLight.swift:263-268`.
   Instantly converts every state from "glowing outline" to "black body with a light segment",
   and un-hides the row rails (G-10). Biggest single-change payoff in the document.
2. **G-28** — surface `HaloUsageMeterCard` in the expanded panel. The component is already a
   near-exact port of §I; this is wiring, not design. Fixes the owner's headline complaint and
   resolves G-34 for free.
3. **G-01** — `tertiaryTextOpacity: 0.50 → 0.42`. One token; quiets ages, meta, section headers,
   usage kickers and the footer simultaneously.
4. **G-09** — force grouped presentation for Halo's list + right-align the group count.
   Restores the entire §C hierarchy (Needs You → Running → Done) that the code already builds.
5. **G-36** — drop `perimeterOpenHandoffFloor` to ~0.15 and kill the perimeter bloom while a
   hero is up. Restores "one loud thing at a time" across permission and question.
6. **G-38 + G-40** — theme the question option chip in qgold and stop the Submit CTA rendering
   grey. Two localised edits that fix the card the owner called out.
7. **G-29** — split header filaments one-per-lane; push the third to the meter card. Fixes the
   crowded header without new components.
8. **G-18 + G-20 + G-46/47** — give the pill a 38pt body and enough width to carry its label.
   Turns the collapsed state from "a tint on the notch" into the mockup's object.
9. **G-02 / G-03** — lower the micro-type floor (or its weight/opacity). Restores the bottom of
   the type ramp; cheap, and directly answers "inconsistent font sizes".
10. **M-21** — add list insert/reorder/removal animation in `HaloSessionListScaffold`. Cheapest
    fix for "missing animations", since every *other* animation in the theme is already correct.
11. **G-11 + G-12** — populate the row meta chips, hide the chevron at rest. Restores row
    density without changing the row's geometry.
12. **G-45** — default the right wing to the agents grid for multi-session working.
13. **G-30 / G-41 / G-08 / M-09 / G-16 / G-26** — small polish batch (threshold pill, "Other"
    italic, glyph crest heights, waiting middle bar, bucket dot, empty-state rhythm).

### Additions from the 2026-07-31 pass 2

Only three of the new gaps earn a place in the top tier; the rest slot in behind item 13.

- **After item 2 (G-28)** — **G-55**: give the §D/§H metadata grid its `.mcell` chrome
  (9pt radius, `hair2` inset stroke, 8/11 padding, wrapping flex). One container change,
  and it is the difference the owner reads as "the row detail is completely off from the
  design". Pairs naturally with **G-50** (9/700@.42 keys, 12.5/560 values), which is the
  same `HaloTypography.floor` fix already queued as G-02.
- **After item 5 (G-36)** — **M-23**: make the morphing panel body opaque before the
  geometry animates. Every other morph defect (M-24/M-25/M-26) is a refinement; this one
  is why the transition reads as a dissolve instead of a solid object. Cheapest of the
  four, largest share of the "it doesn't feel liquid" complaint.
- **Alongside item 10 (M-21)** — **G-66 / M-28**: swap the §G subagent dot for the
  existing three-bar liveness glyph. The component already exists in `HaloClosedPill`;
  it is the only thing making three concurrently-running subagents look inert.

Everything else from pass 2 is polish or follow-on work: **G-56/G-57** need the same
row-data plumbing as G-11; **G-61** is an interaction fix (first click into the panel
dismisses it) that should be filed as a bug rather than a styling ticket; **G-62/M-27**
(the §B hover-peek state) is net-new UI, not a delta, and should be scoped separately;
**G-63/G-67/G-68** (I′) should not be touched until a closed-notch + critical-usage
harness scenario exists to verify them by eye.
