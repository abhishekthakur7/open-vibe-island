# APPENDIX B — Component consistency audit (all three themes)

Read: all three rulers, the shared views (`Sources/OpenIslandApp/Views/IslandPanelView.swift`), all three `*SessionRow.swift`, `Theme/SessionRowContainer.swift`, `IslandSessionRowMetrics.swift`, `Views/Island/IslandNotificationCard.swift`. Cross-checked against `shots/app/*.png` at native @2x.

## B.0 HEADLINE FINDING — the shared question card is unthemed in all three themes

`StructuredQuestionPromptView` (`IslandPanelView.swift:2290-2356`, internals `:2401-2481`, `:2953-2985`) is rendered **byte-for-byte identically in all three themes**. Poured (`PouredSessionRow.swift:872-877`), Flight Deck (`FlightDeckSessionRow.swift:2250-2255`) and Halo (`HaloSessionRow.swift:1997-2002`) all call it with **zero style parameters**.

Visually confirmed in `shots/app/{poured,halo,flightDeck}-questionCard.png`: the numbered option rows, the digit box, the radio marker and the "Submit Answers" button are **pixel-identical rounded-rectangle UI** dropped into three otherwise completely different visual languages.

Worst on Flight Deck: its own MASTER CAUTION header directly above the card is chamfered / mono / tracked / uppercase, and three rows later "Submit Answers" is a smooth continuously-rounded pill in mixed-case system font with zero tracking.

Aggravating: the SPEC-matching type roles for exactly this content — `optionLabel` 13/600, `optionDesc` 11.5/400, `questionText` 14.5/560, `optionNumber` 11/700 — **are defined in all three theme typography enums** (`PouredTypography:203-207`, `HaloTheme:85-92`) but **never wired into the shared view**, which hardcodes its own unrelated literals: option label 12.2/medium (`IslandPanelView.swift:2431`), desc 10.5 (`:2436`), digit 10.5/semibold/mono (`:2417`). Every theme "pins" a scale that this whole card family silently ignores.

## B.1 Per-component matrix (primary offenders)
| Component | Poured | Flight Deck | Halo |
|---|---|---|---|
| Primary hero button | r11, pad 14/8, no border, gradient, **hardcoded 13/semibold** — PouredSessionRow:1885-1898 | chamfer 5, pad 11/8, 1pt paper border, mono 11.5/semibold tr0.8 — FlightDeckSessionRow:3087-3110 | r10, pad 13/8, no border, amber gradient, 13/semibold + keycap |
| Jump / secondary CTA | r10, pad 14/8, white@0.4 1pt border (blendMode overlay), 11.5/600, **glow shadow r10 y4** — PouredSessionRow:2325-2358 | chamfer 5, pad 11/8, 1pt border, no glow | r8 jump chip, pad 9-10/3-4 |
| Ghost / secondary | r11, pad **12/8**, no border — PouredSessionRow:2364-2399 | chamfer 5, pad 11/8 (`.ghost`) | — |
| Codex / terminal CTA | r11, pad **14/9** (not /8), 13/semibold hardcoded, no keycap — PouredSessionRow:1721-1737 | same `FlightDeckApprovalButton` family | r10, pad 13/8, no keycap |
| **Shared question submit** | r10 (`IslandActionButtonStyle`, IslandPanelView:2979), pad 13/8, 1pt border, **11.8/semibold sans** | identical | identical |
| Keycap chip | r4, min 16×16, **one chip per glyph** ("⌘"+"Y" = 2 boxes) — PouredSessionRow:1828-1852 | chamfer 2.5, **one combined chip** holding the whole `⌘Y` string — FlightDeckSessionRow:3116-3124 | r4, min 16×16, one chip per glyph — HaloSessionRow:2232-2252 |
| Header control button | **Circle 22×22**, fill white@0.06→0.14 — PouredHeaderControls:17 | **RoundedRectangle r4, 22×22** — FlightDeckHeaderControls:260-263 | **Circle 26×26** — HaloHeaderControls:20 |
| Diff / command well | fully re-themed: own r10, own gutter — `PouredPermissionDiff` :1943-2014 | outer well chamfer 5, but wraps the **unmodified shared `PermissionDiffPreview`** whose inner background is `RoundedRectangle(cornerRadius: 7)` — :2789-2797 + IslandPanelView:119-122 | fully re-themed: own r9, own gutter — `HaloHeroDiff` :2096-2159 |

