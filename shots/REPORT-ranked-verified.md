# Ranked findings — VERIFIED SET (survived adversarial verification pass 1)

Every finding below was independently re-derived by a verifier instructed to default to REFUTED.
Ranked by how much each cheapens the product against the approved mockups.

---

## 1. The shared question card is unthemed — identical in all three themes
**Severity: MAJOR · Verdict: CONFIRMED · The single biggest "this doesn't belong here" moment in the app.**

`StructuredQuestionPromptView` is called with only `prompt/lang/keyboardCoordinator/onAnswer` from all three themes — **zero style parameters**:
`PouredSessionRow.swift:872-877` · `FlightDeckSessionRow.swift:2250-2255` · `HaloSessionRow.swift:1997-2002`.
Halo's and Flight Deck's own code comments say **"Not restyled" / "never modified"**.

Its interior hardcodes values unrelated to any theme scale: digit 10.5/semibold/mono (`IslandPanelView.swift:2417`), option label 12.2/medium (`:2431`), description 10.5 (`:2436`), submit button 11.8/semibold in a `RoundedRectangle(r10)` (`IslandActionButtonStyle`, `:2953-2985`).

Meanwhile **every theme defines matching roles that go completely unused** — `questionText` 14.5/560, `optionLabel` 13/600, `optionDesc` 11.5/400, `optionNumber` 11/700 (`PouredTypography.swift:203-206`, `HaloTheme.swift:85-92,164-167`).

Visible consequences, measured:
- Poured's question header renders **4 stacked plain-text lines ≈45pt** where the mockup has **one ~24pt row** with an amber `.q-chip` capsule; `questionChip` (`PouredTypography.swift:207`) has zero call sites.
- Poured's `questionText` and `optionLabel` both measure an identical **9pt cap-height** — **0pt hierarchy** where spec calls for a 1.5pt step.
- Halo's primary CTA is a **full-width flat grey** button (fill 22,22,22 / text 120,120,120, R=G=B) where the mockup has a compact **amber-gradient "Next ↵" pill** (peak 255,188,110).
- Every option shows a **persistent hollow radio circle** at rest; the mockup shows a control only on the selected row (state signalled by a tick appearing, never by a permanent shape).
- On Flight Deck a smooth rounded "Submit Answers" pill sits three rows below its own chamfered MASTER CAUTION header — **breaking the chamfer signature outright**.

**Evidence**: `shots/pairs/halo-F-question.png`, `shots/pairs/poured-F-question.png`, and pixel-identical row geometry across `{poured,halo,flightDeck}-questionCard.png`.
**Ticket**: `feat: theme the shared question-prompt interior (option rows, digit box, submit button) via an injection point, and consume each theme's existing option/question roles` → `Sources/OpenIslandApp/Views/IslandPanelView.swift:2290-2481`
**This is one fix surface, not three.**

---

## 2. Flight Deck's hero permission frame does not read as an EVENT
**Severity: MAJOR · Verdict: CONFIRMED (4 independent sub-findings)**

BRIEF §7's top-priority bar is *"a hero permission frame that feels like an EVENT (amber light inside glass; MASTER WARNING annunciator) — not a restyled form."* Flight Deck misses it four ways:

| Sub-finding | Measured | file:line |
|---|---|---|
| **Zero glow bleed on the hero card** — the theme's signature | card edge is a **hard 1px cut**: y=400 x=61 bg(8,9,10) → x=64 border(94,42,36), **0px transition**. Contrast: the closed-pill grid lamp *does* bleed ~3px, so glow works elsewhere | `FlightDeckSessionRow.swift:3019-3065` (`FlightDeckCautionGlow`) |
| **Card fill ~3× too light**, killing the beacon's pop | app **#682E27** (104,46,39) vs mockup **#231718** (35,23,24); beacon-to-card brightness ratio **1.3× vs the mockup's 3.5×** | `FlightDeckSurfaces` alarm tint, `:2757` |
| **MASTER placard undersized** — smaller than the kicker it should dominate | code `10.5pt/.bold`; kicker beside it is `11pt/.semibold`. SPEC requires **12px/mono/800/0.12em**. Measured cap-height ratio **0.83** | `FlightDeckSessionRow.swift:2626-2627` |
| **Session identity block absent** (agent/model/branch) in **5/5** sampled captures | occupies **~35%** of the mockup header width, **0%** of the app's | `FlightDeckSessionRow.swift` ~2600-2660 |

