# Poured Island visual-parity audit and validation specification

Status: implementation input; documentation-only audit  
Reference authority: [`01-poured-island.html`](01-poured-island.html)  
Native authority: the repo-built `OpenIslandApp` at the commit being validated  
Audit baseline: `3042e8df` (`origin/main` when this audit began)

## 1. Executive verdict

The current implementation is approximately **35–40% faithful** to the Poured Island reference. That is a qualitative diagnostic band, not a scientific similarity score. The native overlay has the broad idea—a top-edge island, dark material, sessions, status, usage, and actionable content—but it does not yet preserve the reference's composition, information hierarchy, density, light behavior, or continuous motion system.

The live app observed during the review showed 40 sessions: one running and 39 idle. The panel presented a long flat monitoring list, repeated `/` workspace names, repeated `Codex.app` badges, prominent usage rings, a large `SESSIONS` band, and a broad silver top wash. The reference instead curates a short attention-first narrative: state groups, human-readable work summaries, restrained chrome, one warm attention event, and a blue-black body whose shape and light move as one object.

This explains why localized fixes have not converged. Several upstream choices compound:

- no default state grouping + no surfaced-session cap = a flat 40-row panel;
- raw workspace fallback + hidden collapsed activity = rows that say `/` and little else;
- persistent meters + a large heading + a metrics capsule = chrome competing with work;
- automatic actionable expansion = unstable row rhythm and lost multi-session context;
- a broad rectangular sheen + clipped rectangular hairline = light that describes a card, not a poured silhouette;
- an ink/vibrancy crossfade + a non-animating fillet = a transition that can look like two layers instead of one liquid body.

The following rubric explains the band without pretending to greater precision:

| Dimension | Weight | Current band | Basis |
|---|---:|---:|---|
| Shell and silhouette | 20 | 8–9 | Basic form and radii exist; edge light, notch junction, and material continuity do not yet match. |
| Information architecture and density | 20 | 5–7 | Sessions exist, but the default flat, uncapped, chrome-heavy list reverses the reference hierarchy. |
| A–K state fidelity | 20 | 8–9 | Most product states have native components; several are unvalidated against the reference and key A–C behavior diverges. |
| Material, typography, spacing, chrome | 15 | 5–6 | Palette is close; broad sheen, header treatment, row content, and emphasis are visibly different. |
| Motion and topology | 15 | 4–5 | Some reference timing constants exist; hover peek and one-body morph parity are absent or unproven. |
| Interaction and accessibility | 10 | 5–6 | Native semantics are substantial, but compact attention, transition continuity, and reference-specific accessibility evidence are incomplete. |
| **Total** | **100** | **35–42** | Reported as **approximately 35–40%**, pending calibrated capture evidence. |

Compilation, unit tests, and the presence of individual design tokens cannot raise this result. They can prove code health or internal consistency, not perceptual parity.

## 2. Purpose and non-goals

This document answers four questions:

1. What exactly does the Poured Island reference require?
2. What is confirmed to be different in the current native implementation?
3. Which states remain unvalidated rather than proven wrong?
4. What evidence is required before a change or the whole theme may be called visually faithful?

It covers visual composition, information hierarchy, copy/data presentation, interaction, state coverage, motion, silhouette, material, light, typography, spacing, accessibility adaptations, and acceptance.

It does **not**:

- change UI code;
- redesign or reinterpret the HTML reference;
- add product states or broaden supported runtimes;
- declare an unexercised state defective;
- treat Halo behavior as Poured behavior merely because Halo tooling exists;
- accept a build, test, snapshot, image metric, or implementer's judgment as proof of parity.

## 3. Sources of truth and claim discipline

The design authority is the rendered HTML plus its DOM, CSS, and prose. The file contains no interaction JavaScript: it is a static design board with CSS animation demonstrations, not a deterministic interactive prototype. The implementation authority is a fresh repo build of `OpenIslandApp`. `/Applications/Open Island.app` 0.1.0 build 1105 supplied live evidence for this audit but is not proof of the current branch. Future validation must rebuild and launch the repository app with `zsh scripts/launch-dev-app.sh` before observing it.

Every claim and artifact uses one or more evidence classes:

| Class | Meaning |
|---|---|
| `REF` | HTML DOM/CSS/prose or a canonical rendered board capture |
| `SRC` | Current native source at a named commit |
| `LIVE` | Direct observation/capture of a fingerprinted native build |
| `STATIC` | Registered reference/native still comparison |
| `MOTION` | Synchronized frame or video comparison |
| `INTERACTION` | Pointer, keyboard, focus, hit-test, or state-transition evidence |
| `A11Y` | Accessibility setting, VoiceOver, focus, or semantic evidence |
| `REGRESSION` | Build, lint, unit, snapshot, or other non-parity check |
| `REVIEW` | Independent qualitative visual-review verdict |
| `WAIVER` | Narrow, approved platform-rendering tolerance |

Claim confidence is `confirmed`, `corroborated`, `inferred`, or `unvalidated`. A feature is “missing” only when `REF` is paired with `SRC`, `LIVE`, `STATIC`, or `MOTION`. If a D–J state cannot be reproduced, it is `blocked-unvalidated`; absence of evidence is not evidence of absence.

### 3.1 Evidence anchors for seeded findings

“Confirmed” is not available from a prose impression. Before implementation, a source-survey pass must give every ledger item all applicable anchors: reference selector/section and line, current native file/symbol and line, and fingerprinted capture path. If a required anchor cannot be found, record `not-located`; if the runtime state cannot be produced, record `not-reproducible`. Both resolve to `blocked-unvalidated`, never “missing” or “passed.”

The baseline anchors below make the seeded findings auditable; they must be refreshed against the implementation commit:

