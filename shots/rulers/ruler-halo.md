# HALO — MEASURING RULER

Type scale: `enum HaloTypography` in `Sources/OpenIslandApp/Theme/HaloTheme.swift:29-204`. Floor = 10pt (:32).
Font `.system(design: .default)` unless marked **mono**. Views live in `Sources/OpenIslandApp/Views/Island/Halo*.swift`.

## A. TYPE SCALE
| Role | pt | Weight | Design | Tracking | Tab | Used in | file:line |
|---|---|---|---|---|---|---|---|
| pillLabel | 12.5 | regular | sans | −0.01em | no | closed-pill label | HaloTheme:47 → HaloClosedPill:47 |
| pillValue | 11 | regular | **mono** | — | no | pill mono value | HaloTheme:49 → HaloClosedPill:585,660 |
| workspaceTitle | 14 | 600 semibold | sans | ×−0.01 | no | row title `.ws` | HaloTheme:51 → HaloSessionRow:296 |
| branchDisamb | 10.5 | regular @t3 | **mono** | — | no | dup-name suffix | HaloTheme:53 → HaloSessionRow:309 |
| activity | 12.5 | 400–500 | sans | — | no | row activity line | HaloTheme:55 → HaloSessionRow:273,383 |
| activityVerb | 12.5 | 500 cyan | sans | — | no | live verb | HaloSessionRow:382-384 |
| metaChip | 10.5 | 500 medium | sans | — | no | meta chips | HaloTheme:57 → HaloSessionRow:481-489 |
| metaChipValue | 10 | 500 | **sans** ⚠️ SPEC table says mono | — | **yes** | tabular value chip | HaloTheme:58-61 → HaloSessionRow:482,486 |
| age | 11 | regular @t3 | sans | — | **yes** | row age | HaloTheme:63 → HaloSessionRow:451 |
| sectionHeader | **10** (floor) | 700 bold | sans | 0.10em UPPER | no | list section header | HaloTheme:65 → HaloSessionListScaffold:133,192 |
| summaryLabel | 11 | regular | sans | — | no | summary strip word | HaloTheme:67 → HaloSessionListScaffold:170,251,258 |
| summaryNumber | 12 | 700 | sans | — | **yes** | summary count | HaloTheme:69 → HaloSessionListScaffold:167 |
| outcomeBadge | 10.5 | 700 | sans | — | no | outcome badge | HaloTheme:71 → HaloSessionRow:348 |
| jumpChip | 11.5 | 600 | sans | — | no | jump chip | HaloTheme:73 → HaloSessionRow:514,1193 |
| heroTitle | 14 | 650→`.semibold` (approx) | sans | ×−0.01 | no | hero title | HaloTheme:75 → HaloSessionRow:1696-1698 |
| heroSubtitle | 11 | regular | sans | — | no | hero subtitle | HaloTheme:77 → HaloSessionRow:1702-1703 |
| command | 12 | 600 token / 400 base | **mono** | — | no | command block | HaloTheme:79 → HaloSessionRow:2042 |
| diff | 11.5 | regular | **mono** | — | no | diff rows | HaloTheme:81 → HaloSessionRow:2193 |
| keycap | **10** (floor) | 600 | sans | — | no | ⌘Y/⌘⇧Y/⌘N | HaloTheme:83 → HaloSessionRow:2243 |
| questionText | 14.5 | 560→medium | sans | ×−0.01 | no | shared question view (not Halo-owned) | HaloTheme:85 |
| optionLabel | 13 | 600 | sans | — | no | shared question view | HaloTheme:87 |
| optionDesc | 11.5 | regular | sans | — | no | shared question view | HaloTheme:89 |
| optionNumber | 11 | 700 | **sans** ⚠️ SPEC table says mono | — | **yes** | option digit | HaloTheme:90-92 |
| qChip | **10** (floor) | 700 | sans | 0.05em UPPER | no | question tag chip | HaloTheme:94 → HaloSessionRow:2019-2020 |
| subagentType | 12 | 600 | sans | — | no | subagent type | HaloTheme:96 → HaloSessionRow:655 |
| subagentTask | 11 | regular | sans | — | no | subagent task | HaloTheme:98 → HaloSessionRow:661 |
| subagentElapsed | 11 | regular | sans | — | **yes** | subagent timer | HaloTheme:100 → HaloSessionRow:691 |
| nestHeader | **10** (floor) | 700 | sans | 0.09em UPPER | no | nest header | HaloTheme:102 → HaloSessionRow:622-623,1102-1103 |
| todo | 12 | regular | sans | — | no | todo row | HaloTheme:104 → HaloSessionRow:745 |
| assistant | 12.5 | regular (strong 640 via md theme) | sans | — | no | assistant body | HaloTheme:106 |
| assistantInlineCode | 11 | regular | **mono** | — | no | inline code | HaloTheme:108 |
| metadataValue | 12.5 | 560→`.medium` (approx) | sans | — | no | metadata value | HaloTheme:110 → HaloSessionRow:1080-1087 |
| meterValue | 22 | 660→`.semibold` (approx) | sans | −0.02em (−0.4 view) | **yes** | §I big % | HaloTheme:112 → HaloUsageMeterCard:110-112 |
| emptyTitle | 14 | 600 | sans | — | no | empty title | HaloTheme:114 → HaloEmptyState:49, HaloBootstrapPlaceholder:40 |
| emptySubtitle | 12 | regular | sans | — | no | empty subtitle | HaloTheme:116 → HaloEmptyState:55, HaloInstallHooksHint:44 |

