# Poured Island parity — recorded product/design-owner rulings

Version 5 — 2026-08-03 (R12 appended at the Slice 5 correction round 3; R1–R11
and the theme-retirement ruling unchanged from version 4).
Recorded verbatim by the root orchestrator from the
owner's written instructions (session `75ecb072`, repo owner). This document is
the source of record for these rulings until they are formally registered in
`Validation/PouredParity/principals-v1.json` / `conflict-dispositions-v1.json`
during Gate 0 work; it does not by itself approve any gate.

## R1 — Done visibility and display cap (PI-C-001, PI-C-002, PI-C-007)

> "done stays visible just we will show max 6 on screen, rest can be behind
> 'View All' button"

- Completed sessions stay in the **Done** group; they do not age out to an idle
  roll-up. The Poured list's effective completed-stale window is `never`
  (theme-local; the shared preference and other themes are untouched).
- The list renders at most **6 rows** on screen; when more exist, the remainder
  sits behind a **"Show all N sessions" / "Collapse list"** affordance (the
  existing `island.showAll` / `island.collapseList` strings).
- This resolves the board's §C self-inconsistency (Done rows 12m/22m old with a
  "0 idle" footer): the board is correct — Done does not stale out, and the
  frame's 6 rows are the cap.

## R2 — Workspace identity fallback (PI-C-003)

> "let it be '/' because we will never run in root"

- The bare-`/` case is ruled a non-case. The merged guards stay (they are
  no-ops for every real path and also fixed an empty-cwd discovery bug), but
  all recorded PI-C-003 follow-ups (residual secondary-surface producers,
  raw-title fallback hardening) are closed as out of scope by owner ruling.
- **Note**: the shipped behaviour substitutes `Workspace` rather than rendering
  `/`. The ruling is read as *"spend no more work here"*, not as a request to
  revert to a literal `/` — pending confirmation.

## R3 — Idle disclosure affordance (PI-C-002)

> "correct"

- The footer roll-up acting as a disclosure toggle is ratified. Under R1 the
  idle bucket is always empty ("0 idle", matching the board frame), so the
  disclosure is **unreachable under R1** — retained for a future threshold
  ruling rather than merely dormant.

## R4 — PI-A-001 slice alignment

> "fix the doc for correct alignment"

- The ledger's `slice` tag for PI-A-001 is corrected from 1 to 3, aligning with
  the continuation prompt's canonical order (collapsed narrative work).
- **Interpretation**: applied to the ledger `slice` field only; re-confirm if
  the owner meant another doc.

## R5 — Reference conflicts PI-REF-001 / PI-REF-002 / PI-REF-003, and the
## standing rule

> "mockup is the golden rule always. if there're any contradictions, always
> check with user"

- The rendered mockup (`01-poured-island.html` as rendered, including its CSS
  animations) is authoritative over its prose wherever the two disagree.
  Mapped to the disposition vocabulary this selects `loop` (PI-REF-001) and
  `css-exemplar-only` (PI-REF-002, PI-REF-003), to be formally registered with
  provenance when motion-slice work begins.
- Standing process rule: any newly discovered contradiction inside the
  reference is escalated to the owner; agents never resolve one themselves.

## R6 — Slice 3 candidate style forks (N-1, N-2, N-3, N-5, N-8, N-9, N-10)

> "mock design is the golden rule, follow that for styles and visual look."

Recorded 2026-08-01 (version 2 of this document). Applies R5's standing rule to
the style forks flagged in `poured-candidate-conflicts-slice3.md`: wherever the
reference's **rendered** output and its **prose/caption/dead-CSS** disagree
about style or visual look, the rendered output wins.

Resolved by this ruling, with the applications recorded per item in that file:

- **N-1** — `attnpulse` / `settle` / A4's inline glow really do drop
  `--hairline-inset`. The **closed** surface suppresses its inner contour
  hairline while it casts the attention or settle bloom; quiet and working keep
  it, and the opened panel and the hover peek keep it always.
- **N-2** — the full-size rendered surfaces (pill `r19 = h/2`, panel `--r:26`)
  are the morph's radius authority; the native endpoints already conform and the
  caption prose is no longer load-bearing. No code change.
- **N-3** — the peek renders at `transform:scale(1.0)`, so the model-driven peek
  no longer lifts the collapsed island. The bare-pointer hover keeps `1.03`
  (the board renders no bare-hover frame to contradict it).
- **N-5** — the "glyph travels" claim has no rendered referent, so it overrides
  nothing; the shipped glyph-travel is kept as non-contradicting. No code change.
- **N-8** — the rendered grid draws no distinct idle treatment (`i.idle` falls
  through to `--t3`); the native A2′ grid was confirmed to match (`paper@0.5`).
  No code change.
- **N-9** — floor-at-pill stays as an interim; honouring `404` absolutely would
  make the silhouette narrow on dwell, contradicting the frame it comes from. A
  new parity gap is recorded instead: native pill **468pt** vs board **352px**.
- **N-10** — the pill and the peek render the concave top fillet flares,
  reference-style (out-of-flow 12pt concave corner pieces, `--glass-fillet`
  tone), with no change to layout width.

