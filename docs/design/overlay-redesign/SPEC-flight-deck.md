# Flight Deck 2.0 · Glass Cockpit — Implementation Conformance Spec

Source mockup: `02-flight-deck.html` ("Flight Deck 2.0 — Glass Cockpit").
Target theme: `FlightDeckTheme` (already shipped through AB-311…314). This spec
finalizes the **approved** mockup into checkable deltas against the current Swift
implementation.

Conventions: **mockup px @1x = SwiftUI pt.** Hex is compared against the exact
`Color(red:green:blue:)` literals in `IslandColorTokens.swift`. Verdicts:
`unchanged` (mockup == shipped), `changed` (mockup differs from a shipped token),
`new` (no shipped token/treatment exists).

> **Current conformance state — read first.** The semantic `flightDeck` colors
> remain byte-identical to the approved mapping. The two-tier nomenclature, lamp
> glow, sans-narration/mono-value split, tape gauges with inline reset, STATUS
> code, and engine-cluster display are shipped. Historic `new`/`changed` verdicts
> below describe the pre-remediation baseline; the retained exceptions are recorded
> in §7 and the typography Shipped column.

---

## 1. Token sheet — mockup CSS → current Swift → verdict

### 1a. Colors (`IslandColorTokens.flightDeck`)

| Role | Mockup CSS | Shipped Swift literal | Hex | Verdict |
|---|---|---|---|---|
| Cockpit ground / `surfaceInk` | `--ground #08090a` | `flightDeckInk = rgb(0x08,0x09,0x0a)` | `#08090A` | **unchanged** (exact) |
| Nominal (running) | `--nominal #4ac99e` | `flightDeckNominal = rgb(74,201,158)` | `#4AC99E` | **unchanged** (exact) |
| Advisory (completed·success) | `--advisory #6392c4` | `flightDeckComplete = rgb(99,146,196)` | `#6392C4` | **unchanged** (exact) |
| Caution (question / interrupted) | `--caution #e6aa42` | `flightDeckCaution = rgb(230,170,66)` | `#E6AA42` | **unchanged** (exact) |
| Warning (permission / failed) | `--warning #e04a42` | `flightDeckWarning = rgb(224,74,66)` | `#E04A42` | **unchanged** (exact) |
| Legend ink / `paper` | `--paper #d8e1e6` | `flightDeckPaper = rgb(0xd4,0xda,0xd6)` | shipped `#D4DAD6` | **changed** — mockup is cooler/lighter (`#D8E1E6`, rgb 216,225,230). Small but real; either adopt `#D8E1E6` or keep `#D4DAD6` and document. Contrast on ink stays ≥ 4.5:1 either way. |
| Opened panel body | `--surface #0e1113` | `FlightDeckSurfaces.panel` | `#0E1113` | **unchanged** (theme-local surface) |
| Tiles / sub-panels | `--surface-2 #101519` | `FlightDeckSurfaces.tile` | `#101519` | **unchanged** (theme-local surface) |
| Raised / hovered | `--surface-hi #161c22` | `FlightDeckSurfaces.hover` | `#161C22` | **unchanged** (theme-local surface) |
| Recessed wells (code / tape track) | `--well #060708` | `FlightDeckSurfaces.well` | `#060708` | **unchanged** (theme-local surface) |
| Hairline tier 1 | `--hair rgba(154,176,188,0.14)` | `FlightDeckSurfaces.hairline1` | — | **unchanged** (cool base @ 0.14) |
| Hairline tier 2 | `--hair2 rgba(154,176,188,0.26)` | `FlightDeckSurfaces.hairline2` | — | **unchanged** |
| Hairline tier 3 | `--hair3 rgba(154,176,188,0.40)` | `FlightDeckSurfaces.hairline3` | — | **unchanged** |
| Dim text (`--dim #8a97a0`) | `#8a97a0` | `paper.opacity(secondaryTextOpacity=0.6)` | — | **changed** — mockup uses an explicit cooler grey; shipped derives from paper @ 0.6. |
| Faint text (`--faint #5b656c`) | `#5b656c` | `paper.opacity(tertiaryTextOpacity=0.5)` | — | **changed** — same story @ 0.5. |
| Idle lamp | `--well` + `--hair2` border | `statusIdle = paper.opacity(0.30)` / `statusInactive = 0.26` | — | **unchanged** (concept) |
| Secondary/Tertiary text opacity | — | `0.6 / 0.5` | — | **unchanged** |
| Hairline opacity (default / IC) | — | `0.13 / 0.32` | — | **unchanged** |

**Two-tier alarm — the semantic mapping (critical).** The shipped tokens already
encode the mockup's two tiers correctly:

```
statusWaitingForApproval == statusFailed  == flightDeckWarning  (#E04A42 red)   → WARNING tier
statusWaitingForAnswer   == statusInterrupted == statusWarning == flightDeckCaution (#E6AA42 amber) → CAUTION tier
statusRunning   = flightDeckNominal  (#4AC99E)   statusCompleted = flightDeckComplete (#6392C4)
```

