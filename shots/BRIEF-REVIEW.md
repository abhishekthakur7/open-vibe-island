# Visual-fidelity review — shared brief for critique agents

## Mission
Pixel-level comparison of the SHIPPED APP against the APPROVED MOCKUP for one overlay theme.
This is a **visual/design QA pass**, NOT a functional/state pass. A previous review already
confirmed state/content conformance (right badges, right data, correct no-fake-approve behaviour).
**Do not re-litigate content correctness.** Assume the data shown is correct. Hunt exclusively for
where the app **looks worse** than the mockup.

The mockups are the quality bar: premium, Apple-Dynamic-Island / Linear / Raycast-grade, with a real
type scale, consistent components, and layered-light material.

## Why this review exists (defines the bar)
A prior pass graded frames PASS/FAIL on whether the correct *elements were present*. That let
visually-degraded frames "pass" because the data was right. The reviewer explicitly flagged:
1. **Fonts are not consistent sizes** — the same semantic role (section caption, metadata key, body
   line, chip, button label) renders at different sizes across frames/themes; some type looks ad-hoc
   rather than drawn from the scale.
2. **Components are not consistent** — the same component (button, chip, badge, keycap, card, row,
   meter) is styled differently in different places; radii/padding/weights drift.
3. "Many such problems" — a general premium-polish gap vs the mockups.

Your job: find all of these, with side-by-side proof and exact deltas, ranked by how much they
cheapen the product.

## Assets
- **Your theme's ruler** (type scale + component metrics + known drift): `shots/rulers/ruler-<theme>.md`
  Read this FIRST. It is the measuring instrument. It already lists known SPEC-vs-code drift — confirm
  which of those are actually *visible*, and find more.
- **Mockup crops**: `shots/mockup/` — section-level crops `<theme>-SEC-<A..K>.png` (poured, halo) and
  `<theme>-BOARD-<A..K>-<n>.png` (flightDeck). Plus per-frame crops `<theme>-<frameId>.png`.
- **App crops**: `shots/app/<theme>-<scenario>.png` (+ matching `.ax.json` for the accessibility tree).
- Authority docs: `docs/design/overlay-redesign/BRIEF.md` (§2 physical metrics, §7 fidelity bar) and
  `docs/design/overlay-redesign/SPEC-<theme>.md`.

## Scale
**App captures are @2x (1px = 0.5pt). Mockup crops are @1x (1px = 1pt).**
Always halve app pixel measurements before comparing to mockup/ruler pt values. Stating a delta
without doing this conversion is the #1 way to produce a false finding.

## Frame ↔ scenario map
| Frame | App scenario file | Mockup |
|---|---|---|
| A1 idle / A2 working | `<theme>-closed.png` | `<theme>-A1/A2` |
| A3 attention (permission) | `<theme>-closedAttention.png` | `<theme>-A3` |
| A6 completion variants | `<theme>-completedInterrupted.png`, `<theme>-completedFailed.png` | `<theme>-A6` |
| C session list | `<theme>-sessionList.png` | SEC-C |
| E1 permission (command) | `<theme>-approvalCard.png` | SEC-E / E1 |
| E1+E2 Claude always-allow + diff | `<theme>-diffApprovalCard.png` | SEC-E / E2 |
| E3 codex jump-to-approve | `<theme>-codexApprovalCard.png` | SEC-E / E3 |
| F single question | `<theme>-questionCard.png` | SEC-F / F1 |
| F multi question | `<theme>-multiQuestionCard.png` | SEC-F / F2 |
| G subagents + tasks | `<theme>-subagentsCard.png` | SEC-G |
| H completed | `<theme>-completionCard.png`, `<theme>-longCompletionCard.png` | SEC-H |
| I usage meters | `<theme>-usageMeters.png` | SEC-I |
| J empty state | `<theme>-emptyState.png` | SEC-J |
| B hover peek, D row detail, K motion | not drivable from stills — inspect mockup + code only, mark coverage gap |