| IDs | Reference anchor | Native anchor | Capture anchor |
|---|---|---|---|
| `PI-C-001`, `PI-C-007` | C `.summary`, `.grp` at HTML 769–913; group labels at 809, 844, 878 | `AppModel.loadAppearancePreferences` 753–762; `IslandSessionSectioning.sections` 17–41; `PouredSessionListScaffold.sessionRowsContent` 63–70 | This audit's LIVE observation; canonical path pending Gate 0C |
| `PI-C-002` | C's six-session composition at 773–918 and J empty state | `AppModel.surfacedSessions` 968–990 and the source survey of `sessionBuckets.primary` | LIVE 40-session observation; canonical `C4-stress-40` pending Gate 0C |
| `PI-A-001` | A2 label at 591 and B peek at 706–761 | `AppModel.loadAppearancePreferences` 733–743; `PouredClosedPill.centerLabel` 143–191 | Canonical A/B captures pending Gate 0C |
| `PI-C-003` | C `.ws`/`.disamb` rows at 815–910 | `AgentSession.spotlightDisplayName` 113–138 | LIVE repeated `/`; canonical path pending Gate 0C |
| `PI-B-001` | B note at 706–709 and B/B′ frames through 761 | `IslandPanelView.hoverPeekContent` 459–464 | Canonical pointer capture pending Gate 0C |
| `PI-B-002`, `PI-B-003` | B′ “one liquid body, never a crossfade” at 760–761; K at 1547–1572 | `IslandPanelView` shared morph 992–1065; `OpenedIslandSurfaceShape.animatableData` 25–30 | Canonical K frame strip pending Gate 0C |
| `PI-C-004` | C `.summary` 800–806 | `PouredSessionListScaffold.sessionPanelHeader` 107–134 and `sessionOverviewView` 222–234 | LIVE heavy header/capsule; canonical C1 pending Gate 0C |
| `PI-C-005` | C `.row .act`/`.meta` 815–910 | `PouredSessionRow.rowSummary` 234–247 | LIVE sparse rows; canonical C1 pending Gate 0C |
| `PI-C-006` | C compact `.row.actionable` 811–841; dedicated E/F sections | `PouredRowExpansion.resolved` 63–76 and row action surfaces | Canonical C/E/F transition pending Gate 0C |
| `PI-M-001` | `--specular` and `.glass` 48–55, 131–143 | `IslandMaterialTokens.poured` 128–173 | LIVE broad silver wash; frozen-backdrop path pending Gate 0C |
| `PI-M-002` | `.glass`/`.fillet` 131–143 | `OpenedSurfaceInnerHairline.body` 78–92 and its shape clip call site | Canonical silhouette edge crop pending Gate 0C |
| `PI-I-001` | C header/summary and I usage section | Poured scaffold and usage components located during current source survey | LIVE prominent rings; canonical C/I captures pending Gate 0C |
| `PI-V-001`, `PI-X-001`, `PI-A11Y-001` | A–K sections | Current Poured tests/fixtures and absence of a maintained Poured evidence suite, to be re-surveyed | Missing canonical evidence is the blocker itself |

Line anchors are baseline locators, not acceptance truth. Canonical evidence paths replace the `pending Gate 0C` cells before a gap can progress to implementation.

### 3.2 Reference-evidence classes and conflicts

The program must never invent a direct reference frame for a state the board cannot render:

| Class | Examples | Valid parity evidence |
|---|---|---|
| `rendered-canonical` | Static A–J compositions actually present in the board | Direct registered HTML/native still comparison of that exact composition. |
| `rendered-motion-exemplar` | CSS breathing, attention, morph loop, row loop, shimmer loop in K | Direct capture proves only the CSS properties and frames actually rendered; it does not prove an interactive trigger, reversal, or one-shot lifecycle. |
| `specified-invariant` | B's 0.15 s dwell/1.03 scale, “one liquid body,” K prose spring/settle language | A versioned reference behavior specification and deterministic driver must be authored and independently approved before native acceptance. Until then the affected behavior is `blocked-unvalidated`. |
| `derived-validation` | cap boundary, overflow, 40-session stress, missing `/` fallback | Compare the candidate visually to approved Poured laws, related rendered-canonical regions, and a versioned fixture acceptance spec; do not claim pixel parity to a nonexistent HTML frame. |
| `platform-adaptation` | Reduce Motion/Transparency, Increase Contrast, VoiceOver, keyboard, supported text size | Visual and functional equivalence to an independently approved adaptation spec, informed by the reference hierarchy; exact default-reference pixels are not required. |

Three conflicts are already visible and enter the ledger as `S0/P0` reference blockers:

- `PI-REF-001`: success prose says the shimmer “settles … → quiet,” but `.settle` and `.shimmer::after` are infinite CSS animations. The product/design owner must decide whether the lifecycle is one-shot or an exemplar loop, or provide an updated canonical artifact, before implementation acceptance.
- `PI-REF-002`: K prose specifies an approximate spring response `.5` / damping `.84`, while `.morph` renders a 3.4 s infinite cubic-bezier open/hold/close loop. The loop is a visual topology exemplar, not proof of the stated interactive timing.
- `PI-REF-003`: K labels row entrance “rise + fade, spring settle,” while `.row-enter` is a 2.6 s infinite `ease-out` demonstration with no spring definition. The rendered loop proves start/end geometry, not the claimed production timing or spring.

The same rule applies to hover/reversal and interaction flows: prose plus a static board is a requirement candidate, not a capture driver. Choosing between contradictory authorities is a product/design decision. The root, implementer, and visual reviewers may not make it. Keep the item `blocked-unvalidated` until the product/design owner gives an explicit recorded ruling or supplies an updated canonical reference artifact. Then encode that ruling in a small versioned `poured-reference-behavior` manifest with competing anchors, authority/ruling, deterministic input timeline, expected frames/events, rationale, and approval provenance. Independent reviewers validate that the driver faithfully implements the ruling; they do not select the ruling. Full parity remains blocked until every material conflict is resolved this way.

