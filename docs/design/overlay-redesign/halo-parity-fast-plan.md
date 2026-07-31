# Halo — fast visual-parity implementation plan (view-scoped)

Date: 2026-07-31 (v2 — reorganized by view)
Input: [`halo-parity-gap-analysis.md`](./halo-parity-gap-analysis.md) (gap IDs G-01…G-74, M-01…M-28)
Reference: [`06-halo.html`](./06-halo.html)

## 1. Philosophy (read this first)

This plan supersedes the process in `halo-visual-parity-audit.md` for day-to-day execution.
No gates, no masks, no calibration, no goldens, no per-change test runs.

- **One view at a time.** Each batch below is one view/surface. It carries EVERY gap that view
  owns — typography, layout, color, motion — so the view is fixed once, validated once, and
  locked. Never fix a view's gaps from inside another view's batch.
- **The parity gate is a vision check.** After each batch, an agent looks at the live view
  next to its mockup section and judges "same or not". Only a PASS on that view advances the
  plan. A locked view is not revisited unless a later batch visibly regresses it.
- **Minimum change wins.** Most gaps are token edits or wiring — prefer the one-line fix over
  any refactor. Never restructure a view to "do it properly" if a value change gets the look.
- **Tests are not a gate.** Compile + visual check per batch. If a Halo unit test asserts a
  token value you changed, update the assertion in the same commit — mechanically, without
  running the suite. One `swift test` pass happens once, at the very end.
- **Time-box iteration.** Max 3 implement→look cycles per batch. Still failing? Record the
  remaining delta in §5, move on, surface to the owner at the end.

The one exception to view-scoping is **V0 Foundations**: three genuinely global tokens (edge
bloom rendering, tertiary opacity, micro-type tier) that every view inherits. V0 lands first
with a spot-check only; every later view gate re-validates the foundations in that view's
context.

Out of scope entirely: the `HaloParity*.swift` harness files, `tools/halo_parity/`,
`Validation/HaloParity/`, goldens, reduced-motion variants.

## 2. The verification loop (used after every batch)

Build once per batch (warm `.build`, never clean):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build --disable-automatic-resolution --disable-sandbox -c debug --product OpenIslandApp
```

Launch the state(s) the batch touched:

```bash
OPEN_ISLAND_HARNESS_SCENARIO=<scenario> \
OPEN_ISLAND_HARNESS_PRESENT_OVERLAY=1 \
OPEN_ISLAND_HARNESS_BOOT_ANIMATION=0 \
OPEN_ISLAND_HARNESS_START_BRIDGE=0 \
OPEN_ISLAND_HARNESS_SUPPRESS_INSTALL_HINT=1 \
OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS=30 \
  ./.build/arm64-apple-macosx/debug/OpenIslandApp -appearance.island.v8.theme halo
