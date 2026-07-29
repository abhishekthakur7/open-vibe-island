# Pixel-level visual-fidelity review — overlay themes vs approved mockups

**Scope**: Poured Island 2.0, Flight Deck 2.0, Halo — shipped app vs the approved high-fidelity mockup boards.
**Nature**: visual/design QA only. Content/state conformance was settled by the prior review and deliberately not re-litigated.
**Discipline**: every finding was put through an adversarial verifier instructed to default to REFUTED. Findings are labelled CONFIRMED / RESCOPED. Nothing below is asserted from a single unmeasured impression.

Methodology, capture pipeline and coverage caveats: **`shots/REPORT-methodology.md`**
Appendix A (type-scale audit): **`shots/audit-type-scale.md`** · Appendix B (component audit): **`shots/audit-components.md`**
Raw per-theme critiques: **`shots/critique-{poured,flightdeck,halo}.md`** · Evidence pairs: **`shots/pairs/`**

---

# Answering the two headline complaints

## "Fonts are not consistent sizes"
**Substantiated.** The root cause is not that designers picked wrong sizes — it is that **large parts of the UI never route through the type scale at all.**

- **Flight Deck's `roleFamilies` pins 9 of ~40+ rendered text styles** (`FlightDeckTheme.swift:78-101`) while claiming in its own doc-comment to be the "single source of truth". Everything else is an inline `.system(size:)` literal invisible to tests.
- The single `count` role renders in **four different weight/design combinations at the same 11pt** — bold+sans, bold+mono, medium+sans, semibold+mono (`FlightDeckClosedPill.swift:536,601,633,638`).
- **Poured's hero-frame button labels hardcode `13/semibold`** with no role in `roleTable` at all (`PouredSessionRow.swift:1872`, `:1721`); measured cap-height 9.5pt, ~13% larger than the 11.5pt `jumpChip` role beside it.
- **The purpose-built `monoChip` role has zero call sites**, while `sideBadge` renders monospaced in 4/4 frames against SPEC §2's explicit "drop mono" (`PouredSessionRow.swift:1181-1188`).
- **Flight Deck's usage `%` renders at 9pt**, below the pinned 10pt floor, and is in no test list (`FlightDeckUsageSummary.swift:161`).
- **The shared question card ignores every theme's scale**, hardcoding 12.2/10.5/11.8pt while all three themes define `questionText`/`optionLabel`/`optionDesc`/`optionNumber` roles that go unused.

## "Components are not consistent"
**Substantiated, and it has one dominant cause**: shared views are dropped into three different visual languages unstyled, and where themes *did* fork a component they forked its metrics too.

- **`StructuredQuestionPromptView` is byte-identical in all three themes** — called with zero style parameters; Halo's and Flight Deck's own comments say *"Not restyled" / "never modified"*.
- **Three forked diff implementations**: gutter width 10 / 26 / 22, font 10 / 11.5 / 11.5, marker present / inline / **absent**.
- **Flight Deck nests a `RoundedRectangle(r7)` inside a `chamfer:5` well** in its hero frame, where chamfer *is* the geometry signature.
- **Poured disagrees with itself about what "a button" is**: four different radius/padding/border treatments.
- **Approve/Deny order is reversed in Flight Deck** vs both siblings and vs its own board.

---

# Ranked findings

## 1 — The shared question card is unthemed in all three themes · MAJOR · CONFIRMED
One fix surface, not three. `StructuredQuestionPromptView` receives only `prompt/lang/keyboardCoordinator/onAnswer` (`PouredSessionRow.swift:872-877`, `FlightDeckSessionRow.swift:2250-2255`, `HaloSessionRow.swift:1997-2002`). Interior hardcodes digit 10.5/semibold/mono (`IslandPanelView.swift:2417`), option label 12.2/medium (`:2431`), desc 10.5 (`:2436`), submit 11.8/semibold in `RoundedRectangle(r10)` (`:2953-2985`).

Measured consequences: Halo's primary CTA is **full-width flat grey** (22,22,22 / text 120,120,120, R=G=B) where the mockup has a compact **amber-gradient pill** (255,188,110). Every option shows a **persistent hollow radio circle**; the mockup shows a control only on the selected row. Poured's `questionText` and `optionLabel` both measure **9pt cap-height** — 0pt hierarchy where spec calls for 1.5pt. On Flight Deck a rounded Submit pill sits three rows below its own chamfered MASTER CAUTION header.

