# Hook System

OpenIsland receives hook events from AI agents (Codex / Claude Code / Gemini CLI) via the bundled `OpenIslandHooks` CLI. The helper uses only the fixed private socket at `~/Library/Application Support/OpenIsland/bridge.sock`; environment socket redirects and legacy temporary sockets are not supported. Every privileged connection must provide the kernel-reported peer PID, match the bundled helper’s designated code-signature requirement, and authenticate as `hook-event-submit` with role-specific Keychain bootstrap material. A missing PID, unavailable signature, or invalid proof is denied. The helper then forwards payloads to the app and, when necessary, writes a directive back to stdout so the agent can act on it (e.g. block a tool call).

Bridge bootstrap material is Keychain-only: the bridge intentionally creates no
bootstrap or replay-state files beside `bridge.sock`. Replay and capability
state exist only in memory for their bounded handshake/capability lifetimes.
Each Keychain item has an explicit macOS trusted-application ACL for the
running Open Island app and a fixed, audited OpenIslandHooks helper candidate;
ACL creation fails closed. `local-status-read` can register only as itself,
while the app-control capability can register an observer stream and issue
user-control operations. The wire-only `observer` role is never authenticated.

## Architecture

```

Agent (Codex / Claude Code / Gemini CLI)
  │  stdin: JSON payload
  ▼
Bundled OpenIslandHooks CLI  (fixed hook-event-submit role; --source codex | --source claude | --source gemini)
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

## Installation safety and consent

Hook installation and helper replacement are explicit, per-integration actions.
Before an install, Setup shows the target configuration path, local bundled
source, modes (`0600` for configuration and recovery material; `0755` for the
helper), and the managed hook changes. The bulk installer intentionally does
not make changes: review each integration first.

The versioned bundled OpenCode plugin is accepted only after its signed bundle
manifest entry (artifact ID, version, path, mode, and SHA-256) and the
build-pinned resource identity verify; a caller cannot authorize arbitrary
JavaScript by supplying a runtime hash. The manager records private `0600`
provenance beside both `config.json` and the plugin target, including canonical
target path, manager ID, exact entry/pre/post digests, backup identity, and
resource artifact identity. Status and idempotence require both target bytes
and both sidecars to agree exactly. Open Island validates every existing target
path component without following symlinks; directories must be owned by the
current user or root and may not be group- or world-writable. A target must be
a current-user-owned, singly linked regular file. A custom, partially managed,
marker-mismatched, stale-path, or otherwise ambiguous target is left unchanged
with local remediation guidance.

Replacement uses a private same-directory temporary file, write/fsync,
digest/type/owner verification, rename, and directory fsync. A private journal
records the intended and prior digests plus the verified backup identity; an
interruption is completed only when the intended digest is present or restored
only from that verified backup. Otherwise the state remains an explicit local
ambiguity. Managed configuration backups and their provenance records are
private `0600` siblings, retained for at most 30 days; Open Island never
overwrites or removes an unverified backup. Uninstall revokes the managed hook credential
and restores or removes only verified managed state.

### Noninteractive outcomes and ownership rules

`OpenIslandSetup` is intentionally non-mutating: `install`, `installClaude`,
and `installKimi` exit with `consentRequired` instead of changing a target.
Settings first shows the verified source, exact paths, modes, managed changes,
backup/journal/provenance paths, and wrapper/restoration state; only its
explicit confirmation may mutate. The confirmation is an in-memory,
single-use, short-lived token bound to a no-follow snapshot of every target,
backup, journal, and provenance sidecar (canonical path, type, owner, links,
mode, bytes, provenance generation, and manager outcome). Immediately before
the mutation, Settings re-verifies the artifact and takes the snapshot again;
any change—including a deletion, symlink substitution, mode change, or source
replacement—invalidates consent and leaves every target untouched.
`OpenIslandSetup` writes an outcome token
and remediation to stderr when a hook-management request cannot be completed.
Its stable exit statuses are:

| Outcome | Exit status | Remediation |
|---|---:|---|
| `success` / `noChange` / `exactManaged` / `unowned` | 0 | No action required. |
| `consentRequired` | 20 | Explicit confirmation is required. A source version/digest preview remains a merge blocker until it is shown by Settings. |
| `unsafePath` | 21 | Repair the path so every component is a non-symlink, current-user or root-owned directory that is not group/world writable. |
| `unverifiedArtifact` | 22 | Refresh `Open Island Dev.app` with `zsh scripts/launch-dev-app.sh`, then retry from Settings. |
| `ambiguousUnmanaged` | 23 | Existing bytes were not changed. Inspect or remove the ambiguous managed-looking content manually, then retry. |
| `unresolvedRecovery` | 24 | Existing bytes, journal, and backup were not changed. Inspect and resolve the journal/verified backup manually, then retry. |
| `ioFailure` | 25 | Inspection could not safely read local state. Check filesystem availability and permissions, then retry; target, backup, journal, provenance, and helper remain unchanged. |

Every status surface uses the same structured mapping: `family`, `outcomeCode`,
`exitCode`, and `remediation`. The command output for each `status` command is
a deterministic, sorted-key JSON object containing those fields, and exits with
that object’s `exitCode`. Families are deliberately distinct even when they
share a manager: `claude`, `qoder`, `qwen-code`, `factory-droid`, `codebuddy`,
`codex-cli`, `cursor`, `gemini`, `kimi`, `opencode-config`, `opencode-plugin`,
`claude-status-line`, and `shared-helper`. Partial, stale, and tampered
provenance are all `ambiguousUnmanaged`: the content is not ownership proof and
the supplied remediation remains the exact one shown by health, Settings, and
the CLI.

Status is read-only: it does not prune backups, remove journals, or attempt a
restore. The ownership rule for a mergeable hook manager is exact: all current
manager evidence must agree with the expected command/source/event/format, or
for OpenCode the exact config reference plus the plugin and config provenance.
A marker substring, filename suffix, partial group, stale manifest, different
plugin path, or additional conflicting managed-looking entry is ambiguous and
must remain byte-for-byte unchanged.

The shared Claude-family manager applies this rule independently to Claude,
Qoder, Qwen Code, Factory/Droid, and CodeBuddy: every family uses its own
`--source` command and `claude-hooks:<source>` provenance identity, even though
they share the same settings format and helper artifact.

### Bundled artifact provenance

`package-local-app.sh` and `launch-dev-app.sh` generate
`Contents/Resources/OpenIslandArtifacts.json` after copying final helper and
resource bytes and before signing the enclosing app. The deterministic manifest
records an artifact ID, format/version, bundle-relative path, SHA-256, expected
mode, and marker/template version for `OpenIslandHooks` and every static
resource. Installation accepts the helper only from
`Contents/Helpers/OpenIslandHooks` in a bundle whose manifest entry and bytes
match. It never falls back to an environment override, current working tree, or
`.build` product. A direct `swift run OpenIslandApp` therefore cannot install
hooks; refresh `~/Applications/Open Island Dev.app` with
`zsh scripts/launch-dev-app.sh` and retry from Settings.

The OpenCode plugin is read only after the same manifest check. Its config
entry and plugin are removed only after their exact verified provenance
matches; successful removal also deletes verified sidecars/backups and revokes
the manager-owned hook credential. Generated configuration and Claude
status-line scripts are dynamic because they include current user paths. Before
creating any target, Open Island loads normal, wrapper, and delegate templates
only from their signed manifest entries in
`Contents/Resources/ClaudeStatusLineTemplates/`; marker, template version,
SHA-256, mode, and the exact placeholder contract are verified before
shell-quoted local paths and preserved commands are interpolated. The final
destination digest is checked by the descriptor-anchored atomic writer. The settings target, managed wrapper, and wrapper delegate each receive
an adjacent `0600` provenance record containing their canonical path,
manager/template identity, exact command or script digest, pre/post mutation
digests, and verified backup identity. Status is read-only: a marker, canonical
command path, copied script, missing sidecar, stale template, or recovery
journal is reported as ambiguity or unresolved recovery and remains
byte-for-byte untouched. Uninstall restores original settings only from the
matching verified backup, then removes verified sidecars and backup evidence.

The installed shared helper at `~/Library/Application Support/OpenIsland/bin/OpenIslandHooks`
also has its own adjacent private (`0600`) provenance record. It records the
canonical destination, artifact ID/version/SHA-256/mode/marker/template version,
installed digest, generation, and prior digest. An explicit install is
idempotent only when helper bytes, mode, and that record all match the current
manifest-verified artifact; a missing, stale, tampered, linked, or unmanaged
destination is reported as `ambiguousUnmanaged` and left untouched. Status and
health checks only inspect this evidence; they never update the helper. Regular
integration uninstall retains the helper because it is shared. **Reset
Integrations** removes it only after every manager uninstall and bridge
credential revocation, and only when that exact helper provenance still verifies.

**Fail-open principle**: if the bridge is unavailable the hook process exits silently without writing to stdout, so the agent continues running unaffected.

## Skip Hooks For Delegated Control

Set `OPEN_ISLAND_SKIP_HOOKS=1` on a child agent process when another local controller intentionally owns permission handling for that run. The hook CLI exits immediately without reading or forwarding the payload, so the agent continues without Open Island UI intervention.

`VIBE_ISLAND_SKIP=1` is also recognized as a legacy compatibility alias.

This is meant for per-process launches. Do not set it globally unless you want Open Island hooks disabled for every agent started from that environment.

**Entry point**: [`Sources/OpenIslandHooks/main.swift`](../Sources/OpenIslandHooks/main.swift)

---

## Codex Hooks (`--source codex`)

**Payload type**: `CodexHookPayload`  
**Source**: [`Sources/OpenIslandCore/CodexHooks.swift`](../Sources/OpenIslandCore/CodexHooks.swift)

### Events

| `hook_event_name` | When it fires | Notable fields |
|---|---|---|
| `SessionStart` | Session starts or resumes (`source: "resume"` on resume) | `prompt`, `source` |
| `PreToolUse` | Before a shell command executes | `tool_name`, `tool_input.command`, `turn_id`, `tool_use_id` |
| `PermissionRequest` | Codex requests permission for a tool/action | `tool_name`, `tool_input`, `turn_id` |
| `PostToolUse` | After a shell command completes | `tool_name`, `tool_input`, `tool_response`, `turn_id` |
| `UserPromptSubmit` | User submits a new prompt | `prompt` |
| `Stop` | A turn completes | `last_assistant_message`, `stop_hook_active` |

### Default managed installation

The managed Codex hook installer (`CodexHookInstaller`) installs `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, and `Stop` by default. This keeps the lifecycle hooks low-noise while still allowing OpenIsland to broker Codex's first-class approval requests. Per-command `PreToolUse` / `PostToolUse` hooks remain opt-in because they can add terminal log noise.

