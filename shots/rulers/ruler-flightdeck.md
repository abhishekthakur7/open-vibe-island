# FLIGHT DECK 2.0 — MEASURING RULER

Type scale: `enum FlightDeckTypography` in `Sources/OpenIslandApp/Theme/FlightDeckTheme.swift:26-134`. Floor = 10pt (:30).
Views in `Sources/OpenIslandApp/Views/Island/FlightDeck*.swift`. "sans" = `.default` design; unmarked = **mono**.

## A. TYPE SCALE
| Role | pt | Weight | Design | Tracking | Tab | Used in | file:line |
|---|---|---|---|---|---|---|---|
| microLabelSize | 10 | .semibold typical | mono | varies | no | captions, chips, badges, micro-labels **everywhere** | FlightDeckTheme:44 |
| labelSize | 11 | .medium | mono | — | no | `.label` (mostly unused directly) | FlightDeckTheme:45,109 |
| countSize | 11 | .semibold | mono | — | often | "×N" badge, gauge value, engine count, tile count | FlightDeckTheme:46,112 |
| bodySize | 12 | .regular | mono | — | no | panel body copy | FlightDeckTheme:47,115 |
| sessionNameSize `.ws` | 13.5 | .semibold (mockup 640) | **sans** | −0.135pt | — | session headline | FlightDeckTheme:52,65,124 → FlightDeckSessionRow:675-676, 2148-2149 |
| narrationSize `.narr` | 12 | .medium | **sans** | 0 | — | activity narration, header prompt | FlightDeckTheme:54,127 → FlightDeckSessionRow:714, 2158 |
| assistantSize `.assist` | 13 | .regular | **sans** | 0; lineHeight ×1.55 | — | assistant markdown card | FlightDeckTheme:56,69,130 |
| gaugeLabelSize `.glabel` | **10** (lifted from 9.5) | .semibold | **sans** | — | — | usage tape legend | FlightDeckTheme:59,133 → FlightDeckUsageSummary:151 |
| statusCodeSize `.code` | **10** (lifted from 9.5) | .bold | mono | **0.8pt** (0.08em) | no | STATUS column (RUN/DONE/CAUT/WARN) | FlightDeckTheme:62,67,119 → FlightDeckSessionRow:818-819 |
| closed-pill label | 11.5 | .medium | sans (mono on standby) | 1.0pt on standby caps | — | pill wing label | FlightDeckClosedPill:327,347-348,355 |

### Inline literals (NOT in the role table — the consistency risk surface)
trailing model/time cells 10.5 mono .medium (FlightDeckSessionRow:761,796) · metacell value 12 mono (:936) · agent identity 12 mono (:971) ·
engine elapsed 10.5 mono .semibold (:1325) · donestat values 13 mono .medium (:2373,2381,2388) · todo title 12.5 sans .regular (:1381) ·
engine task 11.5 sans .regular (:1295) · jump-button label 10.5 mono .semibold tracking 0.8 (:1044-1045) ·
**annunciator placard `.master .big` 10.5 mono .bold tracking 1.2 (:2626-2627) — SPEC says 12pt / weight 800 / 0.12em** ·
annunciator kicker 11 mono .semibold tracking 0.6 (:2635-2636) · HELD label **9**pt / value 11 (:2873,2877) ·
command box 11.5 mono .semibold/.regular (:2892,2901,2904) ·
**approval button label 11.5 mono .semibold tracking 0.8 (≈0.07em) (:3098-3099) — SPEC says 11pt / 600 / 0.04em** ·
key-hint chip 10 mono .semibold (:3121) · outcome badge 11 mono .bold tracking 0.8 (:2330-2332,2349-2351) ·
donestat key 10 **sans** .semibold tracking 1.0 (:2401-2404) · metacell key 10 **sans** .semibold tracking 1.0 (:948-949) ·
row chip 10 mono .semibold tracking 0.6 (:1928-1929) · column captions 10 mono .semibold tracking 1.0 (FlightDeckSessionListScaffold:245-247,260-261) ·
annunciator tile label 10 / count 11 (:379-386) · footer texts 10 tracking 1.2/1.0/0.8 (:436,444,451) ·
empty heading 10 tracking **1.8** (FlightDeckEmptyState:60-63) · empty copy 12.5 **sans** (:68-69) · empty sysline 10 tracking 1.0 (:79-81) ·
bootstrap STANDBY 10 tracking **1.6** (FlightDeckBootstrapPlaceholder:24-26) · bootstrap body 12 (:33) · bootstrap sub 10 (:36) ·
install-hint body 12 (FlightDeckInstallHooksHint:43) · install SETUP tag 10 tracking 1.2 (:48-50)

