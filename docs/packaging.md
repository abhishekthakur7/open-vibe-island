# Local Packaging And Development Signing

Open Island has one offline packaging workflow:

```bash
zsh scripts/package-local-app.sh
```

It builds `OpenIslandApp`, `OpenIslandHooks`, and `OpenIslandSetup` from the
current checkout with automatic SwiftPM resolution disabled. It writes a local
bundle and ZIP under `output/local-package/` (or the explicitly constrained
`OPEN_ISLAND_PACKAGE_ROOT`). The bundle contains the helper binaries and a
signed artifact manifest covering those helpers and static hook resources.

The command performs no upload, notarization, publishing, update-feed work, or
service contact. It is the sole supported package/archive workflow. Install or
replace its output manually; Open Island has no updater or release channel.

## Stable local development bundle

For interactive development, refresh before launch instead of reopening an old
bundle:

```bash
zsh scripts/launch-dev-app.sh
```

This builds the checkout and refreshes `~/Applications/Open Island Dev.app`,
then launches that bundle. The bundle is the only supported source for hook
installation because it contains the manifest-verified helpers; a plain
`swift run OpenIslandApp` build cannot install hooks.

For work that requires Accessibility or Automation permissions, create the
stable local signing identity once before repeated manual tests:

```bash
zsh scripts/setup-dev-signing.sh
```

The script creates the self-signed `Open Island Dev Local` identity in the
current user’s login keychain and configures it for local code signing. It does
not use a developer account or contact an external service. A stable identity
keeps macOS TCC grants associated with the bundle across refreshes; ad-hoc
signing remains a fallback but can require re-granting those permissions after
each rebuild. Creating a new keychain identity is a user-authorized,
state-changing action; inspect with `security find-identity -p codesigning -v`
when setup is not desired.

## Local inspection and recovery

`package-local-app.sh` verifies the bundle signature and runs the no-network
bundle policy before it creates the ZIP. To inspect a completed bundle again:

```bash
codesign -d --entitlements :- "output/local-package/Open Island.app"
python3 scripts/verify-no-network-policy.py --bundle "output/local-package/Open Island.app"
```

The script accepts only these local-output customizations:
`OPEN_ISLAND_APP_NAME`, `OPEN_ISLAND_BUNDLE_ID`, `OPEN_ISLAND_VERSION`,
`OPEN_ISLAND_BUILD_NUMBER`, and `OPEN_ISLAND_PACKAGE_ROOT`. It rejects bundle
or ZIP paths outside the selected package root.