### Floor-lifted roles (SPEC §2 corrections, all pinned)
usageKicker 9→**10** (HaloTheme:121) · usageValue 11 (:123) · metadataKey 9→**10** (:125 → HaloSessionRow:1072) ·
thresholdPill 9.5→**10** (:127 → HaloUsageMeterCard:134) · monogram 9.5→**10** (:131 → HaloSessionRow:1369)
No readable role below 10pt (`readableRoleSizes`, HaloTheme:194-196, pinned by HaloThemeTests).
Exempt micro-role: agents-grid `+N` at `max(5, size*0.55)` in a 6pt cell (HaloClosedPill:759).

### Mono contract — EXACTLY 5 mono roles (HaloTheme:141-149)
`pillValue`, `branchDisamb`, `command`, `diff`, `assistantInlineCode`. Everything else sans; tabular figures via `.monospacedDigit()`, never a face swap.

### Tier opacity ladder (`IslandColorTokens.halo`, HaloTheme:750-769)
t1 primary **0.95** (ad hoc, not a token) · t2 **0.63** (:—) · **t3 0.50 ⚠️ corrected from mockup 0.42** (:765; 0.42 = 3.9:1 fails AA, 0.50 = 5.3:1) ·
hairline **0.08** (:767) · hairlineIC **0.24** (:768) · increasedContrastTextBoost 0.24 (t1→1.0, t2→0.87, t3→0.74) ·
statusIdle white@0.42 (:762, a mark not text) · statusInactive white@0.28 (:763)

## B. METRICS
`IslandMetricsTokens.halo` (HaloTheme:787-816): openedTopRadius **20** (:801) · openedBottomRadius **20** (:802) · filletRadius 0 (:814) ·
closedHoverScale 1.03 (:813) · surfaceShadow black@**0.6** r**30** y**12** (:803-807) ·
openedShadowHInset **40** (:809) · openedShadowBInset **48** (:810) · closedShadowHInset **40** (:811) · closedShadowBInset **44** (:812)

`enum HaloMetrics` (HaloTheme:267-309): edge (prismatic ring) **1.5pt** (:269) — the signature · railWidth 2 (:271) · railInsetY 8 (:273) ·
dot 8 (:275) · heroRadius **16** (:277) · heroRingWidth 1.5 (:279) · gridCell 6 (:281) · gridGap 3.5 (:283) · gridRadius 3 (:285) ·
workingBloomRadius 8 (:298) · permissionBloomRadiusMin 8 (:300) · permissionBloomRadiusMax **21** (:303) · questionBloomRadius 6 (:305) · successBloomRadiusMax 20 (:308)

View metrics: pill height 38 (HaloClosedPill:43) · pill glyph 24×24 (:51) · pill innerGap 6 (:52) · notchLaneLabelGap 6 (:53) ·
dot bloom inset −3 → 14pt circle, blur 2, opacity 0.55 / 0.35 failure / 0 idle (HaloSessionRow:1245-1251,1352-1355) ·
monogram chip 16×16 r5 (:1372-1373) · row lead/body gap 13 (:150) · row hPad = sideInset(16) (:46,164) · row vPad top 12 / bottom 12 (6 expanded) (:165-166) ·
nest slab r12 fill white@0.025 stroke white@0.05 1pt (:606-611) · hero card r16 (:1652) · hero padding t15 l16 b16 r16 (:1660) ·
hero outer glow radius **20** (HaloTheme:636) · hero conic `from` **44°** (:642) · annunciator chip 26×26 r8 (HaloSessionRow:1682-1690) ·
command/diff box r9 (:2050,2154,2159) · diff gutter 22 trailing 10 (:2186-2187) · diff maxHeight 180 (:2104) · assistant card maxHeight 150 (:1106) ·
keycap minW15 minH16 r4 stroke 1pt (:2245-2252) · hero button r10 hPad 13 vPad 8 (:2292-2294) · scope row r9 (:1927,2361-2364) ·
codex note r9 hPad12 vPad10 (:2397-2401) · metaChip r6 hPad7 vPad2 (:490) · jumpChip r8 hPad9-10 vPad3-4 (:519,1200) ·
outcome badge Capsule hPad7 vPad2.5 (:351-353) · dismiss 20×20 circle (:1449) · detail chevron 20×20 hit / 9pt glyph (:1495-1500) ·
header control **26×26** circle fill white@0.06→0.14 hover (HaloHeaderControls:20,247-264) · header control spacing 8 (:21) ·
header filament **30pt** notch (HaloUsageSummary:23) / **22pt** top-bar ⚠️ not in SPEC (:25) · filament stroke 2.2 (:27) ·
§I meter dial **52pt** (:29) stroke 3 (:31) · arc span 0.75 (270°) rotated 135° gap-at-top (:35,37) ·
empty glyph 34pt thin static (HaloEmptyState:44) · bootstrap glyph 30pt thin (HaloBootstrapPlaceholder:30) ·
monitoring pill hPad12 vPad6 **strokeBorder only, no fill** (HaloEmptyState:83-89) ·
agents-grid running glow rgba(80,180,255,.7) r5 (HaloClosedPill:735-736) ·
attention badge minW/H 20 hPad6, hot glow r16 rgba(255,150,90,.6) (HaloClosedPill:817-818,830-836)

