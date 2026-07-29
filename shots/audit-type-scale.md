# APPENDIX A — Type-scale consistency audit (all three themes)

Method: static census (`rg '\.system\(size:'` + role-table accessors across all `Poured*`/`FlightDeck*`/`Halo*` views and their `*Typography`/`*Theme.swift`), cross-checked and extended beyond the rulers, plus pixel verification on @2x app crops (PIL tight-crop bbox, halved for pt). **[NEW]** = beyond what the rulers already documented.

## A.1 Per-theme census — what changes or extends the rulers

### Poured
| Rendered | Role / verdict | Call sites | Verdict |
|---|---|---|---|
| 10.5 / medium / **mono** | should be `monoChip` (dead role) or sans per SPEC §2 | `sideBadge` PouredSessionRow:1181-1188 (model/SSH/terminal/subagent/task/plan-mode chips) — monospace visually confirmed on the "Ghostty" pill in `poured-sessionList.png` | OFF-TABLE |
| 10.5 / semibold / **mono** | same | bypass-permissions chip PouredSessionRow:1212-1218 | OFF-TABLE |
| 13 / semibold | **no role exists** (gap between 12.5 `metadataValue` and 14 `heroTitle`) | Allow/Deny title :1872; Codex CTA title :1721 | OFF-TABLE, **hero frame** |
| **[NEW]** jump icon 11.5/bold beside `jumpChip` label 11.5/**600** | icon weight heavier than paired text role | :752, :1021 | MINOR (cosmetic) |
| **Pixel check** | Allow bbox 21px→**10.5pt**, Deny bbox 24px (incl. descender)→**12.0pt**, `heroTitle` bbox 27px→**13.5pt** | `poured-approvalCard.png` | Allow/Deny render **visibly smaller** than the 14pt `heroTitle` directly above them in the same card |

SF-Symbol icon sizes (12/bold, 11/semibold at :1101,1144,1165,1236,1433,1561,1718,2421; ClosedPill:464,467,470) excluded — icons, not text roles.

### Flight Deck
| Rendered | Role / verdict | Call sites | Verdict |
|---|---|---|---|
| countSize(11) / **bold** / **sans** | `count` role is 11/**semibold**/**mono** (FlightDeckTheme:112) | `FlightDeckAttentionSegment` glyph :536 | **[NEW]** off-spec weight + design |
| countSize(11) / **bold** / mono | weight drift | `FlightDeckUsageMiniTape` `%` :601 | **[NEW]** weight drift |
| countSize(11) / **medium** / **sans** | weight + design drift | `FlightDeckTaskCounterChip` count :633 | **[NEW]** weight + design drift |
| countSize(11) / semibold / mono | canonical | `FlightDeckTaskCounterChip` fraction :638; ClosedPill :601,638 | OK |
| **⇒ the single `count` role renders in 4 distinct weight/design combinations at the same 11pt** (bold+sans / bold+mono / medium+sans / semibold+mono) across 6+ call sites | | | **[NEW] role-drift** |
| `%` unit at `countSize − 2` = **9pt** | below the pinned 10pt floor | FlightDeckUsageSummary:161 | **SUB-FLOOR**, visually smaller than the adjacent "78" in `flightDeck-usageMeters.png` |
| MASTER placard 10.5/bold/mono tr1.2 | SPEC says 12 / 800 / 0.12em | FlightDeckSessionRow:2626-2627 | OFF-SPEC — in `flightDeck-approvalCard.png` the placard reads **no louder than the 11pt kicker beside it**, undermining its "loudest element" role |
| Approval button 11.5/semibold/mono tr0.8 (≈0.07em) | SPEC says 11 / 600 / 0.04em | FlightDeckSessionRow:3098-3099 | OFF-SPEC |
| **[NEW]** row age/time cells use mono *design* but skip `.monospacedDigit()` (:761, :796) | engine-elapsed (:1325) and donestat-duration (:2381) apply it redundantly on top of mono | — | MINOR — inconsistent *technique*, identical rendered output |
| `roleFamilies` pins only 9 names; ~40 inline literals bypass it | `readableRoleSizes` (FlightDeckTheme:99-101) cannot catch any of the drift above | — | **Structural: FD has no real single source of truth** |