```

Scenarios: `closed`, `closedAttention`, `sessionList`, `usageMeters`, `approvalCard`,
`questionCard`, `completionCard`, `emptyState`, `subagentsCard`, `subagentsExpanded`,
`diffApprovalCard`, `codexApprovalCard`, `multiQuestionCard`, `longCompletionCard`,
`completedInterrupted`, `completedFailed` (full list: `IslandDebugScenario.swift`).
Raise `AUTO_EXIT_SECONDS` to 120 when the check needs interaction (hover, row click, morph).

Interaction driving: a bare `CGEvent(.mouseMoved)` post does NOT move the cursor, so
`.onHover` never fires. Use `CGWarpMouseCursorPosition` to hover/click (working helper:
`mouse.swift` in the session scratchpad — copy it forward). For morph/motion judgments,
record `screencapture -v -V 6 out.mov` around the open/close and scrub frames.

Then the vision check, done by an agent with computer-use / screenshot ability:

1. `screencapture` the live overlay (crop to the island surface).
2. Compare against the reference screenshot for that view in
   `artifacts/halo-parity/analysis-2026-07-31/ref-*.png` (re-screenshot `06-halo.html` in a
   browser only if a finer crop of a sub-element is needed).
3. Verdict per checklist item: **PASS** (visually the same composition, weight, color,
   size — not pixel-identical; WebKit vs SwiftUI text rendering differs) or **FAIL** with a
   one-line description of what still differs.
4. For animation items, watch at least one full cycle (or trigger the event) and judge by
   eye against the mockup's animated board / §K spec.
5. Save the native screenshot as
   `artifacts/halo-parity/analysis-2026-07-31/after-<batch>-<state>.png`.
6. Re-confirm in passing that the V0 foundations hold in this view (hairline edge, quiet
   tertiary tier) and that previously locked views visible in the frame didn't regress.

A batch is done when every item on its checklist is PASS or explicitly parked in §5.

## 3. View batches, in order

Every gap ID from the analysis is assigned to exactly one batch. Details (exact CSS values,
`file:line`) live in the analysis doc — read the cited rows before editing. Batches are
mostly independent; V0 must be first, V4 before V5/V6 (they live inside rows), V1 before V2
(the pill's I′ gauge and the meter card share usage plumbing).

---

### V0 — Foundations (global tokens; spot-check only)

Gaps: **G-13, M-05, G-01, G-02, G-03** (+ G-35, G-42, G-43 are already correct — don't touch).

Files: `HaloEdgeLight.swift`, `HaloTheme.swift`.

- G-13: the edge bloom is a second full-perimeter lit stroke (`HaloEdgeLight.swift:263-268`);
  make it shadow-only so the visible ring is only the masked angular gradient. This is what
  turns every state from "glowing outline" back into "black body with a hairline".
- M-05: permission bloom pulse radius peak ~21 → ~42 (safe once shadow-only).
- G-01: `tertiaryTextOpacity 0.50 → 0.42` — quiets ages/meta/headers/kickers/footers everywhere.
- G-02/G-03: restore the 9/9.5px micro tier (or keep floor 10 but `.medium` @ 0.42) so
  micro-labels stop competing with body copy.

Spot-check gate (`closed`, `sessionList` vs `ref-A`/`ref-C` — full validation happens per view):
- [ ] Working pill reads as a black body with a moving bright segment, not a glowing outline.
- [ ] Panel border is a hairline; tertiary text visibly quieter than body text.

### V1 — Usage surfaces: header filaments + §I meter card

The owner's headline complaint. Gaps: **G-28, G-34, G-29, G-54, G-30, G-31, G-05** (G-33: leave).

Files: `HaloUsageMeterCard.swift`, `HaloHeaderControls.swift`, `HaloUsageSummary.swift`,
mount point in `HaloSessionListScaffold.swift` / panel body. Mockup section §I.

- G-28/G-34: mount the existing `HaloUsageMeterCard` in the expanded panel (usage
  disclosure / below the list) — it's already a near-exact §I port; this is wiring. The 22px
  threshold-colored numerals finally reach the product.
- G-29: header filaments one-per-lane (first window left of notch, second right); 3rd+
  windows live only in the meter card.
- G-54: header filament value = percent only, 11 @ t2 (drop the `· 2h 9m` bold pack).
- G-30: threshold labels become tinted capsule pills (bg 12–14%, `9.5px/700`).
- G-31: card body chrome per `.meterc` if mounted standalone. G-05: meter label 12.5 → 12.

Visual gate (`usageMeters` vs `ref-I-usage-meters.png`, `native-usageHeader-zoom.png` as before):
- [ ] Meter card in the overlay: 52px rings, 22px colored numerals, `resets in …`,
      FINE/WARN/CRITICAL capsule pills.
- [ ] Header: one filament per lane around the notch, percent-only values.

### V2 — Collapsed pill (§A states, §B hover-peek, I′ compression)

Gaps: **G-18, G-19, G-20, G-46, G-47, G-45, G-08, M-09, G-62/M-27, G-32, G-63, G-67, G-68**.

Files: `IslandPanelView.swift`, `HaloClosedPill.swift`, `V6ClosedPillShape.swift`,
`IslandRightSlotResolver.swift`, `IslandDebugScenario.swift` (enabler). Mockup §A/§B/I′.

- G-18/G-19: pill height `notchHeight + 12` (floor 38) → bottom radius 19 — the pill becomes
  a body hanging below the notch, not a notch tint.
- G-20 + G-46/G-47: raise working/attention min-width so the resolver's labels ("3 working",
  "Approve `swift build`?") actually render.
- G-45: agents grid (not `×9` count) as default right slot when >1 running.
- G-08: uniform liveness crest 14. M-09: restore the middle bar in waiting breathe.
- G-62/M-27: hover-peek — dwell >0.15s reveals the actionable/narrated peek content per §B
  (scale 1.03 already correct).
- I′ compression: G-32 reset countdown (`19h`) not window label; G-63 270° gauge
  (`dasharray 75 100`, rotate 135°, 2.4pt, 15px); G-67 tint the value, dim the provider;
  G-68 drop the stray `shadow(radius:3)`.
- **Enabler (allowed infra, ~10 lines):** add a `closedCritical` scenario (closed notch,
  0 running, one window ≥90%) — today no scenario can show I′ (`usageMeters` pins the panel
  open and its running session outranks usage in `IslandRightSlotResolver.swift:128-145`).

Visual gate (`closed`, `closedAttention`, `closedCritical`; pointer-driven; vs
`ref-A-pill-states.png`, `ref-B-hoverpeek-morph.png`, `ref-I-usage-pill.png`):
- [ ] 38pt pill body, 19pt corners, visibly hanging below the notch.
- [ ] Working: glyph + "N working" + bloomed agents grid. Permission: narrated approve label.
- [ ] Dwell >0.15s shows peek content, not just a scale bump.
- [ ] Critical usage: 270° gauge, dimmed provider, tinted value, reset countdown.

### V3 — Panel shell: open/close morph + header/footer chrome

Gaps: **M-23, M-24, M-25, M-26, G-61, G-14, G-07, G-17 (decide)**.

Files: `IslandPanelView.swift`, `OverlayPanelController.swift`, `HaloTheme.swift` (morph
tokens), `HaloHeaderControls.swift`, footer in `HaloSessionListScaffold.swift`. Mockup §B′/§K
+ §C chrome. Timing envelope (~0.30s spring, no bounce) is already right — don't retune first.

- M-23: body is **translucent during the entire growth** (desktop readable through it) — the
  most damaging break. Surface stays opaque black throughout.
- M-24: width jumps 278→430pt in one frame before animating — animate from the pill's frame.
- M-25: content is at final positions from frame 1 and opacity-crossfades — content should be
  revealed by the growing surface (clip/mask), not crossfaded.
- M-26: close is ~0.13s vs 0.30s open with a full-size content fade — make close the reverse
  of open.
- G-61 (**interaction bug**): first click inside the panel dismisses the overlay; row
  expansion only fires after a pointer-enter. Fix the click/dismiss hit-testing.
- G-14: header top padding 2 → 10. G-07: footer 11pt regular @ 0.42, left-aligned, top
  hairline. G-17: keep 540 (notch clearance) unless it looks wrong side-by-side — owner call.

Visual gate (record `closed`→open→close with `screencapture -v`, scrub frames vs §B/§K and
`halo-morph.mov`; `sessionList` for chrome):
- [ ] One opaque continuous black silhouette both directions; no through-transparency, no
      single-frame size jump, no content crossfade; close mirrors open.
- [ ] First click on a row expands it — never dismisses the overlay.
- [ ] Header breathes below the notch; footer is quiet, left-aligned, hairlined.

### V4 — Session list (§C)

Gaps: **G-09, G-06, G-15, G-16, G-11, G-12, G-71, M-21** (+ verify G-10 rails, M-13, M-11).

Files: `HaloSessionListScaffold.swift`, `HaloSessionRow.swift`. Mockup §C.

- G-09: force grouped presentation — NEEDS YOU → RUNNING → DONE headers render live, color
  dot, count right-aligned via `Spacer()`.
- G-06: drop/demote the `SESSIONS` strip title. G-15: summary strip top hairline + intrinsic
  height. G-16: bucket dot 6.
- G-11: populate row meta chips (model / mode / elapsed) on running rows — slot exists.
- G-12: chevron hidden at rest, hover-reveal. G-71: `.disamb` prints the branch, not a second
  copy of the age.
- M-21: `.animation(.easeInOut(0.22), value: sessionIDs)` + `.transition(.opacity.combined(
  with: .move(edge: .top)))` on rows — the "missing animations" complaint for the list.
- Verify-only: G-10 rails now visible (post V0), M-13 row hover wash, M-11 entrance sweep.

Visual gate (`sessionList`, pointer-driven, vs `ref-C-expanded-panel.png`):
- [ ] Group headers with dot + right-aligned count; attention group on top; rails visible.
- [ ] Rows carry meta chips + branch; no chevron at rest; density matches §C.
- [ ] Rows fade/slide on insert/reorder instead of hard-cutting (judge live).

### V5 — Row detail + completed session (§D / §H)

Gaps: **G-55, G-56, G-50, G-57, G-69, G-74, G-65, G-60, G-49** (+ verify G-44).

Files: `HaloSessionRow.swift` (detail expansion), completion card views. Mockup §D/§H.

- G-55: metadata grid gets its `.mcell` chrome — 6 boxed chips, not bare text. The single
  biggest reason row detail "looks nothing like the design".
- G-56: render the missing fields (Model / Permission / Branch).
- G-50: metadata type ramp — `.mk` 9/700 @ 0.42 keys, `.mv` 12.5/560 values; metadata must
  not out-shout the row title.
- G-57: action row — live `Transcript` on detail; `Reply`/`Dismiss` on completed; copy
  "Jump to Ghostty" not "Jump · Ghostty".
- G-69: RESULT/assistant block 12.5 @ t2 on hairline (not 14 near-t1 on a fill); inline code
  gets its 7% chip.
- G-74: never print the same string in the row line AND the result block; render markdown,
  never raw source. G-65: no `DURATION 0m 00s`. G-60: drop the stray `2 of 5` line.
- G-49: activity line is a narrated summary, not the raw truncated last assistant message
  (confirmed real behavior, not a fixture artifact).

Visual gate (`sessionList`+click, `completionCard`, `longCompletionCard`,
`completedInterrupted`, `completedFailed` vs `ref-D-rowdetail.png`, `ref-H-completed.png`):
- [ ] Expanded row: boxed 6-chip metadata grid, all fields, quiet keys, calm result block.
- [ ] Completed variants: correct actions, no zero-duration, no duplicated text.

### V6 — Subagents nest (§G)

Gaps: **G-66/M-28, G-51, G-52, G-53, G-58, G-59, G-70**.

Files: subagent/task nest views inside the row (see `native-subagentsExpanded.png`). Mockup §G/G′.

- G-66/M-28: subagent liveness = the 3-bar wave glyph, not a static dot.
- G-51/G-52/G-53: nest type ramp to spec — header 10/700 @ t3; type/task/elapsed 12/11/11;
  `in progress` tag 10px.
- G-58: hairline between subagent rows. G-59: halve the nest vertical rhythm — the nest must
  not be taller than the body that owns it. G-70: fan-out count in the `.disamb` slot, not
  folded into the activity sentence.

Visual gate (`subagentsCard`, `subagentsExpanded` vs `ref-G-subagents.png`):
- [ ] Nest reads as a quieter child tier: smaller type, tighter rhythm, animated liveness.

### V7 — Permission hero (§E: command, diff, Codex)

Gaps: **G-36/M-20, G-37, G-21/M-19, G-22/G-48, G-27, M-18, G-73**.

Files: hero view(s) in `IslandPanelView.swift` / Halo hero components, `HaloEdgeLight.swift`
(handoff floor), `HaloTheme.swift` (hero glow). Mockup §E.

- G-36/M-20: `perimeterOpenHandoffFloor 0.55 → ~0.15` + suppress perimeter bloom while a hero
  is shown — light travels INTO the card; one loud thing.
- G-37: hero outer glow radius 20 → ~32 (now that it's the only glow).
- G-21/M-19: render scoped-grant rows (`.scopes` spec: amber code chip, keycap, hover wash).
- G-22/G-48: stop duplicating the row's sentence — hero subtitle becomes the narration.
- G-27: command block never wraps (horizontal scroll or middle-truncate).
- M-18: primary button hover brightness 1.06. G-73: Codex CTA amber, not light-blue.

Visual gate (`approvalCard`, `diffApprovalCard`, `codexApprovalCard` vs
`ref-E-permission-hero.png`):
- [ ] Hero is the single loud thing; perimeter near-dark.
- [ ] Scoped-grant rows present; no duplicated headline; command on one line; CTAs amber.

### V8 — Question card (§F)

Gaps: **G-38, G-39/M-17, G-04, G-40, G-41, G-23, G-24, G-25, G-72**.

Files: option row seam in `IslandPanelView.swift`, `IslandTheme.swift`, question hero view.
Mockup §F. Theme via the Halo seam — don't restyle other themes.

- G-38: qgold option chips — 13% fill + qgold ink; selected = solid qgold + `#2a2003` ink +
  1.5pt qgold@55% inset stroke.