## C. COMPONENT METRICS
| Component | Radius | Height | Pad H/V | Border | Icon | Label role |
|---|---|---|---|---|---|---|
| Primary btn (`HaloHeroButton .primary`) | 10 | intrinsic | 13/8 | none (amber gradient) | — | 13/semibold + keycap |
| Deny btn | 10 | intrinsic | 13/8 | none (translucent red) | — | 13/semibold + ⌘N |
| Codex btn | 10 | intrinsic | 13/8 | none (blue gradient) | — | 13/semibold, **no keycap** |
| Keycap (`HaloKeycap`) | 4 | min 16 | H3 | 1pt white@.16 (dark@.35 on light btn) | — | 10/semibold |
| Attention badge | Capsule | min 20 | H6 | none | — | 12/bold tabular |
| Status dot | Circle 8 + 14 bloom blur2 | — | — | none | 8 | — |
| Agent monogram | 5 | 16×16 | — | none (fill white@.07) | — | 10/bold **mono**, tracking −0.02 |
| Section header | — | 36 summary strip / auto | = sideInset | 1pt hairline top+bottom | dot ~6 (4.13=dot*0.75) | 10/bold 0.10em UPPER |
| Session row | none (void, no card) | auto | 16 / t12 b12(6 exp) | 1pt hairline between rows | dot 8 + monogram 16 | 14 title / 12.5 activity |
| Metadata cell | — | minW 118 | — | — | — | key 10 UPPER tracking .08 / val 12.5 |
| Nest slab | 12 | auto | V7 | 1pt white@.05, fill white@.025 | — | — |
| **Hero card (permission/question)** | **16** | auto | t15 l16 b16 r16 | **1.5pt inset ring (state@.55) + pulsing masked ring** | 26 chip r8 | 14/semibold title, 11 subtitle |
| Assistant/completion card | 12 | max 150 scroll | 13/11 | 1pt white@.05 | — | 10 nest header + 12.5 body |
| Usage filament (header) | Circle | 30 notch / 22 top-bar | — | track white@.1 (.2 reduce-transp) 2.2pt | — | 10 kicker / 11 value |
| Usage dial (§I) | Circle | 52 | — | 3pt stroke | — | 22 %, 11 reset, 10 threshold |
| Command box | 9 | auto | 12/10 | 1pt white@.05, fill white@.028 | — | 12 mono |
| Diff box | 9 | max 180 | hdr 11/6; rows l8 r11 v1 | 1pt white@.05, hdr rule white@.08 | 10.5 doc | 11.5 mono, gutter 22 |
| Jump chip (expanded) | 8 | auto | 10/4 | none (fill blue@.16) | 10.5 arrow | 11.5/semibold |
| Jump chip (collapsed) | 8 | auto | 9/3 | none (fill white@.05) | 10 arrow | 11.5/semibold |
| Dismiss | Circle | 20×20 | — | none (white@.06 → red@.6 hover) | 9 xmark | — |
| Header control | Circle | **26×26** | — | none (white@.06→.14) | 13 SF glyph | — |
| Edge-lit rail | 1 (w/2) | inset 8 t/b | w2 | glow shadow r4-5 | — | — |

## D. FIDELITY BAR
**SPEC §0 identity (verbatim):** *"a pure-black (#000000) OLED void whose only chrome is a 1.5pt living prismatic edge-light traced around the morphing silhouette. There are no fills, no cards, no vibrancy — content floats in the black and structure comes entirely from typography + hairlines."*