**Still open** (not style questions, unaffected by this ruling): **N-4**
(`settled` has no rendered referent — a motion-measurement definition), **N-6**
(`settle` names two mechanisms), **N-7** (`--aggregate` / `--attn-hot` are
tokenised but never drawn).

## R7 — N-7: the collapsed pill with more than one session waiting

> "For N7, if multiple are waiting, loop through them one at a time. may be
> wait 3-4 seconds for 1 then move to 2nd one and then again back to 1
> depending upon how many are waiting."

Recorded 2026-08-01 (version 3 of this document). This is the owner's authority
for the **N > 1 waiting** collapsed state, which R6 explicitly left open (`--aggregate`
/ `--attn-hot` are tokenised in the reference but never drawn, so the board
answers nothing about how a multi-waiting pill should read).

Disposition: the collapsed pill does **not** aggregate the waiting sessions into
a single count-badge treatment. It **spotlights one waiting session at a time**
and rotates: hold a session for roughly 3–4 seconds, advance to the next waiting
session, and wrap back to the first — a cycle whose length is set by how many
sessions are currently waiting. Implementation lands in **Slice 5** (spotlight
rotation); this ruling is the acceptance authority for it.

## Theme retirement — Annual and Instrument

> "yes delete annual and instrument"

Recorded 2026-08-01 (version 3 of this document). The Annual and Instrument
themes are retired outright: theme structs, their per-theme views, their rows in
every token table, their registry entries, and their `theme.*` / `island.*`
localized strings in all three catalogs are deleted. The surviving roster is
**four** — Poured Island (default), Classic, Flight Deck, Halo.

Migration: a persisted `appearance.island.v8.theme` of `"annual"` or
`"instrument"` is simply an unknown id, so `ThemeRegistry.theme(id:)` resolves it
to the default (Poured Island) and `AppModel` normalizes the stored value on
load — no versioned migration step, no crash, no unstyled overlay.

Applied in the commit that carries this ruling.

## R8 — Escape granularity (closes Slice 4 escalation item 10)

Recorded 2026-08-02 (version 4 of this document), obtained directly from the
owner at Slice 5 kickoff.

Two-stage: with a hero (permission / question / detail) open inside the expanded
list, the **first** Esc collapses the hero back to its compact row (list context
preserved); the **second** Esc closes the panel. This is a behaviour **change**
from the shipped behaviour, where Esc closed the whole panel from an open hero.

Applied in Slice 5 (`OverlayPanelController.escapeStage` +
`PouredHeroExpansion`). Poured-scoped: every other theme, and the notification
surface's auto-expanded single row, keep Esc's shipped close-the-panel meaning.

## R9 — Hero opening mechanism (closes Slice 4 escalation item 8)

Recorded 2026-08-02 (version 4 of this document).

In-place expansion is confirmed: the `Answer` chip / chevron grows the row into
the hero **inside the list**, with the surrounding rows visible. Slice 5 refines
the in-place hero's geometry and controls to match the board's D / E / F hero
cards; there is no dedicated replacing hero panel.

## R10 — Hero header narration (closes Slice 4 escalation item 9)

Recorded 2026-08-02 (version 4 of this document).

Ask-first is confirmed: the open hero's header line reads **the ask itself**
("Wants to run …" in amber for a permission; the question text for a question),
not generic activity narration.

## R11 — Permission verb per surface (closes Slice 4 escalation X2)

Recorded 2026-08-02 (version 4 of this document).

Per-surface, as rendered: the compact §C row says **"Approve"**, the §E hero says
**"Allow once"**. Both stay exactly as the board renders each surface, which is
consistent with R5 — the rendered mockup is golden.

Slice-5 extension recorded for completeness, **not** ratified by the owner: §E4
renders a third spelling pair (`Allow` / `Always`). Each surface was implemented
with its own verbatim verb; the E4 pair remains an open escalation candidate
because E4 is not reproducible natively today.

Remaining Slice-4 escalation-queue items (X1, X3, X4, X5, wing distribution,
far-left header glyph, board control glyphs) were **not** ruled on and stay
pending.

## R12 — Rotation question-phase badge (closes the Slice 5 round-2 review split)

Recorded 2026-08-03 (version 5 of this document), ratified over the "always
total-N" alternative a round-2 reviewer argued for.

While the R7 spotlight rotation is running and the held item is a **question**,
the collapsed pill's right-slot badge is the board's A4-verbatim gold **`?`** —
not the aggregate waiting count. The **permission** hold keeps the amber count
badge exactly as board A3 draws it.

- The board's A3 and A4 differ in the badge as well as in the lead marker (amber
  `N` with a `0 0 14px` glow vs a glow-less gold `?`), and the per-item template
  is what R7 rotates; rendering the count through a question hold would mix A3's
  badge into A4's frame.
- The total waiting count stays reachable: the hover peek (§B) lists every
  waiting session, and the collapsed pill's VoiceOver summary states the
  aggregate ("N waiting for you") through both holds.

Applied in Slice 5 correction round 3 (`AppModel.pouredRotationRetaggedBadge` +
`PouredRightSlotView` / `PouredAttentionBadge`). Poured-scoped: every other
theme, the opened island and any single-waiting pill keep
`IslandRightSlotResolver`'s own aggregate answer.
