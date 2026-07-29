# POURED ISLAND 2.0 — MEASURING RULER

Type scale source of truth: `Sources/OpenIslandApp/Views/Island/PouredTypography.swift` (`PouredType.roleTable`, L175-227).
Floor = 10pt (L37). Weight rounding: <450→regular, <575→medium, <675→semibold, else bold (L73-79).

## A. TYPE SCALE (role | pt | weight | design | tracking | tabular | upper | used in | file:line)

| Role | pt | Weight | Design | Tracking | Tab | Upper | Used in | file:line |
|---|---|---|---|---|---|---|---|---|
| workspaceTitle | 14 | 600/semibold | default | −0.01em | no | no | row title `.ws` | PouredTypography:177 → PouredSessionRow:293 |
| completionHeaderTitle | 15 | 640/semibold | default | −0.01em | no | no | **DEFINED, NEVER CONSUMED** | PouredTypography:178 |
| activityLine | 12.5 | 550/semibold | default | 0 | no | no | row `.act`; pill center label | :179 → PouredSessionRow:337, PouredClosedPill:503 |
| activityVerb | 12.5 | 550/semibold | default | 0 | no | no | **DEFINED, NOT SEPARATELY CONSUMED** | :180 |
| branchDisambiguator | 11 | 400/regular | **mono** | 0 | no | no | title-line dup suffix | :181 → PouredSessionRow:301 |
| metaChip | 10.5 | 500/medium | default | 0 | no | no | attachment chip, completion meta | :182 → PouredSessionRow:786,999 |
| monoChip | 10 | 500/medium | **mono** | 0 | no | no | **DEFINED, ZERO CALL SITES (dead)** | :183 |
| age | 11 | 500/medium | default | 0 | **yes** | no | row age, task chip, usage chip, resets | :184 → PouredSessionRow:242, PouredClosedPill:641,694, PouredUsageSummary:237, PouredUsageMeterCard:137 |
| sectionHeader | 10.5 | 650/bold | default | 0.09em ≈0.945pt | no | **YES** | list section header `.grp` | :185 → PouredSessionListScaffold:283 |
| listOverviewTitle | 10.5 | 650/bold | default | 0.16em ≈1.68pt | no | **YES** | list panel header title | :186 → PouredSessionListScaffold:115 |
| summaryLabel | 11 | 400/regular | default | 0 | no | no | summary strip bucket word | :187 → PouredSessionListScaffold:257 |
| summaryNumber | 12 | 700/bold | default | 0 | **yes** | no | summary count; A3/A4 pill badge | :188 → PouredSessionListScaffold:252, PouredClosedPill:608 |
| agentChipLabel | 10.5 | 500/medium | default | 0 | no | no | **DEFINED, NEVER CONSUMED** (grid uses metadataValue) | :189 |
| outcomeBadge | 10.5 | 650/bold | default | 0 | no | no | completion outcome badge | :190 → PouredSessionRow:2424 |
| jumpChip | 11.5 | 600/semibold | default | 0 | no | no | Jump CTA label | :191 → PouredSessionRow:755,1024 |
| displayNumeral | 20 | 640/semibold | default | −0.02em | **yes** | no | §I meter big % | :193 → PouredUsageMeterCard:131 |
| usageRingValue | 11.5 | 700/bold | default | 0 | **yes** | no | header ring inline % | :195 → PouredUsageSummary:223 |
| commandBlock | 12 | 600/semibold | **mono** | 0 | no | no | approval command block | :197 → PouredSessionRow:1586 |
| diff | 11.5 | 400/regular | **mono** | 0 | no | no | E2 diff rows | :198 → PouredSessionRow:2049 |
| keycap | 10 | 600/semibold | default | 0 | no | no | ⌘Y/⌘⇧Y/⌘N chips | :200 → PouredSessionRow:1841 |
| heroTitle | 14 | 640/semibold | default | −0.01em | no | no | approval hero title | :201 → PouredSessionRow:1567 |
| heroSubtitle | 11 | 400/regular | default | 0 | no | no | hero effect line; notif countdown | :202 → PouredSessionRow:1508,1752 |
| questionText | 14.5 | 560/semibold | default | −0.01em | no | no | **DEFINED, NOT CONSUMED** (shared question view) | :203 |
| optionLabel | 13 | 600/semibold | default | 0 | no | no | **DEFINED, NOT CONSUMED** | :204 |
| optionDesc | 11.5 | 400/regular | default | 0 | no | no | repurposed for Codex note | :205 → PouredSessionRow:1692 |
| optionNumber | 11 | 700/bold | default | 0 | **yes** | no | **DEFINED, NOT CONSUMED** | :206 |
| questionChip | 10 | 700/bold | default | 0.05em | **YES** | no | **DEFINED, NOT CONSUMED** | :207 |
| subagentType | 12 | 600/semibold | default | 0 | no | no | §G subagent type | :209 → PouredSessionRow:437 |
| subagentTask | 11 | 400/regular | default | 0 | no | no | §G task desc | :210 → PouredSessionRow:442 |
| subagentElapsed | 11 | 400/regular | default | 0 | **yes** | no | §G live M:SS | :211 → PouredSessionRow:466 |
| nestHeader | 10 | 650/bold | default | 0.08em | **YES** | no | nest header | :212 → PouredSessionRow:407,480 |
| todo | 12 | 400/regular | default | 0 | no | no | §G todo row | :213 → PouredSessionRow:504 |
| assistantBody | 12.5 | 400/regular | default | 0 | no | no | **DEFINED, NOT DIRECT** (markdown theme) | :215 |
| assistantLabel | 10 | 650/bold | default | 0.08em | **YES** | no | "Last message from X" | :216 → PouredSessionRow:710 |
| assistantInlineCode | 11 | 400/regular | **mono** | 0 | no | no | **DEFINED, NOT CONSUMED** | :217 |
| metadataKey | 10 (lifted from mockup 9.5) | 600/semibold | default | 0.06em | **YES** | no | metadata grid keys | :219 → PouredSessionRow:642 |
| metadataValue | 12.5 | 550/medium | default | 0 | no | no | metadata values; agent chip | :220 → PouredSessionRow:632,658 |
| metadataValueMono | 11.5 | 550/medium | **mono** | 0 | no | no | branch/dir values | :221 → PouredSessionRow:629 |
| emptyTitle | 14 | 600/semibold | default | 0 | no | no | "All quiet" | :223 → PouredEmptyState:38 |
| emptySubtitle | 12 | 400/regular | default | 0 | no | no | empty subtitle | :224 → PouredEmptyState:44 |
| bootstrapHint | 14 | 500/medium | default | 0 | no | no | **DEFINED, BYPASSED** (hardcoded) | :225 / PouredBootstrapPlaceholder:25 |
| installHint | 12 | 500/medium | default | 0 | no | no | install hint label | :226 → PouredInstallHooksHint:42 |

