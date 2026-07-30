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
| — | — | — | — |