**Bonus defect found during verification**: `docs/design/overlay-redesign/SPEC-flight-deck.md:158` specifies 12px/800/0.12em **and marks it ✅ complete** — a **stale audit checkmark asserting conformance the code does not have.** The SPEC's ✅ markers cannot be trusted as a conformance record.

**Evidence**: `shots/pairs/flightDeck-E1-master.png`
**Tickets**: `fix: attach FlightDeckCautionGlow bleed to the MASTER hero card` · `fix: darken FD alarm card fill to #231718 so the beacon reads as lit` · `fix: pin FD MASTER placard to 12/800/0.12em` · `fix: restore session identity block inside the FD annunciator header` · `chore: audit SPEC ✅ markers — at least one asserts false conformance`

---

## 3. Halo's permission diff conveys added/removed by COLOUR ALONE
**Severity: MAJOR (accessibility) · Verdict: CONFIRMED with decisive evidence**

`HaloHeroDiff.diffRow` renders exactly two children — `Text("\(row.gutter)")` and `Text(row.line.text)`. **No marker is computed anywhere in the type** (`HaloSessionRow.swift:2182-2198`).

The verifier found the proof I had missed: the fixture's diff content is **markdown bullets that literally begin with `-`** (`AppearancePreviewFixtures.swift:434-448`), so the dash visible in Halo's capture is *content*, not UI. Decisive comparison — `shots/app/poured-diffApprovalCard.png` renders a **double dash** (`3 − − Run swift build…`): the first is Poured's real UI marker, the second the literal bullet. **Halo shows only one.** The mockup's `+`/`−` appear on content that does not start with a dash, confirming they are real UI elements Halo lacks.

Halo is the **only** theme that gets this wrong: the shared `PermissionDiffPreview` has a dedicated marker column (`IslandPanelView.swift:134-136`) and Poured concatenates `markerPrefix` (`PouredSessionRow.swift:2044, 2057-2063`).

Violates BRIEF §5: *"state never conveyed by color alone (pair with icon/shape/label)"* — on the theme's hero frame, for red/green content, i.e. the worst possible colour pair for colour-vision deficiency.

**Evidence**: `shots/pairs/halo-E2-diff-markers.png`
**Ticket**: `fix: Halo permission diff must render +/− markers, not colour alone` → `HaloSessionRow.swift:2186`

---

## 4. Approve/Deny button order is REVERSED in Flight Deck
**Severity: MAJOR (consistency + safety) · Verdict: CONFIRMED, including rendered order**

- Poured: `allowOnce` → `deny` = **Allow LEFT / Deny RIGHT** (`PouredSessionRow.swift:1613-1621`, `1625-1633`)
- Halo: `allowOnce` → `deny` = **Allow LEFT / Deny RIGHT** (`HaloSessionRow.swift:1867-1873`, `1874-1880`)
- **Flight Deck: `deny` → `allowOnce` = Deny LEFT / Allow RIGHT** (`FlightDeckSessionRow.swift:2804-2811`, `2812-2819`)

Verified in the render too (no reversed `HStack` or alignment trick): `shots/app/flightDeck-approvalCard.png` shows DENY left, ALLOW right. Its own board `shots/mockup/flightDeck-E1.png` shows `ALLOW ONCE · ALLOW ALWAYS · DENY`.

This is a **real blocking round-trip** — the agent hook waits on the answer. A user who switches themes carries muscle memory to the wrong button. BRIEF §6 treats row verbs as a shared contract; button order should not be a theme variable.

**Ticket**: `fix: Flight Deck approval buttons must order Allow before Deny` → `FlightDeckSessionRow.swift:2804`

---

## 5. Notch header silently DROPS an entire usage provider
**Severity: MAJOR · Verdict: CONFIRMED — and worse than first described**

The fixture supplies **two** providers, Claude and Codex (`AppModel.swift:1234-1238`). The top-bar capture's `.ax.json` proves Codex is in the data (`"Codex 7d 92% 18h 59m"`) — yet **Codex is entirely absent from every notch capture**.

Cause: `rightUsageWidth < minimumRightUsageLaneWidth` falls back to dropping the right lane's content rather than rebalancing (`HaloHeaderControls.swift:196-198`). Compounding it, `splitUsageProviders(_:)` splits at **provider** granularity while the mockup splits per **window** (`UsageProviderPresentation.windows: [UsageWindowPresentation]`, `IslandUsageSummary.swift:8-11`) — so Claude's 5H and 7D can never be balanced across the cutout the way `shots/mockup/halo-x10.png` shows.