The installer chooses the Codex hook feature flag that the local Codex CLI advertises. Newer Codex builds use `[features].hooks = true`; older builds use the legacy `[features].codex_hooks = true`. Status checks recognize both keys, and managed installs migrate between them when the local Codex version changes.

After hooks are installed or changed, Codex may require a manual trust review before running them. Open `/hooks` inside Codex CLI and approve the expected Open Island hook entries. This approval gate belongs to Codex and is not bypassed by Open Island.

The `CodexHookPayload` model and `BridgeServer` can parse richer events (`PreToolUse`, `PostToolUse`) when they are present in the hook payload, and will surface them in the UI if received. However, these per-tool lifecycle events are **not** installed by the managed installer and must be configured manually if desired.

> **Note on file-edit coverage**: Codex file edits may use internal apply-patch paths that do not emit `PreToolUse` events. File-edit approval should not be treated as guaranteed `PreToolUse` coverage; the current reliable coverage is command/shell-level events, depending on Codex hook configuration.

### Common payload fields

| JSON key | Swift property | Description |
|---|---|---|
| `cwd` | `cwd` | Working directory |
| `hook_event_name` | `hookEventName` | Event type |
| `session_id` | `sessionID` | Session UUID |
| `model` | `model` | Model name |
| `permission_mode` | `permissionMode` | `default` / `acceptEdits` / `plan` / `dontAsk` / `bypassPermissions` |
| `transcript_path` | `transcriptPath` | JSONL transcript file path |
| `terminal_app` | `terminalApp` | Terminal name (`Terminal`, `Ghostty`, `iTerm`, …) |
| `terminal_session_id` | `terminalSessionID` | Terminal session identifier |
| `terminal_tty` | `terminalTTY` | TTY device path |
| `terminal_title` | `terminalTitle` | Tab / window title |
| `turn_id` | `turnID` | Current turn ID |
| `tool_name` | `toolName` | Tool name (e.g. `shell`) |
| `tool_use_id` | `toolUseID` | Tool-use call ID |
| `tool_input` | `toolInput` | Tool input (commonly includes `command` and/or `description`) |
| `tool_response` | `toolResponse` | Tool output (JSON) |
| `prompt` | `prompt` | User prompt text |
| `last_assistant_message` | `lastAssistantMessage` | Last assistant message |
| `stop_hook_active` | `stopHookActive` | Whether the stop hook is active |

