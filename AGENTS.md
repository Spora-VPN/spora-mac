# Spora macOS client

Native macOS client for Spora (P2P VPN through a trusted friend). Swift + SwiftUI +
NetworkExtension over the Rust core at `../spora` (UniFFI). Functional reference:
`../spora-android`. Design source of truth: `.local/design/Spora macOS.dc.html` (committed
direction: window 1b master-detail + menu-bar popover 1d/2e; see
`.local/docs/adr-001-architecture.md`). Distribution: Mac App Store + Developer ID direct
download from spora.to (`.local/docs/adr-002-distribution.md`).

## Build & run

- `scripts/dev.sh build` — build app (xcodebuild via XcodeGen's `project.yml`).
- `scripts/dev.sh run` / `quit` / `shot [name]` / `state <cmd> [k=v…]` / `log` — the feedback
  harness; screenshots land in `artifacts/` (an open sheet as `<name>-sheet.png`). State-seeding
  vocabulary matches Android's `DebugStateReceiver` (`seed`, `share-starting|started|failed|stopped`,
  `connect-connecting|connected|failed|disconnected`, `reset`; `err=` takes `SHARE_LINK_LOST`,
  `NO_RELAYS`, …). macOS extras (full list in `DebugController.swift`): `settings?page=`,
  `relays?spora=&own=&tokens=` (in memory), `make-failed?err=`, `sheet?name=`, `feedback`,
  `telemetry-required`, and real actions: `create-share`, `toggle`, `make-new-link`, `delete`,
  `export-report`, `telemetry?on=`, `updates?do=check|accept` (the direct build's Sparkle).
- `xcodebuild … -scheme Spora test` runs `SporaKitTests` (relay-address checks, error mapping,
  `SPORA_API` parsing, the store migration, the diagnostics hand-over).
- Rust FFI: `../spora/build-ffi-apple.sh` builds the staticlib + Swift bindings into
  `rust-out/` here (gitignored: rebuild it after pulling the core). Rust changes are made in
  `../spora` (its own repo — commit separately).
- Core pin: `.github/core-ref` names the core commit CI builds against (sibling checkout,
  `.github/workflows/ci.yml`: unsigned Debug + Release builds and `SporaKitTests`). A local
  build uses whatever `../spora` has checked out, so it can pass on core changes CI does not
  have yet. Bump the pin to a pushed core commit in the change that needs it.
- Bundle ids: `to.spora.macos` (the app) and `to.spora.macos.tunnel` (the tunnel, in both
  packagings). `to.spora.mac` is registered to another team: don't go back to it. Once a
  release ships, they never change (the extension's replacement, the VPN configuration and
  the Keychain items all key on them).
- Signing: the repo names no team. `scripts/dev.sh build` is unsigned unless
  `DEVELOPMENT_TEAM=<team ID>` is set (environment or argument; then automatic signing with
  `-allowProvisioningUpdates`); other arguments go to xcodebuild. An unsigned build runs all
  but the tunnel extension (the window, the menu bar, shares): its app group is empty, so
  records and the log go to Application Support/Spora (`SporaPaths.appGroup` ignores an
  unprefixed group too), and `SecretStore` falls back to 0600 files where the Keychain would
  prompt. The tunnel extension needs a paid team (NetworkExtension). Never commit a team ID.
- **Direct download build** (ADR-002): the `SporaDirect` target is the same app with
  `SPORA_DIRECT` set, embedding the tunnel as a system extension (`SporaTunnelSysExt`: the
  `Tunnel/` sources plus `TunnelSystemExtension/`, its own SporaKit copy, bundle named after
  its id) instead of the appex. Before each connect it activates the extension
  (`ExtensionActivator`); the first time, macOS waits for the user to allow it, and
  `ApproveExtensionSheet` shows how. `scripts/dev.sh --direct build` signs it with Developer
  ID (manual signing: `DEVELOPMENT_TEAM`, the profiles named by `SPORA_PROFILE_APP` /
  `SPORA_PROFILE_TUNNEL`, a fresh build number so sysextd replaces the extension), then
  `--direct notarize` (sysextd refuses an extension Apple has not notarized, a local test
  build too; keychain profile `SPORA_NOTARY_PROFILE`), `--direct install` (to
  /Applications, the only place macOS activates it from), `--direct run`. Signing and
  notarizing need the login keychain: over SSH, run them in the logged-in user's session
  (`sudo launchctl asuser <uid> sudo -u <user> …`). Test with Debug only: a Release build
  talks to production.
- **Updates (direct build)**: Sparkle 2 (SPM, exact version in `project.yml`), linked into
  `SporaDirect` only: the App Store forbids self-updaters, and CI fails an App Store build
  that has it. `Updater` (started at launch) checks daily without asking and asks before
  it installs (Sparkle's window); Check for Updates… sits in the app menu. Its keys are in
  `App/SporaDirect-Info.plist`, which is `App/Info.plist` plus Sparkle's keys: change both
  (CI compares them). The feed is `SPORA_UPDATE_FEED` (`project.yml`): Release
  `https://spora.to/updates/macos/appcast.xml`; Debug an address that answers nothing, so
  a debug build never asks production. The feed is to move soon to a domain that survives
  a block of spora.to, and every shipped build keeps the URL it was built with. Updates
  carry an EdDSA signature (public half: `SUPublicEDKey`; private half: the build Mac's
  login keychain, from Sparkle's `generate_keys`), and Sparkle installs nothing that fails
  it. The "Sign Sparkle's helpers" script phase signs the executables inside
  Sparkle.framework with the app's identity, the hardened runtime and a timestamp, or
  notarization refuses them. The app has no app sandbox, so Sparkle's XPC services stay
  unused.
- **After an update** the relaunched app replaces the system extension at launch, before
  it reconciles the tunnel (`TunnelManager.replaceOutdatedExtension`): only when macOS has
  the extension enabled at another version than the app's copy (`ExtensionVersion`), so
  never for someone who has not allowed it. A tunnel the old extension runs is stopped and
  started again on the new one. A newer app dragged into /Applications gets the same.
- **Releases** (`scripts/release.sh`, on the build Mac, in a git checkout, in the GUI
  session): refuses a dirty tree and a `../spora` that is dirty or not at
  `.github/core-ref`. Version: `MARKETING_VERSION` in `project.yml`, bumped by hand in the
  commit the release tags; build number: `git rev-list --count HEAD` (dev builds use epoch
  seconds, far above it: a Mac that ran one is never offered a release). It builds the
  core's release library and a universal Release `SporaDirect` signed as `dev.sh --direct
  build` signs, notarizes and staples the app, then a DMG (the app beside a link to
  /Applications), signed, notarized and stapled, signs that for Sparkle, adds its entry to
  `dist/appcast.xml` (keep the published appcast there), and offers the `v<version>` tag.
  It publishes nothing: `Spora-<version>.dmg` and `appcast.xml` go side by side to the
  feed's directory (the appcast names the DMG relative to itself). Ask before publishing.
- **Testing an update** (Debug builds, the lab Mac): build and notarize version N and N+1;
  make N+1's DMG (`hdiutil`, `codesign`, `sign_update`) and an appcast item; serve them
  from the dev machine on the Mac's loopback (`ssh -R`: a LAN address meets macOS's Local
  Network privacy, error -1009) and point the app there (`defaults write to.spora.macos
  SUFeedURL …`, which Sparkle reads before the Info.plist; delete it after). Sparkle
  relaunches the app through LaunchServices, so pin `SPORA_API` there first (`launchctl
  setenv` in the GUI session; unset it after). Install and run N, connect, then `state
  updates do=check` and `state updates do=accept` twice (Install Update, Install and
  Relaunch); `systemextensionsctl list` then shows N+1's extension active.
- For a share without production, run the core's open `relay` locally and seed it as an own
  relay (`state relays spora=0 own=<host:port>`, then `state create-share`).
- **Never contact production from development.** Spora's relays are on by default, so the
  first start registers the Mac with the core's API. Debug builds read `SPORA_API`
  (comma-separated, as the CLI reads it; set but blank is refused, never production); release
  builds always use the built-in production API. `dev.sh run` pins `SPORA_API` to
  `http://127.0.0.1:9` (answers nothing) unless it is set; a debug build launched any other way
  without it talks to production.

## Core service, relays, diagnostics

The core's `spora-service` (via the FFI) holds the device identity, the access to Spora's
relays and the diagnostics; the app wires it up. Android's AGENTS.md ("Relays and shares",
"Diagnostics") is the reference; the macOS specifics:

- **Startup** (`SporaApp.init`): `SporaKit.initLogging()` (the diagnostic log file), crash
  capture (uncaught ObjC exceptions → `writeCrash`), then `ServiceHost` starts the service off
  the main thread (`initService`: state key from the Keychain, minted and saved on the first
  run; `manageRelays` when Spora's relays are on or a saved share uses them). Every share call
  awaits it (`awaitReady`); a failed start is retried on foreground. Only the app runs the
  service.
- **Shares** are the core's: an immutable blob per link (`makeShare` via `ShareMaker`, on the
  relays the settings name), in the Keychain (`SecretStore.shares`); the URL is `shareUrl(blob)`,
  never stored. `startShare` gets a per-share connection log (`connlog/<share id>`) and the
  record dir. Deleting a share keeps its log (the sharer's record of what it was used for), but
  not past its retention: every running share sweeps the others' logs
  (`connLogSweepSiblings: true`, so `connlog/` holds nothing but one directory per share), and
  `SporaApp.init` sweeps them all after `initLogging` (`SporaPaths.sweepConnectionLogs`, the
  core's `sweepConnLogs`). A blob made under another device identity fails with `IdentityMismatch` →
  `shareLinkLost`, whose action is MAKE A NEW LINK (new blob, same id and name). Shares saved
  before this (identity-based, `spora.connections.v1`) are dropped at load.
- **Settings** open in the window's detail region as a page stack (`AppController.settingsPages`):
  the sidebar's SETTINGS / ⌘, opens the list, OPEN SETTINGS under a make error opens Relays
  alone. Relays: Spora's on/off + the user's own relays (checked as the core parses `?r=`;
  tokens sent as `RelayCredential.static`, never in the URL), stored in the Keychain. Telemetry:
  the upload switch; the force notice (`TelemetryRequiredSheet`) has one owner,
  `AppController`. Pages poll the service every 2 s while open.
- **Feedback** (sidebar, Help menu, the force notice): `exportBugReport` zip into
  `~/Library/Caches/to.spora.macos/reports` (pruned after a day), handed to the share picker
  with support@spora.to prefilled for Mail. No Spora server involved.
- **Where things live**: records (`records/`) and the diagnostic log (`diag/`) in the app group
  container `$(DEVELOPMENT_TEAM).to.spora.macos` (`SPORA_APP_GROUP`; none without a team), because the tunnel
  extension writes them too and the app's service bundles and uploads them; the service state
  (`service/`) and connection logs (`connlog/`) in Application Support/Spora. All excluded from
  Time Machine. The direct build's system extension runs as root, so the group container it
  writes into is root's, not the user's: the app fetches its records and log into its own.
- **The hand-over (direct build)**: the system extension serves its `records/` and `diag/` to
  the app over its Mach service (`NEMachServiceName`, `<app group>.tunnel`): SporaKit's
  `DiagnosticsHandover`, started in the extension's `main.swift`. Each end takes only the other
  one, signed by the team that signed itself (a code-signing requirement on the connection, the
  team read from the process's own signature: an unsigned build hands nothing over). The app
  (`TunnelDiagnostics.fetch`) copies each file under its own name, by offset and only ever
  appending, so the core's bug report and uploader read it as if it were written there, a
  record still open and the running extension's log included. Once a file is finished (a
  record with its close entry, a log file rotated away, whatever an earlier extension process
  left) and the app holds all of it, the extension deletes its copy; what is never fetched
  falls to the core's retention. The app asks at launch, on foreground, after a disconnect and
  before a bug report: asking starts the extension's process if it is installed, and never
  installs or activates it. The extension is one per Mac, so whichever user's app asks gets
  what it has.
- **Logging: `SporaLog` (d/i/w/e), never `NSLog`/`print`.** Unified log (subsystem
  `to.spora`) plus the core's diagnostic log file. Never log a blob, a token or a URL. The
  core's flow lines (a share's client destinations) reach the unified log only from a debug
  build of the core (`build-ffi-apple.sh --debug`); a release build keeps them out, and the
  diagnostic file never takes them. Ship only a release build of the core.
- `NetworkReporter` (NWPathMonitor, utun excluded) tells the core the underlying network, in
  each process that runs tunnels: the app (shares) and the tunnel extension.
- The tunnel extension: `initLogging` into the shared log, `connectUtun(recordDir:)`, and the
  sharer's DNS forwarder (`dnsForwarderAddress()`) as the tunnel's resolver.
- FFI calls that touch files or the network (`initService`, `refreshRelays`, `makeShare`,
  `startShare`, `setTelemetryEnabled`, `acknowledgeTelemetryNotice`, `exportBugReport`) run off
  the main thread (`offMain`); `logLine`, `telemetryStatus`, `relayAccessStatus` and the blob
  accessors are cheap.

## Rules

- This repo is public. Internal notes, reviews and specs go in `.local/` (gitignored), never in
  git: nothing from the private Spora repos, their internals, hosts, IPs or credentials. The
  design docs (`.local/docs/`: the ADRs) and the designs (`.local/design/`: the canvas, the
  `_ds/` design-system sync, the logo and icon sources) live there too; a fresh clone has
  none of them. The app's own copies (`App/Resources/Assets.xcassets`) stay in git.
- Every user-facing string via String Catalogs, locales en/ru/be, updated together.
  Micro-labels/statuses/buttons are ALREADY-UPPERCASE in source. `SPORA` literal is hardcoded,
  never localized. Guillemets « » around connection names in prose. No emoji.
- Design system invariants: light theme only; no shadows on cards; no gradients/blur;
  squared toggle; underline inputs; shape-coded status (● active ○ pending ◆ error, dashed =
  waiting-on-a-person); orange = act only, never errors; barcode is the only data-viz.
- Status arrows: ↑ share, ↓ use. Dual role shows both lines, no collapse.
- Errors: enum-mapped to localized strings (raw Rust messages are debug text); attributed to a
  connection at failure time; survive service teardown.
- Secrets → Keychain (`SecretStore`): share blobs, the service's state key, relay tokens. Share
  URLs are bearer credentials.
- The tunnel provider must stay tiny and sandboxed — one source set, packaged as an appex (Debug
  + App Store) and a system extension (Developer ID); app-side state reconciles from
  NEVPNStatus + provider messages. Never activate the system extension for someone who has not
  connected: the first activation is on the first connect, and at launch the app only replaces
  an extension the user already allowed whose version differs from its own (after an update).
