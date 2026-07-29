# Local Data Lifecycle

This is the implementation contract for Open Island's local stores. A store
may not add a field without adding it to this matrix. “Clear History” means
the Settings action; it does not alter preferences, integrations, Keychain
items, source-agent files, or hook backups.

| Store and exact path | Persisted fields and collection trigger | Purpose and protection | Retention and deletion | Migration, Clear History, owner |
| --- | --- | --- | --- | --- |
| Session metadata: `~/Library/Application Support/open-island/session-terminals.json`, `claude-session-registry.json`, `opencode-session-registry.json`, and `cursor-session-registry.json` | `schemaVersion` (`1`), `sessionID`, `origin`, `attachmentState`, `phase`, `outcome`, `updatedAt`; Claude additionally has `firstSeenAt`. Written after local session-state changes. No title, summary, transcript path/text, command, workspace, terminal, payload, or token field persists. | Recover a recent local session’s tool-neutral state. The directory is `0700`; each file is `0600`. | `updatedAt` starts a 30-day clock. Expired rows are dropped on every load and write. Clear History deletes all four files. | Legacy JSON is read once, projected to this schema, and overwritten; absent legacy fields default safely and discarded content is never reconstructed. Owner: `CodexSessionStore` and the three registries. |
| Transcript/event content | No app-owned transcript or event-content store exists. Source-agent transcript files are read in place and are never copied by this product. | Visible current-session state is memory-only. | In-memory content ends with the process; any future app-owned content store must use `0700/0600`, a maximum 7-day clock, and Clear History deletion. | No migration. Clear History does not delete files owned by Codex, Claude, Cursor, or OpenCode. Owner: discovery readers. |
| App-owned logs | No production file log is maintained. `NSLog` is not an app-owned retention store; deterministic harness artifacts are test output supplied by the caller. | Production diagnostics must contain only operation/category/error-code information: never command bodies, transcript text, tokens, full paths, environments, or payloads. | Harness output is not retained by the application. Any future app-owned log must be `0600`, rotate/delete at 7 days, and be eligible for Clear History. | No migration. Owner: runtime diagnostics. |
| IPC Keychain bootstrap | Login Keychain generic-password item service `app.openisland.local.bridge.bootstrap.v2`; account is bridge role and value is a random 32-byte secret. No event/session content is stored. Created or rotated only for managed bridge roles. | Keychain ACL limits access to the signed app/helper; `AfterFirstUnlockThisDeviceOnly`. | Exists only while its managed integration remains enabled. Clear History preserves it. Reset Integrations revokes every non-observer bridge role. | No disk migration or fallback. Owner: `KeychainBridgeBootstrapStore`. |
| Socket and replay state | `~/Library/Application Support/OpenIsland/bridge.sock` has no serialized payload. Challenge/replay/capability state contains nonce/token, role, and protocol expiry only and is memory-only. `rate-limits.json` is a separate minimized cache. | Bridge directory/socket protections are enforced by bridge security; no transcript or command body belongs here. | Socket is removed/recreated at launch; replay/capability state expires at the protocol maximum. | Stale filesystem state is removed by bridge startup. Owner: bridge transport/server. |
| Cache: Claude rate limits | `~/Library/Application Support/OpenIsland/rate-limits.json` holds only rate-limit window percentages and reset times, written by the opted-in Claude status-line integration. | UI usage display; no prompt, command, environment, transcript, or token-count history. | A cache is valid for at most 7 days; expired cache is ignored/deleted. Clear History deletes it. | Legacy `/tmp` caches are read only for migration and never rewritten there. Owner: `ClaudeUsageLoader`. |
| Preferences | UserDefaults feature settings: display, theme, language, notification/sound, hotkey, launch-at-login, and managed-hook intent/migration keys. | Feature configuration only; no session content or IPC secret. | Kept until changed. Clear History excludes them. Reset Integrations removes managed-hook intent/migration keys only. | Defaults tolerate missing values. Owner: `AppModel`, `LanguageManager`, and `AgentIntentStore`. |
| Hook backups | Source-tool configuration siblings named `<managed-target>.backup.open-island` (for example under `~/.claude`, `~/.codex`, `~/.cursor`, `~/.gemini`, `~/.kimi`, or `~/.config/opencode`). Legacy `<managed-target>.backup.<timestamp>` siblings made by earlier Open Island versions are pruned during managed status/mutation checks. | Reversible managed-hook mutation; may contain source-tool configuration. They are not application history. | Exactly one regular, non-symlink backup per managed target, mode `0600`; a status/mutation check removes expired backups strictly older than 30 days, and successful uninstall/restore removes them immediately. Clear History excludes them. | Managed by hook installers; no content is copied into application storage. Owner: `ManagedHookBackupLifecycle`. |
| Shared hook helper | `~/Library/Application Support/OpenIsland/bin/OpenIslandHooks` and adjacent `.OpenIslandHooks.open-island-provenance.json` | Manifest-verified helper shared by managed agent integrations; the helper has the manifest mode and its provenance is `0600`. The sidecar contains only canonical path, artifact identity/version/digest/mode/marker/template version, installed/prior digests, backup identity, and generation. | Individual integration uninstall retains this shared helper. Reset Integrations removes helper and sidecar only after all manager uninstalls and bridge credential revocation, and only with exact verified provenance. Clear History excludes it. | No migration: missing or invalid evidence is ambiguity and remains untouched. Owner: `ManagedHooksBinary`. |

## User controls

- **Clear History** deletes Open Island session metadata and eligible local
  caches/logs. It preserves preferences, source-agent transcripts, hook backups,
  installed integrations, and Keychain credentials.
- **Reset Integrations** first presents one aggregate, one-shot consent record
  covering every manager target, backup, journal, provenance sidecar, current
  ownership outcome, intent key, credential role, and the shared helper. Any
  unsafe, ambiguous, or unresolved member blocks the whole reset before its
  first mutation. Immediately before execution every member is re-observed;
  a changed target, sidecar, artifact identity, or outcome aborts the whole
  reset. Exact manager uninstall/restore runs in the displayed order, then
  managed intent is cleared, all non-observer bridge roles are revoked, and the
  exact verified shared helper is removed last. Runtime interruption leaves the
  existing manager journal/verified backup recovery path intact. It does not
  delete session history or unrelated configuration.

## Local recovery boundary

At launch the bridge removes and recreates only its verified app-owned stale
socket state; it does not follow symlinks or delete an unsafe path. Expired
registry/cache rows are discarded under their retention clock. Hook recovery is
separate from history: Settings status is read-only, and a hook journal can
only complete a verified target write or restore its matching verified backup.
An ambiguous, unmanaged, or tampered source-tool file remains untouched and
receives remediation rather than an automatic repair.
