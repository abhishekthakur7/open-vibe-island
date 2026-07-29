# Coordinator's own findings (independent of the critique fleet)

> **VERIFICATION PASS 1 COMPLETE.** All coordinator findings CONFIRMED. Two mechanism corrections
> (C3, C4) and two rescopes on audit findings (see "Verifier corrections" at the bottom). The
> corrections are folded into the entries below — read those, not the original narration.

## CONFIRMED — code + pixel evidence

### C1. Halo's permission diff drops the `+`/`−` marker column — add/remove is conveyed by COLOUR ALONE
- **Severity**: MAJOR (accessibility + fidelity)
- **Mockup shows**: `shots/mockup/halo-E2.png` — line 13 red reads `− Branch off main and open a PR.`, line 13 green reads `+ Never edit the main worktree.` The `−`/`+` glyphs are explicit.
- **App shows**: `shots/app/halo-diffApprovalCard.png` — no marker glyph on any diff row. Added and removed rows are distinguished only by text colour and row background tint.
- **Code**: `HaloSessionRow.swift:2186-2196` — `diffRow()` renders exactly two children: `Text("\(row.gutter)")` and `Text(row.line.text)`. There is no marker.
- **Contrast with the other two implementations**:
  - Shared `PermissionDiffPreview` (`IslandPanelView.swift:134-155`): dedicated marker column, `frame(width: 10, alignment: .leading)`, own `markerColor`. → Flight Deck inherits this, so FD is fine.
  - Poured `PouredPermissionDiff.row` (`PouredSessionRow.swift:2044`, `markerPrefix` :2057-2063): marker is concatenated into the text string (`"+ "` / `"− "` / `"  "`), same colour as the line. Glyph present → accessible.
  - Halo: **no marker at all.**
- **Why it matters**: BRIEF §5 "Accessibility sanity: … state never conveyed by color alone (pair with icon/shape/label)". Halo is the only theme that violates this, on its hero frame.
- **Ticket**: `fix: Halo permission diff must render +/− markers, not colour alone` → `Sources/OpenIslandApp/Views/Island/HaloSessionRow.swift:2186`