The function is **triplicated verbatim**: `HaloHeaderControls.swift:128-145` · `PouredHeaderControls.swift:124-141` · `FlightDeckHeaderControls.swift:120-136`.

Only observable in notch mode — the default top-bar captures hide it entirely. Caught only because notch capture was forced.

**Evidence**: `shots/pairs/halo-C-notch-header.png`, `shots/notch/{halo,poured}-usageMeters.png`
**Ticket**: `fix: notch header drops a usage provider under width pressure; split lanes per window and de-duplicate splitUsageProviders across the 3 themes`

---

## 6. Flight Deck usage gauges overflow the header band
**Severity: MAJOR · Verdict: CONFIRMED, banner-independent**

`FlightDeckUsageSummary` is an `HStack` of per-provider chips, each an internal **`VStack` of window gauges** (`FlightDeckUsageSummary.swift:32-43, 60-65`). A 2-window Claude chip is **taller than the header's reserved band**, so it overflows both directions.

- **Upward**: gauge content is cut at the panel's **physical y=0 top edge** — nothing to do with the known banner artifact.
- **Downward**: in `shots/notch/flightDeck-usageMeters.png` the gauge text **overlaps the header control buttons** (mute/settings/quit), producing garbled "SE TOP" over the icons. This capture is entirely banner-free proof.
- **Isolation**: `shots/app/flightDeck-sessionList.png` (no usage windows) renders a clean header — the trigger is usage-window count.

**Evidence**: `shots/pairs/flightDeck-I-gauge-overflow.png`
**Ticket**: `fix: Flight Deck usage tape-gauges overflow the opened-header band (clip + overlap)` → `FlightDeckUsageSummary.swift`, `FlightDeckHeaderControls.swift`

---

