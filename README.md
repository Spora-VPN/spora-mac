# Spora for macOS

macOS client for [Spora](https://github.com/Spora-VPN/spora), a P2P VPN: share your internet connection with someone you trust, or connect through theirs. All networking lives in the Rust core; this repo is the macOS app around it: a window and a menu-bar popover in SwiftUI, and a NetworkExtension packet tunnel. The [Android app](https://github.com/Spora-VPN/spora-android) is the functional reference.

**Status: in development, not released.**

## Layout

- `App/` is the app: window, menu-bar popover, flows, settings (relays, telemetry), feedback, notifications. Shares run in the app process: the core's userland exit needs no privileges and no tunnel.
- `Tunnel/` is the `NEPacketTunnelProvider`, the connect side. It finds the utun file descriptor and hands it to the core's `connect_utun`; everything else happens in the core.
- `Packages/SporaKit` holds the models, state machines, errors and persistence (share links and other secrets in the Keychain), and starts the core's service (the device identity, Spora's relays, the diagnostic log and the telemetry switch). It is compiled together with the Swift bindings the core generates; its tests are in `Packages/SporaKit/Tests`.
- `Packages/SporaDesign` holds the design tokens and SwiftUI components, with IBM Plex bundled.

## Build

You need macOS 13 or later, Xcode, Rust (rustup) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The core is a sibling checkout at the commit named in `.github/core-ref`:

```bash
git clone https://github.com/Spora-VPN/spora
git clone https://github.com/Spora-VPN/spora-mac
git -C spora checkout "$(grep -v '^#' spora-mac/.github/core-ref)"
(cd spora && ./build-ffi-apple.sh)
cd spora-mac
scripts/dev.sh build
```

`build-ffi-apple.sh` builds the core's FFI as a universal static library and generates its Swift bindings into `rust-out/` here (`--debug` for a faster debug build). `scripts/dev.sh build` generates `Spora.xcodeproj` from `project.yml` and builds it into `build/`.

The project signs automatically with Spora's team. Extra arguments to `scripts/dev.sh build` go to `xcodebuild`, so `scripts/dev.sh build DEVELOPMENT_TEAM=<your team ID>` signs with yours. The packet tunnel needs a paid Apple Developer team (the NetworkExtension entitlement); without one, `scripts/dev.sh build CODE_SIGNING_ALLOWED=NO` still compiles everything, which is what CI does.

The tests: `xcodebuild -project Spora.xcodeproj -scheme Spora test`.

The app talks to Spora's API (device registration, relay access, telemetry when switched on). A Debug build uses the API that `SPORA_API` names, comma-separated, and Spora's production API when it is unset; a Release build always uses production. `scripts/dev.sh run` sets `SPORA_API` to `http://127.0.0.1:9` (answers nothing) unless you set it yourself.

## Feedback harness

`scripts/dev.sh run [locale]` launches the Debug build (Belarusian by default), `shot [name]` writes a screenshot of the window to `artifacts/`, `state <cmd> [k=v…]` seeds UI states (`seed`, `share-starting`, `connect-connected`, `reset`, … the same vocabulary as the Android app's debug receiver; the macOS extras are listed in `App/Sources/Debug/DebugController.swift`), `log` streams the app's log and `quit` stops it. States travel over the `spora-debug://` URL scheme, which only Debug builds handle.

## Languages

English, Russian and Belarusian, in the String Catalog `App/Resources/Localizable.xcstrings`, always updated together.

## License

[GPL-3.0](LICENSE). [NOTICE](NOTICE) lists what the app bundles: the IBM Plex fonts (SIL Open Font License) and the Spora core.