No role sits below the 10pt floor. `readableRoleSizes` at PouredTypography:232.

### ⚠️ OFF-TABLE HARDCODED FONTS (bypass PouredType entirely — the "inconsistent fonts" smoking gun)
- PouredClosedPill:557 — count badge `×N`: `.system(11, .semibold, .monospaced)`
- PouredClosedPill:765 — agents-grid `+N`: `.system(max(5, size*0.55), .bold, .monospaced)`
- PouredHeaderControls:251 — header glyph: `.system(10, .semibold)`
- PouredUsageSummary:231 — ring provider label: `.system(10, .medium)` + tracking 0.6
- **PouredSessionRow:1183 — `sideBadge` (model/SSH/terminal/subagent/task chips): `.system(10.5, .medium, .monospaced)`**
- **PouredSessionRow:1213 — bypass-permissions chip: `.system(10.5, .semibold, .monospaced)`**
- PouredSessionRow:513 — "now" doing-tag: `.system(10, .semibold)`
- PouredSessionRow:1044 — completion Dismiss ghost: `.system(12, .medium)`
- **PouredSessionRow:1721 — Codex CTA title: `.system(13, .semibold)`** (hero frame!)
- **PouredSessionRow:1872 — Allow/Deny button title: `.system(13, .semibold)`** (hero frame!)
- PouredSessionRow:1920 — scope-row label: `.system(12, .regular)`
- PouredSessionRow:1999 — diff "N more lines": `.system(10, .monospaced)`
- PouredSessionRow:2022,2030 — diff header icon / "+N/−N": `.system(10, .semibold)` / `.system(10.5, .semibold)`
- PouredSessionListScaffold:146,153 — footer "Grouped by…" / idle count: `.system(11)`
- PouredSessionListScaffold:288 — section header count: `.system(10.5, .medium).monospacedDigit()`
- PouredEmptyState:77 — hooks pill: `.system(11, .regular)`
- PouredBootstrapPlaceholder:25,28 — `14/medium`, `12`
- PouredUsageMeterCard:51,127,153,155 — meter title, window label, threshold word/glyph

## B. METRICS TOKENS (`IslandMetricsTokens.poured`, IslandMetricsTokens.swift:201-229)
openedTopRadius 26 (:214) · openedBottomRadius 26 (:215) · filletRadius 12 notch-only (:227)
surfaceShadow black@0.5 r34 y18 (:216-221) · openedShadowHInset 28 (:222) · openedShadowBInset 34 (:223)
closedShadowHInset **40** (:224) · closedShadowBInset **44** (:225) — grown for AB-329 attention bloom
closedHoverScale 1.03 (:226)
Pill height ~38 notch / ~24 top-bar. Pill radius = height/2. Panel 540 notch / 520 top-bar. List side inset 46 notch / 16 top-bar. maxSessionListHeight 560 (PouredSessionListScaffold:21).