This is **exactly** the mockup: permission → red, question → amber, failed →
red, interrupted → amber. **No `IslandColorTokens` tint-role remapping is
required for the color axis.** `FlightDeckThemeTests.statusPaletteIsTheFour...`
(lines 52–77) already pins these equalities and must stay green.

The nomenclature correction is shipped: red permission is **MASTER WARNING** and
the amber question wraps the shared prompt in **MASTER CAUTION**. The table is
kept as the semantic mapping record:

| Phase | Color token (unchanged) | Shipped placard | Required placard |
|---|---|---|---|
| `waitingForApproval` (permission) | `statusWaitingForApproval` = warning **red** | `masterWarning` "Master Warning" | **MASTER WARNING** red beacon |
| `waitingForAnswer` (question) | `statusWaitingForAnswer` = caution **amber** | `masterCaution` "Master Caution" | **MASTER CAUTION** amber header above the question prompt |

`island.flightDeck.approval.masterWarning` is shipped in all three locales; the
question annunciator reuses `masterCaution`.

### 1b. Metrics (`IslandMetricsTokens.flightDeck`)

| Token | Mockup | Shipped | Verdict |
|---|---|---|---|
| `openedTopRadius` / `openedBottomRadius` | panel is a sharp rect (radius 0); chamfer lives on children via `--ch` | `6 / 6` | **unchanged** — keep 6 so the pill→panel morph has a radius to animate; children carry the chamfer (matches mockup's `.oct`). |
| Chamfer default (`--ch`) | `6px` | `FlightDeckChamferedRectangle` card `6`, box `5`, button `5`, placard `3`, keycap `2.5` | **unchanged** — mockup per-element chamfers (`6/5/4/3/2`) map onto shipped `6/5/3/2.5`. |
| `surfaceShadow` | panel relies on desk gradient (no hero drop shadow) | `black · 0.42 · r14 · y7` | **unchanged** (crisp shallow shadow is on-idiom). |
| Attention pill bloom | `.attn-perm 0 6px 26px -14px rgba(224,74,66,.6)`; `.attn-caut 0 6px 24px -16px rgba(230,170,66,.5)` | `FlightDeckClosedGlow` per-state seam | **implemented** — status-tinted colored glow outside the pill |
| `closedHoverScale` | "~1.03" | `1.028` | **unchanged** |
| Shadow insets | — | `18 / 22 / 12 / 14` | **unchanged** |
| `filletRadius` | 0 (no poured fillet) | `0` | **unchanged** |

Physical dims (from `OverlayPanelController`, **not** theme tokens — brief §2):
pill height ≈ 38pt (24pt top-bar); panel width 540pt notch / 520pt top-bar; list
side inset 46pt notch / 16pt. Mockup's board px (520/560/600, 200px notch lane)
are illustrative and consistent with these.

### 1c. Motion (`IslandMotionTokens.flightDeck`)

| Token | Mockup | Shipped | Verdict |
|---|---|---|---|
| `openAnimation` (relay-snap) | "response **.32** / damping **.92**" | `.spring(response: 0.32, dampingFraction: 0.92)` | **unchanged** (exact — this is the named identity). |
| `closeAnimation` | pill transitions `.32s`; morph not numerically specified | `.smooth(duration: 0.24)` | **unchanged** |
| `popAnimation` | beacon flash / attention pop | `.spring(response: 0.22, dampingFraction: 0.6)` | **unchanged** |
| `openedSurfaceUnmountDelay` | — | `0.28` | **unchanged** |
| Lamp **snap-on 120ms** + soft decay | §K: "Lamp snap-on 120ms on · soft decay"; `snapon` uses `steps(1,end)` (instant on) | named `FlightDeckMotion.Snap` leaf constants | **implemented** (instant on / 120ms decay) |
| Running **breathe 2s** phosphor | `@keyframes phosphor 2s` (opacity 0.86→1 + glow 5px→11px) | named `FlightDeckMotion.Breathe` + phosphor glow leaf | **implemented** |
| Attention pulse | `attn 1s` (perm) / `1.2s` (caut), opacity 1→0.28 | named warning/caution attention periods | **implemented** |
| Success settle | `settle 3s`: nominal flash+scale → advisory dim | named `FlightDeckMotion.Settle` leaf | **implemented** |
| Reduce Motion | `animation-duration:.001ms` | every animated leaf gates on `accessibilityReduceMotion` and paints a steady state | **unchanged** (already conformant). |

### 1d. Material (`IslandMaterialTokens.flightDeck`)

| Token | Mockup | Shipped | Verdict |
|---|---|---|---|
| `material` / `blendingMode` / `appearanceName` | opaque flat panel | `.hudWindow / .behindWindow / .vibrantDark` (fallback only) | **unchanged** |
| `usesVibrancy` | opaque | `false` | **unchanged** |
| `tintOpacity` | opaque | `1.0` | **unchanged** |
| `specularTopEdge` | none (flat) | `nil` | **unchanged** |
| **Phosphor glow / self-lit lamps** | every lit lamp/beacon: `box-shadow: 0 0 5–14px <status>` bleeding outside the silhouette | `FlightDeckPhosphorGlow` applied to lit lamps/beacons | **implemented** — static code confirms the shared bleed primitive; pixel extent remains manual verification. |

---

## 2. Typography spec

The token layer intentionally carries no typography. `FlightDeckTypography`
(in `FlightDeckTheme.swift`) now records the theme's readable-role floor and
the **two-font system**; a few older view-local typography sites remain and
are called out honestly in the Shipped column below:

- **Sans narration** = `-apple-system / SF Pro Text` — session/workspace names,
  live activity narration prose, option labels, assistant-message rich text.
- **Mono tabular values** = `SF Mono` (`design: .monospaced`, `tabular-nums`) —
  all timers, counts, percentages, status codes, key hints, command/diff, brand
  wordmark, placards.

> **Shipped state.** The row uses `sansScaled(...)` for the session headline and
> narration; values retain the mono helper. SwiftUI exposes standard weight
> stops, not CSS numeric interpolation, so 640/800-like mockup weights are
> represented by the closest available `.semibold`/`.heavy` stop.

### Full scale (mockup value → role → floor compliance)

| Role | Mockup | Font | Weight / tracking | Floor | Shipped |
|---|---|---|---|---|---|
| Session/workspace name (`.ws`) | 13.5px | **sans** | 640 / −0.01em | ✅ | **13.5pt SF Pro/default, semibold (600), −0.135pt;** one line/tail. |
| Live narration (`.narr`, `.narr2`) | 12px | **sans** | 400–600 | ✅ | **12pt SF Pro/default, medium (500);** one line/tail. |
| Assistant rich text (`.assist`) | 13px/1.55 | **sans** | 400 | ✅ | **13pt SF Pro/default, regular (400);** declared 1.55 line-height role. |
| Option label (`.qopt .ol`) | 13px | **sans** | 600 | ✅ | **13pt SF Pro/default, semibold (600).** |
| Option description (`.od`) | 11.5px | **sans** | 400 | ✅ | **11.5pt SF Pro/default, regular (400).** |
| Duration readout (`.dur`) | 12px | **mono** tabular | 600 | ✅ | **13pt SF Mono, medium (500), tabular** in completion donestats; view-local, so not the 12pt target. |
| Model/meta (`.meta`) | 10.5px | **mono** | 400 | ✅ | **10.5pt SF Mono, regular/medium by cell;** tabular where numeric. View-local. |
| Age (`.age`) | 10px | **mono** | 400 | ✅ (at floor) | **10.5pt SF Mono, regular, tabular.** View-local. |
| Gauge value (`.gval`) | 12px | **mono** tabular | 700 | ✅ | **11pt SF Mono, bold (700), tabular** (`gaugeValue`). See accepted deviation below. |
| Command / diff (`.cmd`, `.diff`) | 13 / 12px | **mono** | 600 / 400 | ✅ | **Command 11.5pt SF Mono semibold (600); unified diff 10pt SF Mono regular (400)** in its style. |
| Brand wordmark (`.brand .wm`) | 11px | **mono** | / 0.18em | ✅ | **11pt SF Mono, medium;** Latin caps/tracking are view-local. |
| MASTER placard (`.master .big`) | 12px | **mono** | 800 / 0.12em | ✅ | **12pt SF Mono, heavy (nearest 800), 1.44pt tracking;** Latin caps, CJK un-cased/untracked. |
| ACK switch label (`.ack .lab`) | 12px | **mono** | 800 / 0.10em | ✅ | **11.5pt SF Mono, semibold (600), 0.8pt tracking;** a view-local deviation. |
| Button (`.btn`) | 11px | **mono** | 600 / 0.04em | ✅ | **11.5pt SF Mono, semibold (600), 0.8pt tracking;** question Submit is sentence case/no tracking. |
| Caps micro-label (`.caps`) | 10px | **sans** | 600 / 0.14em UPPER | ✅ (at floor) | **10pt, contextual:** most captions SF Mono semibold; metacell/donestat keys SF Pro/default semibold; Latin caps + tracking, CJK neutralized. |
| **Status code (`.code`)** | **9.5px** | mono | 700 / 0.08em | ❌ → **lift to 10** | **10pt SF Mono, bold (700), 0.8pt tracking;** Latin caps (`statusCode`). |
| **Column caption (`.colcap`)** | **9px** | sans | 600 / 0.14em UPPER | ❌ → **lift to 10** | **10pt SF Mono, medium (500), typically 1.4pt tracking;** Latin caps. View-local. |
| **Gauge label (`.glabel`)** | **9.5px** | sans | 600 / 0.13em UPPER | ❌ → **lift to 10** | **10pt SF Pro/default, semibold (600);** no explicit tracking/case at this call site (`gaugeLabel`). |
| **Metacell/summary/donestat key** | **9px** | sans | 600 / 0.12–0.13em UPPER | ❌ → **lift to 10** | **10pt semibold (600), mixed family:** metacell/donestat default/sans, summary SF Mono; roughly 0.8–1.0pt Latin caps tracking. View-local. |
| **Unit tag (`.gval u` "%")** | **9px** | mono | / 0.1em | ❌ → **lift to 10** | **10pt SF Mono, semibold (600), no explicit tracking** (`gaugeUnit`). |
| **Key hint (`.kk` `⌘Y`)** | **9px** | mono | | ❌ → **lift to 10** (shipped `keyHint` is already 10) | **10pt SF Mono, semibold (600), no explicit tracking.** |
| Overflow `+N` (grid) | fitted | mono | 800 | **exempt** (fitted micro-indicator, sized to lamp — same exemption shipped uses) | **Exempt fitted micro-indicator;** not a readable-role floor entry. |

**≥10pt floor compliance:** the mockup routinely drops to 9–9.5px on micro-labels;
the shipped theme pins `FlightDeckTypography.floor = 10` and asserts it in
`FlightDeckThemeTests.everyReadableTypographyRoleHoldsTheTenPointFloor`. **Every
sub-10 caps role above must be lifted to 10pt** — density comes from tracking +
rules, never sub-10 type. Only the fitted `+N` roll-up is exempt.

**Letterspaced-caps unit labels:** uppercase + `.tracking()` on Latin only; both
neutralize to un-cased/0-tracking for CJK via `FlightDeckText.caps/tracking`
(already implemented). Unit tags ("%", "5H", "7D") stay Latin placards in every
locale (same rule EICAS legends and `FlightDeckUsagePlacard` follow).

**Numeral rules:** `tabular-nums` on every timer/counter/meter/percentage — met
for free by `design: .monospaced` on all mono roles.

**Phase 6 role map (not legacy aliases).** `countGlyph` is the 11pt default/sans
bold attention glyph (`⚠` / `?`); `countLabel` is the 11pt default/sans medium
subagent phrase; `gaugeValue` is the 11pt bold mono numeric readout; `gaugeUnit`
is the 10pt semibold mono `%`; and `annunciatorCount` is the distinct **17pt bold
mono** summary-tile count. The last is intentionally not the 11pt closed-pill
count. `completionJumpLabel` is the completion rail's **10.5pt semibold mono**
Jump label; its arrow uses the existing 10pt `microLabel` role to satisfy the
readable floor. Roles such as duration, model/meta, brand wordmark, ACK switch label,
column caption, and metacell/summary/donestat key remain view-local rather than
pretending to have a single table role.

**Floor closure.** The formerly view-local reset countdown, actionable
Model · Branch context, and HELD placard are now named `resetCountdown`,
`annunciatorContext`, and `heldLabel` roles: each is **10pt SF Mono medium** and
included in the readable-role sweep. This closes the audited Flight Deck 9–9.5pt
readable-text escapes; fitted grid `+N` remains the sole stated exemption.

---

## 3. Slot-by-slot implementation map (8 `IslandTheme` slots)

### Slot 1 — `closedPill` → `FlightDeckClosedPill`
- **Mockup:** pill fused around the 200px notch lane, content in wings.
  Left wing = 3-bar liveness (`.bars idle/run/wait/warn`) + optional sans
  narration; right wing = `×N` count **or** mini annunciator grid (`.mgrid`
  7×7px lamps) **or** attention segment (`.seg warn/caution` with ACK/ANSWER
  ×N) **or** usage mini-tape (`7D 76%`). Per-state ambient variants A1–A6
  (idle/working/perm/question/settle/interrupted-failed) each read across the
  room; attention pill carries a **colored bloom** border+shadow.
- **Replaces/modifies:** `FlightDeckClosedPill` + `FlightDeckRightSlotView` +
  `FlightDeckAnnunciatorLight`. Keeps `V6ClosedPill` width math (morph frame
  stays identical).
- **Hardest detail:** (a) **phosphor glow on the running lamp + 2s breathe**;
  (b) the **attention `.seg` (ACK×1 / ANSWER×1)** and the **usage mini-tape**;
  and (c) a status-tinted closed-pill bloom. All three are now shipped through
  the right-slot and closed-glow seams; retain them as regression requirements.

### Slot 2 — `openedHeader` → `FlightDeckHeaderControls` + `FlightDeckUsageSummary`
- **Mockup:** notch-split lanes; brand mark + wordmark; usage as **linear tape
  gauges** with 70/90 threshold ticks + `RESETS-IN` countdown; mute/settings/quit
  as squared panel switches.
- **Replaces/modifies:** header layout **unchanged**. `FlightDeckUsageSummary` /
  `FlightDeckUsageWindowGauge` / `FlightDeckTickGauge` are **restyled**:
  12-tick-segmented → **continuous tape + 2 ticks + inline resets-in**.
- **Hardest detail:** surfacing **`resetsAt` inline** (today only in `.help()`
  tooltip) while keeping the notch-split width math; the tape must draw the 70%
  hairline tick + 90% red `crit` tick at fixed x regardless of fill %.

### Slot 3 — `sessionRow` → `FlightDeckSessionRow` (+ approval / question / completion bodies)
- **Mockup (non-actionable):** grid `Status | Session | Model | Time`. **Status =
  a lamp + a text code** (RUN/DONE/CAUT/WARN/INTR/FAIL/IDLE). Session = name
  (sans) + branch chip + optional SSH / `⚙ N SUB` chip + narration sub-line.
  Actionable rows dominate: `act-perm` red inset bar + gradient wash;
  `act-caut` amber. Hover-reveal dismiss (`✕`).
- **Replaces/modifies:** `FlightDeckRowContent`. The shipped register is
  `STATUS|SESSION|MODEL|TIME`: STATUS has a lamp plus text code, and former APP
  data (SSH) is folded into the session chip lane.
- **Actionable — permission** → `FlightDeckApprovalCard`: **MASTER WARNING** (see
  §1a two-tier). Red beacon + placard + `PERMISSION REQUIRED` kicker; command in
  a chamfered mono box; affected-path line; inline diff; ALLOW(inverted)/DENY
  (outlined) switches with **real ⌘Y / ⌘⇧Y / ⌘N** hints; scoped always-allow
  from `suggestedUpdates`; **held Ns** counter; Codex → jump-to-approve bar.
- **Actionable — question** → **MASTER CAUTION** amber annunciator header above
  `StructuredQuestionPromptView`; numbered digits 1–9, multi-select, freeform
  Other, and Enter submission.
- **Actionable — completion** → chamfered mono card; outcome banner for
  interrupted/failed; reply input where supported.

**Approved F2.4 identity-run deviation.** The board's third `.ann-ctx` flex
column was evaluated in the placard/kicker/HELD top line. At both 540pt notch and
520pt top-bar widths it produced a ~**0.61** placard:kicker cap-height ratio,
truncated the kicker, and wrapped the HELD readout. Shipped places Model · Branch
as a dedicated second line below the beacon/placard/kicker/HELD line. The settled
top-line cap-height range is **1.06–1.70**; retain that measurable readability
result rather than forcing the board's third-column geometry.
- **Hardest detail:** the permission card is the hero — a *pulsing red glow*
  (`FlightDeckCautionGlow` retinted to warning), the two-tier rename, and keeping
  the **⌘Y/⌘⇧Y/⌘N** glyphs in lock-step with the global handler (never the
  mockup's ⏎/⎋). Plus the new STATUS-code column re-aligning every register.

### Slot 4 — `sessionList` → `FlightDeckSessionListScaffold`
- **Mockup:** annunciator **summary strip** (`ATTN/RUN/DONE/IDLE`, lit when
  non-zero, dark at zero) → **column captions** (`STATUS SESSION MODEL TIME`) →
  section headers (tinted lamp + caps title + count) → rows → **BRIDGE LINK
  footer** (green blinking lamp + `LINK`/`NO LINK` + session count).
- **Replaces/modifies:** `FlightDeckSessionListScaffold` — mostly present.
  Column captions must gain a **STATUS** caption (mockup 74px) to sit over the new
  status-code column; footer must **drop `socket path` and `EVT/MIN`** (no data
  source — §6).
- **Hardest detail:** the caption strip already registers MODEL/APP/TIME lanes to
  the row grid; re-registering to `STATUS|SESSION|MODEL|TIME` while the row's
  fixed lanes shift.

### Slot 5 — `notificationCard` → `IslandNotificationCard` (inherits row treatment)
- **Mockup:** the single actionable item as a card (`.alarm`) — `minihead`
  (brand + "Show all N ›") + annunciator + phase interior. Auto-collapse 10s
  (completions), hover pauses countdown.
- **Replaces/modifies:** unchanged wiring; inherits `FlightDeckSessionRow` via the
  factory. The MASTER WARNING/CAUTION annunciator is the card's hero.
- **Hardest detail:** the `minihead` notch-split + "Show all N" affordance already
  exist in the shared card; ensure the two-tier annunciator renders identically in
  `.notification` and `.list` presentations.

### Slot 6 — `emptyState` → `FlightDeckEmptyState`
- **Mockup §J:** lamp grid (1 lit, breathing) + heading **"ALL SYSTEMS NOMINAL"**
  + monitoring copy + `BRIDGE LINK · MONITORING · 0 SESSIONS` sysline + footer.
- **Replaces/modifies:** `FlightDeckEmptyState` — shipped heading is **"NO SIGNAL"**
  (dim). Mockup is confident/positive (green lit lamp).
- **Hardest detail:** tone flip (NO SIGNAL → ALL SYSTEMS NOMINAL) + a breathing
  lit lamp in the empty grid (needs the same glow treatment).

### Slot 7 — `bootstrapPlaceholder` → `FlightDeckBootstrapPlaceholder`
- **Mockup:** not a distinct frame; reuse the empty-state "power on, monitoring"
  idiom (squared hairline panel, `STANDBY`/probing caption).
- **Replaces/modifies:** unchanged shell; align caption + glow with the empty state.

### Slot 8 — `installHint` → `FlightDeckInstallHooksHint`
- **Mockup:** not a distinct frame; a squared hairline panel with a `SETUP`
  caption (string exists: `island.flightDeck.hint.setup`).
- **Replaces/modifies:** unchanged shell; verify chamfer/hairline idiom + tap CTA.

---

## 4. Scenario acceptance criteria (A–K)

### A — Collapsed pill, ambient states
- A1 idle: bars `.idle` at ~4px, opacity 0.5; right wing caps **"STANDBY"**; no
  status color; near-invisible.
- A2 working: bars `.run` wave at **1.4s** (`#4AC99E` + 5px glow); sans narration
  "**Editing** AppModel.swift" (verb `#4AC99E`); right = mini grid, running lamps
  breathe at **2s** with glow, idle lamps dark.
- A3 permission (WARNING): pill `attn-perm` = **red** border `rgba(224,74,66,.55)`
  + bloom `0 6px 26px -14px rgba(224,74,66,.6)`; bars `.warn` red; `.seg warn`
  ⚠ ACK ×1 at `attn 1s`.
- A4 question (CAUTION): pill `attn-caut` = **amber** border; bars `.wait` amber;
  `.seg caution` `?` ANSWER ×1 at `cautbg 1.2s`.
- A5 completion settle: `settle 3s` — nominal `#4AC99E` flash+scale(1.25) →
  advisory `#6392C4` calm dot; narration "Done · AGENTS.md" (`#6392C4`).
- A6 outcome variants: interrupted = amber `⊘` (`#E6AA42`); failed = red `✕`
  (`#E04A42`); **never green for both**; each pairs glyph + color (not color alone).

### B — Hover peek
- Dwell **0.15s** → shape begins to open; pill scales **~1.028**.
- Peek tray drops per-session micro-rows, **actionable item on top** (perm before
  running before question); `Click to open · Esc to dismiss` caption.
- Expand is **one shape**: top radius 0→6, glyph **travels** into header (no
  crossfade); motion = relay-snap (response .32 / damping .92).

### C — Expanded list
- Header notch-split: left `CLAUDE · 5H 17%` green tape + `RESET 2H 10M`; right
  `CLAUDE · 7D 76%` amber tape + `RESET 4D 06H`; mute/settings/quit switches.
- Summary strip: `ATTN 2` (red lit) · `RUN 2` (green lit) · `DONE 3` (blue lit) ·
  `IDLE 0` (dark).
- Column captions `STATUS SESSION MODEL TIME`.
- Rows top-to-bottom by attention: `WARN` perm (red inset) → `CAUT` question
  (amber inset) → `RUN` → `RUN ⚙3 SUB` → `DONE` → `INTR` (amber).
- Duplicate `the-automator` disambiguated by **branch chip** (`feat/auth-bridge`
  vs `main`).
- Footer: green **blinking** link lamp + `BRIDGE LINK LINK` + `N SESSIONS`
  (**no** socket path, **no** EVT/MIN — §6).

### D — Row detail
- Metagrid: Agent / Model / **Mode** (`acceptEdits`) / **Branch** / Uptime
  (tabular, live) / Terminal + **`ATTACHED`** badge.
- "NOW" narration: verb `#4AC99E` + file paper; "Last message" as **clean rich
  text** (not raw dump); inline `code` in `#4AC99E`.
- Primary CTA = **Jump to terminal**; Transcript link; **Dismiss hover-reveal**.

### E — Permission (hero, MASTER WARNING)
- Red beacon (chamfer 3) pulsing at **1s**; placard **"MASTER WARNING"** (red);
  `PERMISSION REQUIRED` kicker; `HELD 0m 08s` counter counting up.
- E1 command: `$ swift build -c release --product OpenIslandHooks` syntax-lit in a
  chamfered mono box; narration; scoped `⌘⇧Y` always-allow options.
- E2 diff: `−1 +2`; del row red gutter/bg, add row green gutter/bg (phosphor
  `#4AC99E`/`#E04A42`).
- ACK switches: **ALLOW ONCE ⌘Y** (inverted paper), **ALLOW ALWAYS ⌘⇧Y** (ghost),
  **DENY ⌘N** (outlined). Glyphs match the real global handler, never ⏎/⎋.
- E3 Codex: no ACK switches; `↗ Approve in Codex` bar + `Jump to Codex.app`
  (`requiresTerminalApproval == true`).

### F — Question (MASTER CAUTION)
- Amber beacon pulsing at **1.2s**; placard **"MASTER CAUTION"** (amber) — this
  header is **new** (shipped question has none).
- F1: `AUTH Q 1/2 · SINGLE` (digits 1–3) with per-option descriptions; `SCOPE
  Q 2/2 · MULTI` (digits 4–6, amber-filled checks) + `Other` (digit 7) freeform;
  hint "Digits **1–9** select · Enter submits · Esc closes"; Submit `⏎`.
- F2 compact single: one question, `1/2` hint, tight footprint.
- Digits/Enter driven by `OverlayUICoordinator` (not restyled semantics).

### G — Subagents + tasks (engine cluster)
- 3 engines, each: type placard (`EXPLORE`/`GENERAL`/`PLAN`, `#4AC99E`) + breathing
  lamp + task line + **per-subagent elapsed** (`3m 04s` tabular from `startedAt`) +
  arc fill %.
- Todo list `4 / 6 DONE`: done=blue check + strikethrough; doing=green breathing
  box; pending=dim.
- Compression: whole cluster → **one pulsing lamp** + wing "3 subagents · 4/6".

### H — Completed (advisory blue)
- `SUCCESS` badge (blue check); result as **prose** (not dump); donestats Outcome
  `✓ Success` / Duration `43m 12s` / Files `3 changed` / Agent; follow-ups
  **Jump / Transcript / Reply / Dismiss**.
- Interrupted/failed variants carry the outcome banner + amber/red status.

### I — Usage meters (tape gauges)
- NOM: `< 70%` green fill; ticks at 70 (hairline) + 90 (red crit); `Resets in 2h 10m`.
- CAUT: `70–90%` amber; value amber.
- CRIT: `≥ 90%` red, fill past the 90 tick, gauge **blinks**; `Resets in`.
- Pill compression: worst window → wing mini-tape + `7D 76%` (amber).

### J — Empty
- Lamp grid: 1 lit (breathing `2.6s`) + 3 dark; heading **"ALL SYSTEMS NOMINAL"**;
  monitoring copy; `BRIDGE LINK · MONITORING · 0 SESSIONS`; footer `IDLE`.

### K — Motion strip (live CSS → Swift constants)
- Phosphor pulse (running · 2s), Expand morph (one shape · radius latch), Attention
  pulse (master alarm · 1s), Row entrance (relay-snap in), Success settle (flash →
  advisory), **Lamp snap-on (120ms on · soft decay)**. Each demo maps to a named
  Swift animation constant; `prefers-reduced-motion` → steady.

---

## 5. Conformance checklist

### Fixture coverage (`AppearancePreviewFixtures.sessions`, `AppearanceSettingsPane.swift:1155`)
The deterministic fixture/harness matrix now maps A–K as follows. Keep these rows
as the required regression inventory rather than treating them as missing work:

| Frame | Fixture need (fields to set) |
|---|---|
| A1 / J | empty (0 sessions) |
| A2 / C-run | running + `currentTool`/`currentCommandPreview` → "Editing AppModel.swift" |
| A3 / C-perm / E1 | `waitingForApproval` + `permissionRequest.commandPreview` (`swift build …`) + `suggestedUpdates` |
| E2 | `permissionRequest.fileDiffSource` (old/new) on an Edit |
| E3 | `waitingForApproval` + `tool: .codex` + `requiresTerminalApproval = true` |
| A4 / F1 | `waitingForAnswer` + multi-`QuestionPromptItem` (single + `multiSelect` + option descriptions + Other) |
| F2 | single-question prompt (`tool: .opencode`) |
| A5 / H | `completed` + `outcome: .success` + assistant message (markdown) + `reply` action |
| A6 / C-intr | `completed` + `outcome: .interrupted` |
| A6 | `completed` + `outcome: .failed` |
| C-dupe | two `the-automator` sessions w/ different `worktreeGitBranch` **(claude only)** |
| D | running + `attachmentState: .attached` + `permissionMode: .acceptEdits` + `isRemote` (SSH) |
| G | claude running + `activeSubagents[3]` (agentType/task/startedAt) + `activeTasks[6]` (4 done/1 inProgress/1 pending) |
| I | `UsageProviderPresentation` windows with **non-nil `resetsAt`** at 17/76/93% |

### Token equality coverage
- `FlightDeckThemeTests.statusPaletteIsTheFour...` — **unchanged** (two-tier color
  mapping already correct).
- `everyReadableTypographyRoleHoldsTheTenPointFloor` — extend `readableRoleSizes`
  with any new sans roles; all ≥ 10 (lift the 9–9.5px caps).
- `chamferedChromeMorphsWithoutAPouredFillet` — unchanged (radii 6, fillet 0).
- `flightDeckIsAFlatPanelWithoutVibrancy` — unchanged.
- `FlightDeckUsageWindowGauge.usageColor` band tests (90/70) — unchanged when the
  gauge geometry flips to tape (keep the same thresholds).
- `masterWarning` is pinned to `statusWaitingForApproval` (red) and
  `masterCaution` to `statusWaitingForAnswer` (amber).
- `FlightDeckApprovalFormat.Shortcut.glyphString` is pinned as
  `⌘Y / ⌘⇧Y / ⌘N`.

### Snapshot pins (Settings previews, AB-305)
Pin one snapshot per frame A–K at the editing profile, both notch + top-bar,
default + Increase Contrast + Reduce Motion, en + zh-Hans. Hero pins:
permission (MASTER WARNING red), question (MASTER CAUTION amber), engine cluster,
tape gauges (NOM/CAUT/CRIT), empty (ALL SYSTEMS NOMINAL).

### Judged-by-eye (manual sign-off)
- Phosphor glow bleeds **outside** each lit lamp silhouette (pill, lane, tiles,
  engines, footer, empty grid) without smearing text.
- Running breathes at 2s (not blink); lamp snap-on reads as instant-on / soft-decay.
- Permission frame "feels like an EVENT" (pulsing red glass), not a restyled form.
- Sans headline vs mono values is visibly distinct; no mid-word truncation;
  duplicate names disambiguated by branch.
- Attention pill readable "across the room"; exactly **one loud thing** at a time.
- Colored attention bloom on the closed pill matches per-state tint.

---

## 6. Data / plumbing prerequisites (source field per brief §3)

| Shown in mockup | Status today | Source field (§3) | Action |
|---|---|---|---|
| **RESETS-IN** countdown on gauges | surfaced inline (`RESET <countdown>`) | `UsageWindowPresentation.resetsAt` | keep fixtures non-nil; countdown is now named 10pt mono readable text |
| **Attachment** readout (`ATTACHED`/stale/detached) | rendered as an honest detail badge | `AgentSession.attachmentState` | retain state-specific badge |
| **Narrated activity** ("Editing AppModel.swift") | rendered as narration, not a raw `$ <preview>` echo | current tool name + `currentCommandPreviewText` / `spotlightActivityLineText` | keep truthful verb-map translation |
| **Branch** chip + disambiguation | rendered when available; recency is fallback | `worktreeGitBranch` (**claude only**) | preserve availability gate; never invent Codex branch content |
| **Permission mode** chip (`acceptEdits`) | rendered when available | `permissionMode` (**claude only**) | preserve Claude-only gate |
| **Subagents engine cluster** + per-subagent elapsed | rendered; elapsed is live from `startedAt` | `activeSubagents[]` (agentType/task/`startedAt`) | retain; per-engine progress arc stays absent because no truthful source exists |
| **Todo list** (4/6) | rendered with completed/in-progress/pending semantics | `activeTasks[]` (pending/inProgress/completed) | retain icon + text state channels |
| **`⚙ N SUB` / compression** in pill+row | rendered as row chip and pill task-counter roll-up | count of `activeSubagents` | retain |
| **HELD Ns** on the alarm | rendered using an explicitly bounded `updatedAt` approximation | *(no explicit "request arrived at" field)* | retain approximation disclosure; hide implausibly stale values |
| **SSH** badge | shipped shows APP=`SSH` | `isRemote` | reuse; render as chip |
| Diff / scoped always-allow / Codex jump | shipped ✅ | `fileDiffSource`, `suggestedUpdates`, `requiresTerminalApproval` | keep |
| Usage compressed into pill (mini-tape) | routed as a right-slot usage case | `usedPercentage` (worst window) | retain critical-only policy noted below |
| Attention `.seg` (ACK×1 / ANSWER×1) in pill | routed as a right-slot attention-count case | waiting count by phase | retain glyph + placard + tint distinction |
| **Footer `socket path` + `EVT/MIN`** | shipped footer = link + count only | **no source field** (EVT/MIN, socket path) | ⚠ **do not render** — invented precision (the "×4" trap, brief §1.2/§3). Keep shipped's honest link + session count. |

---

## Appendix — key files

- Tokens: `Sources/OpenIslandApp/Theme/IslandColorTokens.swift` (`.flightDeck`
  L282–316), `IslandMetricsTokens.swift` (L90–116), `IslandMotionTokens.swift`
  (L100–113), `IslandMaterialTokens.swift` (L107–122), `IslandThemeTokens.swift`.
- Slots: `Views/Island/FlightDeckClosedPill.swift`, `FlightDeckHeaderControls.swift`,
  `FlightDeckUsageSummary.swift`, `FlightDeckSessionRow.swift` (incl.
  `FlightDeckApprovalCard` L1410, `FlightDeckCautionGlow` L1625,
  `FlightDeckApprovalButton` L1671, `FlightDeckChamferedRectangle` L929),
  `FlightDeckSessionListScaffold.swift` (BRIDGE LINK footer L376),
  `FlightDeckEmptyState.swift`, `FlightDeckBootstrapPlaceholder.swift`,
  `FlightDeckInstallHooksHint.swift`.
- Typography: `FlightDeckTypography` / `FlightDeckText` in `FlightDeckTheme.swift`.
- Fixtures: `Views/AppearanceSettingsPane.swift` `AppearancePreviewFixtures` (L1155).
- Strings: `Resources/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings`
  (`island.flightDeck.*`, including the shipped `approval.masterWarning`).
- Tests: `Tests/OpenIslandAppTests/FlightDeckThemeTests.swift`,
  `FlightDeckSessionRowTests.swift`.

## 7. Recorded implementation deviations

- **Paper:** the mockup proposes `#D8E1E6`; shipped shared `flightDeckPaper` is
  **`#D4DAD6`**. This is an intentional retained token deviation, not a semantic
  status remap.
- **Pill usage:** the mockup illustrates amber `7D 76%`; shipped prioritizes the
  pill slot only for the worst **critical (≥90%)** usage window, so a production
  usage pill normally reads red critical instead. Keep that cross-theme attention
  policy unless product direction changes.
- **Gauge value:** the mockup target is 12pt; shipped `gaugeValue` is **11pt bold
  mono**. It is named and floor-compliant, but remains a documented size deviation.
- **Weights:** where the board specifies 640/650/660/800, SwiftUI uses the nearest
  standard weight stop. These are approximations, not falsely exact CSS weights.