**Also shared and also missing: question pagination.** `StructuredQuestionPromptView` has **no pagination state whatsoever** — a `ForEach` stacks every question in one `VStack`/`ScrollView`. Both questions and all 7 options are simultaneously visible under one Submit button, where the mockup shows one question with "Submit & next".

Evidence: `shots/pairs/halo-F-question.png`, `shots/pairs/poured-F-question.png`
**Ticket**: `feat: theme the shared question-prompt interior + add pagination` → `IslandPanelView.swift:2290-2481`

## 2 — Flight Deck's hero permission frame does not read as an EVENT · MAJOR · CONFIRMED
BRIEF §7's top-priority bar, missed four ways:

| Sub-finding | Measured | file:line |
|---|---|---|
| **Zero glow bleed** on the hero card | flat bg through x=63, hard jump to border at x=64 — **0px transition**, fully opaque alpha (not a masking artifact). The closed-pill bloom shows a real **~17.5pt** alpha gradient and even the in-strip lamp shows ~4px — so `FlightDeckPhosphorGlow` works elsewhere but hard-cuts here, despite `FlightDeckCautionGlow` specifying `radius:9, bleed:2` | `FlightDeckSessionRow.swift:3019-3065` |
| **Card fill ~3× too light**, collapsing beacon contrast | app **#682E27** (104,46,39) vs mockup **#231718** (35,23,24); beacon/card luminance **1.29× vs 2.58×** | `FlightDeckSurfaces`, `:2757` |
| **MASTER placard smaller than the kicker it should dominate** | code 10.5pt/.bold vs kicker 11pt/.semibold; SPEC requires 12px/800/0.12em; measured cap ratio 0.83 | `:2626-2627` |
| **Model and Branch completely unreachable** — including via VoiceOver | exhaustive grep: never referenced anywhere in `FlightDeckActionableRowContent`, incl. the accessibility label | ~2600-2660 |

> **RESCOPED**: the original claim that the whole identity block is missing is **REFUTED** — the agent name *is* rendered, relocated to the row header above the card, which is a defensible layout choice. Only **Model and Branch** are genuinely absent.

> **Bonus defect**: `SPEC-flight-deck.md:158` specifies 12px/800/0.12em **and marks it ✅ complete** while the code ships 10.5/700 — a stale checkmark asserting false conformance. The SPEC's ✅ markers are not a trustworthy conformance record.

Evidence: `shots/pairs/flightDeck-E1-master.png`

## 3 — Halo's closed-pill glyphs are achromatic; the A3 attention shape is unreachable · MAJOR · CONFIRMED
Not an animation artifact — a structural gap, confirmed by code shape.

`HaloTheme` **never overrides the `closedGlyphTint(...)` protocol hook** (Poured does), so the glyph falls back to achromatic `tokens.colors.paper`. Sampled RGB(255,255,255) running, RGB(143,141,141) attention — zero saturation where the mockup shows a cyan→blue gradient (59,206,255 → 105,124,255). **Halo's own correct cyan/gold/amber logic in `HaloClosedPill.swift` is dead code in the normal render path.**

Worse: `UnifiedBars.Mode` has **no permission case**, so Halo's A3 "ringed dot" shape is unreachable — the loudest ambient state renders as the same neutral bars as idle.

This matters more than its size suggests: the pill is where the product lives 95% of the time, and the glyph is the thing users glance at first. "Readable across the room" fails when the loudest state is grey.

**Fix belongs in `HaloTheme.swift`** (add the `closedGlyphTint` override), not `HaloClosedPill.swift`.

> Related, **REFUTED as a Poured defect**: Poured's two-bar attention glyph geometrically matches `UnifiedBars(mode:.waiting)` exactly (heights [10,0,10]) — the capture is legitimately showing **A4 question**, not A3 permission. `PouredPillAmbientState.resolve` is a pure function of a hardcoded fixture phase, so "mid-morph capture" is also refuted. Poured's A3 ringed dot is fine.