### Material (`IslandMaterialTokens.poured`, IslandMaterialTokens.swift:137-174)
material `.hudWindow` · blending `.behindWindow` · appearance `.vibrantDark` · tintOpacity 0.5
specularTopEdge white@0.5 sheen 26pt (:142-146)
**bodyGradient 3-stop**: rgb(26,31,44)@.86 @0.0 → rgb(13,17,26)@.94 @0.62 → rgb(9,12,20)@.96 @1.0 (:147-163)
specularHardEdge white@0.14 sheen 1pt (:164-168)
innerHairline opacity 0.05 width 0.5pt (:169-172)

### Closed pill geometry (PouredClosedPill.swift)
glyphSize 24×24 (:49) · innerGap 6 (:50) · notchLaneLabelGap 6 (:51) · pad = height/2 (:53)
Pill layout anim `timingCurve(0.4,0,0.2,1, 0.45)` (:243)

### Usage (PouredUsageMetrics, PouredUsageSummary.swift:16-29)
headerRingNotch **30pt** (:18) · headerRingTopBar **22pt** (:20) ⚠️ SPEC says flat 30 — top-bar is 22 by design
headerRingLineWidth 3.5 (:23) · meterDial 52 (:25) · meterDialLineWidth 6 (:28)

### Right slot (PouredPillMotion.RightSlot, :146-175)
badge pad H5/V1.5 (:148-149) · badge radius 6 (:150) · attn glow r14 @0.55 (:155-156)
task-chip spacing 3 (:160) · usage dial 13 (:164) · dial line 2.5 (:165) · thresholds 90/70 (:173-174)

### Header controls (PouredHeaderControls.swift)
buttonSize **22** (:17) · spacing 8 (:18) · hPadding 18 non-notch (:19) · notchHPadding 46 (:21)
topPadding 2 (:20) · notchLaneSafetyInset 12 (:22) · minRightUsageLane 58 (:23)

## C. COMPONENT METRICS
| Component | Radius | Height | Padding H/V | Border | Icon | Label role | file:line |
|---|---|---|---|---|---|---|---|
| Primary Jump btn | 10 | intrinsic | 14/8 | white@0.4 1pt overlay | 11.5 bold | jumpChip 11.5/600 | PouredSessionRow:2334-2359 |
| Allow once (amber grad) | 11 | intrinsic | 14/8 | none | — | **hardcoded 13/semibold** | :1885-1898 |
| Deny (red wash) | 11 | intrinsic | 14/8 | none | — | **hardcoded 13/semibold** | :1895-1897 |
| Ghost/secondary | 11 | intrinsic | 12/8 | none (fill .08→.14 hover) | — | hardcoded 12/medium | :2397-2399 |
| Codex CTA | 11 | intrinsic | 14/9 | none (gradient) | 12 bold | **hardcoded 13/semibold** | :1725-1736 |
| Keycap chip | 4 | min 16 | H3 | 1pt stroke | — | keycap 10/600 | :1846-1851 |
| Attention badge (pill) | 6 | derived | 5/1.5 | none | — | summaryNumber 12/700 | PouredClosedPill:606-621 |
| Outcome badge | Capsule | derived | 9/3 | none | 9 bold | outcomeBadge 10.5/650 | :2419-2430 |
| Bypass chip | Capsule | derived | 8/3 | warn@0.4 1pt | — | **hardcoded 10.5/semi mono** | :1212-1218 |
| sideBadge | Capsule | derived | 8/3 | none | — | **hardcoded 10.5/med mono** | :1181-1188 |
| Identity tick | 1 | 13 | w2 | none | — | — | PouredRowMotion:61-65 |
| Section header | none | V top10/bot7 | H=sideInset | top hairline 1pt | dot 7×7 | sectionHeader 10.5/650 | PouredSessionListScaffold:274-303 |
| Session row | none | V top11/bot8-11 | H=sideInset(16) | top hairline 1pt @0.08 | varies | workspaceTitle 14/600 | PouredSessionRow:104-186,260-263 |
| Metadata cell | 9 | minW 84 | 11/8 | white@0.045 1pt | — | key 10/600, val 12.5/550 | :2304-2318 |
| Approval hero card | **15** | intrinsic | 14 all | accent 1pt | 24×24 chip r8 | heroTitle 14/640 | :1536-1547 |
| Question hero card | **18** | intrinsic | pad 3 | ring 1pt | — | shared view | :871-885 |
| Completion card | **12** | intrinsic | hdr 14/11-9; rail 14/11 | white@0.09 1pt | 9 bold | outcomeBadge | :915-953 |
| Usage ring (header) | Circle | 30 notch / 22 top-bar | — | track @0.18 | — | usageRingValue 11.5/700 | PouredUsageSummary:18-20,251-317 |
| Usage dial (§I) | Circle | 52, stroke 6 | — | — | — | displayNumeral 20/640 | PouredUsageMeterCard:117-123 |
| Command box | 10 | intrinsic | 12/10 | white@0.06 1pt | — | commandBlock 12/600 mono | :1592-1602 |
| Diff box | 10 | max 180 (E2) / 160 | hdr 10/6; row l8 r10 v1 | white@0.06 1pt | 10 semi | diff 11.5/400 mono | :1946-2088 |
| Nest slab | 12 | — | H9/V8 | white@0.05 1pt, fill white@0.025 | — | nestHeader 10/650 | :531-537,411-413 |
| Assistant card | 12 | max 150 | 13/11 | white@0.045 1pt, fill white@0.025 | — | markdown theme | :707-733 |
| Attachment chip | Capsule | — | 8/4 | fill white@0.05 | dot 7×7 | metaChip 10.5/500 | :778-795 |
| Empty/bootstrap shell | 16 | — | V22/H18 | hairline | glyph 34×34 | emptyTitle 14/600 | PouredEmptyState:58-65 |