### Directive responses

#### `PreToolUse`

The app can block a command by writing this to stdout:

```json
{"decision": "block", "reason": "Blocked by Open Island"}
```

#### `PermissionRequest`

The managed `PermissionRequest` hook has a 1-hour timeout so the user can approve or deny from the UI.

Allow:

```json
{
  "continue": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow"
    }
  }
}
```

Deny:

```json
{
  "continue": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "User denied the permission request"
    }
  }
}
```

All other Codex events require no stdout response.

---

## Claude Code Hooks (`--source claude`)

**Payload type**: `ClaudeHookPayload`  
**Source**: [`Sources/OpenIslandCore/ClaudeHooks.swift`](../Sources/OpenIslandCore/ClaudeHooks.swift)

### Events

| `hook_event_name` | When it fires | Directive response |
|---|---|---|
| `SessionStart` | Session starts (`startup` / `resume` / `clear` / `compact`) | None |
| `SessionEnd` | Session ends | None |
| `UserPromptSubmit` | User submits a prompt | None |
| `PreToolUse` | Before a tool call | **Yes** — allow / deny / modify input |
| `PostToolUse` | After a successful tool call | None |
| `PostToolUseFailure` | After a failed tool call | None |
| `PermissionRequest` | Agent requests user approval | **Yes** — allow or deny (24 h timeout) |
| `PermissionDenied` | A permission was denied | None |
| `Notification` | Agent emits a notification | None |
| `Stop` | Turn ends normally | None |
| `StopFailure` | Turn ends with an error | None |
| `SubagentStart` | A sub-agent starts | None |
| `SubagentStop` | A sub-agent stops | None |
| `PreCompact` | Before context compaction | None |