## 4. Poured design laws

These are acceptance constraints extracted from the reference, not aspirational adjectives.

1. **One continuous blue-black glass body.** Pill, peek, and panel are states of one surface.
2. **Light describes shape.** A delicate, contour-following edge catch reveals the body; a broad silver chrome band does not.
3. **Quiet is the default.** The normal state is near-monochrome and restrained.
4. **One warm attention event.** Amber is scarce and belongs to the item needing the user now.
5. **Attention floats to the top.** State grouping and ordering make the next decision obvious.
6. **The overlay narrates work.** It says what is happening in human language, never exposes `/` or raw implementation debris as the principal label.
7. **Density is curated.** The expanded view is a glanceable status surface, not an unbounded monitoring table.
8. **Progressive disclosure preserves context.** Pill → peek → panel and row → detail reveal information without replacing the user's spatial model.
9. **Motion preserves topology.** No crossfade, seam, corner snap, or content flash may imply two bodies.
10. **Hierarchy comes from restraint.** Type, spacing, hairlines, and a small number of state accents do more work than capsules and persistent gauges.
11. **State is not color-only.** Shape, iconography, copy, and accessibility semantics carry the same meaning.
12. **Accessibility preserves comprehension.** Adaptation may change pixels, but not hierarchy, state meaning, or functional equivalence.

“Premium” therefore means coherence, precision, and restraint—not more blur, brighter highlights, more badges, or more animation.

## 5. Five independent parity dimensions

A scenario passes only when all applicable dimensions pass:

| Dimension | Question |
|---|---|
| Structural | Are the same elements present, ordered, grouped, capped, and disclosed in the same hierarchy? |
| Visual/material | Do geometry, silhouette, light, color, typography, spacing, opacity, and emphasis match? |
| Copy/data | Are names, activity, metadata, counts, time, and fallback behavior equally understandable and stable? |
| Interaction/UX | Do hover, click, focus, shortcuts, expansion, reversal, and recovery produce the same model? |
| Motion | Do timing, easing, event order, material continuity, topology, and attention choreography match? |

A beautiful still with the wrong interaction fails. Correct behavior with the wrong shell fails. Matching endpoints with a crossfade between them fails.

## 6. What already exists and should be preserved

Parity work must not discard working native foundations:

- Poured ink/paper colors and the 26 pt outer corner / 12 pt fillet values are represented in theme tokens.
- Closed-state vocabulary includes idle, working, permission, question, success, and multi-session states.
- Native code contains the 3 s working pulse, 1.9 s permission pulse, question breathing, and success-settle concepts.
- Rows already have brand ticks, disambiguation support, hover dismiss, detail metadata, prose rendering, and jump actions.
- Permission/question keyboard contracts and question pagination exist.
- Dedicated subagent/task, completion, usage, and empty-state components exist.
- Reduce Motion and non-color status cues exist in parts of the Poured implementation.

These facts mean the work is a parity program, not a ground-up rewrite. They do not prove the existing pixels or transitions match.

## 7. Confirmed gap ledger

Severity and implementation priority are separate:

- `S0` validation blocker; `S1` structural/topological; `S2` clearly perceptual; `S3` localized polish; `S4` platform-rendering tolerance.
- `P0` validation/foundation; `P1` core collapsed/expanded/attention path; `P2` state completeness; `P3` final polish.