Row detail: leading status bar w3, vPad 10 open / 8 closed, leadingPad 14 (:161-169). `.bar` indicator h34 actionable / h28 (:1139). `.glyph` 14×20 (:1147). `.tint` dot 8×8 (:1152). animatedDot 9×9 dual shadow r5→9 / r10→15 (:2244-2251). Detail chevron icon 10/bold, column 28 (:1236-1241). Age column minW 46, badge spacing 6 (IslandSessionRowMetrics:26,15).

## D. FIDELITY BAR (SPEC + BRIEF §7)
- 3-stop body gradient (above) = inner-luminance elevation. Never a flat fill + border.
- TWO specular layers: soft 26pt sheen @0.5 **plus** hard 1pt edge @0.14. Plus 0.5pt inner hairline @0.05.
- Glow bleed: A3/A4 amber glow must bleed ~4px OUTSIDE the silhouette at r34 — rendered outside the morph clip (`PouredClosedGlow`, PouredClosedPill:288-427); window insets grown to 40/44.
- Shadow stacks: surface black@0.5 r34 y18; A3 pill glow = 2 layers (r18→34 + wider @0.6·op, radius+4); hero glow = **3 layers** (ambient r42 @.34→.6; inner r10+8·pulse; outer r20+10·pulse) (PouredPillMotion:77-104).
- A5 settle: white flash r30 spread3 @0.4 → green r22 spread2 @0.4 over 2.6s ease-out, key 22%.
- Motion "liquid": open `spring(0.5, 0.84)`; close `.smooth(0.34)`; pop `spring(0.34, 0.55)`; pill width `timingCurve(0.4,0,0.2,1, 0.45)`; row entrance rise 10pt + fade + scale 0.98→1 on the morph spring.
- Ambient periods: working lumen 3.0s; permission attnpulse 1.9s; hero heropulse 2.4s; question breathe 2.6s; settle 2.6s one-shot; waiting tile 0.7s; usage danger 0.8s; empty glyph 3.0s.
- Reduce Motion: hold the peak/settled frame, never acquire the clock.

## E. CONFLICTS / KNOWN DRIFT
1. **SPEC §2 says "drop mono" for meta chips — code did NOT.** `sideBadge` (PouredSessionRow:1181) and bypass chip (:1213) still mono at 10.5. Meanwhile `monoChip` role (the one role reserved for mono chips) is **dead code, zero call sites**.
2. **Hero-frame button titles bypass the type scale**: Allow/Deny (:1872) and Codex CTA (:1721) hardcode 13/semibold — not in `roleTable`, unpinnable.
3. Header ring is 30pt notch / **22pt top-bar** (PouredUsageSummary:20) — measuring top-bar captures against a flat "30pt" is a false mismatch.
4. 11 roles defined but never consumed (completionHeaderTitle, activityVerb, agentChipLabel, questionText, optionLabel, optionNumber, questionChip, assistantBody, assistantInlineCode, bootstrapHint, monoChip).
5. Metrics/material axis is fully conformant to SPEC — **all drift is in typography.**
6. Text ramp: secondaryTextOpacity 0.6 (IslandColorTokens:215), hairline 0.08 (:218) — SPEC-corrected values, code follows.