### Common payload fields

| JSON key | Swift property | Description |
|---|---|---|
| `cwd` | `cwd` | Working directory |
| `hook_event_name` | `hookEventName` | Event type |
| `session_id` | `sessionID` | Session UUID |
| `transcript_path` | `transcriptPath` | JSONL transcript file path |
| `permission_mode` | `permissionMode` | Permission mode |
| `model` | `model` | Model name |
| `agent_id` | `agentID` | Sub-agent ID (SubagentStart/Stop) |
| `agent_type` | `agentType` | Sub-agent type |
| `source` | `source` | Start source (`startup` / `resume` / `clear` / `compact`) |
| `tool_name` | `toolName` | Tool name |
| `tool_input` | `toolInput` | Tool input parameters (JSON) |
| `tool_use_id` | `toolUseID` | Tool-use call ID |
| `tool_response` | `toolResponse` | Tool output (JSON) |
| `permission_suggestions` | `permissionSuggestions` | Suggested permission changes (PermissionRequest) |
| `prompt` | `prompt` | User prompt text |
| `message` | `message` | Notification message body |
| `title` | `title` | Notification title |
| `notification_type` | `notificationType` | Notification type |
| `stop_hook_active` | `stopHookActive` | Whether the stop hook is active |
| `last_assistant_message` | `lastAssistantMessage` | Last assistant message |
| `error` | `error` | Error message (Failure events) |
| `error_details` | `errorDetails` | Extended error details |
| `is_interrupt` | `isInterrupt` | Whether the event is an interrupt |
| `agent_transcript_path` | `agentTranscriptPath` | Sub-agent transcript path |
| `terminal_app` | `terminalApp` | Terminal name |
| `terminal_session_id` | `terminalSessionID` | Terminal session identifier |
| `terminal_tty` | `terminalTTY` | TTY device path |
| `terminal_title` | `terminalTitle` | Tab / window title |