| ID | Sev/Pri | States | Confirmed delta and consequence | Evidence | Required acceptance |
|---|---|---|---|---|---|
| `PI-C-001` | S1/P1 | C | `sessionGroup` defaults to `.none`; Poured then suppresses group headers. The reference's Needs you → Working → Done hierarchy disappears. | REF C; SRC `AppModelTypes.swift`, `IslandSessionSectioning.swift`, `PouredSessionListScaffold.swift`; LIVE flat list | Fresh-default mixed fixture visibly groups and orders by state; attention is first. |
| `PI-C-002` | S1/P1 | C,J | All surfaced visible sessions enter the primary list without a display cap. The observed 40-session case becomes a long table. | REF C/J; SRC `AppModel.swift`; LIVE 40 sessions | 40-session fixture has a documented cap/overflow treatment, stable ordering, and preserves all attention items. |
| `PI-A-001` | S1/P1 | A,B | The notch center/narrative label defaults off. Collapsed state can become glyph + agent/count rather than “Editing …” or the actionable narrative. | REF A/B; SRC `AppModel.swift`, `PouredClosedPill.swift` | Default A1/A2/A2′ captures show the required narrative without opening. |
| `PI-C-003` | S1/P1 | C,D | Workspace fallback can surface raw `/`; live rows repeated `/`, destroying identity and disambiguation. | REF C/D; SRC `AgentSession+Presentation.swift`; LIVE | Missing/root-path fixtures never use a bare slash as the primary label and remain distinguishable. |
| `PI-B-001` | S1/P1 | B,K | Hover peek is gated to Halo. Poured gets scale but not the reference's 0.15 s dwell, one-actionable preview, or “+N more.” | REF B/B′; SRC `IslandPanelView.swift` | Pointer capture proves no peek before dwell, correct peek after dwell, compressed overflow, and clean exit/open. |
| `PI-B-002` | S1/P1 | B,K | Closed/open content and opaque ink/vibrancy appearances crossfade. The reference explicitly requires one liquid body, never a crossfade. | REF B′/K; SRC `IslandPanelView.swift` | 60 fps alpha/topology evidence shows one surface and no layered transparency or content flash at every checkpoint. |
| `PI-B-003` | S1/P1 | B,K | The 12 pt notch fillet is not part of animatable data, so the junction can appear fixed or snap while other radii change. | REF B′/K; SRC `OpenedIslandSurfaceShape.swift`, `IslandPanelView.swift` | Registered high-resolution edge strips show continuous, symmetric fillet evolution on open, reverse, and close. |
| `PI-C-004` | S1/P1 | C,I | Native adds a 36 pt uppercase `SESSIONS` header and a capsule overview; the reference uses a shallow full-width summary strip. | REF C; SRC `PouredSessionListScaffold.swift`; LIVE | Top-chrome height, summary bounds, first-row Y, order, and visual weight match the registered reference. |
| `PI-C-005` | S1/P1 | C | Normal collapsed rows render activity only when expanded. Reference rows narrate activity/result and metadata while remaining compact. | REF C; SRC `PouredSessionRow.swift`; LIVE sparse rows | Running/done/idle rows show exact expected narrative and metadata without detail expansion; wraps match. |
| `PI-C-006` | S1/P1 | C,E,F | Actionable rows auto-expand, conflating compact list attention with dedicated permission/question surfaces and consuming context. | REF C/E/F; SRC `PouredSessionListScaffold.swift`, `PouredSessionRow.swift` | Two permissions + question + running fixture preserves compact grouped rhythm; selection deliberately opens the hero. |
| `PI-M-001` | S2/P1 | A–K | Native material adds a broad 26 pt white-at-50% soft sheen; the reference's principal catch is a subtle 1 px white-at-14% edge. Live shell looks silver and flatter. | REF CSS; SRC `IslandMaterialTokens.swift`; LIVE | Frozen-backdrop luminance profile, edge mask, overlay, and reviewer pass show a narrow contour catch and blue-black body. |
| `PI-M-002` | S1/P1 | B–K | The native inner hairline strokes a rectangle and is clipped by the opened shape rather than tracing the actual poured contour. | REF CSS/body; SRC `OpenedSurfaceMaterial.swift`, `IslandPanelView.swift` | Edge mask follows corners and both concave fillets continuously; no clipped straight fragments. |
| `PI-I-001` | S2/P1 | C,I | Persistent usage rings and metrics chrome compete with the current task and attention state. | REF C/I; SRC Poured usage/scaffold components; LIVE | Saliency/chrome-area review shows content and attention dominate; I still communicates thresholds and reset time. |
| `PI-C-007` | S1/P1 | C | Equal-weight idle rows, repeated badges, no cap, and no grouping produce no effective density discipline in the 40-session case. | REF C; LIVE; compounds 001–006 | 6-, cap-boundary-, overflow-, and 40-session comparisons maintain legibility, stable grouping, and glanceable height. |
| `PI-V-001` | S0/P0 | A–K | No maintained Poured HTML↔native still/motion conformance suite or committed evidence matrix proves parity. Current tests verify internals only. | Existing Poured tests and Halo-specific parity tooling | Gates 0A–0C produce fingerprinted reference/native baselines, masks, thresholds, and independent baseline review before UI edits. |
| `PI-X-001` | S0/P0 | D–J | Dedicated native implementations exist, but several D–J states were not exercised in the live review; exact parity is unvalidated. | REF D–J; SRC components; missing capture evidence | Each deterministic D–J fixture receives static, interaction, a11y, and motion evidence where applicable. |
| `PI-A11Y-001` | S0/P2 | A,C,E,F,I,J,K | Accessibility behaviors exist in source but have not been compared against Poured hierarchy after material/density changes. | SRC Poured components; absent A11Y bundle | Named Reduce Motion/Transparency, Increase Contrast, VoiceOver, keyboard, and text-size runs pass independently. |
| `PI-REF-001` | S0/P0 | H,K | Success prose says settle-to-quiet, but the rendered CSS demonstrations loop infinitely. | REF prose 1547–1571; REF CSS 196–201, 508–513 | Product/design-owner ruling plus a versioned one-shot/loop driver precedes H/K acceptance. |
| `PI-REF-002` | S0/P0 | B,K | K prose calls for spring response/damping, while the only rendered morph is a 3.4 s cubic loop. | REF prose 1547–1559; REF CSS 494–500 | Product/design-owner ruling plus a versioned interactive morph driver precedes B/K acceptance. |
| `PI-REF-003` | S0/P0 | K | K calls row entrance a spring settle, while `.row-enter` renders a 2.6 s infinite ease-out loop. | REF label 1565–1567; REF CSS 501–507 | Product/design-owner ruling plus versioned row-entry timeline/driver precedes K2 acceptance. |

Line numbers deliberately are not normative: the continuation task must use current symbols and bind evidence to its commit.

### 7.1 Ledger record required during implementation

Each row must expand to a machine-readable or tabular record containing: stable ID, A–K state, title, reference expectation, current behavior, exact delta, evidence IDs/locations, confidence, severity, priority, source symbols, deterministic scenario, affected regions, static/motion/interaction/a11y acceptance, implementation slice, owner, status, review verdict, waiver, and final artifact paths.

Allowed status values are `open`, `implementation-in-progress`, `implemented-awaiting-capture`, `metric-fail`, `review-fail`, `passed`, `waived`, and `blocked-unvalidated`. A metric pass never changes a row to `passed` without independent visual review.

## 8. Required A–K scenario manifest

The implementation task must classify and materialize every scenario as `rendered-canonical`, `rendered-motion-exemplar`, `specified-invariant`, `derived-validation`, or `platform-adaptation`. Titles, paths, agents, counts, order, timestamps, elapsed times, usage, choices, and result text must be frozen. Only the first two classes may claim direct rendered HTML comparison. Other classes require the approved specification/driver evidence defined in §3.2 and always receive visual review of the native result.