### Floor audit (SPEC §2, lines 143-179)
✅ `.code` 9.5→10 · `.colcap` 9→10 · `.glabel` 9.5→10 · metacell/donestat/engine/todo keys 9→10 · `.kk` 9→10
❌ **usage unit `%` renders at `countSize - 2` = 9pt** (FlightDeckUsageSummary:161) — still sub-floor, and **not covered by any `readableTextSizes` test list**
✅ overflow `+N` exempt at `max(5, size*0.55)` (FlightDeckClosedPill:738)
⚠️ `readableRoleSizes` (FlightDeckTheme:99-101) covers only the 9 `roleFamilies` entries — the dozens of inline literals above are NOT pinned. `roleFamilies` is **not** the single source of truth despite its doc comment.

## B. METRICS
`IslandMetricsTokens.flightDeck` (IslandMetricsTokens:151-166): openedTopRadius **6** (:152) · openedBottomRadius **6** (:153) ·
surfaceShadow black@**0.42** r**14** y**7** (:154-158) · openedShadowHInset 18 (:160) · openedShadowBInset 22 (:161) ·
closedShadowHInset 12 (:162) · closedShadowBInset 14 (:163) · closedHoverScale **1.028** (:164) · filletRadius 0 (:165)

### Chamfer radii (`FlightDeckChamferedRectangle`, FlightDeckSessionRow:2016-2039) — the theme's geometry signature
approval/MASTER card **6** (:2757,2827,2830) · completion card **6** (:2321-2322) · running-preview box 6 (:2275-2276) ·
command/diff well **5** (:2786-2787,2796-2797) · approval buttons **5** (:3087,3109-3110) · assistant card 4 (:1026,1028) ·
todo well 4 (:1368,1370) · metacell tile **3** (:956,958) · engine tile 3 (:1307,1309) · donestat tile 3 (:2410,2412) ·
annunciator beacon 3 (:2662) · MASTER placard 3 (:2631) · row chip **2.5** (:1934,1936) · key-hint chip 2.5 (:3125) ·
todo status box 2 (:1409,1416,1418) · engine lamp 1.5 (:1800) · empty lamp 2 / sysline dot 1 (FlightDeckEmptyState:113,77) ·
closed-pill grid lights **0** (square) (FlightDeckClosedPill:418-421)
SPEC §1b line 87 cites "card 6, box 5, button 5, placard 3, keycap 2.5" — code matches exactly.

### Grid / header
headerControlButtonSize **22** (FlightDeckHeaderControls:18) · spacing 8 (:19) · hPad 18 (:20) · topPad 2 (:21) · notchHPad 46 (:22) ·
notchLaneSafetyInset 12 (:23) · minRightUsageLane 58 (:24) · header button radius **4** (:260,263) · top-edge highlight 1pt (:270-272)
statusColumnWidth **58** (FlightDeckSessionRow:110) · leadingColumnGap 10 (:114) · columnGap 8 (:115) · modelColumnWidth **66** (:116) ·
timeColumnWidth **44** (:117) · detailToggleColumn 28 / dismissColumn 16 / trailingControlHeight 28 (IslandSessionRowMetrics:28,29,33)
Row summary pad top 11 / bottom 8 (sub-line) or 11 (:727-728) · status lane leading inset 5 (:1604) · vPad 6 (:641) ·
**status-lane width by priority: alert 5 / running 4 / done 3.5 / idle 3** (:174-181)
List max scroll 560 (FlightDeckSessionListScaffold:28) · column caption strip vPad 6 (:234) · summary annunciator strip height **40** (:141) ·
section header pad 10/7 (:270-271) · footer height **26** (:457)

### Surface tones (`FlightDeckSurfaces`, FlightDeckTheme:155-230) — mode-agnostic
panel **#0E1113** (:162) · tile **#101519** (:167) · hover **#161C22** (:171) · well **#060708** (:176) ·
hairlineBase **#9AB0BC** (:185) tier1 0.14 (:188) / tier2 0.26 (:191) / tier3 0.40 (:193), IC boost +0.19 (:198) ·
dimInk **#8A97A0** (:225) · faintInk **#5B656C** (:229) · paper **#D4DAD6** (IslandColorTokens:307) ⚠️ mockup says #D8E1E6 — unresolved by design

No notch vs top-bar metric divergence except `FlightDeckHeaderControls.usesNotchAwareLayout` (lane split + 46 vs 18 hPad).