**Edge-light gradient stops (`HaloEdgeLightModel.stops`, HaloEdgeLight:357-418):**
- idle — flat white@.08, no gradient
- working — white@.05 0–176°, **cyan @232°**, **violet @300°**, white@.05 348–360°; orbit 0→360°/6s linear
- permission — amber@.04 @0°, **amber @40°**, **magenta @84°**, amber @128°, amber@.04 190–360°; pulse .55↔1 / 1.9s
- question — qgold@.04 @0°, qgold @46–122°, qgold@.04 190–360°; pulse / 2.6s
- success — green→cyan→green; opacity 1→.12 / 3s ease-out
- failure — white@.05 0–20°, **red @60–120°**, white@.05 160–360°; **STATIC, no animation, never glows**

**Bloom stack:** working r8 @.45 · permission r8→**21** @.50→.85 (loudest) · question r6 @.40 · success r20→0 @.70→0 · failure **nil**

**Specular:** `specularTopEdge = nil` (HaloTheme:846). SPEC §1d verbatim: *"The animated 1.5pt perimeter edge-light replaces the specular concept entirely."* No bodyGradient, no specularHardEdge, no innerHairline. tintOpacity 1.0.

**Motion "orbit" (`HaloMotion`, HaloTheme:318-341):** orbit 6s linear (:320) · permissionPulse 1.9s ease-in-out (:322) · question 2.6s (:324) ·
success 3s ease-out one-shot (:326) · sweep (row entrance) 0.7s single pass (:328) · heroRing 2.2s (:330) ·
wave 1.05s stagger [0, .13, .26] (:332,337) · breathe 2.4s (:339) · gridDot 2s (:341)
Transitions (HaloTheme:824-829): open `spring(0.46, 0.86)` · close `.smooth(0.32)` · pop `spring(0.34, 0.66)` · unmountDelay 0.36

**Glow-travel (§3b verbatim):** *"the light fires at the pill edge → travels down the growing silhouette → condenses into the card ring… because pill→panel is one continuously morphing shape."* Perimeter dims to a **0.55 floor** while the hero grows its ring (`perimeterOpenHandoffOpacity`, HaloEdgeLight:330-341, floor :323).

**Permission hero (SPEC §5E, "the most-polished frame", verbatim):** *"Void body (#000) with inset amber ring rgba(255,160,80,.55) 1.5pt + outer glow 0 0 48 -8 rgba(255,140,80,.5) + pulsing ::before ring (edgepulse 2.2s). The light travels from the pill edge into this ring."*
Implemented `HaloHeroShell` (HaloSessionRow:1636-1740): black fill + colored shadow (glowRadius 20) + 1.5pt strokeBorder inset ring + `HaloHeroPulseRing` masked AngularGradient conic from 44°, opacity .55↔1 / 2.2s. Annunciator chip 26pt r8, fill attention@0.1, stroke attention@0.3.

**Color discipline:** identity is an **achromatic monogram** (white@.07 fill, white@.63 text). Edge-light is never brand-colored; `AgentSession.brandColorHex` deliberately unused.

**Exact hexes to verify:** surfaceInk #000000 · cyan #33DCFF · green #5FE39A · amber #FFB14D · qgold #FFCF7A · warn #E6AA42 · red #E0596C · violet #7C5CFF · magenta #FF5EA8 · Allow-once text **#3a2205** (HaloSessionRow:2305) · Deny text **#f0a6b0** (:2306)

## E. CONFLICTS / DRIFT
1. **metaChipValue kept sans** — SPEC §2 table marks `.chip.mn` **mono**; code's "exactly five mono roles" excludes it (HaloTheme:58-61, 138-149). Documented deviation but a real SPEC-vs-code mismatch.
2. **optionNumber kept sans** — SPEC §2 marks `.opt .num` **mono**; code keeps sans+tabular (HaloTheme:90-92). Same pattern.
3. **Header filament 22pt on top-bar** — SPEC §5C only ever gives 30pt; the 22pt top-bar variant (HaloUsageSummary:25) is an undocumented-in-spec engineering addition. Measuring top-bar captures against a flat 30pt = false mismatch.
4. **Weight approximations** — SPEC's 560/650/660 are unreachable in SwiftUI: →`.medium`/`.semibold`/`.semibold` (HaloSessionRow:1081,1696-1697; HaloUsageMeterCard:110). Judgment calls, not spec values.
5. `notificationCard` factory delegates via `ClassicTheme.interim` (HaloTheme:1127-1143) but resolves to the real `HaloSessionRow` at render (IslandNotificationCard reads `\.islandTheme`). Correct behaviour; the "interim/Part 2 seam" naming (HaloTheme:888-889) is stale.
6. **No drift found** in surfaceInk, the six status hexes, HaloEdge accents, all HaloMetrics, all HaloMotion periods, agents-grid geometry (6, 3.5, 3), registry position. Reduce-Motion fallbacks fully implemented per-state.