### PreToolUse directive response

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow" | "deny" | "ask",
    "permissionDecisionReason": "reason shown to the agent",
    "updatedInput": { ... },
    "additionalContext": "extra context injected into the turn"
  }
}
```

| Field | Description |
|---|---|
| `permissionDecision` | `allow` — proceed; `deny` — block; `ask` — let the agent ask the user |
| `permissionDecisionReason` | Human-readable reason forwarded to the agent |
| `updatedInput` | Replace the tool's input parameters (optional) |
| `additionalContext` | Inject additional context into the turn (optional) |

### PermissionRequest directive response

The `PermissionRequest` event has a **24-hour timeout** to allow the user to review and approve in the UI.

Allow:

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedInput": { ... },
      "updatedPermissions": [ ... ]
    }
  }
}
```

Deny:

```json
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "User denied the permission request",
      "interrupt": false
    }
  }
}
```

Setting `interrupt: true` terminates the current agent turn immediately.

---

## Gemini CLI Hooks (`--source gemini`)

**Payload type**: `GeminiHookPayload`  
**Source**: [`Sources/OpenIslandCore/GeminiHooks.swift`](../Sources/OpenIslandCore/GeminiHooks.swift)

### Events

| `hook_event_name` | When it fires | Current OpenIsland behavior |
|---|---|---|
| `SessionStart` | Session starts or resumes | Creates or restores the Gemini session, title, jump target, and transcript metadata |
| `BeforeAgent` | Gemini starts handling a prompt / turn | Marks the session running, updates prompt text, refreshes terminal metadata |
| `AfterAgent` | Gemini finishes a turn | Marks the turn completed and emits a completion card |
| `SessionEnd` | Gemini reports the session ended | Marks the hook-managed session ended and removes it from active visibility |
| `Notification` | Gemini emits a notification message | Updates the session summary / activity text without blocking the agent |

### Common payload fields

| JSON key | Swift property | Description |
|---|---|---|
| `cwd` | `cwd` | Working directory |
| `hook_event_name` | `hookEventName` | Event type |
| `session_id` | `sessionID` | Session identifier |
| `transcript_path` | `transcriptPath` | Gemini transcript file path |
| `timestamp` | `timestamp` | Hook timestamp |
| `prompt` | `prompt` | User prompt text |
| `prompt_response` | `promptResponse` | Gemini response text |
| `source` | `source` | Session start source |
| `reason` | `reason` | Session-end reason |
| `notification_type` | `notificationType` | Notification category |
| `message` | `message` | Notification message |
| `details` | `details` | Structured notification payload |
| `stop_hook_active` | `stopHookActive` | Whether Gemini stop hook support is active |
| `terminal_app` | `terminalApp` | Terminal name |
| `terminal_session_id` | `terminalSessionID` | Terminal session identifier |
| `terminal_tty` | `terminalTTY` | TTY device path |
| `terminal_title` | `terminalTitle` | Tab / window title |