## 4 — Halo's permission diff conveys added/removed by COLOUR ALONE · MAJOR · CONFIRMED
`HaloHeroDiff.diffRow` renders exactly two children — gutter number and line text. No marker is computed anywhere in the type (`HaloSessionRow.swift:2182-2198`).

Decisive proof: the fixture's diff content is **markdown bullets that literally begin with `-`** (`AppearancePreviewFixtures.swift:434-448`), so the dash visible in Halo's capture is *content*. `shots/app/poured-diffApprovalCard.png` renders a **double dash** (`3 − − Run swift build…`) — Poured's real UI marker plus the same bullet. **Halo shows one.** The mockup's markers appear on content not starting with a dash.

Halo is the only theme that gets this wrong (shared view has a marker column at `IslandPanelView.swift:134-136`; Poured concatenates at `PouredSessionRow.swift:2044,2057-2063`). Violates BRIEF §5 *"state never conveyed by color alone"* — on the hero frame, for red/green content.

Evidence: `shots/pairs/halo-E2-diff-markers.png`

## 5 — Approve/Deny order is REVERSED in Flight Deck · MAJOR · CONFIRMED
Poured and Halo: `allowOnce` → `deny` (Allow LEFT). **Flight Deck: `deny` → `allowOnce`** (`FlightDeckSessionRow.swift:2804-2811`, `2812-2819`). Verified in the render — no reversed `HStack` trick. Its own board shows `ALLOW ONCE · ALLOW ALWAYS · DENY`.

This is a real blocking round-trip; the hook waits on the answer. Theme-switching users carry muscle memory into the wrong button. BRIEF §6 treats row verbs as a shared contract.

## 6 — Poured's session list buries the list under expanded rows · MAJOR · CONFIRMED (cause RESCOPED)
Measured: expanded row title-to-title **251pt**, collapsed **49pt**, mockup uniform **86–98pt** regardless of state. Only **2 of 9** sessions fit before cutoff vs the mockup's **6 rows across 3 sections**.

> **RESCOPED cause**: not the notification surface, and not "every row expands". The gate is `showsDetail` (`PouredSessionRow.swift:116`): `!isStaleCompleted && (rawPresence != .inactive || isActionable)` — an **overly broad recency/presence trigger** that expands merely-running and recently-completed rows the mockup keeps compact.

The reviewer's "space spent, not invested" diagnosis, inverted: over-invested per row, under-invested in overall visibility.
Evidence: `shots/pairs/poured-C-rowheight.png`

## 7 — Notch header silently DROPS an entire usage provider · MAJOR · CONFIRMED
The fixture supplies **two** providers (Claude + Codex, `AppModel.swift:1234-1238`). The top-bar `.ax.json` proves Codex is in the data (`"Codex 7d 92% 18h 59m"`) — yet **Codex is absent from every notch capture**. Cause: `rightUsageWidth < minimumRightUsageLaneWidth` falls back to dropping content rather than rebalancing (`HaloHeaderControls.swift:196-198`).

Compounding: `splitUsageProviders(_:)` splits at **provider** granularity while the mockup splits per **window**, so Claude's 5H/7D can never balance across the cutout. **Triplicated verbatim** across all three themes.

Only observable in notch mode — invisible to the default top-bar captures. Evidence: `shots/pairs/halo-C-notch-header.png`

