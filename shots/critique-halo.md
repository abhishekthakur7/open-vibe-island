# Halo — per-frame visual fidelity critique (raw agent output, pre-verification)

Calibration confirmed by the critiquing agent: t1 text sampled 242/255 = 0.949; t3 sampled 128/255 = 0.502 — **the corrected t3 = 0.50 is shipping correctly** (not the mockup's failing 0.42). This validates the sampling method used below. All deltas already halved for @2x→@1x.

## Findings (⚠ = flagged by coordinator as at-risk of being a fixture/content artifact, sent to adversarial verify)

| # | Frame | Dim | Sev | Mockup shows | App shows | Delta | Suspected file:line |
|---|---|---|---|---|---|---|---|
| 1 | A2 | 6 colour | MAJOR | working liveness glyph in cyan→blue gradient (peak RGB 59,206,255 → 105,124,255) | glyph renders **pure achromatic white** (255,255,255 / 242,239,238) | saturation 0 vs saturated cyan; working state carries zero colour signal | `HaloClosedPill.swift` wave glyph paint (motion const HaloTheme:332,337) |
| 2 | A3 | 2/6 | MAJOR | loudest ambient state = single solid **amber-filled dot** left of label | **two neutral-gray bars** (143,141,141 / 74,72,71 — R≈G≈B), same glyph family as idle/working | saturation 0; wrong shape (2 bars vs 1 filled dot) | `HaloClosedPill.swift:817-836` |
| 3 | A3 | 3 layout | MINOR | ~6pt glyph→label gap (`notchLaneLabelGap`) | ~5pt (10px @2x) | 1pt short of token | `HaloClosedPill.swift:53` |
| 4 ⚠ | C | 2/3 | MAJOR (caveated by agent) | rows grouped under `NEEDS YOU / RUNNING / DONE` headers w/ counts | flat chronological list, 0 section headers | 0 vs 3 headers | `HaloSessionListScaffold.swift:133,192` — **coordinator note: `appearance.island.v8.notch.sessionGroup = none` is the user's setting; likely NOT a defect** |
| 5 | C | 3 | MINOR | footer = "6 sessions · 2 need you" (left) + "≡ Group by project" (right) | left half only; right side empty | 1 of 2 footer elements | `HaloSessionListScaffold.swift` footer |
| 6 ⚠ | E1/E2/E3 | 2 | MINOR | annunciator slot pairs monogram **+ model label** ("Sonnet 5"/"Opus 4.8"/"Codex") | bare 16×16 monogram only, no label | 0/3 hero frames show the label | `HaloSessionRow.swift:1682-1690` |
| 7 | E2 | 4 | MINOR | scope sentence highlights the scope term in an amber mono chip (`rgba(255,160,80,.1)` bg, `#ffd6a4` text) e.g. `*.md` | "AGENTS.md/" is plain uniform-gray inline text, no chip | chip tint 0% applied | `HaloSessionRow.swift:2361-2364` / `:2397-2401` |
| 8 | E3 | 2 | MINOR | "Jump to Codex" carries an inline `⌘J` keycap | no keycap at all | 0 vs 1 keycap | `HaloSessionRow.swift:2292-2294` — **new mockup-vs-code drift not in the ruler** |
| 9 | F1 | 4/6 | MAJOR | primary CTA "Next ↵" = compact intrinsic-width **amber-gradient pill** (peak 255,188,110) | "Submit Answers" is **full-card-width, flat neutral** fill (22,22,22), gray text (120,120,120), R=G=B, zero amber | full-scale hue delta; the "restyled form" anti-pattern §7 warns about, on the theme's own primary CTA | shared question view — **corroborates Appendix B.0** |
| 10 | F1 | 2 | MINOR | unselected options carry **no** persistent control; only selected gets ring+check; number chips faintly amber-tinted (38,32,21) | **every** option shows a permanent hollow radio circle (130,112,73); chips neutral gray (25,25,25) | control on 4/4 rows vs 0/2 unselected; chip tint 0% vs ~15% | shared question option row |
| 11 | F2 | 3 | MAJOR | **one question at a time**, full-height focus, "N of M" counter in the card header, paginated | both questions stacked in one continuous scroll, single Submit at the bottom | 2 concurrent vs 1; "N of M" demoted from qChip pill to inline plain text | question flow container; `HaloTheme:94` qChip not reapplied |
| 12 ⚠ | H | 2 | MAJOR | metadata grid has 4 cells: Outcome / Duration / **Model** / Finished | only 3 cells — Model absent in **both** independent captures | 3/4 fields (75%) | `HaloSessionRow.swift:1072-1087` |
| 13 ⚠ | H | 2 | MAJOR | footer of up to 4 actions: Jump (primary) + Transcript + Reply + Dismiss (×, right) | single combined "↗ Jump · Ghostty"; other three absent in both captures | 1/4 footer actions | `HaloSessionRow.swift:519,1200`; dismiss :1449 — **coordinator note: dismiss is hover-reveal by design, invisible in a static capture** |
| 14 ⚠ | A6-Failed | 6 | MAJOR | failed = static dim-**red** edge/dot + coloured outcome pill, "visibly distinct" per SPEC A6 | status dot neutral gray (75,75,75), R=G=B; **no outcome badge at all** — unlike the Interrupted sibling which shows an amber "■ Interrupted" pill | saturation 0%; 0 badges vs 1 for every other variant | `HaloSessionRow.swift:1245-1251,1352-1355`; badge :351-353 |
| 15 ⚠ | A6-Failed | 2 | MAJOR | same OUTCOME/DURATION/FINISHED + RESULT template as every other completed outcome | Failed uses a **different template**: AGENT/TERMINAL 2-col grid + "LAST MESSAGE · CODEX" card | 2 templates for one semantic slot | completed-detail `outcome == .failed` branch |
| 16 | I | 2 | coverage gap | SEC-I full usage card: three **52pt** filament dials + FINE/WARN/CRITICAL badges + "resets in …" | only the compact 22pt top-bar header filaments; the 52pt dial card never appears | 0/3 dial cards visible | `HaloUsageMeterCard` |
| 17 | G | — | coverage gap | expanded nested subagent list + todo states | row shows only its collapsed one-line summary; nested expansion never renders (click-to-expand not exercised) | — | — |
| 18 | J | — | coverage gap | "All quiet" + subtitle + "Monitoring · N workspaces" pill | clipped by the install-hint banner — only a sliver of the monitor glyph visible | — | harness artifact; **extend the known-clipped list to include `halo-emptyState`** |

## Confirmed CORRECT (not findings — recorded for honesty)
- **E1/E2 permission hero materially matches spec** — inset amber→magenta ring ~1.5pt, outer glow bleed, Allow-once/Deny colours, real syntax-highlighted command and diff. The frame the brief calls "most-polished" largely earns it.
- **t3 tertiary opacity = 0.50** confirmed shipping (peak 128/255), i.e. the SPEC correction landed and the mockup's 0.42 is the wrong one.
- **Header control buttons measured 26×26pt** (51px@2x) — matches spec exactly, not oversized.
- **Square vs round option markers** correctly differentiate multi-select from single-select in F2.
- **Rich assistant markdown** (bold, inline mono code chips, links) renders correctly in longCompletionCard.

## Per-frame grid (Typo / Component / Layout / Material / Motion / Colour / Premium)
| Frame | Typo | Comp | Layout | Material | Motion | Colour | Premium |
|---|---|---|---|---|---|---|---|
| A2 | PASS | MINOR | PASS | PASS | verify-live | MAJOR | MINOR |
| A3 | PASS | MAJOR | MINOR | PASS | verify-live | MAJOR | MAJOR |
| C | PASS | MAJOR⚠ | MINOR | PASS | n/a | PASS | MINOR |
| E1 | PASS | MINOR | PASS | PASS | verify-live | PASS | PASS |
| E2 | PASS | MINOR | PASS | PASS | verify-live | PASS | MINOR |
| E3 | PASS | MINOR | PASS | PASS | verify-live | PASS | MINOR |
| F1 | PASS | MAJOR | MAJOR | MAJOR | verify-live | MAJOR | MAJOR |
| F2 | PASS | MINOR | MAJOR | MAJOR | verify-live | MAJOR | MAJOR |
| G | gap | gap | gap | gap | gap | gap | gap |
| H | PASS | MAJOR⚠ | MINOR | PASS | verify-live | PASS | MAJOR |
| A6-Interrupted | PASS | PASS | PASS | PASS | verify-live | PASS | PASS |
| A6-Failed | PASS | MAJOR⚠ | MINOR | PASS | verify-live | MAJOR⚠ | MAJOR |
| I | gap | MAJOR | gap | gap | gap | partial | gap |
| J | gap | gap | gap | gap | gap | gap | gap |

## Holistic verdicts
- **A2/A3 pill** — body (ring, glow, badge) is right, but both liveness glyphs lost their colour: working shows white bars instead of cyan, attention shows gray bars instead of a solid amber dot. Most damaging gap for "readable across the room", since the glyph is what users glance at first.
- **C list** — rows individually clean and correctly typeset; the list lacks grouped sections and a balanced footer (grouping likely a settings artifact).
- **E1/E2/E3 heroes** — best frames in the set; genuinely read as an event. Remaining gaps are polish nits.
- **F1/F2 questions** — **the weakest frames.** Flat gray full-width Submit with zero accent, persistent radio circles on every option, and a stacked instead of paginated multi-question flow. Exactly the "restyled form, not a premium event" failure §7 warns about.
- **H completed** — typography and rich text genuinely good; missing metadata field and footer actions reproduce across two captures.
- **A6** — Interrupted is a strong match; Failed drops to a badge-less, colourless layout, contradicting SPEC A6's "visibly distinct outcomes".
- **G / I / J** — genuine coverage gaps needing dedicated re-captures (row expanded, usage card, banner-free empty state).