### Current feature coverage

- Session lifecycle ingestion for Gemini CLI via `OpenIslandHooks --source gemini`
- Session list and island visibility updates from Gemini hook events
- Prompt / response metadata capture for completion cards and session details
- Terminal jump metadata enrichment for Terminal.app, iTerm2, Ghostty, and other supported terminals
- Process-assisted liveness matching so active Gemini CLI sessions can stay visible even when hook traffic is sparse

### Current limitations

- Gemini hooks are currently treated as fire-and-forget. OpenIsland does not send Gemini-specific approval or modification directives back to stdout.
- Gemini hook payloads sometimes include a duplicated copy of the final response body, often with whitespace-only differences. OpenIsland applies a best-effort compatibility pass before rendering completion content, but the result is not guaranteed to be perfect for every response shape.
- Gemini support is currently limited to the hook events and UI/session behaviors listed above. It does not yet match the richer permission / interaction flows available for Claude Code or OpenCode.

---

## Timeout Policy

| Source | Event | Timeout |
|---|---|---|
| Codex | `PermissionRequest` | **1 hour** (awaits human approval) |
| Codex | All other managed events | **45 seconds** |
| Claude Code | `PermissionRequest` | **24 hours** (awaits human approval) |
| Claude Code | All other events | **45 seconds** |
| Gemini CLI | All events | Bridge default |

---

## Terminal Auto-detection

The hook process infers the terminal type from environment variables at runtime:

| Environment variable | Inferred terminal |
|---|---|
| `ITERM_SESSION_ID` or `LC_TERMINAL=iTerm2` | `iTerm` |
| `CMUX_WORKSPACE_ID` or `CMUX_SOCKET_PATH` | `cmux` |
| `GHOSTTY_RESOURCES_DIR` | `Ghostty` |
| `WARP_IS_LOCAL_SHELL_SESSION` | `Warp` |
| `TERM_PROGRAM=Apple_Terminal` | `Terminal` |
| `TERM_PROGRAM=WezTerm` | `WezTerm` |

For iTerm, Terminal, and Ghostty the process additionally runs an AppleScript query to obtain the session ID, TTY, and window title — used to power the "jump back to terminal" feature. The `cmux` terminal uses `CMUX_SURFACE_ID` instead of AppleScript.

---

## Related source files

| File | Responsibility |
|---|---|
| [`Sources/OpenIslandHooks/main.swift`](../Sources/OpenIslandHooks/main.swift) | Hook CLI entry point — routes to Codex, Claude, or Gemini path |
| [`Sources/OpenIslandCore/CodexHooks.swift`](../Sources/OpenIslandCore/CodexHooks.swift) | Codex payload model, output encoder, terminal detection |
| [`Sources/OpenIslandCore/ClaudeHooks.swift`](../Sources/OpenIslandCore/ClaudeHooks.swift) | Claude Code payload model, directive types, output encoder |
| [`Sources/OpenIslandCore/GeminiHooks.swift`](../Sources/OpenIslandCore/GeminiHooks.swift) | Gemini CLI payload model, terminal detection, metadata helpers |
| [`Sources/OpenIslandCore/BridgeServer.swift`](../Sources/OpenIslandCore/BridgeServer.swift) | Unix socket server — handles incoming hook payloads |
| [`Sources/OpenIslandCore/BridgeTransport.swift`](../Sources/OpenIslandCore/BridgeTransport.swift) | Protocol codec and envelope types |