### C2. Three forked diff implementations with three different geometries (component inconsistency)
- **Severity**: MAJOR (this is the reviewer's complaint #2, in one component)
- Same logical component, three call sites, three sets of metrics:

| | marker | gutter width | trailing pad | font | row padding |
|---|---|---|---|---|---|
| Shared `PermissionDiffPreview` (IslandPanelView.swift:132-146) | separate col, w10, spacing 6 | none | — | **10pt** mono | H6 / V1 |
| Poured `PouredPermissionDiff` (PouredSessionRow.swift:2038-2055) | inline in text | **26** | 10 | **11.5pt** (`diff` role) | l8 r10 / V1 |
| Halo `HaloHeroDiff` (HaloSessionRow.swift:2186-2196) | **absent** | **22** | 10 | **11.5pt** | l8 r11 / V1 |

- Gutter width varies 10 → 26 → 22 with no shared token; diff font varies 10pt → 11.5pt.
- **Ticket**: `refactor: unify the three permission-diff implementations behind one metric set + marker contract`

### C3. Notch-mode header lane split is per-PROVIDER, but the mockup splits per-WINDOW — single-provider users get an unbalanced header
- **Severity**: MAJOR (layout, affects the most common configuration, all three themes)
- **Mockup shows**: `shots/mockup/halo-x10.png` (§C) — `CLAUDE 5H` sits in the LEFT lane, `CLAUDE 7D` in the RIGHT lane, balanced around the notch cutout, controls far right. Same in the Poured and Flight Deck boards.
- **App shows**: `shots/notch/halo-usageMeters.png` — BOTH `CLAUDE 5H` and `CLAUDE 7D` are crammed into the left lane; the right lane holds only the three control buttons. The header reads left-heavy and the right lane is dead space.
- **Code**: `splitUsageProviders(_:)` splits the `[UsageProviderPresentation]` array, i.e. by **provider**. A Claude-only user has `providers.count == 1` → `case 1: return ([providers[0]], [])` → right lane empty. The 5H and 7D *windows* live inside that single provider and are never split.
  - `HaloHeaderControls.swift:128-145`
  - `PouredHeaderControls.swift:124-140`
  - `FlightDeckHeaderControls.swift:120-136`
- **Aggravating**: the function is **triplicated verbatim** across the three themes — same bug, three copies.
- **Note**: only observable in notch mode; top-bar mode uses a single lane, so the harness's default top-bar captures hide it. Caught via the forced-notch capture set in `shots/notch/`.
- ⚠️ **VERIFIER MECHANISM CORRECTION — the defect is WORSE than originally narrated.** The fixture actually supplies **two** providers (Claude *and* Codex), not one (`AppearancePreviewFixtures.usageProviders`, via `AppModel.swift:1234-1238`). The top-bar capture's `.ax.json` proves Codex is present in the data (`"Codex 7d 92% 18h 59m"`), yet Codex is **entirely absent from the notch captures**. So the observed crowding is not the `case 1` single-provider branch I described — it is the `rightUsageWidth < minimumRightUsageLaneWidth` fallback (`HaloHeaderControls.swift:196-198`) **silently dropping an entire usage provider** rather than rebalancing. `UsageProviderPresentation.windows: [UsageWindowPresentation]` (`IslandUsageSummary.swift:8-11`) confirms one provider carries multiple windows. Both the provider-granularity split *and* the silent-drop fallback are real; the second is the more serious of the two.
- **Ticket**: `fix: notch header drops an entire usage provider when the right lane is under-width; split lanes by window, not provider (all 3 themes) + de-duplicate splitUsageProviders`

### C4. Flight Deck usage gauges overflow the header band — clipped above, overlapping content below
- **Severity**: MAJOR (layout breakage, both placements)
- **App shows (top-bar, 3 windows)**: `shots/app/flightDeck-usageMeters.png` — the tape-gauge tiles wrap into a 2-row grid. Row 1 (`Claude · 5H`, `Codex 7D`) is **clipped by the panel's top edge**: only the `RESET 2H 9M` / `RESET 18H 59M` footers survive, the label + tape rows are cut off. Row 2 (`Claude · 7D 78%`) **draws on top of** the content beneath it — its orange tape bar and `RESET` text collide with the banner text.
- **App shows (notch, 2 windows)**: `shots/notch/flightDeck-usageMeters.png` — same failure with only **two** windows; the gauge stack collides with the header control buttons (speaker/gear/power render over `SETUP`), and `Claude · 7D 78%` is clipped mid-tile.
- ⚠️ **VERIFIER MECHANISM CORRECTION**: it is **not** a wrapping 2-row grid. `FlightDeckUsageSummary` is an `HStack` of per-provider chips, each internally a **`VStack` of window gauges** (`FlightDeckUsageSummary.swift:32-43, 60-65`). Claude's 2-window chip is simply **taller than the header's reserved band**, so it overflows both upward (clipped by the panel edge) and downward (collides with whatever sits below). Severity and core defect stand; "wraps to 2 rows" was an imprecise description.
- ✅ **VERIFIER: banner-independence CONFIRMED.** The gauge content is cut off at the panel's **y=0 physical top edge** — nothing to do with the banner. And the stronger, entirely banner-free proof is the notch capture: in `shots/notch/flightDeck-usageMeters.png` the "RESET 2H 9M" text and gauge content **directly overlap the header control buttons** (mute/settings/quit), producing garbled "SE TOP" text over the icons. Compared against `shots/app/flightDeck-sessionList.png` (no usage windows → clean header), confirming the trigger is usage-window count.
- **Contrast**: `shots/app/flightDeck-sessionList.png` (same theme, no usage windows present) renders a clean header — confirming the trigger is the presence of usage gauges, not the banner.
- **Ticket**: `fix: Flight Deck usage tape-gauges overflow the opened-header band (clip + overlap)` → `Sources/OpenIslandApp/Views/Island/FlightDeckUsageSummary.swift`, `FlightDeckHeaderControls.swift`

### C5. Approve/Deny button ORDER is reversed in Flight Deck vs the other two themes — and vs its own mockup
- **Severity**: MAJOR (consistency + safety on a blocking, destructive-adjacent control)
- **Code**:
  - Poured — `allowOnce` first, `deny` second → **Allow LEFT / Deny RIGHT** (`PouredSessionRow.swift:1614` then `:1626`)
  - Halo — `allowOnce` first, `deny` second → **Allow LEFT / Deny RIGHT** (`HaloSessionRow.swift:1867` then `:1874`)
  - Flight Deck — `deny` first, `allowOnce` second → **Deny LEFT / Allow RIGHT** (`FlightDeckSessionRow.swift:2804` then `:2812`) — **reversed**
- **Mockup**: `shots/mockup/flightDeck-E1.png` shows the row as `ALLOW ONCE · ALLOW ALWAYS · DENY` — affirmative first, destructive last. Flight Deck's shipped order contradicts **its own approved board**.
- **Evidence pair**: `shots/pairs/flightDeck-E1-master.png` (mockup left, app right).
- **Why it matters**: this is a real blocking round-trip — the hook waits on the answer. A user who switches themes carries muscle memory to the wrong button. BRIEF §6 lists row verbs as a shared contract; button order should not be a theme variable.
- **Ticket**: `fix: Flight Deck approval buttons must order Allow before Deny (match Poured/Halo + the FD board)` → `Sources/OpenIslandApp/Views/Island/FlightDeckSessionRow.swift:2804`

## CHECKED AND CLEARED — do NOT file (recorded so the report is honest)

### N1. Halo session-row edge-lit rail — PRESENT, correct
Initially suspected missing from `shots/notch/halo-usageMeters.png`. Pixel-sampled the running row's left margin: rail occupies x=118–121 (4px @2x = **2.0pt**, matching `HaloMetrics.railWidth = 2`), colour `rgb(104,130,195)` = the cyan→violet running gradient. Correctly gated to live/actionable rows only (`HaloSessionRow.swift:182`, `HaloEdgeLitRail` :1382-1391). **Not a defect.**

### N2. Halo §C session list shows no section headers
The mockup groups rows under tinted `NEEDS YOU / RUNNING / DONE` headers; the app capture shows a flat list. This is **the user's setting**, not a defect — `appearance.island.v8.notch.sessionGroup = none` in `defaults read app.openisland.dev`. Grouping renders when the setting is on. **Not a defect.**

### N3. "Attention pill glow is a huge banded halo" — NOT CONFIRMED, do not file
At reduced viewing scale the A3 attention pill in all three themes appeared to be engulfed in an oversized, concentrically-banded orange halo, far cruder than the mockup's precise thin edge-light. **Measurement does not support this.** Lateral glow bleed sampled through the pill body:

| Theme | pill body width | glow span | bleed per side | spec |
|---|---|---|---|---|
| Poured | 320pt | 330pt | **5.0pt** | BRIEF/SPEC: "+4px outside at r34" ✓ |
| Flight Deck | 226pt | 228pt | **1.5pt** | `FlightDeckPhosphorGlow` bleed default 2pt ✓ |
| Halo | 240pt | 258pt | **9.5pt** | `permissionBloomRadiusMax` 21 — within budget ✓ |

All three are within their specified bloom budgets. A follow-up attempt to measure banding via centre-column falloff was **invalid** — the scanline passed through the pill's label glyphs, not the glow. The apparent severity is best explained by the app capture rendering the bloom against **pure black** (the harness captures the panel alone) while the mockup renders it against a **dark-grey desktop strip**; identical glow reads far louder on black. **No finding filed.** If someone wants to pursue it, it needs a capture with desktop context behind the pill.

### N4. Content differences in the notch captures
`shots/notch/*` restored the user's real session registry (real workspace names, Chinese summaries) rather than fixtures, because the `usageMeters`/`sessionList` scenarios overlay usage fixtures on the live list. Judge layout/type/components from these, not content.

## C6. SCENARIO-SURFACE MISMATCH — a scoping correction that reframes several findings
Not a product defect; a **review-methodology correction** that must be stated in the report so downstream tickets aren't mis-filed. Source: `Sources/OpenIslandApp/IslandDebugScenario.swift:108-300`.

The 15 harness scenarios render **two different surfaces**:

| Surface | Config | Scenarios |
|---|---|---|
| **Notification card** (auto-surfaced, deliberately compact — the thing that pulls the island open) | `notchOpenReason: .notification` + `islandSurface: .sessionList(actionableSessionID:)` | `approvalCard`, `questionCard`, `completionCard` (:183-195), `longCompletionCard`, `diffApprovalCard`, `codexApprovalCard`, `multiQuestionCard`, `completedInterrupted` (:263-273), `completedFailed` (:276-286) |
| **Plain session list** (no actionable session, rows collapsed) | `notchOpenReason: .click` + `islandSurface: .sessionList()` | `sessionList`, `subagentsCard` (:250-260), `usageMeters` (:289-300) |

Consequences:
1. **The "completion card is missing its footer actions" claim — triangulated by all three theme agents — is measuring the notification card against mockup §H, which depicts the full expanded completed-session treatment.** Different surfaces. Sent to adversarial verification; expect REFUTED or RESCOPED-to-coverage-gap.
2. **§G subagents never expands** because `subagentsCard` has no `actionableSessionID` and renders the subagents session as an ordinary collapsed row. A **scenario limitation, not a product defect.**
3. **§I's 52pt dial card never appears** because `usageMeters` only injects usage fixtures into the header lane. Same class — **scenario limitation.**
4. **Halo's Failed-vs-Interrupted template difference** cannot be a surface difference — both use the identical notification-card path — so it is driven by fixture data (agent kind), pending verification.

**Recommendation**: add harness scenarios that drive the *expanded row* (§D detail, §G engine cluster) and the §I full meter card, otherwise those frames can never be visually regression-tested.

## OPEN LEADS handed to the verify pass
- Halo running row appears to lack the mockup's meta-chip cluster (`Opus 4.8`, `acceptEdits`, `⏱ 1m 42s` chips); app renders a bare `🕐 <1m` with no chip background, AND the same age is already shown top-right (apparent duplication). Needs measurement.
- Halo row vertical rhythm looks looser than the mockup (more dead space per row). Needs measurement against the mockup's row pitch.
- Halo hero ring/bloom appears dimmer and thinner than the mockup's amber→magenta ring. Needs pixel sampling vs the spec's `rgba(255,160,80,.55)` ring / `rgba(255,140,80,.5)` glow.
- Halo scope row renders the scoped pattern as plain text; mockup puts it in a mono chip (`*.md`). Needs confirmation.

---

# VERIFIER CORRECTIONS to the cross-cutting audits (Appendices A & B)

Applied after adversarial verification pass 1. **Correct these before filing tickets.**

## RESCOPED — Appendix A.6 item 4: FD `count` role in four weight/design combinations
**Substance CONFIRMED, file citation WRONG.** The four combinations and their line numbers are exactly right, but they live in **`FlightDeckClosedPill.swift`**, not `FlightDeckSessionRow.swift` — which contains no `countSize` usage at all.

Corrected citation — all at `FlightDeckTypography.countSize` = 11pt, whose canonical role is 11/semibold/mono (`FlightDeckTheme.swift:112`):
| file:line | Rendered | What it is |
|---|---|---|
| `FlightDeckClosedPill.swift:536` | **bold + sans** | `spec.glyph` |
| `FlightDeckClosedPill.swift:601` | **bold + mono** | `"\(percent)%"` |
| `FlightDeckClosedPill.swift:633` | **medium + sans** | subagent count phrase |
| `FlightDeckClosedPill.swift:638` | semibold + mono (canonical) | `completed/total` |

## RESCOPED — Appendix A.6 item 5 / Halo critique: `nestHeader` renders at two weights
**Real but much narrower than claimed.** Weights verified exactly, but reading each call site's context shows only **two of the five** are genuine same-role instances:

- **The real defect**: `HaloSessionRow.swift:622` ("SUBAGENTS" caption — uppercase, `*0.09` tracking, `.bold`) vs `:1102` (assistant-card label — uppercase, `*0.09` tracking, `.semibold`). Both are true small-caps captions above a card body, and they genuinely differ in weight.
- **NOT instances of this defect** (do not cite them): `:625` and `:720` are numeric count/progress readouts ("N active", "2 of 5") — not uppercased, not tracked, appropriately lighter, and merely reuse the `nestHeaderSize` *size constant*. `:2019` is the separately-specified `.q-tag` chip role with its own documented spec (10pt/700/0.05em at `:2010`) that happens to also be bold.

## CONFIRMED with a bonus finding — Appendix A.6 item 1: FD MASTER placard
Code is `size: 10.5, weight: .bold, design: .monospaced` (`FlightDeckSessionRow.swift:2626-2627`); the kicker beside it is 11/semibold (`:2635`) — so the placard is genuinely *smaller than the kicker it is supposed to dominate*.
**Bonus**: `docs/design/overlay-redesign/SPEC-flight-deck.md:158` requires "12px / mono / 800 / 0.12em" **and marks it ✅ complete** — a **stale audit checkmark**. The SPEC asserts conformance the code does not have. Worth a ticket of its own: the SPEC's ✅ markers cannot be trusted as a conformance record.

## CONFIRMED with sharper evidence — F1: Halo diff markers
The verifier found the decisive proof I missed. The fixture's diff content is **markdown bullets that literally begin with `-`** (`AppearancePreviewFixtures.swift:434-448`). So the `−` visible in the Halo capture is *content*, not UI. Proof: `shots/app/poured-diffApprovalCard.png` renders a **double dash** (`3 − − Run swift build...`) — the first is Poured's real UI marker, the second is the literal bullet. Halo shows only one dash. The mockup's markers appear on content that does *not* start with a dash, confirming they are real UI elements Halo lacks.

## CONFIRMED — F9 sanctioned-exception check
`FlightDeckTypography`'s doc-commented "one intentional exception" to the 10pt floor (`FlightDeckTheme.swift:23-25`) is the **closed-grid `+N` overflow indicator**, NOT the usage `%`. So the 9pt `%` at `FlightDeckUsageSummary.swift:161` is an unsanctioned floor violation, not a documented exception.
