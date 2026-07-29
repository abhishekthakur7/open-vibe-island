# Flight Deck 2.0 — per-frame visual fidelity critique (raw agent output, pre-verification)

Calibration followed: flat/opaque body is CORRECT for this theme; only **absence of glow bleed** is penalised.

## Findings
| # | Frame | Dim | Sev | Mockup shows | App shows | Measured delta | Suspected file:line |
|---|---|---|---|---|---|---|---|
| F1 | E1/E2 | 4 material | **MAJOR** | MASTER WARNING/CAUTION card silhouette has a soft ambient halo bleeding into the void (`FlightDeckCautionGlow`) | card edge is a **hard 1px cut** from background straight to card fill — **zero blend/blur pixels** | `approvalCard.png` y=400: x=61 bg(8,9,10) → x=64 border(94,42,36), **0px transition**. Same at top edge y=261→262; reconfirmed in `diffApprovalCard.png` x=63→64. **Contrast: the closed-pill grid lamp DOES show a ~3px halo** — so glow works elsewhere but is absent on the hero card | `FlightDeckSessionRow.swift:3019-3065`, card chamfer :2757/2827/2830 |
| F2 | E1/E2/E3 | 4 | **MAJOR** | card body fill is near-black maroon **#231718**, so the bright beacon pops ~3.5× brighter as a distinctly "lit" element | card body fill is a much lighter, desaturated red wash; beacon barely differentiates | app bg **#682E27** (104,46,39) vs mockup **#231718** (35,23,24) — app is **~3× lighter**. App beacon #883B31 gives only a **1.3×** brightness ratio vs the mockup's **3.5×** | `FlightDeckSurfaces` alarm tint composition, `FlightDeckSessionRow.swift:2757` region |
| F3 | E1/E2/E3 | 1 typo | **MAJOR** (pixel-confirms known drift) | "MASTER WARN" reads as a loud headline | placard cap-height measurably smaller | app cap-height **15px@2x = 7.5pt**; mockup **9px@1x = 9pt**. Ratio **0.83** — matches code's 10.5pt vs SPEC's 12pt (0.875) | `FlightDeckSessionRow.swift:2626-2627` |
| F4 | E1,E2,E3,F1,F2 (**5/5 sampled**) | 2 comp | **MAJOR** | MASTER header is a unified strip: beacon + placard left, divider, **session identity (agent, model, branch)** centre, HELD timer right — all inside the tinted card | card header has only beacon + placard + kicker + HELD. **No identity slot exists inside the card in any of 5 captures**; that data sits in the plain black row above | identity block = **~35%** of mockup header width (x≈470-750 of 1098) vs **0%** in all 5 app samples | `FlightDeckSessionRow.swift` ~2600-2660 |
| F5 | C | 3+4 | **MAJOR** | ATTN/RUN/DONE/IDLE are 4 **full-height instrument tiles** with a coloured left accent bar and a large bold count over a caption | 4 small **single-row pill chips** (icon+digit+label inline) after a plain "SESSIONS" label | mockup tile bbox **55pt** vs app chip row **44px@2x = 22pt** → mockup is **~2.5× taller/more prominent** | `FlightDeckSessionListScaffold.swift:141` (strip height 40) |
| F6 | I | 1 | **MAJOR** (pixel-confirms known drift) | — | "%" renders visibly smaller than its numeral | "78" cap **16px@2x = 8pt**; "%" cap **13px@2x = 6.5pt**, ratio **0.81**, matching `countSize−2` = 9pt vs 11pt (0.818). Independent confirmation of the sub-floor violation | `FlightDeckUsageSummary.swift:161` |
| F7 | I | 6 colour | **MAJOR** (pixel-confirms known drift) | FD caution token **#E6AA42** | gauge fill sampled **#E39244** (227,146,68) | **ΔG = −24 (~9%)**, visibly more orange/red-shifted, less amber-yellow — consistent with raw SwiftUI `.orange` | `FlightDeckUsageSummary.swift:193-202` (`usageColor(for:)`) |
| F8 | I | 3 | MINOR (capture artifact) | — | tape gauges only partially visible; the install-hint banner overlaps and draws text through the bar | gauge content visible only y=0-90 of a 1386px capture; obscured y≈95-175 | harness / `FlightDeckInstallHooksHint` z-order — **see coordinator finding C4, same root cause** |
| F9 | H (**2/2 sampled**) | 3 | **MAJOR** | footer action row — Jump to terminal, Transcript/Reply, Dismiss — always visible under the metadata tiles | card closes (rounded bottom + drop shadow) immediately after the OUTCOME/DURATION/AGENT tile row in both captures. **No action row rendered** | 0 of 2 cards show any footer affordance; mockup reserves ~44pt for it | `FlightDeckSessionRow.swift` ~2321-2412 |
| F10 | H | 2 | MINOR | outcome renders as a large bordered icon+label box in a 2-column layout beside the prose | outcome is only a small inline "✓ SUCCESS" badge above the prose (single column); data isn't lost (still in the tile row), only the component differs | mockup result box ≈86×86pt dedicated container vs app's ~14pt inline badge | `FlightDeckSessionRow.swift` completion composition |
| F11 | E3 | 6 colour | **MAJOR** | "Jump to Codex.app" is a small, right-aligned, **neutral dark blue-grey** button beside explanatory copy in its own "APPROVE IN CODEX" sub-panel — a **wayfinding** action, not a decision | "RESPOND IN TERMINAL" is a **full-width button in the same alarm-red palette** as the rest of the MASTER WARNING card — borrowing DENY-adjacent urgency for a navigation action — with no explanatory copy or sub-panel | width **100%** of card (≈940px@2x) vs mockup's **~27%**; fill matches the alarm-red family vs mockup's neutral ~#26313C | `FlightDeckSessionRow.swift` ~2892-2910 |
| F12 | F1/F2 | 2 | MINOR | topic tag ("AUTH"/"SCOPE") is a bordered uppercase **mono chip** | plain grey **mixed-case sans** text, no border, no background | mockup chip ≈62×22pt with 1px border + padding; app has 0px border, no fill | question-topic label; `:1928-1936` chip style not applied |
| F13 | A3 | 3 | MINOR (MAJOR if reproducible outside harness) | full "ACK ×1" badge, rounded right corner, glow bloom fully visible | content **hard-clipped at the canvas edge** — the "1" of "×1" and the pill's right corner/bloom cut off mid-shape | alpha bbox ends x=769 of a 1112px canvas; cutoff is a **flat vertical edge**, not a rounded corner. **AX tree confirms the full label "1 waiting for approval" exists**, ruling out a data bug → points to capture-canvas width | harness pill sizing for the attention state |
| F14 | G | — | coverage gap | expanded engine cluster (3 subagent tiles) + 6-item task checklist | only the collapsed row ("⚙ 3 SUB" chip + narration) — identical to sessionList.png. **AX tree contains no engine-tile or task-list text** | cannot score dims 1-4 for the expanded state | capture/fixture — row never expanded |

