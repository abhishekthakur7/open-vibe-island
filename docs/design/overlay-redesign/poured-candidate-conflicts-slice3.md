# Poured Island parity — candidate reference conflicts found in Slice 3

Status: **PARTLY RULED.** Owner ruling **R6** (2026-08-01,
`poured-owner-rulings.md`) resolves every *style* fork here in the RENDERED
mockup's favour: N-1, N-2, N-3, N-5, N-8, N-9, N-10. **N-4, N-6 and N-7 stay
OPEN** — they are not style questions (a motion-measurement definition, a
mechanism/naming collision, and a missing-state question respectively).

Discovered by the Slice 3 reference mapper while mapping the collapsed pill,
the hover peek and the morph against
`docs/design/overlay-redesign/01-poured-island.html` (sha256
`eedf838c10a69450e320e339019cc45b776bd4c90a990af5873da5e0f6fc56e5`).

These candidates are:

- **not covered** by the registered reference conflicts `PI-REF-001`,
  `PI-REF-002`, `PI-REF-003`, nor by owner rulings R1–R5 in
  `poured-owner-rulings.md`;
- **not encoded anywhere** — they have no ledger item, no scenario, no
  conflict record and no disposition vocabulary in `Validation/PouredParity/`;
- **escalations under R5** ("mockup is the golden rule always; if there are any
  contradictions, always check with user"). No agent may resolve one — the
  style forks below were resolved by the **owner**, in **R6**.

Line numbers are 1-based into the reference HTML at the sha256 above.

## N-1 — attention/settle keyframes drop the contour hairline

`@keyframes attnpulse` (HTML:193-194) and `@keyframes settle` (HTML:198-200)
write `box-shadow` as `var(--shadow),var(--specular),<glow>` — omitting
`var(--hairline-inset)`, which `.glass` declares in its base rule
(HTML:134) and which `@keyframes lumen` deliberately preserves
(HTML:187-188). Consequence: for the whole duration of the A3 (permission),
A4 (question) and A5 (success) animations the body renders **without** the
0.5px contour hairline that the design law "light traces the contour" depends
on. Fork: is the hairline drop intentional under attention/settle, or a
keyframe authoring slip that the native implementation must not copy?

**RULED by R6 — rendered mockup wins.** The drop is authoritative. Applied:
while the **closed** surface's ambient state casts the attention (A3/A4) or
settle (A5) glow, the ONE-BODY background suppresses the material's inner
hairline; quiet (A1) and working (A2/A2′) keep it, exactly as `lumen` does.
Scoped to the closed surface — the opened panel and the hover peek keep the
hairline always, since the board's peek body carries plain class `glass`
(`:717`). Seam: `IslandTheme.closedSurfaceSuppressesInnerHairline` (default
`false`) → `PouredPillAmbientState.suppressesInnerHairline` →
`OpenedSurfaceBackground.suppressesInnerHairline`.

## N-2 — B′ filmstrip caption radii match no rendered element

The B′ caption (HTML:760-761) specifies "Top radius 0→26, bottom radius
pillHeight/2→26". No rendered element uses those endpoints:

- collapsed pill: r19 (HTML:147, `.pill.big` at HTML:156),
- filmstrip frames: r16 / r19 / r22 (HTML:742, 749, 755),
- §K live morph: r12 → r22 (HTML:497-499).

Fork: which radius endpoints are authoritative for the native morph — the
prose (0→26 / h/2→26), the filmstrip (16/19/22) or the §K animation (12→22)?

**RULED by R6 — rendered mockup wins; native endpoints already conform, no
code change.** The *full-size* rendered surfaces are the authority: the pill
is `border-radius:19px` = `pillHeight/2` on a 38px body (`:147`) with a flat
top, and the panel is `--r:26px` (`:55`, `.panel` `:215`). The shipped morph
interpolates exactly that — `topCornerRadius 0 → 26`, `bottomCornerRadius
closedHeight/2 → 26` (`IslandMetricsTokens.poured.openedTopRadius/
openedBottomRadius == 26`). The 16/19/22 filmstrip cells (`:742,749,755`) are
150px schematic miniatures, and §K's 12→22 is already ruled
`css-exemplar-only` (PI-REF-002/003), so neither is geometry authority. The
caption prose happens to state the same endpoints and is overridden only in
the sense that it is no longer load-bearing.

## N-3 — hover scale 1.03 is prose-only and unapplied

The §B note states "0.15s dwell, scale 1.03" (HTML:707) and a `.pill.hover-lift`
rule exists with `transform:scale(1.03)` (HTML:157), but the class is applied
to no element in the document, and the rendered peek body carries an inline
`transform:scale(1.0)` (HTML:717). Fork: does the peek lift by 1.03 (prose +
dead class) or stay at 1.0 (rendered truth)?

**RULED by R6 — rendered mockup wins.** The peek stays at `1.0`. Applied: the
`|| model.hoverPeekActive` term is gone from the collapsed surface's
`scaleEffect`, so a model-driven peek renders unlifted
(`IslandPanelView.closedSurfaceScale`). The transient pointer-only
`isHovering` path keeps the `closedHoverScale` token (`1.03`): the board
renders **no** bare-hover frame, so nothing rendered contradicts the prose
invariant there and it stands.

## N-4 — no reference animation has a settled terminal state

**STILL OPEN after R6 — not a style question.**

Every animation in the reference is `infinite`: HTML:163, 167, 181, 185, 191,
196, 495, 502, 512. `motion-authority-v1.json` requires a `settled` terminal
checkpoint (`required_checkpoints[-1] == "settled"`, `required_events ==
["trigger","settled"]`). Outside the `loop` ruling recorded for PI-REF-001,
that checkpoint therefore has no rendered referent anywhere in the reference.
Fork: how is `settled` to be measured for PI-REF-002 / PI-REF-003 exemplars
and for the non-conflict animations (breathe, wave, breathe-dot, rowin)?

## N-5 — "status glyph travels into the header" has no rendered instance

The §B note asserts the status glyph *travels* into the header rather than
crossfading (HTML:708-709). The rendered peek carries a `.dot` marker, not a
`.glyph` (HTML:720), and filmstrip frames 2 and 3 are empty bodies with no
status mark at all (HTML:749-750, 755-756). Fork: what exactly travels, from
where to where, and what is its identity at each end?

**RULED by R6 — no rendered authority, no code change.** Under "the rendered
mockup is golden" this prose claim has no rendered referent at all, so it
cannot override anything. The shipped glyph-travel
(`IslandPanelView.islandGlyphOverlay`, AB-243) is therefore kept as-is: it
contradicts no rendered frame, and removing it would be a change made on the
authority of a sentence R6 just demoted. Re-open only if a future board
renders the traveling glyph.

## N-6 — "settle" names two different mechanisms

**STILL OPEN after R6 — not a style question.**

A5 uses `.settle` / `@keyframes settle` — an outer box-shadow glow that goes
white → green → nothing (HTML:196-201). §K's "Success settle" demo uses
`.shimmer` / `@keyframes shim` — an inner translating linear-gradient sweep
(HTML:508-513). Two unrelated mechanisms share one name in the copy. Fork:
which one is the success lifecycle the native surface must reproduce (this is
adjacent to PI-REF-001 but is a *naming/mechanism* collision, not the
loop-vs-one-shot lifecycle question that ruling covers)?

## N-7 — `--aggregate` and `--attn-hot` are tokenised but never drawn

**STILL OPEN after R6 — not a style question.**

`--aggregate:#e7a762` (HTML:26) and `--attn-hot` (HTML:32) are declared in the
token block and referenced by no rule or element. Relatedly, no §A frame
renders the N>1-waiting collapsed roll-up (A3 shows a single "1" count).
Fork: is there an intended aggregate-attention collapsed state that the board
simply never drew, or are these dead tokens?

## N-8 (minor) — A2′ idle grid cell has no rule

`<i class="idle">` inside `.agrid` (HTML:606) has no matching `.agrid i.idle`
rule; `.agrid` only styles `i`, `i.on` and `i.wait` (HTML:178-181). The cell
therefore renders as the plain `i` default. Fork: is the idle grid cell meant
to be visually distinct from an empty cell?

**RULED by R6 — rendered mockup wins; native already matches, no code
change.** The rendered grid draws no distinct idle treatment: `i.idle` falls
through to `.agrid i { background: var(--t3) }` (`:179`), i.e. `--t3 =
rgba(242,245,251,.5)` (`:45`) — the same tone as an empty cell. **Confirmed:**
the native A2′ grid is identical — `PouredAgentsTileView`'s `.idle` case fills
`paper.opacity(PouredPillMotion.AgentsGrid.idleCellOpacity)` with
`idleCellOpacity == 0.5` on Poured's `paper`, and there is no separate
empty-cell case (the grid renders only the cells it is handed). Nothing
diverges.

## N-9 — the board's 404pt peek width is unreachable on the native pill

The §B peek body is drawn at `width:404px` (HTML:717), growing out of a
`.pill.big` measured at `352` (HTML:156). The native collapsed Poured pill is
**468pt** wide, and `PouredHoverPeek.resolvedWidth` floors the grown body at
the pill it grew from (`min(availableWidth, max(closedPillWidth, 404))`) so the
silhouette can never *narrow* on dwell. Consequence: 404 is never rendered —
the peek grows in height only, and the board's 352→404 horizontal growth
(a +15% widening that is a visible part of the "the shape begins to grow"
reading) has no native counterpart. Fork: honour `404` absolutely (which means
the peek is narrower than the pill it grows from, i.e. the silhouette shrinks
sideways as it grows down), or keep the floor-at-pill rule and treat the
native pill's 468pt width as the real delta to reconcile against the board's
352pt pill?

**RULED by R6 — second fork taken; floor-at-pill stays as an interim, and a
NEW parity gap is recorded.** "Rendered mockup is golden" cannot be honoured
by making the silhouette *narrow* on dwell: the same rendered board shows the
peek growing out of the pill as one continuous body, so honouring 404
absolutely against a 468pt pill would contradict the frame it comes from.
`PouredHoverPeek.resolvedWidth`'s floor is therefore **unchanged (interim)**,
and the real divergence is booked as its own gap:

> **NEW PARITY GAP (R6/N-9):** the native closed Poured pill measures **468pt**
> where the board's `.pill.big` is **352px** (`:156`). Until the pill's own
> width is reconciled to the board, the board's 352→404 peek widening has no
> native counterpart and the peek grows in height only. Closing this belongs to
> collapsed-pill width work, not to the peek.

## N-10 — the collapsed pill and the peek render flat tops, not concave fillets

Every `.pill` in the reference draws the concave notch-junction fillets as
explicit `.fillet.l` / `.fillet.r` spans, and the §B peek body draws them too
(HTML:712-736). Natively both take `topCornerRadius: 0`, and `NotchShape`
degenerates *both* top fillet curves to straight vertical lines at
`topCornerRadius == 0` — the curve's two control points collapse onto the edge
`x` (`Sources/OpenIslandApp/NotchShape.swift:65-72`) — so neither the shipped
pill nor the peek renders any fillet at all. This is **non-regressive**: the
peek merely matches the pill that has always looked this way, so it is not a
Slice 3 defect. Fork: give the pill and the peek a nonzero top radius so the
fillet curves actually engage (matching the board), or accept flat tops as the
deliberate native reading of a surface attached to the physical notch?

**RULED by R6 — rendered mockup wins.** The pill and the peek get the flares.
Applied **reference-style** rather than by raising `topCornerRadius` (which
would round the top edge itself, which the board does *not* do): two concave
quarter-round pieces are drawn adjacent to the top outer corners, mirroring
the reference's out-of-flow `.fillet.l` / `.fillet.r` spans — a 12pt square at
`left:-12 / right:-12`, filled `--glass-fillet rgba(20,25,36,.92)`, masked to
the square-minus-quarter-disc region centred on its own outer corner
(`:50,56,136-143`). New nullable material token
`IslandMaterialTokens.cornerFillet` (`nil` for every other theme, per the
Slice-2 precedent) + `IslandCornerFilletShape` /
`View.islandCornerFilletFlares`. Attached to the morph surface (faded out by
the morph interpolant, since past `topCornerRadius > 0` the panel's own
`NotchShape` shoulders occupy the same corner), to the Reduce-Motion closed
surface, and to `PouredHoverPeek` (`:718`). Drawn in an overlay and offset
outward, so **no layout width changes** and every `externalOuterWidth` golden
is untouched. The opened panel is untouched (see R-c).

**Reduce Transparency**: the flares **stay**, repainted in the flat RT body
tone (`surfaceInk`). The reference fills them from `--glass-fillet` — a
near-opaque body ink, not `--specular` / `--hairline-inset` — so they are
silhouette, not sheen; the light layers stand down under RT and these do not,
because dropping them would change the shape rather than the glass.

---

# Native residuals (not reference conflicts)

Flag-only records from the Slice 3 round-2 re-review. Unlike the `N-` items
above, these are **not** candidate-vs-reference conflicts and carry **no
resolution** — they are parked observations and decisions-of-record.

## R-a — closed label band and opened header controls read simultaneously (~270ms)

Re-review B observed roughly 270ms during the open transition where the closed
label band and the opened header controls appear simultaneously visible in the
56fps H.264 diagnostic capture. This may be encoder motion blur rather than a
real overlap of two content layers. Content **choreography timing** has no
reference authority in this program — PI-REF-002 marks the reference HTML as a
css-exemplar only — so there is nothing to judge this against today. Parked to
be re-judged under **Slice 7 (motion closure)**, where the motion contract gets
its authority.

## R-b — marker migration for pre-existing centre-label choices

Decision of record: explicit centre-label choices made **before** the
`appearance.island.v8.<profile>.centerLabel.explicit` marker key existed carry
no marker, and are therefore treated as **non-explicit** under the Poured notch
default flip (PI-A-001). Accepted because Slice 3 is the slice where that
default flips, so "never chose" and "chose the old `.off` default" are the same
population; any affected user can re-pick from the settings pane, which now
records the choice even when it is a no-op re-pick.

## R-c — PI-B-003 evidence adjudication (concave top shoulder)

The **opened** Poured surface **does** render the concave top shoulder. Root
alpha-trace of the isolated `cacheDisplay` silhouette: the left bound moves
92 → 132 over the top 32pt and the right bound 1147 → 1107, i.e. a symmetric
inward taper, not a flat top
(`artifacts/poured-parity-analysis/2026-08-01/slice3/candidate/opened-grouped-six/overlay.png`).
Consequently the flat-top scope of **N-10** above remains **pill / peek only**;
it does not extend to the opened surface. Mid-flight fillet *evolution* during
the morph remains capture-gated — judging it requires a silhouette-isolating
motion recorder, which does not exist yet.