- G-39/M-17: qgold@7% row hover wash. G-04: label 0.95 / desc 0.63 with `lineLimit(2)`.
- G-40: disabled CTA floors up (sat 0.75 / op 0.8) or pre-select first option — the CTA must
  never read grey.
- G-41: "Other" italic 12 @ 0.42. G-23: workspace·agent subtitle + `n of m` progress.
- G-24: inline tag row + `multi-select` chip. G-25: CTA first, hint beside it, keycaps.
- G-72: hero head is title + subtitle + right-aligned `1 of 2`, not a 4-line stack.
- Re-check the V7 perimeter handoff in the question state.

Visual gate (`questionCard`, `multiQuestionCard` vs `ref-F-question.png`):
- [ ] Card reads qgold-warm; selected option unmistakably amber; CTA never grey.
- [ ] Head: title + subtitle + progress; footer: CTA then keycap hint.

### V9 — Empty state (§J) + final sweep

Gaps: **G-26, G-64 (decide)** + everything parked in §5.

- G-26: empty-state spacing 6/15 (`HaloEmptyState.swift`).
- G-64: the amber install-hint banner in real mode isn't in mockup §J — owner call whether
  to restyle or keep.
- Clear the §5 parked list or hand its remainder to the owner.

Final gate — full side-by-side pass of **all scenarios** (including subagents, row detail,
morph recording, completed variants) vs all `ref-*.png`, judged by a fresh vision agent that
did not implement anything. Its verdict list is the completion report to the owner.