## Positive confirmations (not findings)
- **Closed-pill agents-grid lamp (A2)**: lit lamp shows a genuine soft green halo bleeding **~2-3px outside its housing** — phosphor glow works correctly here. This is what makes F1 (no bleed on the hero card) a real finding rather than a theme-wide absence.
- **Empty-state monitor lamp (J)**: visible green bleed with chamfered (not square) corners — PASS for the portion visible before the known clip.
- **A6 outcome semantics**: INTERRUPTED renders amber/⊘, FAILED renders red/× — never green for both. PASS.

## Per-frame grid (Typo / Comp / Layout / Material / Motion / Colour / Premium)
| Frame | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| A1/A2 | PASS | PASS | PASS | PASS | verify-live | PASS | PASS |
| A3 | MINOR | MINOR | MAJOR | MINOR | verify-live | PASS | MINOR |
| A6 | PASS | PASS | PASS | MINOR | verify-live | PASS | PASS |
| C | MINOR | MAJOR | MAJOR | MAJOR | verify-live | PASS | **MAJOR** |
| E1 | MAJOR | MAJOR | MINOR | MAJOR | verify-live | PASS | **MAJOR** |
| E2 | MAJOR | MAJOR | MINOR | MAJOR | verify-live | PASS | **MAJOR** |
| E3 | MAJOR | MAJOR | MINOR | MAJOR | verify-live | MAJOR | **MAJOR** |
| F1/F2 | MINOR | MAJOR | MINOR | MAJOR (shared comp) | verify-live | PASS | MINOR/MAJOR |
| G | gap | gap | gap | gap | verify-live | gap | gap |
| H | PASS | MINOR | MAJOR | PASS | verify-live | PASS | MINOR/MAJOR |
| I | MAJOR | PASS | MINOR | PASS | verify-live | MAJOR | **MAJOR** |
| J | gap (clip) | PASS | gap (clip) | PASS | verify-live | PASS | gap |
| B, D, K | coverage gap — not drivable from stills |

## Holistic verdicts
- **C is the biggest single delta in the whole review** — the annunciator strip is meant to be the cockpit's defining instrument-panel moment and instead reads as a thin status bar.
- **E1/E2/E3: the brief's own top-priority bar ("the hero permission frame must feel like an EVENT") is NOT met** — flat no-bleed silhouette, a 3× too-light card fill that kills the beacon's pop, an undersized placard, missing identity data, and on E3 a colour-discipline violation that paints a navigation action in decision-red.
- **H** — missing the entire follow-up action row is a functional-feeling loss, not just cosmetic.
- **I** — two independently pixel-confirmed drift items (sub-floor `%`, off-token gauge colour).
- **A1/A2, A6, J** — close to the mockup; the differences are expected top-bar chrome or the known clip artifact.
