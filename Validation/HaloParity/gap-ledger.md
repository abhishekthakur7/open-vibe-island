# Halo parity gap ledger

Version: `gate-0a-v2`  
Commit: `d3917044fc76a3bafaaccba7b17f3954dbaddb5e`  
State: `NOT PASSED`  
Earliest open gate: `0B`

This is the root-owned integration of the reference/spec, native-implementation, and validation-harness audits. Gate 0A passed on the frozen validation artifacts and authenticated in-task user authority. Product visual styling remains forbidden until Gates 0B and 0C pass.

Scenario disposition summary: `57 total` — `57 exact`, `0 temporary-surrogate`, `0 temporary-exclusion`, `0 blocked`. `exact` means deterministic reference/native state reproduction; it does not claim visual parity.

## Gate 0A closure

The `HP-0A-*` reproduction findings below are addressed for Gate 0A by the frozen 57-row authored reference authority, dedicated native fixture catalog, deterministic controller/event mappings, two resolved display profiles, canonical ScreenCaptureKit live-window proof for both renderers, and the authenticated user approval recorded in this Codex task.

Canonical closure evidence:

- report: `artifacts/halo-parity/d3917044fc76a3bafaaccba7b17f3954dbaddb5e/gate0a-canonical-capture-20260730T171200Z/reports/gate-0a.json`
- capture proof: `Validation/HaloParity/calibration/v1/gate-0a-capture-authenticity.json`
- authority projection SHA-256: `36b90cf34cf59c3a21846c5a874386300358694d465ad684eda492901ba6654d`
- dispositions: `57 exact`, `0 temporary-surrogate`, `0 temporary-exclusion`, `0 blocked`

The authored reproduction choices resolve earlier reference ambiguities only for deterministic comparison. They do not approve product styling, waive a hard invariant, grant a scenario parity pass, authorize Gate 7, or authorize goldens.