| Scenario | Reference state | Principal validation | Known status |
|---|---|---|---|
| `A1-idle` | Quiet collapsed pill | silhouette, label, idle glyph, restrained light | Native component exists; exact parity unvalidated. |
| `A2-working-one` | One working session | narrated label, wave, 3 s breathing | Center label/default and visuals diverge or are unvalidated. |
| `A2m-working-many` | Multiple active sessions | count/grid compression and hierarchy | Validate count and one-primary narrative. |
| `A3-permission` | Permission attention pill | warm single attention, 1.9 s pulse | Timing concept exists; pixel/motion parity unvalidated. |
| `A4-question` | Question attention pill | distinct wording/shape and 2.6 s breath | Unvalidated. |
| `A5-success` | Just-completed pill | success lifecycle is blocked by `PI-REF-001` | Prose says settle-to-quiet; CSS exemplar loops. Resolve before acceptance. |
| `A6-outcomes` | failure/interrupted/mixed outcomes | shape + copy, not color alone | Unvalidated. |
| `B1-hover-peek` | Hover after 0.15 s | scale 1.03, one actionable narrative, `+N more`, exit | Confirmed missing for Poured. |
| `B2-pill-peek-panel` | Continuous three-state form | topology, geometry, content reveal, reversal | Crossfade and fillet gaps confirmed. |
| `C1-grouped-six` | 2 needs you / 2 working / 2 done | group order, shallow summary, row rhythm | Major structural gaps confirmed. |
| `C2-cap-boundary` | Derived: exactly the approved visible cap | no accidental overflow or height jump | Requires versioned derived-fixture spec; no direct HTML frame exists. |
| `C3-overflow` | Derived: cap + 1 with attention last in input | attention remains visible; truthful overflow | Requires versioned derived-fixture spec. |
| `C4-stress-40` | Derived: 1 running / 39 idle and mixed-attention variant | usable height, identity, curation, scroll/overflow | Live failure case; validate against approved laws/fixture spec. |
| `D1-detail` | Expanded running-session detail | calm metadata grid, prose, primary jump, hover dismiss | Native foundation exists; unvalidated. |
| `E1-command-permission` | Permission hero with command | hierarchy, approve/deny, shortcuts, focus | Unvalidated. |
| `E2-diff-permission` | Permission with diff | diff legibility/density and action persistence | Unvalidated. |
| `E3-jump-codex` | Codex jump handoff | platform copy and action hierarchy | Unvalidated. |
| `E4-notification` | Notification/action alternative | state semantics and recovery | Unvalidated. |
| `F1-question` | Single question | choice hierarchy, keyboard, answer transition | Unvalidated. |
| `F2-multi-question` | Multiple questions/pagination | progress, stable height, focus | Native pagination exists; unvalidated. |
| `F3-multi-select` | Multiple selection | selected state and confirm affordance | Unvalidated. |
| `F4-compact-question` | Question inside list | compact attention without hero takeover | Auto-expansion gap confirmed. |
| `G1-nested-tasks` | Parent with subagents/tasks | hierarchy, progress, nested disclosure | Native component exists; unvalidated. |
| `G2-compressed-row` | Task progress in compact row | readable compression | Unvalidated. |
| `G3-task-pill` | Task state in closed surface | priority and count | Unvalidated. |
| `H1-completed` | Just completed | outcome copy and success emphasis; lifecycle blocked by `PI-REF-001` | Static composition can be validated; time behavior awaits ruling. |
| `H2-post-success` | State after success emphasis | final state blocked by `PI-REF-001` | Do not prescribe quiet or loop until product/design-owner ruling. |
| `I1-usage-normal` | Nominal meters in panel | subordinate placement, value/reset text | Prominence gap observed. |
| `I2-usage-threshold` | Elevated/critical usage | threshold state without overwhelming work | Unvalidated. |
| `I3-usage-pill` | Usage in collapsed state | compression and state priority | Unvalidated. |
| `J1-empty` | No visible sessions | monitoring/hooks reassurance and recovery action | Native component exists; unvalidated. |
| `K1-open-close` | pill ↔ panel | one-body motion, event order, reversal | Confirmed topology/material risk. |
| `K2-row-entry` | rows enter/leave/reorder | rise/fade geometry; timing/spring blocked by `PI-REF-003` | Requires product/design-owner ruling and driver. |
| `K3-attention-cycle` | idle → attention → resolved | one warm event, timing, settle | Unvalidated. |

Every scenario also receives applicable `-reduced-motion`, `-reduced-transparency`, `-increased-contrast`, keyboard, VoiceOver, light/dark appearance, and supported text-size variants. The `/` workspace case is a regression fixture, never the canonical display copy.

### A — Collapsed states

The pill is not a miniature dashboard. Its job is to state the highest-value truth in one glance: quiet, what is working, or what needs the user. Validate the actual label on both notch and external-display profiles, left/right slot balance, glyph geometry, counts, warm-attention scarcity, and the transition from transient success back to quiet. The current default-off notch label is a structural gap; the exact pixels and normal/reduced motion of the other closed states remain unvalidated.

### B — Hover peek and morph

After the reference's dwell, hover promotes the single most actionable narrative and compresses the rest to `+N more`. Opening grows that same surface into the panel. Validate pre-dwell stability, peak scale, content choice, overflow truthfulness, pointer exit, click-through, open, close, and mid-flight reversal. The Poured hover-peek gate, material crossfade, and non-animating fillet are current blockers.

### C — Expanded session list

