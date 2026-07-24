# Architecture

## System Shape

The project is a single Swift package with four targets:

| Target | Role |
|---|---|
| **OpenIslandApp** | SwiftUI + AppKit shell — menu bar extra, overlay panel (notch/top-bar), settings. Entry point: `OpenIslandApp.swift` with `AppModel` as the central `@Observable` state owner. |
| **OpenIslandCore** | Shared library — models (`AgentSession`, `AgentEvent`, `SessionState`), bridge transport (Unix socket IPC with JSON line protocol), hook models/installers, transcript discovery, session persistence/registry. |
| **OpenIslandHooks** | Lightweight CLI executable invoked by agent hooks. Reads hook payload from stdin, forwards to app bridge via Unix socket, writes blocking JSON to stdout only when island denies a `PreToolUse`. |
| **OpenIslandSetup** | Installer CLI for managing `~/.codex/config.toml` and `hooks.json`. |

## Data Flow

### Hook-based agents (Codex, Claude Code, and forks)

```
Agent
  │  stdin: JSON payload
  ▼
OpenIslandHooks CLI  (--source codex | --source claude | ...)
  │  Unix socket
  ▼
BridgeServer → AppModel → UI
  │  BridgeResponse
  ▼
OpenIslandHooks CLI
  │  stdout: JSON directive (only when a response is needed)
  ▼
Agent
```

### Plugin-based agents (OpenCode)

```
OpenCode → JS plugin (~/.config/opencode/plugins/) → Unix socket → BridgeServer → AppModel → UI
```

### Session discovery (on launch)

1. Restore cached sessions from registry
2. Discover recent JSONL transcripts (`~/.claude/projects/`)
3. Reconcile with active terminal processes
4. Start live bridge

**Fail-open principle**: if the bridge is unavailable, the hook process exits silently without writing to stdout, so the agent continues running unaffected.

## Event Model

The shared `AgentEvent` enum drives all state transitions:

- Session started / updated / completed
- Permission requested
- Question asked
- Tool use (pre/post)
- Subagent lifecycle
- Jump target updated

Each event carries a stable session identifier, agent type, timestamps, and enough metadata to route approvals or focus changes.

## State Management

- `SessionState.apply(_:)` is the single source of truth for session mutations (pure reducer)
- `AppModel` owns all live state and bridge lifecycle
- All models are `Sendable` and `Codable`

## Transport

- Unix domain sockets for app ↔ hook communication
- Newline-delimited JSON envelopes (`BridgeCodec`)
- Bridge server lives inside the app process

## Terminal Jump-Back

Terminal focus restoration is implemented per-terminal:

| Terminal | Strategy |
|---|---|
| Terminal.app | TTY targeting via AppleScript |
| Ghostty | Window ID matching |
| cmux | Unix socket API |
| Kaku | CLI pane targeting |
| WezTerm | CLI pane targeting |
| iTerm2 | AppleScript session/TTY probe |
| tmux (multiplexer) | switch-client → select-window → select-pane |

The hook helper enriches payloads with terminal-local hints (terminal app, TTY, session ID, window title) from environment inspection at hook invocation time.

## Theme system

The island overlay is composed entirely from a swappable **theme**. A theme is
one value conforming to `IslandTheme` (`Sources/OpenIslandApp/Theme/`):

- **Identity** — a stable `id` (persisted, never localized), plus a localized
  `name` / `descriptor` resolved through `lang.t`.
- **`tokens: IslandThemeTokens`** — the colour / metric / motion tokens injected
  into `\.islandTokens` for every descendant surface.
- **Capability flags** — `rowIsDrawingGroupSafe` (gates the row's
  `.drawingGroup()` rasterization) and `usesVibrancy` (gates the opened
  surface's native vibrancy base vs. a flat fill).
- **`agentsGridGeometry`** — the closed-island grid strategy. Classic delegates
  to the `V6RightSlotView` statics, which encode Classic's shape (pinned by
  `AgentsGridLayoutTests`), not a universal invariant.
- **Slot factories** — one factory per overlay slot: `closedPill`,
  `openedHeader`, `sessionRow`, `sessionList`, `notificationCard`, `emptyState`,
  `bootstrapPlaceholder`, `installHint`. Each owns a group of the finer slots it
  renders (e.g. `sessionList` owns the sessions summary, section headers and
  footer; `sessionRow` owns the approval / question / completion bodies; the
  factory doc comment maps the Scope slots it covers).

`IslandPanelView` reads the active theme off the `@Observable` `AppModel`
(`model.islandTheme`), injects it and its tokens into the environment, and
composes the overlay purely from `theme.<slot>(...)` — it never names a concrete
component. Descendant slot components (and `OverlayPanelController`'s panel
sizing) read the theme from the environment / model, so changing the selection
re-renders live with no restart.

### Adding a theme

1. Add a type conforming to `IslandTheme`, returning your slot views and tokens.
2. Append it to `ThemeRegistry.all` (order = picker order; first = default).
3. Add its `theme.<id>.name` / `.descriptor` strings to the three
   `Localizable.strings`.

Nothing in `IslandPanelView` changes. Selection is global (not per display
profile), stored on `AppModel.islandThemeID`, persisted to
`appearance.island.v8.theme`; a missing or unknown id falls back to the registry
default via `ThemeRegistry.theme(id:)`.

### Not theme-swappable (shared invariants)

Themes swap *look*, never *behavior*. The following stay fixed across every
theme, and a new theme must respect them rather than reimplement them:

- **Presentation / display rules** — which session is actionable, the
  attention-is-loudest hierarchy, stale-completed → idle regrouping, notch vs.
  top-bar layout selection, and the AB-282…286 display rules — live in
  `SessionState`, `AgentSession+Presentation`, and the values `AppModel` hands to
  the slot factories, not in the views.
- **`RowActions` wiring** — approve / answer / reply / jump / dismiss are built
  by `AppModel` and passed in; a themed row renders them, it doesn't decide them.
- **Keyboard shortcuts** — registered by the row / question views through the
  `OverlayUICoordinator`, independent of styling.
- **Hover container** — `SessionRowContainer` owns the shared hover-highlight
  state and hit-area; themed rows receive the highlight as a value.
- **Accessibility gates** — Reduce Motion crossfade fallback, Reduce
  Transparency flat ink, Increase Contrast opacities, Dynamic Type scaling, and
  the VoiceOver row/grid summaries are all baked into the shared components and
  tokens; a theme inherits them.

### New-theme surface checklist

A complete theme covers: closed pill (both layouts) / morph + glyph travel +
completion pop / opened chrome (both notch and top-bar profiles) / header +
usage chips + controls / sessions summary + section headers + footer / empty +
bootstrap + install hint / all row states + the four indicator preferences /
approval + question + completion bodies + notification card / Settings previews
(AB-305) / the accessibility fallbacks listed above.

## Technologies

- SwiftUI for most UI composition
- AppKit for panel behavior, status item control, and activation policy edge cases
- Unix domain sockets for IPC
- JSON event envelopes for debugging and adapter simplicity
- Sparkle for auto-updates

## Engineering Rules

- Preserve clean separation between UI state and transport concerns
- Version the event schema so adapters can evolve safely
- Keep setup reversible when editing third-party tool config files
- Keep the runtime surface bound to real agent state rather than shipping UI-level demo toggles