## 8 — Flight Deck usage gauges overflow the header band · MAJOR · CONFIRMED (banner-independent)
`FlightDeckUsageSummary` is an `HStack` of per-provider chips, each an internal **`VStack` of window gauges** (`:32-43, 60-65`). A 2-window chip is taller than the reserved band, overflowing **upward** (cut at the panel's physical y=0 edge) and **downward** (in `shots/notch/flightDeck-usageMeters.png` the gauge text overlaps the mute/settings/quit buttons, garbling "SE TOP" over the icons — entirely banner-free proof). `flightDeck-sessionList.png` (no usage windows) renders clean, isolating the trigger.

## 9 — Flight Deck's §C annunciator strip is ~2.4× too small · MAJOR · CONFIRMED
Tile measures **21.5pt** vs the mockup's **51–52pt**. The mockup's tile has a full-height coloured accent bar and a large count/caption hierarchy; the app renders a single-row pill chip with a 6×6pt lamp. The cockpit's defining instrument-panel moment reads as a thin status bar.
> Note: `FlightDeckSessionListScaffold.swift:141`'s `.frame(height:40)` is the **outer strip container**, not the tile.

Evidence: `shots/pairs/flightDeck-C-annunciator.png`

## 10 — Flight Deck's E3 CTA reads as a decision, not wayfinding · MAJOR · CONFIRMED (mechanism RESCOPED)
Width **94–95%** of card vs mockup's **~30%**. Sampled interior (135,63,52) warm red vs mockup (32,44,56) neutral blue-grey.
> **RESCOPED mechanism**: the code correctly uses `kind:.ghost` with neutral tokens — but a translucent ghost button composited directly on the alarm-red hero background **renders red regardless**. The defect is structural (the mockup extracts the CTA into its own neutral sub-panel; the app leaves it inside the alarm field), not a hardcoded-colour bug.

## 11 — Poured's `sideBadge` is monospaced in 4/4 frames · MAJOR
`.system(size:10.5, weight:.medium, design:.monospaced)` at `PouredSessionRow.swift:1181-1188` and `:1213-1218`, bypassing `PouredType` entirely, against SPEC §2's explicit "drop mono". `monoChip` — the role built for this — has **zero call sites** codebase-wide. `SPEC-poured-island.md:38-40` independently documents the drift. Pervasiveness is the finding: it's the one chip in every frame that doesn't match its neighbours.

## 12 — Three forked diff implementations · MAJOR
Gutter **10 / 26 / 22**; font **10 / 11.5 / 11.5**; marker **column / inline / absent**.

## 13 — Flight Deck's completion card genuinely lacks Transcript · MAJOR · CONFIRMED
Unlike Halo and Poured (see "Corrected/withdrawn" below), Flight Deck has **no frame-scope excuse**: its own board `flightDeck-BOARD-H-9.png` depicts the *same* notification-card chrome (identical "SHOW ALL N" affordance) with Jump/Transcript/Reply/Dismiss present. Grep of `FlightDeckActionableRowContent`/`completionBody` shows **zero references to Transcript** — it exists only in the unrelated non-actionable path. Structurally absent, not fixture-starved.

## 14 — Flight Deck nests a rounded shared view in a chamfered well · MAJOR
`FlightDeckChamferedRectangle(chamfer:5)` wrapping `PermissionDiffPreview`'s `RoundedRectangle(cornerRadius:7)` — two corner primitives touching in the loudest frame.

## 15 — Flight Deck's usage gauge uses raw SwiftUI system colours · MAJOR
Sampled **#E39244** vs the FD caution token **#E6AA42** — ΔG = −24. `usageColor(for:)` returns `.red/.orange/.green` instead of the status tokens (`FlightDeckUsageSummary.swift:193-202`).

## 16 — Poured's button family disagrees with itself · MAJOR
Jump r10 pad14/8 bordered+glowed · Allow/Deny r11 pad14/8 unbordered · Ghost r11 pad **12**/8 · Codex CTA r11 pad14/**9**.

## 17 — Flight Deck's `count` role in four weight/design combos · MAJOR · RESCOPED
Substance exact, **file corrected**: `FlightDeckClosedPill.swift:536,601,633,638` (not `FlightDeckSessionRow.swift`).

## 18 — Flight Deck's usage `%` at 9pt, below the pinned floor · MINOR (untested)
`countSize - 2` = 9pt vs `floor = 10`. Not in `readableRoleSizes`. The doc-commented "one intentional exception" is the `+N` overflow chip, **not** this.

## 19 — Halo's `nestHeader` caption at two weights · MINOR · RESCOPED
Real defect is exactly `HaloSessionRow.swift:622` (`.bold`) vs `:1102` (`.semibold`) — both uppercase small-caps captions with `*0.09` tracking. **Do not cite** `:625`, `:720` (numeric readouts, not captions) or `:2019` (separately-specified `.q-tag` role).

## 20 — Halo completion grid omits Model · MINOR-MEDIUM · CONFIRMED
`displayModelName` unions claude/openCode/cursor metadata only; `CodexSessionMetadata` has no `model` field, and the fixture is a codex session — so the cell is structurally always `nil`. Correct behaviour for codex, but codex is the chosen fixture.

---

# Corrected or withdrawn — findings that did NOT survive
Recorded so nothing here is over-claimed.

| Claim | Verdict | Why |
|---|---|---|
| **Completion card missing Dismiss** (all 3 themes) | **NOT A BUG** | `notificationRowActions` (`IslandPanelView.swift:937-945`) deliberately omits `dismiss:` with an explicit comment — the notification card isn't dismissible. Row wiring is correct; it's handed `nil` on this surface. |
| **Completion card missing Reply** (all 3) | **NOT A BUG** | Gated on `model.completionReplyEnabled`, default `false` (`AppModel.swift:298,758`), matching BRIEF §6's "narrow support". A feature flag, not a rendering gap. |
| **Completion card missing Transcript** (Halo, Poured) | **FIXTURE GAP** | No fixture sets `transcriptPath`. Untested code, not an agent-kind exclusion. (Flight Deck is different — see finding 13.) |
| **Halo's Failed outcome uses a different template / grey dot** | **FIXTURE BUG, not a template bug** | Both outcomes share one code path. `completedFailed.updatedAt` is 9 min old, exceeding Halo's 5-min stale threshold → flips to `presence:.inactive` → routes through the *idle* template. Fix belongs in `AppearancePreviewFixtures`, not the badge/dot code. |
| **Poured's A3 attention glyph is malformed** | **REFUTED** | The two-bar shape matches `UnifiedBars(mode:.waiting)` exactly — the capture legitimately shows **A4 question**, not A3 permission. Poured's ringed dot is fine. |
| **Flight Deck's hero header drops the whole identity block** | **REFUTED in part** | Agent name *is* rendered, relocated above the card. Only Model and Branch are absent. |
| **Halo's session list is missing section headers** | **USER SETTING** | `appearance.island.v8.notch.sessionGroup = none`. |
| **Attention pills have a huge banded glow** | **REFUTED by measurement** | Lateral bleed measured within spec for all three (Poured 5.0pt, FD 1.5pt, Halo 9.5pt). The drama was an artifact of the harness capturing against pure black vs the mockup's grey desktop. |
| **Halo's row edge-rail is missing** | **REFUTED** | Present at 2.0pt, correct cyan→violet gradient, correctly gated to live/actionable rows. |
| **Poured's question header is 4 lines / ~45pt** | **RESCOPED** | Measured on the wrong frame — that figure is `multiQuestionCard`'s. The single-question card correctly collapses a redundant title. The missing AUTH chip is real; the magnitude was mis-sourced. |

---

# Review-methodology defect worth fixing
`IslandDebugScenario.swift:108-300` renders only **two** surfaces: the compact **notification card** (all approval/question/completion scenarios) and the **plain session list** (`sessionList`, `subagentsCard`, `usageMeters`). Consequently:
- **§D row detail and §G's engine cluster never render** — `subagentsCard` has no `actionableSessionID`, so the row stays collapsed.
- **§I's 52pt meter card never renders** — `usageMeters` only injects fixtures into the header lane.
- **§B hover-peek and §K motion** are not drivable from stills at all.

These frames **cannot currently be visually regression-tested.**
**Ticket**: `test: add harness scenarios driving the expanded row (§D, §G) and the full usage-meter card (§I)`
**Ticket**: `fix: AppearancePreviewFixtures.completedFailed.updatedAt exceeds the stale threshold, masking the failed-outcome template`

# Coverage caveats
- All app captures are **top-bar** except the forced-notch set in `shots/notch/` (5 scenarios × 3 themes). Notch/top-bar metric differences are SPEC-sanctioned and were not filed.
- **Motion (dimension 5) was never asserted from stills** — graded "verify live" throughout. The named motion identities were verified in code only.
- Hover, focus and pressed states were not exercised.
- The install-hint banner is a harness artifact; it clips `poured-emptyState`, `poured-completedFailed`, `flightDeck-emptyState` and — newly observed — **`halo-emptyState`**.
- The `multiQuestionCard` colliding-UUID fixture bug was excluded from judgement.
