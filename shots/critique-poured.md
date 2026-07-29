# Poured Island 2.0 — per-frame visual fidelity critique (raw agent output, pre-verification)

Method notes from the critiquing agent (important — these prevented two false findings):
- Every RGBA app crop was composited onto **true black** before judging glow/material. Several apparent "faint" glows were **white-matte artifacts of the viewing tool**, not code defects.
- Corner radii measured by scanning the leftmost non-background pixel per row near a card's top-left and finding where the curve flattens into the vertical edge.
- Text sizes measured by cap-height/x-height bounding boxes of isolated glyphs. All app px → pt halved per the @2x rule.

## Findings (⚠ = coordinator-flagged as at-risk of being a fixture/content artifact)

| # | Frame | Dim | Sev | Mockup shows | App shows | Measured delta | Suspected file:line |
|---|---|---|---|---|---|---|---|
| 1 | A3 | 6 | MINOR | single filled dot (~8pt) with a soft ring | **two vertical amber bars** (pause-icon-like), no dot/ring | app glyph = 2 bars ~1.5pt wide, ~5pt apart; **0 circular elements** in a 5× zoom | `PouredClosedPill.swift:121-125,435-451` (`PouredPillRingedDot` looks correct) vs the AB-243 traveling-glyph seam `:96-98,200-203` — possibly a **mid-morph capture**, flag verify-live |
| 2 | A2 | 5 | MINOR | 3 staggered wave bars, clearly bar-shaped | glyph reads as near-square dots | bar width 2.5pt vs on-screen height ~4-6pt → near 1:1 aspect instead of tall/thin | `UnifiedBars.swift:40-47` — **verify live**, static capture of a breathing animation |
| 3 | C,E1,E3,G | 1 | **MAJOR** | terminal/agent chips ("codex","Opus 4.8","SSH") in plain sans, matching neighbouring chips | `sideBadge` ("Ghostty","Codex.app") renders **clearly monospaced in every frame checked** — fixed glyph advance, distinctive mono G/d/x | confirmed at 5× zoom in **4/4 frames**. Pervasiveness is itself the finding: it is the one chip in every frame that doesn't match its neighbours | `PouredSessionRow.swift:1181-1188`, `:1213-1218`; dead `monoChip` at `PouredTypography.swift:183` |
| 4 | E1/E2/E3 | 1 | **MAJOR** | Allow/Deny/Codex-CTA labels drawn from the scale, close to the Jump CTA's weight/size | measured "Allow" cap-height 19px@2x = **9.5pt cap** → ~13-14pt font, matching the hardcoded `13/semibold` | ~13% oversized vs the 11.5pt `jumpChip` role used elsewhere in the same row family; unpinnable | `PouredSessionRow.swift:1872,1885-1898`, `:1721` |
| 5 | C | 3 | **MAJOR** | compact one-line rows; actionable row height **86–98pt** (title-to-title 274→372 = 98pt; 486→572 = 86pt) | top two sessions render as full row-**detail** cards (metadata grid + last-message block + Jump + Pane-attached chip) **inline in the list**, not compact summary rows | title-to-title = 504px@2x = **252pt** → **~2.6–2.9× taller**. Only **2 of 9** sessions fit before cutoff vs the mockup fitting **6 rows across 3 sections** in the same footprint | `PouredSessionRow.swift` row-detail composition / `PouredSessionListScaffold.swift` height budget — conflates §3.3 row with §D detail in list context |
| 6 ⚠ | C/D | 2 | MINOR (verify) | 6-cell metadata grid (Agent/Model/Permission/Branch, Live/Directory) | only 3 cells (Agent/Live/Directory) | 3 of 6 (50%) — **could be fixture data availability**, not asserted as a hard omission | — |
| 7 | F | 2 | **MAJOR** | one compact header row: amber `.q-chip` capsule ("AUTH") + session name + "Question 1 of 2" tabular progress, all on one ~24pt line | **no chip component at all**; 4 stacked plain-text lines | header block 90px@2x = **45pt** (4 lines) vs mockup's single **24pt** row — visually confirms the dead `questionChip` role | `PouredTypography.swift:207` (DEFINED, NEVER CONSUMED) |
| 8 | F | 1 | MEDIUM | `questionText` 14.5/560 vs `optionLabel` 13/600 — a visible size step | both measured at identical 18px@2x = **9pt cap-height** | **0pt** apparent difference where spec calls for 1.5pt | `PouredTypography.swift:203-204` (both DEFINED, NEVER CONSUMED) |
| 9 | F | 6 | MINOR | no indicator on unselected options; amber tick + 1.5px ring **only** on the selected row | **every** option row shows a hollow radio-circle at rest | 4/4 rows show a ring vs 0/3 unselected in the mockup | shared question view |
| 10 | F-multi | 3 | **MAJOR** | one question at a time, "Submit & next" progression | both questions render fully expanded, **stacked in one scrolling card** | combined content ≈ 660px@2x = **330pt**, structurally taller/denser than any single mockup F frame | (independent of the known fixture text-duplication bug) |
| 11 ⚠ | H | 2 | **MAJOR** | 4 footer actions — Jump (primary) + Reply/Transcript/Dismiss (ghost) — plus a "RESULT" caption and bulleted prose | only "Jump to terminal"; Reply/Transcript/Dismiss and the RESULT caption absent. **Card's rounded bottom edge + shadow render in full — confirmed NOT a clipping artifact** | 1 of 4 footer actions (25%); 0 of 1 captions | `PouredSessionRow.swift:915-953`; a Dismiss ghost exists at `:1044` but isn't wired into this footer — **coordinator note: dismiss is hover-reveal by design** |
| 12 | I | 3 | MAJOR / coverage gap | dedicated full-meters card: 52pt conic dials, Fine/Warn/Critical states, per-window "resets in …" | capture shows only the compact header-ring summary (34/78/92); the full-dial card never appears in the captured extent | 0 of 1 primary §I component instances observed. **What IS visible (header rings) matches spec closely** | needs a targeted capture |
| 13 | F | 2 | MINOR (±1-2pt caveat) | question hero r18 vs approval hero r15 — an intentional escalation | corner flatten measured 31px@2x = **15.5pt** vs approval hero's measured **13.5pt** | ~2.5pt undersized; the escalation is **nearly invisible** in practice (13.5→15.5 measured vs 15→18 spec'd) | `PouredSessionRow.swift:871-885` |
| 14 | A6 | — | coverage gap | closed-pill outcome glyphs (▮ stop / ✕ fail in a tinted circle) **on the pill** | both captures show the **fully-expanded row-detail card**, not the closed pill; `completedFailed` additionally clipped by the banner artifact | frame-scope mismatch — cannot compare pill glyphs. The comparable part (outcome badge chip colour) **matches spec** (amber/red) | — |