## C. COMPONENT METRICS
| Component | Chamfer | Height | Pad H/V | Border | Icon | Label |
|---|---|---|---|---|---|---|
| ALLOW btn (`.inverted`) | 5 | intrinsic | 11/8 | 1pt `paper` full | — | mono 11.5/.semibold tracking 0.8 |
| DENY btn (`.outlined`) | 5 | intrinsic | 11/8 | 1pt paper@0.4 (0.7 IC) | — | same |
| Ghost btn (always-allow / terminal CTA) | 5 | intrinsic | 11/8 | 1pt paper@0.18 (0.5 IC) | 10.5 semibold | mono 11.5/.semibold |
| Keycap `.kk` | 2.5 | intrinsic | 4/1 | 1pt fg@0.35 | — | mono 10/.semibold |
| Count badge `×N` | — | intrinsic | none | none | — | mono 11/.semibold |
| Attention segment `⚠ ACK ×N` | — | intrinsic | HStack sp3 | none | glyph 11/.bold | mono 10/.bold tracking 0.8 |
| Row chip (SSH/branch/mode/⚙N SUB) | 2.5 | intrinsic | 5/1 | 1pt tier-2 or tint@0.4 | — | mono 10/.semibold tracking 0.6 |
| ATTACHED/STALE/DETACHED badge | — | intrinsic | none | none | — | mono 10/.semibold tracking 0.6 |
| Agent monogram | circle | 6×6 | — | none | 6 | mono 12/.medium beside |
| Agent cell (actionable) | rect | **3×11** | — | none | — | mono 10.5/.medium |
| Annunciator beacon lamp | 3 | 11×11 | — | none (filled) | — | — |
| Section header | — | pad 10/7 | = sideInset | top hairline 1pt | dot 7×7 | 10/.semibold tracking 0.9; count mono 10/.medium |
| Session row | — | intrinsic | sideInset; t11 b8/11 | top hairline 1pt | lamp 8×8, glyph 11/.semibold | sans 13.5/.semibold + sans 12/.medium |
| Metacell | 3 | minW **74** | 9/7 | 1pt tier-1 | — | key sans 10/.semibold tr1.0; val mono 12/.medium |
| **MASTER WARNING card** | **6** | intrinsic | outer **13** all; cmd box 9/7 | **1.5pt alarm@0.85 (1.0 IC)** | beacon 11×11 | placard mono 10.5/.bold tr1.2; kicker mono 11/.semibold tr0.6 |
| Completion card | 6 | intrinsic | md 12/9; donestats 12/t6 b12 | 1pt tier-2 | check 10.5 bold | badge mono 11/.bold tr0.8 |
| Tape gauge | track r1 | trackHeight **8** (mini 6) | gauge width **150**; mini 16 | tick 1pt, track hairline 1pt | — | legend sans 10/.semibold; value mono 11/.bold + unit mono **9**/.semibold |
| Command box (well) | 5 | intrinsic | 9/7 | 1pt tier-2 | — | mono 11.5/.semibold; path 10.5/.medium @0.5 |
| Diff box (well) | 5 | intrinsic | 9/7 | 1pt tier-2 | — | shared `PermissionDiffPreview` |
| Engine tile | 3 | minW 120 / maxW 168 | 10/9 | 1pt tier-2 | lamp 8×8 chamfer 1.5 | placard mono 10/.bold tr0.6; task sans 11.5; elapsed mono 10.5/.semibold |
| Todo row | — | intrinsic | 11/8 | divider 1pt tier-1 | status box 14×14 (chamfer 2) | title sans 12.5 strikethrough-on-done; tag mono 10/.semibold tr0.6 |
| Header button | r **4** | 22×22 | — | 1pt hairline (+0.14 hover) + 1pt top-edge highlight | glyph 10/.semibold | — |
| Annunciator tile (ATTN/RUN/DONE/IDLE) | r 3 | intrinsic | 5(compact)/7 · 4 | 1pt tier-2 | lamp 6×6 | count mono 11/.bold; caption 10/.semibold tr0.8 |
| Bridge footer lamp | rect | 6×6 | — | none | 6×6 | 10/.semibold tr 1.2/1.0/0.8 |
| Empty monitor lamp | 2 | 11×11 grid / 6×6 sysline | — | dark variant 1pt tier-2 | — | — |

## D. FIDELITY BAR
**Material (`IslandMaterialTokens.flightDeck`, IslandMaterialTokens:195-212):** `.hudWindow` / `.behindWindow` / `.vibrantDark`, **tintOpacity 1.0** (fully opaque),
`specularTopEdge: nil`, `bodyGradient: nil`, `specularHardEdge: nil`, `innerHairline: nil`. `usesVibrancy = false` (FlightDeckTheme:318).
FD deliberately has **zero gradient stops** — flat ink fill. Depth comes from the discrete surface-tone stack (panel→tile→hover→well), not a continuous gradient. This is SPEC-sanctioned ("unchanged"), NOT a fidelity miss.