## THE RUBRIC — grade every frame on all 7 dimensions
For each frame place the app crop beside the mockup crop and grade each dimension
**PASS / MINOR / MAJOR** with a concrete pixel-level observation and the suspected `file:line`
(the ruler's component table gives you these). **"Looks fine" is not an answer — measure.**

1. **Typography — scale adherence & consistency** (reviewer's #1 complaint)
   - Does every text role render at the ruler's pt size + weight? List role → intended pt → apparent pt.
   - **Cross-frame consistency**: is the same semantic role the same size/weight *everywhere* it appears?
     Flag any role that drifts between frames.
   - tabular-nums on every timer / counter / meter / duration / percentage? (BRIEF §2 mandates it.)
   - No mid-word truncation ("clau…", "You are gener…"); ellipsis only at sensible boundaries.
   - No sub-10pt roles; micro-labels have correct letter-spacing; casing matches the theme's grammar.
   - Baseline alignment & optical corrections: shared baselines, optically aligned numbers, no text
     vertically mis-centered in its chip/button/row.
2. **Component consistency** (reviewer's #2 complaint)
   - Inventory reusable components and check each renders identically wherever it appears: primary
     button, secondary/ghost button, deny button, keycap chips, count/attention badge, status chip,
     agent monogram, section header, session row, metadata cell, card container, usage dial/gauge,
     code/command box, diff box.
   - Same corner radius, padding/inset, height, border/hairline weight, icon size, glyph style for the
     same component across frames?
   - Buttons: consistent min-height, label casing, icon-label gap, keycap placement/size.
3. **Layout, spacing & density rhythm**
   - Consistent gutters, row insets, vertical rhythm; no cramped or floating elements; no dead space
     (BRIEF diagnosis: "space spent, not invested").
   - Card internal padding matches the mockup; header/summary/footer proportions match.
   - Alignment grids honoured (list side insets, notch-gap reservation, meter lanes).
4. **Material & polish — the §7 fidelity bar**
   - Multi-stop gradients (not flat fills), specular top edges, inner luminance, glow that **bleeds
     outside the silhouette**, believable multi-layer shadow stacks. Flag any surface that is
     "a single flat fill with a border".
   - The permission hero must read as an **EVENT** (amber light inside glass / MASTER WARNING
     annunciator), not a restyled form — compare intensity/depth to the mockup hero.
   - Per-state ambient pill variants readable "across the room"; attention states genuinely loudest.
   - Depth/blur/vibrancy where the theme calls for it; corner-radius continuity on the morph shape.
   - NOTE: what counts as correct material is **theme-specific** — see your ruler's fidelity section.
     Flight Deck is deliberately flat/opaque with zero gradients (that is CORRECT, not a miss); its
     signature is phosphor glow bleed on every lit lamp. Halo is a pure-black void whose only chrome
     is a 1.5pt edge-light (no fills/cards/vibrancy is CORRECT). Poured is the layered-glass one.
5. **Motion identity** — cannot be verified from stills. Note which stateful elements *appear* static
   in the capture and flag as "verify live"; do not assert motion failures from a single frame.
6. **Semantic colour discipline** — colour = state only, never decoration; identity stays a whisper
   (small monogram/tick, never a coloured pill). Thresholds/states never conveyed by colour alone.
7. **Overall "premium delta"** — one holistic call per frame: does this frame look as good as the
   mockup? If not, say specifically what cheapens it (thin type / flat material / misalignment /
   inconsistent components).

## KNOWN ARTIFACTS — do NOT file these
- **Install-hint banner**: the harness binary's hooks probe reads false, so a "No agent hooks installed
  — SETUP" banner appears in the summary lane. It is a harness artifact, not a product bug. It also
  **clips short panels** — `poured-emptyState`, `poured-completedFailed`, `flightDeck-emptyState` are
  cut off at the bottom. Judge only what is visible; mark the rest a coverage gap.
- **Multi-question fixture bug**: `multiQuestionCard` renders every option as option[0] / digit "1"
  because `AppearancePreviewFixtures.stableID` truncates seeds to 16 bytes → colliding UUIDs. It is a
  fixture/test bug; production uses fresh UUIDs. Judge F-multi layout/typography/components only,
  **ignore the duplicated option text**.
- **Placement**: the harness renders **top-bar** mode (this Mac's main display is external). The SPECs
  differ from notch mode by metrics only (pill 38↔24pt, panel 540↔520pt, insets 46↔16pt). Do not file
  a finding that is purely a notch-vs-top-bar metric difference. Both Poured and Halo deliberately use
  a **smaller 22pt** header usage ring/filament in top-bar mode (vs 30pt notch) — that is correct.

## Output format — structured, not prose
Return findings as a list. For each finding:
- `frame`: e.g. "E2"
- `dimension`: 1-7 from the rubric
- `severity`: MINOR | MAJOR
- `mockup_shows`: what the mockup does
- `app_shows`: what the app does
- `measured_delta`: exact pt/px/radius/weight numbers (remember the @2x conversion)
- `suspected_file_line`: from the ruler's component/slot table
- `evidence`: the two image paths you compared
Then a per-frame 7-cell grid (PASS/MINOR/MAJOR) and a one-line holistic "premium delta" verdict per frame.
Be specific and measured. A finding without a number in `measured_delta` is not a finding.