The canonical six-session fixture must read in this order: restrained usage/control wings, shallow non-zero summary, Needs you, Working, Done, then quiet footer. Each compact row must carry workspace/disambiguation, narrated activity or result, relevant metadata, age, and state. Validate the cap boundary and 40-session stress state as seriously as the attractive six-row state. The current default list fails grouping, curation, identity, narrative density, compact attention, and chrome hierarchy.

### D — Session detail

Selection expands in place into a calm metadata grid, human-readable last-message prose, a dominant jump action, secondary transcript action, and hover-reveal dismiss. Validate selection continuity, rich-text wrapping, long paths/branches, action priority, scroll containment, collapse, and focus restoration. Native foundations exist, so status remains unvalidated until registered comparison rather than presumed missing.

### E — Permission

The dedicated permission surface must clearly name the request, render commands or diffs safely, expose approve/deny with matching shortcuts, and preserve context/countdown behavior. It is distinct from the compact permission row in C. Validate command, diff, Codex jump, and notification variants, focus order, destructive-action clarity, countdown/hover pause, resolution, and return to the correct prior state.

### F — Questions

Validate single, paginated, multi-select, and compact question forms. Copy, choice grouping, selection states, keyboard numbers, confirm behavior, progress, focus, height stability, and answered transition must match. The reference's compact list state must not be forced into the full hero solely because it needs attention.

### G — Subagents and tasks

Nested work must communicate parent/child ownership, progress, and compression without becoming a generic badge pile. Validate the full nested view, compressed row, and pill summary with long names, zero/full/partial progress, multiple agents, disclosure, navigation, and completion changes. Dedicated code exists; comparison evidence does not.

### H — Completion

Completion must clearly communicate the outcome without remaining permanently loud. Validate outcome copy, glyph/shape, row result, interruption/failure distinction, retention/staleness behavior, and the final state. The exact shimmer lifecycle is blocked by `PI-REF-001`: do not require either a one-shot or a loop until the reference-behavior manifest resolves the prose/CSS conflict.

### I — Usage

Usage communicates percentage and reset horizon while remaining subordinate to work and attention. Validate normal/elevated/critical thresholds, conic geometry, digits, reset copy, wing balance, panel placement, pill compression, unavailable data, and Reduce Transparency/Contrast variants. The current live prominence is a confirmed hierarchy issue; the meter component itself is not assumed wrong without capture.

### J — Empty

Empty means no visible sessions, not product failure. Validate the monitoring/hooks reassurance, recovery guidance/action, icon/light restraint, panel height, transition from last session to empty, arrival of the first session, keyboard/VoiceOver semantics, and no stale counts. The native empty component is unvalidated rather than absent.

### K — Motion system

K is the cross-state contract used by A–J: ambient cycles, attention, hover, shape growth, content reveal, row insertion/removal/reorder, hero transitions, completion settle, close, and reversal. Validate normal and reduced motion independently. The central invariant is object permanence—one surface and a stable content hierarchy throughout—not merely matching duration constants or endpoints.

## 9. Canonical environment and evidence bundle

Every run writes `artifacts/poured-parity/<native-commit>/<run-id>/manifest.json` with:

- Git commit and dirty state;
- HTML, scenario, fixture, mask, threshold, and capture-script hashes;
- target, executable path, build configuration, app version/build, and launch command;
- macOS version/build, hardware/GPU, display logical resolution, backing scale/DPR, and color profile;
- appearance, accent color, Reduce Motion, Reduce Transparency, Increase Contrast, and supported text size;
- locale, timezone, and 12/24-hour mode;
- browser engine/version, zoom, DPR, viewport, and rendering flags;
- app/window bounds and screen position;
- frozen backdrop asset/hash;
- capture tool, format/encoding, and timestamps;
- bundle/signing identity for TCC-sensitive behavior.

The bundle contains:

```text
manifest.json
ledger.json
reference/full/       native-baseline/full/       native-candidate/full/
registered/<scenario>/<region>/{reference,baseline,candidate}.png
masks/<scenario>/*.png
comparisons/<scenario>/{side-by-side,blink,overlay,diff,heatmap}.png
metrics/{calibration,static,motion,geometry,light,text}.json
motion/<scenario>/{reference,native,frames,strip,landmarks}.*/
interaction/           accessibility/              regression/
reviews/<slice>/<reviewer>.md
```

Evidence is stale if its commit, fixture, environment, masks, or thresholds do not match the candidate under review.

## 10. Gates 0A–0C: validation before UI edits

### Gate 0A — Deterministic reproduction

Inventory what the HTML can actually render, then classify all A–K cases using §3.2. Record trigger steps, steady-state conditions, hashes, and named anchors. Materialize direct HTML fixtures only where the board contains the state. For specified, derived, or adaptation cases, first create and independently approve the versioned behavior/fixture/adaptation manifest and any reference driver. Any required authority or state that cannot be reproduced is `blocked-unvalidated`; do not edit its visuals until reproduction is reliable.

### Gate 0B — Neutral renderer calibration

Use neutral shapes, gradients, text blocks, translucency, and a frozen backdrop to establish:

- CSS px ↔ SwiftUI pt ↔ captured device-pixel mapping;
- same-renderer repeatability;
- cross-renderer font/raster/color baseline;
- registration anchors and permitted integer translation;
- antialiasing bands, masks, and provisional thresholds.

Capture each renderer repeatedly—at least five still repetitions per neutral target and three repeated motion runs—under the identical frozen fingerprint. Quantify per-pixel and per-landmark repeatability, capture noise, color variance, timing jitter, and any browser/native raster baseline. An independent non-implementing reviewer must inspect and approve the neutral assets, registration anchors, exclusion rationale, masks, antialiasing bands, and thresholds before any feature candidate is rendered.