## Confirmed PASSES (stated to avoid false negatives)
- **3-stop body gradient present and smooth** — sampled RGB(31,34,44)→(14,16,23) **monotonically** down the panel in `poured-sessionList.png`. Not flattened.
- **A3 amber glow bleeds ~8–9pt outside the pill silhouette** at visible alpha (more at low alpha) — but **only apparent when composited on black**; on a white matte it looks nearly invisible. Viewing artifact, not a code defect.
- **Approval hero r15 and completion card r12** both measured within ~1.5pt of spec.
- **E1 effect-line amber tint** ≈ (214,183,135), consistent with `rgba(255,214,160,.75)` over the dark card.
- **Header usage rings** (34/78/92): conic dial styling, threshold colouring and "resets in …" countdown all match the mockup well.
- **E2 (diff) and E3 (Codex) are the strongest matches observed** — diff colouring/gutter numbers, the honest single "Jump to Codex to approve" CTA, and the scoped always-allow row all track the mockup closely.

## Per-frame grid (Typo / Comp / Layout / Material / Motion / Colour / Premium)
| Frame | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| A1/A2 | PASS | MINOR | PASS | PASS | verify-live | PASS | MINOR |
| A3 | PASS | MINOR | PASS | PASS | verify-live | PASS | MINOR |
| A6 | PASS | gap | gap | gap | gap | PASS | gap |
| C | MAJOR | MAJOR | MAJOR | PASS | verify-live | PASS | **MAJOR** |
| D | MINOR | MINOR | MINOR | PASS | gap | PASS | MINOR |
| E1 | MAJOR | MINOR | PASS | PASS | verify-live | PASS | MINOR |
| E2 | MAJOR | PASS | PASS | PASS | verify-live | PASS | MINOR |
| E3 | MAJOR | PASS | PASS | PASS | verify-live | PASS | MINOR |
| F single | MAJOR | MAJOR | MINOR | PASS | verify-live | MINOR | **MAJOR** |
| F multi | n/a | MAJOR | MAJOR | PASS | verify-live | PASS | **MAJOR** |
| G | MINOR | PASS | MINOR | PASS | verify-live | MINOR | MINOR |
| H | MINOR | MAJOR | MINOR | PASS | n/a | PASS | **MAJOR** |
| I | PASS | gap | gap | PASS | verify-live | PASS | gap |
| J | PASS | PASS* | PASS* | PASS | verify-live | PASS | PASS |
| B, K | — | — | — | — | — | — | coverage gap (not drivable from stills) |

\* modulo the known install-hint-banner clipping on `poured-emptyState.png`.

## Holistic verdicts
- **C is the single worst frame** — rows are ~2.7× too tall because full row-detail content is baked into the list view, hiding most of the session list. This is the reviewer's "space spent, not invested" complaint **inverted**: over-invested per row, under-invested in overall visibility.
- **E1/E2/E3 are the strongest cluster** — glass, radius, diff/gradient and honesty-of-CTA all read close to the mockup; let down only by the pervasive mono `sideBadge` and the hardcoded button font.
- **F single reads exactly like the "restyled form, not a designed component" anti-pattern** BRIEF §7 warns against: missing chip, flat type hierarchy, decorative always-on radio rings.
- **F multi** structurally diverges from the one-question-at-a-time flow; very tall, cluttered card.
- **G** is one of the better busy frames — nest slabs and task list close to spec.
- **H** functional but plain — missing footer actions and the RESULT caption/bullets that make the mockup's completion card feel "rendered beautifully".
- **J** is the best-conforming frame in the set.
