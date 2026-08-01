# Poured Island parity — recorded product/design-owner rulings

Version 1 — 2026-08-01. Recorded verbatim by the root orchestrator from the
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