## 7. Poured's `sideBadge` renders monospaced in 4/4 frames, against SPEC
**Severity: MAJOR (this is the reviewer's "inconsistent fonts" complaint, most visible instance)**

"Ghostty" / "Codex.app" render in a clearly monospaced face — fixed advance width, distinctive mono glyph shapes — in **every frame checked** (approvalCard, codexApprovalCard, sessionList, subagentsCard). SPEC §2 says **drop mono for meta chips**. Meanwhile `monoChip`, the role built for exactly this, has **zero call sites**.

Pervasiveness is itself the finding: it is the one chip in every frame that does not match its neighbours.
`PouredSessionRow.swift:1181-1188` (sideBadge), `:1212-1218` (bypass chip); dead role at `PouredTypography.swift:183`.

**Ticket**: `fix: wire or delete PouredType.monoChip; convert sideBadge/bypass chip to sans per SPEC §2`

---

## 8. Three forked diff implementations with three different geometries
**Severity: MAJOR · Verdict: CONFIRMED exactly**

| | marker | gutter | font |
|---|---|---|---|
| Shared `PermissionDiffPreview` | separate column, w**10** | — | **10pt** |
| Poured `PouredPermissionDiff` | inline in text | **26** | **11.5pt** |
| Halo `HaloHeroDiff` | **absent** | **22** | **11.5pt** |

`IslandPanelView.swift:136,141` · `PouredSessionRow.swift:2041` + `PouredTypography.swift:198` · `HaloSessionRow.swift:2186` + `HaloTheme.swift:81`.
**Ticket**: `refactor: unify the three permission-diff implementations behind one metric set + marker contract`

---

## 9. Flight Deck nests a rounded shared view inside its chamfered well
**Severity: MAJOR · Verdict: CONFIRMED**

Outer well is `FlightDeckChamferedRectangle(chamfer: 5)` (`FlightDeckSessionRow.swift:2792-2797`) wrapping the unmodified `PermissionDiffPreview`, whose inner container is `RoundedRectangle(cornerRadius: 7)` (`IslandPanelView.swift:119-122`) — **two different corner primitives touching**, in the theme's loudest frame, where chamfer *is* the geometry signature. Visible in `shots/app/flightDeck-diffApprovalCard.png`.

**Ticket**: `fix: give FD a chamfer-native diff renderer (mirroring PouredPermissionDiff/HaloHeroDiff) or parameterise the shared view's shape`

---

## 10. Flight Deck's §C annunciator strip is ~2.5× too small
**Severity: MAJOR** — mockup renders ATTN/RUN/DONE/IDLE as four **55pt instrument tiles** with coloured left accent bars and a large count over a caption; the app renders a **22pt single-row pill strip**. The cockpit's defining instrument-panel moment reads as a thin status bar.
`FlightDeckSessionListScaffold.swift:141`. **Evidence**: `shots/pairs/flightDeck-C-annunciator.png`

---

## 11. Poured session-list rows are ~2.6–2.9× taller than the mockup
**Severity: MAJOR (pending cause confirmation in verify pass 2)** — mockup actionable rows measure **86–98pt**; app title-to-title measures **252pt**. Only **2 of 9** sessions fit before cutoff vs the mockup's **6 rows across 3 sections** in the same footprint. The reviewer's "space spent, not invested" diagnosis, inverted: over-invested per row, under-invested in overall visibility.
**Evidence**: `shots/pairs/poured-C-rowheight.png`

---

## 12. Flight Deck's usage gauge uses raw SwiftUI system colours, not its own tokens
**Severity: MAJOR · Verdict: CONFIRMED by pixel sample** — gauge fill sampled **#E39244** (227,146,68) vs the FD caution token **#E6AA42** (230,170,66): **ΔG = −24**, visibly more orange/red-shifted. `usageColor(for:)` returns `.red/.orange/.green` @0.95 instead of `statusWaitingForApproval`/`statusWaitingForAnswer`/`statusRunning`.
`FlightDeckUsageSummary.swift:193-202`

---

## 13. Flight Deck's usage `%` renders at 9pt, below the pinned floor
**Severity: MINOR→MAJOR (untested) · Verdict: CONFIRMED** — `countSize - 2` = 9pt (`FlightDeckUsageSummary.swift:161`) against `floor = 10` (`FlightDeckTheme.swift:30`). Measured cap-height ratio **0.81** vs its own numeral. Not in `readableRoleSizes`, so **no test catches it**. The doc-commented "one intentional exception" (`:23-25`) is the closed-grid `+N` overflow indicator, **not** this — so it is an unsanctioned violation.

---

## 14. Flight Deck's `count` role renders in four weight/design combinations
**Severity: MAJOR · Verdict: RESCOPED — substance right, file citation corrected to `FlightDeckClosedPill.swift`**

All at `FlightDeckTypography.countSize` (11pt), canonical role 11/semibold/mono (`FlightDeckTheme.swift:112`):
`:536` bold+**sans** · `:601` bold+mono · `:633` **medium**+**sans** · `:638` semibold+mono (canonical).
**Ticket**: `refactor: split FD countSize into named sub-roles instead of ad hoc weight+design per call site`

---

## 15. Flight Deck's E3 CTA paints a navigation action in decision-red
**Severity: MAJOR (colour discipline)** — "RESPOND IN TERMINAL" renders **full-width in the alarm-red palette**; the mockup uses a small (~27% width) **neutral blue-grey** wayfinding button in its own "APPROVE IN CODEX" sub-panel. Colour = state, and red is the deny/decision colour. `FlightDeckSessionRow.swift` ~2892-2910.

---

## 16. Poured's own button family disagrees with itself
**Severity: MAJOR** — one theme, four treatments of "a button": Jump r10 pad14/8 **bordered + glowed** (`:2325-2358`); Allow/Deny r11 pad14/8 unbordered (`:1885-1898`); Ghost r11 pad **12**/8 (`:2364-2399`); Codex CTA r11 pad14/**9** (`:1725-1737`). Hero-frame labels hardcode `13/semibold`, bypassing `roleTable` entirely (`:1872`, `:1721`) — measured cap-height 9.5pt, ~13% larger than the 11.5pt `jumpChip` role used elsewhere in the same row family.

---

## 17. Halo's `nestHeader` caption renders at two weights
**Severity: MINOR · Verdict: RESCOPED — narrower than claimed**
The real defect is exactly two call sites: `HaloSessionRow.swift:622` ("SUBAGENTS" caption, `.bold`) vs `:1102` (assistant-card label, `.semibold`) — both true small-caps captions above a card body, both uppercase with `*0.09` tracking.
**Do NOT cite** `:625`, `:720` (numeric progress readouts, not uppercased/tracked, appropriately lighter) or `:2019` (the separately-specified `.q-tag` chip role with its own spec at `:2010`). They merely reuse the size constant.

---

## Structural root cause behind several of the above
Flight Deck's `roleFamilies` doc-comment claims to be the "single source of truth" but pins only **9 of ~40+** rendered text styles (`FlightDeckTheme.swift:78-101`). That is what allowed findings 2, 13 and 14 to exist unnoticed.
**Ticket**: `test: extend FD roleFamilies/readableRoleSizes to every call site, or lint-fail any inline .system(size: outside FlightDeckTheme.swift`