## B.2 Drift findings
| # | Component | Should be | Is | Where | Sev | Visible |
|---|---|---|---|---|---|---|
| 1 | Question card interior | Themed per SPEC (roles exist in every theme) | Verbatim shared view, zero theme params, hardcoded fonts/radii unrelated to any scale | IslandPanelView:2290-2481 | **MAJOR** | `*-questionCard.png` / `*-multiQuestionCard.png` — option rows, digit box and submit pill pixel-identical across all three themes |
| 2 | FD diff box | Chamfered nesting throughout (card 6 → well 5 → …) | Outer well chamfer 5, but the shared preview's inner scroll container is `RoundedRectangle(r7)` — **a rounded box nested inside a chamfered box, in FD's loudest hero frame** | FlightDeckSessionRow:2789-2797; IslandPanelView:119-122 | **MAJOR** | `flightDeck-diffApprovalCard.png` at 3× — the "Updated (+3 −2)" outer edge is visibly chamfer-cut, the box directly beneath is visibly rounded; two corner primitives touching within ~40px |
| 3 | Question submit button | Match each theme's button primitive | Always plain `RoundedRectangle(r10)`, sans 11.8/semibold — breaks FD's chamfer signature outright | IslandPanelView:2953-2985 | **MAJOR** (FD), MINOR (Poured/Halo — r10 coincides with their own button radius) | chamfered DENY/ALLOW vs rounded "Submit Answers" in the same capture family |
| 4 | Keycap chip composition | One grouping rule | Poured/Halo split each glyph into its own chip (code comment: "one chip per glyph"); FD combines the full shortcut into one chip | PouredSessionRow:1828-1837; HaloSessionRow:2238; FlightDeckSessionRow:3116-3124 | MINOR — plausibly a deliberate FD signature, but **undocumented as such**; needs a design call | Poured/Halo show 2 boxes, FD shows 1 |
| 5 | Header control shape | One "header icon button" class | **3 primitives**: Poured circle 22, Halo circle 26, FD **rounded-square r4** 22 | PouredHeaderControls:17; HaloHeaderControls:20; FlightDeckHeaderControls:260-263 | MINOR — Halo's 26 is a documented signature; **the circle→square swap on FD is the real inconsistency** | power-button corner in all three `*-questionCard.png` |
| 6 | Poured's own button family | One radius/padding/border treatment | Jump r10 pad14/8 **bordered + glowed**; Allow/Deny r11 pad14/8 unbordered; Ghost r11 pad **12**/8; Codex CTA r11 pad14/**9** | PouredSessionRow:1725-1737, 1885-1898, 2325-2358, 2364-2399 | **MAJOR** — a single theme disagreeing with itself about what "a button" is | `poured-approvalCard.png`, `poured-codexApprovalCard.png`, `poured-completionCard.png` — three distinct curvatures + padding rhythms in one theme |
| 7 | Poured Allow/Deny + Codex CTA label | From `PouredType.roleTable` | Hardcoded `.system(size:13, weight:.semibold)` | PouredSessionRow:1721, :1872 (label struct :1868) | MAJOR | code-level; also the root cause of #6 (the button has no label-role contract) |

## B.3 Shared-view inheritance report
| Shared view | Poured | Flight Deck | Halo |
|---|---|---|---|
| `StructuredQuestionPromptView` | wrapped in gold wash + r18 ring (:871-901); **interior untouched** | annunciator header only, **no card chrome at all** (:2248-2256); interior untouched | wrapped in `HaloHeroShell` r16 ring + glow (:1978-2003); **interior untouched** |
| `PermissionDiffPreview` | **not used** — own `PouredPermissionDiff` (:1943-2014) | **used verbatim**, wrapped in a chamfer-5 well (:2789-2797) — the only theme still exposed to the shared r7 / 10.5-bold-mono / 10-mono styling | **not used** — own `HaloHeroDiff` (:2096-2159) |
| `IslandActionButtonStyle` | as-is | as-is | as-is |
| `IslandNotificationCard` "show all N" footer | raw `.system(10.5, .medium)` (:101), identical in all three — consistently unthemed rather than drifting | same | same |

**Pattern**: Poured and Halo both fully re-themed the diff renderer but left the question-prompt interior untouched; Flight Deck did neither. **No theme has ever restyled `StructuredQuestionPromptView`'s interior** — that is a single well-defined fix surface, not three.

## B.4 Cross-theme structural comparison
| Component | Poured | Flight Deck | Halo | Analogous? |
|---|---|---|---|---|
| Hero card radius | **15 approval / 18 question** | 6 chamfer (uniform) | 16 (uniform) | Poured is internally inconsistent — two radii for one conceptual "hero card" class |
| Keycap radius | 4 | chamfer 2.5 | 4 | FD deliberately off-ladder, consistent with its own signature — likely intentional |
| Header control | circle 22 | **rounded-square r4** 22 | circle 26 | Halo's 26 documented; FD's shape swap is not |
| Diff/command radius | 10 | chamfer 5 | 9 | each tracks its own card family — fine |
| Submit button (shared) | r10 rounded | r10 rounded (**breaks chamfer**) | r10 rounded (coincidentally matches Halo) | only accidentally right for Halo; genuinely wrong for FD |

## B.5 Ranked component problems
1. **Theme the shared question-prompt interior** (option row, digit box, submit button) — the most visible "this doesn't belong here" moment in the app, worst on Flight Deck where it breaks the chamfer signature inside its own MASTER CAUTION family. Needs a per-theme style injection point (e.g. via `\.islandTheme`, the way `sessionRow` is themed). → `Sources/OpenIslandApp/Views/IslandPanelView.swift:2290-2481`
2. **Stop FD nesting a rounded shared view inside its chamfered well** — parameterise `PermissionDiffPreview`'s shape or give FD a chamfer-native diff renderer mirroring `PouredPermissionDiff`/`HaloHeroDiff`. → `FlightDeckSessionRow.swift:2789-2797` (or `IslandPanelView.swift:119-122`)
3. **Unify Poured's button family** onto one radius + padding rhythm + border rule, and route labels through `PouredType.roleTable`. → `PouredSessionRow.swift:1721-1898, 2325-2399`
4. **Decide and document the header-control shape policy** — circle vs rounded-square. → `FlightDeckHeaderControls.swift:260-263`
5. **Decide the keycap glyph-grouping convention** (combined vs per-glyph) as an explicit per-theme rule.