Version the calibration manifest, neutral artifacts, masks, and thresholds together. Any later calibration, registration, mask, antialiasing-band, or threshold revision invalidates all comparisons produced with the prior version. The revision must state the neutral evidence that requires it, receive independent approval, increment the calibration version, and recapture affected reference/baseline/candidate evidence. Never loosen a threshold, expand an exclusion mask, blur a diff, or change registration because an implementation failed.

### Gate 0C — Canonical baseline

At 2× backing scale, capture the untouched HTML and untouched native implementation for every rendered-canonical or rendered-motion-exemplar scenario. For other scenarios, capture native baseline evidence beside the approved related canonical regions and behavior/fixture/adaptation manifest—never a fabricated “HTML reference.” Produce the full comparison bundle and obtain an independent baseline-adequacy verdict that populates the ledger. Only then may a visual edit begin.

The existing `tools/halo_parity` and `scripts/halo-parity/halo` are Halo-specific. Either generalize genuinely shared primitives without changing Halo evidence semantics or create a Poured namespace. Blind renaming is forbidden.

## 11. Static comparison protocol

For rendered-canonical comparisons, reference and native use the same logical canvas, 2× scale, backdrop, appearance, profile, and crop. Register by named silhouette/layout anchors with integer translation only—no scaling or nonlinear warp. Derived/adaptation cases use the same native capture discipline but are reviewed against their approved manifest and relevant canonical regions, never mislabeled as direct pixel comparisons.

Stable masks are versioned for outer silhouette, notch/center label, edge catch/inner stroke, backdrop/material, emissive glow, header/chrome, rows, status/activity, usage, text-layout, non-text content, each D–J surface, and OS-external content. Text is assessed with exact copy plus geometry; it is not hidden just to improve SSIM.

For every affected region generate side-by-side, blink, 50% overlay, signed difference, and heatmap. Provisional screening targets, frozen after Gate 0B, are:

- key geometry landmarks within 1 logical pixel;
- exact text wrapping and line count, with baseline/bounds landmarks within 1 logical pixel;
- silhouette IoU ≥ 0.985;
- symmetric silhouette edge distance p95 ≤ 1 logical pixel and maximum ≤ 2 outside the declared antialiasing band;
- stable opaque-region ΔE2000 median ≤ 2 and p95 ≤ 5;
- stable non-text masked SSIM ≥ 0.98;
- chrome/mask area ratio within 2% of the reference.

These are screening tools, not an optimization target. A reviewer-visible mismatch fails even if every metric passes. A miss remains open unless it is proven to be an `S4` platform-rendering variance and approved by the root plus both final reviewers.

Hard automatic failures include wrong scenario/copy/order, missing or extra principal elements, wrong topology, clipped content, a bare `/` title, attention hidden by overflow, color-only state, mismatched line count, a visible crossfade, a fillet/corner snap, stale evidence, or capture-environment mismatch.

## 12. Motion comparison protocol

Capture rendered CSS exemplars and native motion at 60 fps or better with the same logical size. Direct synchronization is permitted only for events the CSS actually renders. Interactive triggers, hold, reversal, exit, and one-shot lifecycles require the independently approved versioned reference behavior driver first. Record explicit `t=0`, trigger, 10%, 25%, 50%, 75%, settled/hold, extrema, reversal, and exit where the approved timeline defines them. Review realtime, frame-by-frame, and at 0.25×.

Reference rhythms that must be verified against the HTML at the captured hash include:

| Motion | Reference target |
|---|---|
| Working ambient breath | 3.0 s ease-in-out cycle |
| Permission attention | 1.9 s ease-in-out cycle |
| Question/breathe family | 2.6 s ease-in-out cycle |
| Success settle | **Conflict:** prose says settle-to-quiet; `.settle`/`.shimmer` CSS loop at 2.6 s. Block until `PI-REF-001` resolves authority. |
| Hover | 0.15 s dwell, approximately 1.03 peak scale |
| Open/close morph | **Conflict:** prose says response ≈0.5/damping ≈0.84; rendered CSS is a 3.4 s cubic loop. Block until `PI-REF-002` resolves authority. |
| Row entrance | **Conflict:** label says spring settle; rendered CSS is a 2.6 s infinite ease-out loop. Block until `PI-REF-003` resolves authority. |

Acceptance requires event-order parity, landmark timing within one 60 fps frame (16.7 ms), key geometry within 2 logical pixels at sampled frames, continuous silhouette topology, continuous material identity, no notch/fillet/edge/content discontinuity, and reversal from the current visual state without snapping. Per-frame silhouette masks and alpha/luminance profiles must make a hidden crossfade measurable.

An independent reviewer must explicitly pass four separate questions: silhouette topology, material continuity, content choreography, and attention flow. Matching endpoints alone is insufficient.

## 13. Interaction and accessibility

Interaction evidence covers hover enter/exit and dwell, click/selection, row expansion/collapse, compact versus hero attention, permission/question actions, task navigation, jump behavior, completion settling, empty-state recovery, hit targets, pointer/focus feedback, keyboard traversal/activation, and rapid reversal.

Accessibility variants cover Reduce Motion, Reduce Transparency, Increase Contrast, supported appearance/text-size modes, VoiceOver traversal/labels/values/status/actions, and keyboard focus/activation. They need not pixel-match the default reference, but must preserve information order, state meaning, usable contrast, non-color cues, silhouette integrity where applicable, and functional equivalence. Reduced Motion and normal motion are separate approvals; one cannot stand in for the other.

## 14. Implementation and review gates

