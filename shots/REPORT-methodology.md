# Methodology & coverage (part of the visual-fidelity report)

## What was compared
Shipped app vs the three approved mockup boards, for **Poured Island 2.0**, **Flight Deck 2.0** and **Halo**.
This was a **visual/design QA pass**, not a functional/state pass — content correctness was assumed settled by the prior review and deliberately not re-litigated.

## Capture pipeline
**App (top-bar mode)** — the direct-binary harness rendered each `IslandDebugScenario` into the real overlay `NSPanel`:
```
OPEN_ISLAND_HARNESS_SCENARIO=<scenario> OPEN_ISLAND_HARNESS_PRESENT_OVERLAY=1 \
OPEN_ISLAND_HARNESS_START_BRIDGE=0 OPEN_ISLAND_HARNESS_BOOT_ANIMATION=0 \
OPEN_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS=1.5 OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS=3 \
OPEN_ISLAND_HARNESS_ARTIFACT_DIR=<dir> "$BIN"
```
15 scenarios × 3 themes = **45 frames** → `shots/app/` (plus a sibling `.ax.json` accessibility tree per frame).

**App (notch mode)** — this Mac's main display is an external 4K, so the harness defaults to top-bar and the notch-mode design surface would never have been reviewed. Forced it by writing the built-in display's UUID to `overlay.display.preference`, then captured 5 metric-sensitive scenarios × 3 themes = **15 frames** → `shots/notch/`. Confirmed genuine notch mode: panel measured 540pt vs top-bar's 520pt. **The display preference was restored afterwards.**

**Mockups** — rendered headless via `playwright-cli` at a fixed viewport, screenshotting every `.frame`, every `section`, and every `.board` container, named from each frame's `.fid`/`.id` label. **104 crops** → `shots/mockup/`, giving complete §A–§K coverage for all three boards.

**Scale rule applied throughout**: app captures are **@2x** (1px = 0.5pt); mockup crops are **@1x** (1px = 1pt). Every measured delta was halved before comparison. This was called out to every agent as the #1 source of false findings.

## Measuring instruments
Before any comparison, three **rulers** were extracted (one per theme) from the SPECs + `Sources/OpenIslandApp/Theme/*Theme.swift`: the full type scale (role → pt → weight → design → tracking → tabular), every metrics token, the slot→Swift type map, per-component metrics, the theme's specific fidelity bar, and all known SPEC-vs-code drift.
→ `shots/rulers/ruler-{poured,flightdeck,halo}.md`

Critically, the rulers encode what "correct material" means **per theme**, which prevented a whole class of false findings:
- **Flight Deck** is deliberately flat and opaque (tintOpacity 1.0, no gradients, no specular edge). Flat ≠ defect. Its signature is **phosphor glow bleed on lit lamps**.
- **Halo** is a pure-black OLED void whose only chrome is a 1.5pt edge-light. No fills/cards/vibrancy is **correct**.
- **Poured** is the only theme that owes layered glass (3-stop body gradient + two specular layers + inner hairline).

## Agent fleet
- 3 × ruler extraction (parallel, read-only)
- 3 × per-theme visual critique against the 7-dimension rubric
- 1 × cross-cutting **type-scale consistency** audit (both a static code census and pixel verification)
- 1 × cross-cutting **component consistency** audit
- 2 × **adversarial verification** passes, instructed to default to REFUTED and to specifically test for: content/fixture-vs-design confusion, hover-gated affordances, conditional data (Model is claude/opencode/cursor only; Transcript needs a transcript path), scale errors, animation phase, and user settings.

## Coverage gaps (stated honestly, not scored as failures)
| Gap | Why |
|---|---|
| **B** (hover peek / morph), **K** (motion strip) | Not drivable from stills. Motion identity was explicitly **not** asserted from single frames. |
| **D** (row detail), **G** (subagents expanded) | The harness scenarios render the *collapsed* row; click-to-expand was never exercised. All three agents independently confirmed the expanded state never appears — AX trees contain no engine-tile/task-list text. Needs a re-capture with the row expanded. |
| **§I full usage-meter card** | Both Poured and Halo agents report the 52pt dial card never appears in the `usageMeters` capture — only the compact header rings/filaments. What *is* visible matches spec. Needs a targeted capture. |
| **A6 closed-pill outcome glyphs** (Poured) | The mapped captures show the expanded row-detail card, not the closed pill — a frame-scope mismatch. |
| **J empty state** | Clipped by the install-hint banner in all three themes. |
| Motion, hover, focus and pressed states generally | Verified from code where possible, never asserted from stills. |

## Known artifacts explicitly excluded from findings
- **Install-hint banner** ("No agent hooks installed — SETUP"): the bundled binary's hooks probe reads false. A harness artifact, not a product bug. It also clips short panels — `poured-emptyState`, `poured-completedFailed`, `flightDeck-emptyState`, and (newly observed, extend the known list) **`halo-emptyState`**.
- **multiQuestionCard fixture bug**: every option renders as option[0]/digit "1" because `AppearancePreviewFixtures.stableID` truncates seeds to 16 bytes → colliding UUIDs. Fixture/test bug; production uses fresh UUIDs. F-multi was judged on layout/typography/components only.
- **Notch vs top-bar metric differences** (pill 38↔24pt, panel 540↔520pt, list insets 46↔16pt, usage ring/filament 30↔22pt) are SPEC-sanctioned.
- **Session grouping absent from §C**: `appearance.island.v8.notch.sessionGroup = none` is the user's own setting.

## Evidence index
| Artifact | Path |
|---|---|
| App frames, top-bar (46) | `shots/app/` |
| App frames, notch (15) | `shots/notch/` |
| Mockup crops (104) | `shots/mockup/` |
| Side-by-side pairs (12) | `shots/pairs/` |
| Per-theme rulers | `shots/rulers/` |
| Shared agent brief | `shots/BRIEF-REVIEW.md` |
| Raw per-theme critiques | `shots/critique-{poured,flightdeck,halo}.md` |
| Type-scale audit (Appendix A) | `shots/audit-type-scale.md` |
| Component audit (Appendix B) | `shots/audit-components.md` |
| Coordinator's own findings | `shots/findings-coordinator.md` |