**Glow bleed — the theme's signature (SPEC §1d, "the single biggest visual delta"):**
SPEC verbatim: *"every lit lamp/beacon: box-shadow: 0 0 5–14px <status> bleeding outside the silhouette… shipped lamps are flat, no glow… §7 fidelity bar mandates 'glow that bleeds outside the silhouette.'"*
Implemented as `FlightDeckPhosphorGlow<S: Shape>` (FlightDeckPhosphorGlow:29-52): fill shape with tint → `.blur(radius:)` → `.opacity(intensity)` → `.padding(-bleed)` (default bleed **2**) so light spills outside before blurring.
Applied at: closed-pill running/waiting lamp (FlightDeckClosedPill:782-787,822-827) · status lane (FlightDeckSessionRow:1732-1737) · engine lamp (:1812-1817) · annunciator tile (FlightDeckSessionListScaffold:371-376) · bridge lamp (:494-499) · empty monitor lamp (FlightDeckEmptyState:129-134) · MASTER card halo (`FlightDeckCautionGlow` radius 9, FlightDeckSessionRow:3019-3065).
**Every lit lamp in every frame must show visible bleed. A flat lamp = MAJOR.**

**Shadows:** opened surface black@0.42 r14 y7 — *"an avionics panel is seated in the airframe, it does not float."*
Closed-pill attention bloom: warning-red r12 @0.6 y6 border@0.55; caution-amber r8 @0.5 y6 border@0.5 (`FlightDeckMotion.Bloom`, FlightDeckPhosphorGlow:170-178).

**Motion "phosphor" / relay-snap (`FlightDeckMotion`, FlightDeckPhosphorGlow:92-250):**
breathe (running lamp) 2.0s, opacity .86→1.0, glow r5→11, ease-in-out (:94-96) · monitor (empty heartbeat) 2.6s (:113-115) ·
attention: warningPeriod **1.0s**, cautionPeriod **1.2s**, opacity 1.0→0.28 (:117-129) ·
snap: onDuration **0.0 (instant)**, decayDuration **0.12** (:131-140) ·
settle (A5 one-shot) 3.0s, flashScale 1.25, flashGlow 18, settledGlow 5, key 0.2 (:142-158) ·
entrance (relay-snap) slide 12pt, opacity 0→1, spring(0.32, 0.92) (:180-196)
Theme springs (IslandMotionTokens:107-112): open `spring(0.32, 0.92)` · close `.smooth(0.24)` · pop `spring(0.22, 0.6)` · unmountDelay 0.28.
*"A hard, deterministic snap — an annunciator panel latches to its readout with no overshoot, the way a relay throws."* All ramps gated on `accessibilityReduceMotion` → steady lit peak.

## E. CONFLICTS / DRIFT
1. **MASTER placard undersized**: SPEC §2 says **12pt / weight 800 / 0.12em**; code renders **10.5pt / .bold(700) / tracking 1.2** (FlightDeckSessionRow:2626-2627). Smaller AND lighter than spec. `.heavy`/`.black` exist and weren't used. Genuine deviation on the hero frame.
2. **Usage `%` unit at 9pt** (FlightDeckUsageSummary:161) — violates the pinned 10pt floor; untested by any `readableTextSizes` list.
3. **Approval button tracking ≈2× spec**: SPEC 11pt/600/**0.04em**; code 11.5pt/.semibold/0.8pt ≈ **0.07em** (FlightDeckSessionRow:3098-3099).
4. **Usage gauge uses raw SwiftUI system colors** — `usageColor(for:)` returns `.red/.orange/.green` @0.95 (FlightDeckUsageSummary:193-202), NOT the FD status tokens `#E04A42`/`#E6AA42`/`#4AC99E`. System green/orange/red differ visibly from the FD palette. **Measurable, unflagged.**
5. `roleFamilies` covers only 9 roles; the long tail of inline `.system(size:)` literals is unpinned (see §A).
6. `paper` is `#D4DAD6` in code vs mockup `#D8E1E6` — SPEC left it an open choice. Measure against **#D4DAD6**.
7. **No conflicts** in metrics tokens (radii 6/6, shadow 0.42/14/7, insets 18/22/12/14, hover 1.028, fillet 0) or motion tokens — all exact SPEC matches. SPEC's "changed" motion rows describe a since-closed gap (AB-336/337/339 landed).