| Gate | Required result |
|---|---|
| `G0A` Reproduction | Exact affected A–K state and source hashes are deterministic. |
| `G0B` Calibration | Unit mapping, renderer variance, masks, and thresholds are frozen. |
| `G0C` Baseline | Reference/native-before bundle and independent baseline review exist. |
| `G1` Structure/copy | Projection, grouping, order, cap, labels, content, and wraps pass. |
| `G2` Geometry/material | Silhouette, contour light, fill, shadow, radii, and notch pass. |
| `G3` Hierarchy/light | Chrome, saliency, state emphasis, and one-attention rule pass. |
| `G4` Interaction/UX | Pointer, keyboard, focus, disclosure, and recovery pass. |
| `G5` Normal motion | 60 fps topology, timing, reversal, and choreography pass. |
| `G6` Accessibility | Each affected named adaptation passes independently. |
| `G7` Regression | Build, lint, targeted units/snapshots pass as supporting evidence only. |
| `G8` Slice review | A non-implementing visual reviewer returns `PASS`. |
| `G9` Final parity | All A–K states and two independent final reviewers pass the same commit. |
| `G10` Golden eligibility | Native goldens may be recorded only after cross-renderer parity approval. |
| `G11` Integration | Integrated `main` is rebuilt, recaptured where affected, pushed, and clean. |

### Mandatory per-change visual loop

For every coherent visual change:

1. Select ledger IDs, scenarios, regions, expected differences, and applicable gates before editing.
2. Capture the unchanged rendered reference where one exists; otherwise bind the approved invariant/derived/adaptation manifest and its related canonical regions. Always capture the pre-change native evidence.
3. Implement only the selected system.
4. Build and capture the candidate from its exact commit.
5. Generate registered side-by-side, blink, overlay, diff/heatmap, geometry/light/text reports, and a motion strip when affected.
6. Give the actual assets—not a prose summary—to a non-implementing visual reviewer.
7. Require `PASS`, `FAIL`, or `BLOCKED`, with ledger IDs, inspected evidence, visible deltas, and exact correction requests.
8. The root adjudicates. On failure, make only ledger-backed corrections and repeat from capture.
9. Integrate only after all affected gates pass.

Tests are mandatory regression evidence. They are never visual acceptance. An implementer cannot approve their own pixels, and a reviewer cannot pass assets they did not inspect.

## 15. Anti-random-fix rules

- Every edit maps to a ledger ID, deterministic scenario, region, expected result, and acceptance check.
- Change one coherent visual system at a time; do not mix projection, material, type, and motion unless the ledger records an inseparable dependency.
- Establish the baseline before changing code.
- Do not tune from memory or adjectives such as “more premium.” Compare to registered evidence.
- Do not loosen thresholds/masks, change the crop/backdrop, or update goldens after a failure.
- Do not use native-to-native snapshots to claim HTML parity.
- Do not make the candidate imitate browser rasterization artifacts that Gate 0B identified as renderer variance.
- Do not promote an inference to a confirmed gap without evidence.
- Do not accept a subagent completion statement without inspecting the diff, build, captures, and review verdict.
- Do not let accessibility adaptations regress while chasing default-mode pixels.

## 16. Recommended implementation order

1. Validation foundation: deterministic fixtures, capture environment, masks, registration, bundle, ledger.
2. Session projection and identity: grouping, cap/overflow, ordering, workspace fallback, 40-session behavior.
3. Shell geometry and material: true contour, hairline/catch, fill/shadow, notch/center label.
4. Collapsed, hover, and morph: A/B/K, narrative, peek, animatable fillet, continuous material/content transition.
5. Expanded list: shallow strip, grouped rows, density, compact actionable states, usage/chrome priority.
6. Detail, permission, questions: D/E/F.
7. Tasks, completion, usage, empty: G/H/I/J; completion lifecycle stays blocked until `PI-REF-001` has a product/design-owner ruling.
8. Normal motion and accessibility closure; morph and row timing stay blocked until `PI-REF-002`/`003` have product/design-owner rulings.
9. Integrated all-scenario comparison and final independent review.

This order fixes upstream curation before tuning row pixels and establishes the real body before tuning its light. A dependency-driven deviation is allowed only if recorded before edits.

## 17. Definition of done

Use exactly four outcome labels:

- `FULL PARITY`: all requirements pass and there are no waivers.
- `PARITY WITH S4 WAIVER`: all requirements pass except one or more independently approved renderer-only S4 tolerances.
- `BLOCKED-UNVALIDATED`: a required authority, scenario, driver, capture, or review cannot be established safely.
- `NOT YET PARITY`: work is reproducible and actionable, but one or more requirements still fails or remains open.

`FULL PARITY` may be claimed only when:

- every required A–K scenario has valid evidence for its §3.2 class: direct rendered comparison where available, or approved invariant/derived/adaptation authority plus native baseline/final visual evidence;
- all five parity dimensions pass for each scenario;
- no item is `open`, `blocked-unvalidated`, `metric-fail`, or `review-fail`;
- every `S0`, `S1`, `S2`, and `S3` item is closed as `passed`;
- no item is waived. If only one or more qualifying `S4` tolerances are waived, the highest permitted outcome is `PARITY WITH S4 WAIVER`; each waiver remains in the ledger/final report and requires root plus both-final-reviewer approval;
- every applicable static threshold and hard invariant passes;
- every applicable 60 fps normal-motion sequence passes;
- accessibility and reduced-motion variants pass separately;
- every coherent slice has an independent visual-review disposition;
- two fresh non-implementing reviewers pass the integrated commit after inspecting the full assets;
- regression checks pass, explicitly labeled as non-parity evidence;
- no unrelated design or UI change is present;
- the final `main` commit is pushed and the repository is clean.

If a state or environment is skipped, the result is `BLOCKED-UNVALIDATED`. A proven and approved renderer-only tolerance results in `PARITY WITH S4 WAIVER`, never `FULL PARITY`.