Then, once: `DEVELOPER_DIR=… swift test` (expect the 5 known-red session-list/grid failures —
pre-existing, time-dependent, not caused by this work). Fix only Halo assertion mismatches
introduced by token changes. Squash-merge to main per repo convention.

## 4. Execution notes for agents

- One batch = one view = one agent (or one agent pair: implement + fresh-eyes visual judge).
- Subagents run as the `opus5` agent type (Claude Opus 5, reasoning effort medium — set in
  `.claude/agents/opus5.md`).
- Every batch commit message cites its view + gap IDs.
- Don't touch: other themes' look, the parity-harness files, the mockup, the audit doc, and
  — above all — views already locked by an earlier batch.
- The mockup's CSS is ground truth for values; the gap analysis has exact `file:line`
  targets — read the relevant analysis rows before editing, not the whole doc.
- If a harness scenario doesn't show what you need, do NOT build new state-driving
  infrastructure beyond the one sanctioned `closedCritical` enabler (V2) — park the item in §5.

## 5. Parked items (append during execution)

| Batch | Gap ID | Remaining delta | Why parked |
|---|---|---|---|
| V2 | G-20/G-46/G-47 (R2: **RESOLVED**) | — | Owner sanctioned touching the shared lane. The 84pt cap was never a physical fact — it was a guess. Replaced by `V6ClosedPill.notchLaneLabelWidth(physicalNotchWidth:height:)`: the lane the hardware actually admits before the closed pill would outgrow the opened panel, i.e. `(macbookMaxOuterWidth − notchWidth)/2 − (pad + glyph + 4 + 6)`, floored at the original 84 so no display can ever get *less* lane. `macbookMaxOuterWidth` (540) is now the single source of truth `OverlayPanelController.preferredNotchOpenedPanelWidth` reads, so the closed silhouette can never be wider than the panel it grows into (the §B′ law: the shape only ever *grows*). Measured live on this MacBook: cutout **193.5pt**, Halo pill 38pt → lane **84 → 120.25**. All six themes route through it (`V6NotchContent` + the five theme pills); short labels and label-less pills are byte-identical (`hi` and `nil` goldens unchanged in `PouredClosedPillWidthRegressionTests`), only the long-label golden moved 454 → 540 and was reconciled in the same commit. Six-theme guard, `closed` + `closedAttention`, label forced on: `after-R2-lane-sixtheme-{closed,closedAttention}.png` — every theme renders more of its label, none overflows the cutout (poured, the widest, ends 4pt clear at 655.25 vs the cutout's 659.25 edge). Pinned by `HaloClosedPillWidthRegressionTests.notchLaneLabelWidthIsBudgetedFromTheHardware` |
| V2 | G-46/G-47 residual (**owner call**) | On a MacBook the pill still ships label-less by default — not because the lane truncates (fixed above) but because `AppModel.loadAppearancePreferences` defaults the **notch** profile's `centerLabel` to `.off` (`AppModel.swift:733-743`, AB-241's "an untouched install must keep looking exactly as it did"). Flip it to `.agentAction` and the board's §A pill speaks; leave it and G-46/G-47's "centre is empty" survives as a *preference* default | Not a Halo concern — `centerLabel` is a shared user preference, and changing its default changes the shipped first-run look of all six themes. One line if the owner wants it. Everything downstream is verified: launch any scenario with `-appearance.island.v8.notch.centerLabel agentAction` and the narrated labels render (`after-R2-lane-sixtheme-*.png` were captured exactly that way) |
| V2 | G-62/M-27 (R2: **RESOLVED**) | — | Built Halo-scoped as `HaloHoverPeek` + `HaloHoverPeekContent` (new `Views/Island/HaloHoverPeek.swift`), mounted by `IslandPanelView.hoverPeekOverlay(availableWidth:)`. Board composition (`06-halo.html:709-721`) reproduced: 408pt / r18 black body, `12×15` padding, bloomed amber `.dot`, title 13/600 @ t1 (`open-island wants to run a command`), pending command 11.5 mono @ t2 (middle-truncated), `.mono-tag` monogram, and 9pt below the `Click to review & approve` hint @ t3 with a right-aligned `+N more waiting` chip. Dwell is the board's **0.15s** (`syncHoverPeek`), so a pointer merely crossing the pill still gets only M-16's 1.03 bump. **Morph handoff:** the peek owns no morph state — its opacity is a plain function of the existing `morphProgress`, so it retires inside the growth's first fifth; cycle 1 shipped it as an `if !usesOpenedVisualState` mount and the ancestor `.animation(_:value: notchStatus)` faded it over the *whole* open, leaving it opaque on top of the growing silhouette 120ms in (caught on camera) — fixed by moving the gate into the opacity and pinning `.animation(nil, value:)`. Verified live with `CGWarpMouseCursorPosition` + a `CGEvent` ⌥⌘O: `after-R2-peek-{hover,unhover,morph-handoff}.png`. Negatives in `after-R2-peek-negatives.png`: `closed` (running, nothing waiting) → no peek, Poured on the same fixture → no peek. **Deltas from the board, deliberate:** (a) the peek is non-interactive chrome hanging off the pill's bottom edge, not the pill *becoming* a 408pt surface — the mockup's §B frame draws the peek as the island itself, which would mean a second geometry owner beside `morphProgress` (explicitly out of scope); the pill keeps the pointer and the click the hint promises. (b) `+N` counts other sessions **blocked on the user**, the reading the board's caption supports and the only one that stays true; the board's own literal `+2 more sessions` is not self-consistent with its §C list. Enabler: `closedAttentionQueue` (below) |
| V2 | — (enabler, R2) | — | Two sanctioned fixture enablers landed in `IslandDebugScenario`, both following the `closedCritical` precedent (collapsed notch, `previewHeight: 78`, demo sessions only, no usage providers): **`closedMultiRunning`** — `listSessions` with two idle rows swapped for live runners, the only state where >1 session runs at once (G-45); **`closedAttentionQueue`** — `closedAttention` plus the existing `questionSession` behind the permission, the only state where >1 session is blocked on the user (G-62's `+N` chip). Both are truthful compositions of fixtures that already existed — no new payload shapes |
| V2 | G-32 (R1: **RESOLVED**) | — | Owner sanctioned the plumbing. `resetsAt` now rides the payload: `IslandRightSlotResolver.UsageReading.resetsAt` (new, defaulted `nil`) → `worstUsage(in:)` → `IslandRightSlotContent.usage(percent:windowLabel:providerTitle:resetsAt:)`, with a three-token static overload keeping every existing construction site (and its tests) untouched. Halo's I′ pill formats it through the shared `UsageCountdownFormatter` against an injectable `now` (`HaloClosedPill.now` → `HaloRightSlotView.now`, defaulting to the wall clock), and falls back to the window label when a provider reports no reset — so the other five themes' pills are byte-identical (their `.usage` patterns bind the new value to `_`). Verified on `closedCritical`: **filament + `Codex 92%` + `18h 59m`** (`after-R1-closedCritical.png`), the board's §I′ composition (`06-halo.html:1301-1305`, third token now 11pt/`--t3` per the board, was 10pt). The literal `19h` of the board would need the fixture's `now + 19h` to be read at the same instant it was built — the harness loads the snapshot at launch and captures seconds later, so the honest shared grammar renders `18h 59m`; production reads a real `resetsAt` |
| V2 | G-45 (R2: **RESOLVED**) | — | The multi-running fixture landed (`closedMultiRunning`) and the grid renders correctly first try: `after-R2-closedMultiRunning-agentsGrid.png` / `after-R2-agentsGrid-zoom.png` show the §A2′ wing — one 6pt circle per surfaced session at the board's 3.5pt gap, the three running ones cyan with the `rgba(80,180,255,.7)` bloom, the rest flat at t3 — beside the aggregate `3 working` label. Nothing was changed Halo-side; the implementation was right and only unreachable. Two honest differences from the board's frame, both data not styling: the grid is 3×3 because the fixture surfaces 9 sessions (the board's fixture has 6, and "one bloomed light per session" is the rule), and the lit cells cluster rather than interleave because the cross-theme `agentsGridRightSlotContent` orders by first-observation, not by phase |
| V4 | M-21 (+ M-11 re-verify) | `.animation`/`.transition` modifiers landed and are structurally correct (Halo-scoped, identity covers bucket moves), but insert/reorder/removal was never watched live | Every `IslandDebugScenario` snapshot is static — no mutating fixture exists and building one is outside the sanctioned-enabler budget |
| V4 | G-10 (R3: **RESOLVED**) | — | Owner sanctioned fixing the interaction, and it turned out to be two faults, the first of which invalidates the original diagnosis. **(1) The rail was never on screen.** `.rail{left:0}` (`06-halo.html:285`) sits on `.isle.panel`'s *painted* border-box edge; our row's `x=0` is the **layout frame**'s, and `NotchShape` draws the silhouette's walls at `rect.minX + topCornerRadius` (`NotchShape.swift:35-38`) — so the rail was rendering 20pt out in the transparent shoulder and being clipped away entirely. Measured on this MacBook before the fix: frame edge 486pt, painted wall 506pt, and every pixel of the running row's left gutter between them is desktop backdrop (max channel sum 0 inside the panel across x 212…270). The parked note's "rail renders, verified in code + 20× zoom" was reading the *code*, not the pixels. New `HaloSessionRowFormat.railWallInset(sideInset:openedTopRadius:)` pushes it onto the wall on the notch profile and leaves the `.topBar` profile (which paints from `rect.minX`) at 0. **(2) Once visible, the perimeter really did drown it** — but the board's answer is not "dim the left segment": **every** opened frame in the mockup is a class-less `<div class="isle panel">` (§C, §E, §F, §H), so `.isle::before` falls through to `background:var(--hair)` — "idle: bare 8% hairline, edge OFF" (`:130`). The loud perimeters (`.isle.work`/`.perm`/`.ques`) live only on the **closed pill** and the mid-morph `.travel` stages. Measured collision: the orbiting segment sweeping the left wall reads `(119,125,249)` against a `.rail.run` of `(119,139,250)` — one pixel apart, once per 6s orbit. New `HaloEdgeLightModel.perimeterSettlesToHairline(for:isOpened:)` paints the idle hairline for **opened `.working`** (painting the hairline rather than flooring the working ring's opacity is what keeps V0's edge alive — a floored `white@.05` base would leave the silhouette with *no* edge). Scoped to `.working`: the attention states already hand over through `perimeterOpenHandoffOpacity` + `perimeterSuppressesBloom` (a dimmed *amber* hairline, G-36/M-20 as judged) and `.success`/`.failure` draw no rail to collide with. Verified live: `after-R3-sessionList-rail.png` — rail cyan→violet at the wall, perimeter static and achromatic (0 inter-frame delta across a full 6s orbit, was 215) — and `after-R3-sessionList-rail-expanded.png` (row clicked open; the rail spans the whole §D detail). Pinned by `HaloPermissionHeroTests.openedWorkingPerimeterSettlesToTheBoardsBareHairline` / `.railStartsAtThePaintedWallOnTheNotchProfileOnly` |
| V4 | G-11/G-71 (demo only) | Meta chips and branch-disamb are wired, but the `sessionList` running row is a Codex fixture with no model/permission/branch data, so the live line reads `Ghostty · 🕐 2m` and no branch chip shows | Judge passed the slot at tier/size; exact `Opus 4.8 / acceptEdits / branch` content needs real Claude-session data — verify on a live session |
| V5 | G-56 | `Model` / `Permission` / `Branch` cells never appear in any harness scenario — the §D grid renders Agent / Duration / Terminal only | The cell builders are live and correct (`HaloSessionRow.swift:869-885`), but every expandable fixture is a Codex session with no `claudeMetadata` and no branch, so the three cells have nothing to draw. Same root as the parked V4 G-11/G-71 — verify on a live Claude session |
| V5 | G-57 (R3: **RESOLVED (Dismiss) / closed as product truth (Reply)**) | — | **Dismiss** — owner sanctioned the behaviour change. `notificationRowActions` now carries the same `dismiss` the §H list row uses (`IslandPanelView.swift`, one line): `AppModel.dismissSession` already retires the notification surface itself (`dismissNotificationSurfaceIfPresent`) and *suppresses* rather than tombstones the session, so the card closes into the pill and stays undo-safe. Shared, so every theme's notification card gains it — verified live on Halo (`after-R3-completionCard-dismiss.png`: `↗ Jump to Ghostty` · `Transcript` ghost · right-aligned `✕ Dismiss`, the board's §H rail exactly; `after-R3-completedFailed-dismiss.png`) and spot-checked on Poured (`after-R3-poured-completionCard-dismiss.png` — its own slab idiom, right-aligned, visually sane). No test asserted the old action set. **Reply** — deliberately still absent, and *not* a fixture gap: `TerminalTextSender.canReply` returns `false` **unconditionally, for every session** (`TerminalTextSender.swift:8`), because reply injection was removed with the rest of the arbitrary-AppleScript surface — "Local-only mode intentionally does not send text to another application" (`:4-6`). So there is no product capability to gate on, and faking one for the harness would advertise a send that cannot happen. The mockup's reply affordance is blocked on that product decision, not on Halo |
| V5 | G-49 (R3: **assessed — product decision, no code change**) | The done-row line is the completion message's first sentence with markdown flattened, not a narration of the work ("Updated `AGENTS.md` & `CLAUDE.md` with …") | R3 surveyed every field that could already carry a summarising one-liner. **Result: none reaches a live row.** (a) `ClaudeSessionMetadata` (`ClaudeHooks.swift:267-281`, 14 fields) and `CodexSessionMetadata` (`CodexSessionTracking.swift:4-20`, 7) have no summary/title/description — the only text is `lastAssistantMessage` (the raw message we already use) and the user's own prompts. (b) No Claude hook payload key carries one either (full decoded set at `ClaudeHooks.swift:400-433`); the `away_summary` literal at `:784-788` is a *notification-type discriminator*, it reads no text. (c) `ClaudeSubagentInfo.summary` (`:231`) is declared but **never written** in production (`BridgeServer.swift:1120-1125` omits it; `subagentStop` deletes the entry) and is a subagent field with no parent-session counterpart anyway. (d) The one real summarising artifact — the transcript's `{"type":"summary","summary":…}` record — **is** already parsed, at `ClaudeTranscriptDiscovery.swift:155-158`, but it is assigned straight into `lastAssistantMessage`, so the distinction is destroyed at the point of ingest; it is last-writer-wins against later assistant turns, and that reader runs **only on the stale-recovery discovery path** (`SessionDiscoveryCoordinator.swift:61`) — live hook-driven sessions never open the transcript. **What a true narration would need** (all new plumbing, none of it Halo-side): a dedicated `transcriptSummary` field on `ClaudeSessionMetadata` (so the summary record stops being aliased onto the message); a tail-read of the transcript for *live* sessions, or a hook that forwards the summary; a precedence rule for summary-vs-last-message per phase; and an equivalent or an explicit no-op for Codex/Cursor/Gemini/OpenCode, none of which emit a summary at all. `HaloActivityNarration` (`HaloSessionRow.swift:1814-1895`) stays the honest minimum — flatten, first sentence, word-boundary clip; its own doc comment already says "deliberately not a summariser — the row has no model to call". Owner call whether the plumbing is worth it |
| V5 | G-55 (verify-later) | The `.mcell` grid's 6-cell wrapping layout is structurally verified (`HaloMetaGridLayout` flow layout) but never visually exercised — `sessionList` renders real discovered Codex sessions, so max 3 cells ever appear on one line | Same fixture gap as G-56 above; confirm the wrap on a live Claude session with all six fields |
| V4 | — (cosmetic) (Q1: **RESOLVED**) | Running row could show trailing age and clock chip with the same string (`2m` / `🕐 2m`) | Fixed in ba37605f: trailing age suppresses itself when its string equals the clock pin's (`metaClockLabel` equality check, Halo-scoped); other rows keep their ages |
| V7 | G-21 (Q1: **RESOLVED**) | Scoped-grant rows were structurally unreachable on `approvalCard` (fixture had no `toolName`) | Owner sanctioned the fixture enabler: `toolName: "exec_command"` landed in ba37605f; row renders and judged PASS (`✓ Always Allow` + amber chip + ⌘⇧Y). Q3 (92a8c6e5) additionally stripped the shared string's orphaned parens Halo-side (handles fullwidth （） for zh) and aligned the fixture's `currentToolInputPreview` with its own subtitle |
| V7 | G-21 (cosmetic) (R3: **RESOLVED**) | — | Owner sanctioned the Core copy change, and it took two edits because the copy was only half the cause. **(1) Copy.** `ClaudePermissionUpdate.displayLabel` said "writing to … from this project"; the board writes "**edits to** `*.md` **in** this project" (`06-halo.html:1031`). `actionVerb` now returns `edits to` for `Write`/`Edit`, and the `.projectSettings` preposition follows the verb — because the board writes *both*: a command is allowed "running `rtk grep` **from** this project" (`:993`). Every other verb and every other destination is byte-identical, so no other theme's label moved except for the edit case. Pinned by `ClaudeHooksTests.editGrantLabelsUseTheMockupsShorterPhrasing`. **(2) Layout.** Four characters were not enough — the row still cut to "in this pr…" *with a visible gap beside it*. `HaloScopeRow` was pushing its keycap over with `Spacer(minLength: 8)`, which is a flexible **sibling that competes for the leftover**; the board uses `.scope .sk{margin-left:auto}` (`:393`), which takes no width of its own. Replaced with `.frame(maxWidth:.infinity, alignment:.leading)` on the sentence, returning ~14pt to the trailing phrase. Verified live on `diffApprovalCard`: `after-R3-diffApprovalCard.png` renders `✓ Yes, allow edits to [AGENTS.md] in this project ⌘⇧Y` complete, no ellipsis |
| V7 | G-22/G-48 (Q1: **RESOLVED**) | Dead space under the row title while a hero was presented (orphaned agent badge in the `.lead` column's second slot) | Fixed in ba37605f: the lead column drops its second slot during any hero (permission and question) — the hero's `.who` chip already carries the agent identity; row is one line, judged PASS on all three hero scenarios |
| V7 | G-73 (RESOLVED) | Mockup `06-halo.html:1056` inline-styles the Codex CTA cool-blue (`#7ec9ff→#4aa3df`, ink `#04233a`) while the plan/gap row said amber. Owner ruled 2026-07-31: **mockup wins — Codex is blue.** CTA reverted to the cool-blue slab (follow-up commit after c20d2046); the blue is the honest-fork signal, matching `.codex-note` | Closed — no remaining delta |
| V7 | — (cosmetic) (Q1+Q3: **RESOLVED**) | Codex CTA lacked the `⌘J` keycap; who-chip was a bare `C` | ba37605f added the keycap + `C Codex` chip label; 92a8c6e5 made the keycap honest — `OverlayPanelController.handleJumpShortcut` registers a real ⌘J that fires the presented card's jump action (guarded on a resolvable `jumpTarget`, event passes through otherwise), keycap moved into `HaloHeroFormat.Shortcut.jump` preserving the "every case tracks a real handler" contract; verified live (⌘J dismissed the overlay into the pill) |
| V8 | G-04 (Q1+Q3: **RESOLVED**) | Two-line `.od` wrap was never rendered live (no fixture description long enough) | Owner sanctioned the fixture edit: ba37605f lengthened one `questionCard` option description — wrap renders and judged PASS. That exposed a latent §F defect: option rows were center-aligned vs the board's `flex-start` (`.opt`, 06-halo.html:405); 92a8c6e5 top-aligns the row for Halo (freeform "Other…" row keeps centring per the board's own `.opt-other`) |
| V8 | — (cosmetic, V7 family) (Q1: **RESOLVED**) | Collapsed row repeated the hero's question sentence verbatim on `questionCard` | Fixed in ba37605f: suppression seam generalized to `presentsHero(edgeState:isExpanded:)` covering `.permission` and `.question`; judged PASS |
| V9 (final gate) | V1 residual (R1: **RESOLVED**) | — | Owner sanctioned changing the header. Root cause was worse than Q2 measured: `NotchShape` draws the silhouette's walls `openedTopRadius` (20pt) *inside* the layout frame (frame 486…1026pt, painted 506…1006pt on this MacBook), so the shared 46pt notch padding is really a 26pt visible gutter and the naive 46→16 would have clipped the quit control against the wall (caught in cycle 1, screenshot). Landed three Halo-scoped knobs, all passed *into* the shared `IslandHeaderLaneLayout.metrics(...)` as new defaulted parameters (`trailingPadding` / `notchLaneSafetyInset` / `minimumRightLaneWidth`), leaving the other five themes on the shared constants: **trailing gutter 36** (= the board's own visible 16, leading stays 46 because the traveling glyph lands there), **22pt notch-profile controls at 6pt spacing** (the board's 26/8 stay on the top-bar profile), **6pt notch inset**. Net `141.5 − 6 − 78 − 6 = 51.5pt`, over Halo's own 45pt floor. `HaloUsageSummary` grew a `ViewThatFits` degrade ladder (`HaloUsageLaneRung`: full → shortTitle → windowOnly → compact → minimal → arcOnly) so each lane draws the richest form its width admits — the left lane keeps the board's `CLAUDE 5H`/`34%` at the 30pt arc, the right lane renders `minimal` (15pt arc + `78%`). Verified live: `after-R1-halo-header.png` (filament renders, 6pt clear of the cutout, controls unclipped), `after-R1-halo-sessionList-header.png`; poured/classic headers pixel-identical bar animation phase (30 / 2 differing px, `before|after-R1-{poured,classic}-header.png`). Pinned by `HaloUsageTests.notchProfileGeometryLeavesTheRightLaneAFilamentToDraw` (which also asserts the *shared* constants still yield 0 on the same hardware) |
| V9 (final gate) | — (cosmetic, G-22/G-48 family) (Q1: **RESOLVED**) | `codexApprovalCard` hero subtitle duplicated the command block | Fixed in ba37605f: subtitle now reads the mockup's `Codex needs a decision — in-app only` (new `island.halo.approval.codexDecision`, en/zh-Hans/zh-Hant), forked on `requiresTerminalApproval`; judged PASS. Q3 note: the merged NEEDS YOU header ink was also reverted to tertiary per the board's `.grp{color:var(--t3)}` rule — only the dot carries state colour |
| V9 (final gate) | — (copy) (Q2: **RESOLVED**) | Group headers read `IN PROGRESS` / `JUST DONE` / `IDLE`; mockup §C says `NEEDS YOU` / `RUNNING` / `DONE` | Fixed in Q2 without touching the shared cross-theme copy: `HaloSectionTaxonomy` (`HaloSessionListScaffold.swift`) skins the state sections with Halo-only `island.halo.section.*` strings (en/zh-Hans/zh-Hant) — `state-approval` **and** `state-answer` → `NEEDS YOU` (merged into one group, as the board files both rows under one header), `state-running` → `RUNNING`, `state-done` → `DONE`. `state-idle` has no board word and keeps `IDLE`. Other themes still render `island.section.*` verbatim |
| V9 (final gate) | — (fixture) | `Transcript` chip absent on row detail for both expandable fixtures — `trimmedTranscriptPath` is nil for discovered Codex sessions (renders fine on `completionCard`) | Same fixture-gap family as G-56/G-11 — verify on a live Claude session |
| V9 (final gate) | M-26 residual (Q2: **does not reproduce**) | Morph envelopes measured symmetric on a 120fps capture with per-frame silhouette tracking (`after-Q2-morph.mov`, white backdrop, CFR-normalised timing): **open** t50 142ms / t90 267 / t99 ~390; **close** t50 117–133 / t90 242–308 / t99 350–392 — within 1–3 frames at 120fps, both directions on the one `morphProgress` spring (`.spring(0.46, 0.86)` for open *and* close) | The earlier 0.19 / 0.13 reading is a content-gate artifact, not an animation one: Halo reveals the panel body only above `morph 0.55` (M-25), a window the spring crosses **slowly** on open (the settle tail ≈ open t75 200ms) and **fast** on close (≈ t50 117ms). Equalising that would mean keeping the body painted while the silhouette shrinks — i.e. deleting M-25's empty-container law. No code change; frame strips `after-Q2-morph-{open,close}-frames.png` show the reverse-geometry shrink, opaque throughout, no jump |
| V9 (final gate) | — (test infra) (R3: **RESOLVED — suites deleted**) | — | Owner ruled per the standing "delete failing tests" decision. The three suites pin **committed PNG goldens**, but the owner deliberately purged every PNG from the repo (`da6045df`), so their design can never be satisfied again: the `__Snapshots__/` dirs carried only `environment-fingerprint.txt`, this machine's fingerprint *matches*, so the pixel compare ran instead of skipping and all 64 goldens were missing. Deleted `HaloConformanceSnapshotTests.swift`, `PouredConformanceSnapshotTests.swift`, `ThemeSnapshotHarnessTests.swift`, their shared `Tests/OpenIslandAppTests/Support/ThemeSnapshotting.swift` (no other suite referenced it — the seven remaining mentions repo-wide are doc comments), and the three `__Snapshots__/` fingerprint sidecars. `swift test` now reports **XCTest: 18 tests / 0 failures** (was 18 + 64 errors) and **swift-testing: 1118 tests in 97 suites, passed**. Note for whoever runs the suite next: `AppModelSessionListTests.completionNotificationHoverCancelsPendingTimedCollapse` reads the **live cursor** (`OverlayUICoordinator.swift:454`, `NSEvent.mouseLocation`), so it fails deterministically if the pointer is parked over the notch area — as it is right after a `CGWarpMouseCursorPosition` verification run. Move the mouse away before gating; it is not a code failure (confirmed identical at `a7cb0922`). The Python-side tooling (`scripts/tests/test_validate_harness_artifacts.py`, `tools/halo_parity/cli.py`) still names the golden paths, unchanged and already inert since the PNG purge; `pytest` is not installed on this machine and is not part of the `swift test` gate |
