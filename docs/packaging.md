# Local Packaging

`zsh scripts/package-local-app.sh` builds `OpenIslandApp`,
`OpenIslandHooks`, and `OpenIslandSetup` from the current checkout. It writes a
local bundle and ZIP archive to `output/local-package/` by default.

The bundle embeds the helper binaries in `Contents/Helpers/` and uses a local
development identity named `Open Island Dev Local` when present. Otherwise it
uses ad-hoc signing. Create the stable local identity once with:

```bash
zsh scripts/setup-dev-signing.sh
```

The package and development-launch scripts disable automatic SwiftPM
resolution. They never upload, publish, notarize, generate update metadata, or
contact an update feed; dependencies must already be available locally.

Optional local output overrides are `OPEN_ISLAND_APP_NAME`,
`OPEN_ISLAND_BUNDLE_ID`, `OPEN_ISLAND_VERSION`, `OPEN_ISLAND_BUILD_NUMBER`,
and `OPEN_ISLAND_PACKAGE_ROOT`.