### Halo
| Rendered | Role / verdict | Call sites | Verdict |
|---|---|---|---|
| `roleFamilies` (HaloTheme:141-185) genuinely covers **all 35 readable roles** for size+family — unlike FD's 9-of-many | | | **Structural PASS on the size axis** |
| **[NEW]** `nestHeader` (10pt UPPER, spec'd 700 at HaloTheme:101) renders at **two weights**: `.bold`(700) at HaloSessionRow:622 & :2019; `.semibold`(600) at :625, :720, :1102 | same visual role — a small-caps caption above a card body | :622 vs :1102 | **[NEW] role-drift, weight axis** |
| **[NEW]** `HaloQuestionTag` (semantically `qChip`, 10/700/0.05em per HaloTheme:93-94) is coded by borrowing `nestHeaderSize` + its tracking multiplier | numerically harmless today (both = 10) but the roles are aliased by accident | HaloSessionRow:2019-2020 | **[NEW] token hygiene** — latent fragility, not currently visible |
| `metaChipValue` / `optionNumber` sans vs SPEC's mono | documented deliberate deviations | HaloTheme:58-61, 90-92 | Known (ruler) |
| 560/650/660 → .medium/.semibold/.semibold | unreachable SwiftUI weights | HaloSessionRow:1081,1696-1697; HaloUsageMeterCard:110 | Known |

## A.2 Role-drift table (the money table — ranked by prominence)
| Semantic role | Sizes/weights actually rendered | Where | Prominence |
|---|---|---|---|
| **Poured hero button label** (no role exists) | 13/semibold, sitting beside `heroTitle` 14/640 with no defined relationship | PouredSessionRow:1721, 1872 | **HERO — highest** |
| **FD `count` role** (canonical 11/semibold/mono) | bold+sans / bold+mono / medium+sans / semibold+mono — **4 renderings** | FlightDeckSessionRow:536,601,633,638 + ClosedPill:601,633,638 | High — every closed-pill state |
| **FD MASTER placard** (should be loudest text in the app) | 10.5/bold vs SPEC 12/800 | FlightDeckSessionRow:2626 | **HERO — highest** |
| **Halo nestHeader / section caption** | bold(700) vs semibold(600) | HaloSessionRow:622 vs 625/720/1102 | Medium |
| **Poured sideBadge** (`monoChip` role dead) | 10.5/medium/mono everywhere SPEC §2 said drop mono (+ bypass chip 10.5/semibold/mono) | PouredSessionRow:1181, :1213 | High — nearly every row |
| **FD approval button label** | 11.5 / tr 0.8pt vs SPEC 11 / 0.04em | FlightDeckSessionRow:3098 | HERO frame |

## A.3 Sub-floor violations
| Role | pt | file:line | Test-pinned? |
|---|---|---|---|
| FD usage `%` unit | **9pt** | FlightDeckUsageSummary:161 (`countSize − 2`) | **No** — not in `readableRoleSizes`. Visually confirmed smaller than the adjacent value. |
| everything else, all 3 themes | ≥10pt | — | Poured & Halo `readableRoleSizes` are comprehensive and pinned; no other sub-floor found |

## A.4 Cross-theme comparison
| Semantic slot | Poured | Flight Deck | Halo | Verdict |
|---|---|---|---|---|
| Section/list caption | 10.5/650/0.09em | 10/semibold/mono/1.0em | 10/700/0.10em | Aligned; FD sits at the literal floor while others keep 0.5pt headroom |
| Metadata key | 10/600/0.06em | 10 sans semibold tr1.0 | 10/600/0.08em | Aligned |
| Meta/status chip | 10.5/500 → **mono** at sideBadge (off-spec) | 10/semibold/mono tr0.6 | 10.5/500 sans | **Poured is the outlier** — only theme rendering this slot in mono where SPEC calls for sans |
| Keycap | 10/600 | 10/semibold/mono | 10/600 | Aligned |
| Button label | **13/semibold hardcoded** (untracked) | 11.5/semibold/mono (pinned to a named constant) | 13/semibold (also not in `roleFamilies`) | Poured & Halo both leave button labels off the formal scale; **FD is the only one with its button label pinned** |
| Hero/permission title | heroTitle 14/640 | MASTER placard **10.5/bold** | heroTitle 14/650 | **FD is the clear outlier** — its hero headline is smaller than the other two, contradicting the annunciator identity SPEC and BRIEF §4 both demand |

## A.5 tabular-nums audit (BRIEF §2 mandates it on every timer/counter/meter/duration/percentage)
- **Poured — PASS.** age (:239/242), summary count (:1000), ring % (:221-223), section-header count (:288), fraction chip (:632). 10 call sites, all covered.
- **Flight Deck — functionally pass, methodologically inconsistent.** engine elapsed (:1325), HELD value (:2877), donestat duration (:2381) covered. Row age/time (:761,:796), metacell value (:936) and usage `%` (UsageSummary:159) rely on a fully monospaced *design* (which already tabularises) but skip the explicit modifier. No rendering bug; **zero test coverage across the whole tape-gauge value stack.**
- **Halo — PASS.** age (:451), subagent elapsed (:691), summary number (:167), meter value/reset (UsageMeterCard:111,118), usage kicker/value (UsageSummary:314). `metadataValue` applies it conditionally via a `tabular` flag (:1059) — correct by design.

## A.6 Ranked type-scale problems
1. **FD MASTER WARNING placard reads no louder than its own kicker** — FlightDeckSessionRow:2626-2627 (10.5/bold vs SPEC 12/800/0.12em). Highest-prominence frame in the app, visibly undersized. → *`fix: pin FD MASTER placard to SPEC 12/800/0.12em (use .heavy/.black if .bold caps at 700)`*
2. **Poured Allow/Deny/Codex-CTA labels are untracked literals on the hero frame** — PouredSessionRow:1872, :1721; nothing in `roleTable` pins them, so any edit drifts silently. → *`feat: add a heroButtonLabel role (13/600) to PouredTypography and consume it at both call sites`*
3. **Poured `sideBadge`/bypass chip still mono against SPEC §2's explicit "drop mono", while the purpose-built `monoChip` role has zero call sites** — dead code beside a live violation. → *`fix: wire or delete PouredType.monoChip; convert sideBadge/bypass chip to sans per SPEC §2`*
4. **FD `count` role renders in 4 weight/design combinations** — FlightDeckSessionRow:536,601,633,638; ClosedPill:601,633,638. → *`refactor: split FD countSize into named sub-roles (countBadge/countValue/countLabel) instead of ad hoc weight+design per call site`*
5. **Halo `nestHeader` renders bold in one context, semibold in another** — HaloSessionRow:622,625,720,1102,2019. → *`fix: standardise Halo nestHeader weight to 700 per HaloTheme:101, or split into two named roles if the lighter weight is intentional`*
6. **FD usage `%` unit is 1pt below the pinned floor and invisible to tests** — FlightDeckUsageSummary:161. → *`fix: raise FD usage % unit to 10pt and add it to readableRoleSizes`*
7. **FD approval-button tracking ≈2× SPEC** — FlightDeckSessionRow:3098-3099.
8. **Structural root cause**: FD's `roleFamilies` doc-comment claims "single source of truth" but pins 9 of ~40+ rendered styles — this is what let #1, #4, #6 and #7 exist unnoticed. → *`test: extend FD roleFamilies/readableRoleSizes to every call site, or lint-fail any inline .system(size: outside FlightDeckTheme.swift`*