| ID | Sev | Scenarios | Regions/dimension | Finding | Evidence / source findings | Required restoration |
|---|---:|---|---|---|---|---|
| HP-0A-001 | P0 | B, B′, D, E-travel, F1–F3, H | Interaction, Motion | The HTML is a static board with no state API, handlers, or product-event timeline. | `REF-001`, `REF-005`, `REF-010`, `REF-011`, `REF-014`, `REF-019`; `HAR-005`, `HAR-013` | Add deterministic reference state setters/events or obtain explicit user-approved waivers. |
| HP-0A-002 | P0 | A1, A2, A2′, A4, A6, G′, I′, J′ | Structural, Copy/data | Exact isolated native closed fixtures and capture triggers do not exist. | `NAT-011`, `NAT-018`, `NAT-019`; `HAR-005`, `HAR-022` | Register exact closed debug fixtures and a Halo-only manifest runner without weakening the fixed smoke contract. |
| HP-0A-003 | P0 | C, D, G, H | Structural, Copy/data | Native fixtures do not reproduce the reference data, grouping, order, and copy exactly. Default grouping is `.none`; the live capture showed nine sessions and no Needs You section. | `NAT-013`, `NAT-014`; pre-edit `native-expanded-session-list.png` versus `iab-reference-expanded-c-canonical-attempt.png` | Add isolated six-session C data, force `.state` grouping, and pin exact row membership/copy. |
| HP-0A-004 | P0 | F2, F3 | Interaction | No deterministic native sequence advances to question page 2, toggles multi-select, types Other, submits, or exercises the compact variant. | `NAT-012`; `REF-014` | Add stateful question harness controls and post-action assertions. |
| HP-0A-005 | P0 | H-interrupted, H-failed | Structural, Visual, Copy/data | Reference H authors only success; interrupted and failed detail states are absent. | `REF-016` | Product/design must author exact reference states or the user must approve named waivers. |
| HP-0A-006 | P0 | I, I′, ST-USAGE-* | Structural, Copy/data | Full usage meters are preview/snapshot-only in native live composition; I′ lacks reset time and priority combinations; zero/missing reference states are absent. | `NAT-010`, `NAT-019`; `REF-017`, `REF-018` | Author exact zero/missing/priority states and compose the approved full card in the live surface only after Gate 0 passes. |
| HP-0A-007 | P0 | AX-RM, AX-IC, AX-RT, AX-KBD, AX-VO, AX-TEXT | Accessibility | The reference has no reduced-motion, contrast, transparency, keyboard, VoiceOver, or text-scale states. | `REF-020`, `REF-021`; `NAT-016`; `HAR-014` | Author adaptations and deterministic captures; do not substitute native unit branches. |
| HP-0A-008 | P0 | DP-NOTCH, DP-TOPBAR | Structural, Visual | The two shipped display-profile viewport/panel/crop contracts are unnamed. | `REF-024`; `HAR-019` | Declare exact geometry, scale, display, crop, and registration coordinates for both profiles. |
| HP-0A-009 | P0 | A5, K-success | Motion, edge-core, bloom | Reference success loops forever and does not settle to a bare idle hairline; native success is view-entry state without deterministic retrigger. | `REF-003`, `REF-004`; `NAT-017`; `HAR-004`, `HAR-012` | Provide a one-shot event seam, frame zero, and exact settled state in both renderers. |
| HP-0A-010 | P0 | B′, K-morph | Motion, silhouette/body, edge-core | Reference morph is illustrative; native normal motion lacks timestamped proof and its internal content crossfades. Reduce Motion explicitly crossfades two bodies. | `REF-008`, `REF-011`; `NAT-008`, `NAT-009`; `HAR-012` | Author/capture exact forward and reverse product events and measure topology/edge continuity. |
| HP-0A-011 | P0 | E-travel | Motion, edge-core, bloom | Attention travel is three unrelated reference nodes; native exposes only a final opacity handoff, not a light-centroid path. | `REF-010`; `HAR-012` | Implement deterministic reference/native event capture and reciprocal intensity envelopes. |
| HP-0A-012 | P0 | K-condense | Motion | Native permission pulse uses `sin(time * 3.2)` (~1.96s), not the pinned 1.9s token. | `NAT-006` | Wire the live clock to the approved period after Gate 0 baseline evidence exists. |
| HP-0A-013 | P1 | A4 | Visual, state semantics | A4 parent color does not tint the glyph bars in the HTML; intended qgold hue is ambiguous. | `REF-006` | Resolve intended glyph tint and author one exact reference. |
| HP-0A-014 | P1 | A6-interrupted | Visual, edge-core | A6 caption says amber interrupted, while DOM gives the idle outer hairline. | `REF-007` | Resolve the authoritative interrupted edge. |
| HP-0A-015 | P1 | C | Visual, grouping | Reference comment says only the active/actionable row gets a rail, while C renders four rails. | `REF-009`; `NAT-020` | Approve a deterministic rail multiplicity/tie rule. |
| HP-0A-016 | P1 | G′ | Structural | Audit language says agents-grid; HTML uses a count plus nodes glyph. | `REF-015` | Resolve the authoritative compact representation. |
| HP-0A-017 | P1 | B | Interaction | Native implements immediate 1.03 scale and 0.15s dwell but opens the full panel; no peek model exists. | `NAT-008` | Add an explicit peek state only after the exact reference event is authored. |
| HP-0A-018 | P1 | all opened | Visual, edge-core | Live opened composition adds a generic 1pt white stroke alongside Halo's 1.5pt perimeter. | `NAT-007` | Baseline and measure the duplicate edge before any removal. |
| HP-0A-019 | P1 | C, K | Visual, bloom | Pre-edit native collapsed state has a broad bright continuous cyan/violet bloom; expanded perimeter remains prominent. | computer-use captures; known baseline; `HaloEdgeLight` working bloom opacity `.45`, radius `8` | Carry as a Gate 3 candidate defect; no styling before Gates 0A–0C pass. |
| HP-0A-020 | P1 | C | Structural, Copy/data | Pre-edit expanded native frame is a flat, over-spaced table, contains generic activity (`Running sed...`), has weak state hierarchy, and uses user/live data. | `native-expanded-session-list.png` | Replace with isolated fixture evidence first; later structure/copy changes require metric-backed Gate 1 entries. |
| HP-0B-001 | P0 | all | Calibration | No neutral primitive suite, repeated samples, unit-transform proof, registration report, color report, or motion timestamp noise floor exists. | `HAR-006`, `HAR-008`, `HAR-019` | Build neutral calibration without using Halo divergence; freeze versioned profiles before styling. |
| HP-0B-002 | P0 | all | Masks | None of the six required versioned masks exists; edge core and bloom cannot be scored independently. | `HAR-007` | Create and review lossless masks in registered coordinates. |
| HP-0B-003 | P0 | reference captures | Capture provenance | The in-app browser is available and was used, but its screenshot API returned JPEG bytes. PNG crops derived from those JPEGs are not lossless canonical captures. | `file iab-reference-viewport-*.jpg`; hashes in evidence bundle | Establish a lossless in-app-browser capture path or record this as an unresolved capture-tool blocker; never label a JPEG transcode lossless. |
| HP-0C-001 | P0 | all | Evidence bundle | No registered reference/native comparison, overlay, heatmap, hard-invariant report, or five-dimension baseline exists. | `HAR-001`, `HAR-009`, `HAR-015` | Complete Gates 0A and 0B, then produce the failing baseline bundle. |
| HP-0C-002 | P0 | all Halo snapshots | Visual regression | Halo has no PNG goldens; 26 missing-golden failures are expected. Snapshot surfaces do not render the exact live Halo closed/open composition. | `NAT-001`–`NAT-004`; `HAR-002`, `HAR-003` | Do not record goldens before Gate 7. Fix harness composition and fail/quarantine environment mismatch. |
| HP-0C-003 | P0 | all motion | Motion | There is no timestamped 60fps normal-motion capture/report pipeline. | `NAT-005`; `HAR-004`, `HAR-012` | Add frame-zero, timestamps, dropped/duplicate detection, silhouette, light-path, envelope, and optical-flow reports. |
| HP-0C-004 | P1 | smoke matrix | Harness | Retained smoke reports reference missing PNGs and stale worktree paths; validator tests expect nonexistent fixtures; `closedAttention` is omitted. | `HAR-009`, `HAR-010`, `HAR-018`, `HAR-022`; `NAT-021` | Make evidence self-contained and add a separate Halo manifest runner. |
| HP-0C-005 | P1 | snapshots | Harness | Snapshot helper documentation is imprecise about Reduce Motion; sidecar files are unhandled SwiftPM resources. | `HAR-016`, `HAR-017` | State the actual frozen/model-layer mechanism and handle sidecars explicitly. |
| HP-0C-006 | P1 | all | Review | No signed cross-renderer/human saliency review exists and source authority is dirty/untracked. | `HAR-020`, `HAR-021` | Preserve exact hashes/dirty state now; require signed review on the eventual candidate commit. |

## Source-audit ambiguity disposition

`REF-006`, `REF-007`, `REF-008`, `REF-009`, `REF-012`, `REF-013`, `REF-015`, `REF-023`, and `REF-024` are frozen by the authored Gate 0A authority for reproduction only. None is silently interpreted as a visual-parity pass or accepted product styling.

## Anti-random-fix hold

No product visual file was edited in this run. Every later edit must cite one or more ledger IDs, affected scenarios, target regions, intended metric, and predicted effect.
