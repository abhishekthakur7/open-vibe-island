# Open Island

Open Island is a native, local-only macOS companion for AI coding agents. It
lives in the notch or top bar, displays local agent-session state, and can
return focus to a supported local terminal session. It has no account, server,
telemetry, updater, relay, remote runtime, or distribution service.

Open Island observes and controls only the software and files it owns. A
focused terminal or agent remains an independent application: its own network
traffic, credentials, transcripts, and permissions are not Open Island traffic
or storage.

## Install

One command builds the release bundle and installs it to `/Applications`
(sudo is required to write there; the copy replaces any previous install):

```bash
zsh scripts/package-local-app.sh && sudo rm -rf "/Applications/Open Island.app" && sudo ditto "output/local-package/Open Island.app" "/Applications/Open Island.app"
```

## Requirements

- macOS 14+
- Swift 6.2 (Xcode)

## Build and verify locally

The package has no third-party SwiftPM dependencies. These commands build only
the current checkout; use an outer network-denial environment when verification
must prove offline execution.

```bash
swift build
swift test
swift run OpenIslandApp
zsh scripts/harness.sh ci
```

`swift run OpenIslandApp` is the canonical development runtime. Opening
`Package.swift` in Xcode and selecting `OpenIslandApp` is equivalent for
interactive development.

## Local app bundles

The only packaging workflow is:

```bash
zsh scripts/package-local-app.sh
```

It produces `output/local-package/Open Island.app` and
`output/local-package/Open Island.zip` from the checkout. It uses a local
identity when available (otherwise ad-hoc signing) and never uploads,
notarizes, publishes, checks for updates, or contacts a service. Replacing an
installed local copy is a deliberate manual action.

For a refreshable development bundle, use:

```bash
zsh scripts/launch-dev-app.sh
```

This rebuilds and refreshes `~/Applications/Open Island Dev.app` before
launching it. For stable Accessibility and Automation grants during repeated
manual verification, first create the local signing identity:

```bash
zsh scripts/setup-dev-signing.sh
```

That command creates a self-signed identity in the current login keychain; it
does not contact an Apple or Open Island service. See
[docs/packaging.md](docs/packaging.md) before using either workflow.

## First launch and integrations

Session discovery reads supported local agent data and starts the private local
bridge. Hook installation is opt-in in Settings: it previews every target and
does not change ambiguous or user-owned configuration. See
[docs/hooks.md](docs/hooks.md) for consent, recovery, and uninstall behavior.

## More

[docs/index.md](docs/index.md) is the documentation map. The privacy,
data-lifecycle, architecture, and local security boundaries are documented
there in detail.
