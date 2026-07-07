# Spora macOS client

Native macOS client for Spora (P2P VPN through a trusted friend). Swift + SwiftUI +
NetworkExtension over the Rust core at `../spora` (UniFFI). Functional reference:
`../spora-android`. Design source of truth: `Spora macOS.dc.html` (committed direction:
window 1b master-detail + menu-bar popover 1d/2e; see `docs/adr-001-architecture.md`).

## Build & run

- `scripts/dev.sh build` — build app (xcodebuild via XcodeGen's `project.yml`).
- `scripts/dev.sh run` / `quit` / `shot [name]` / `state <cmd> [k=v…]` / `log` — the feedback
  harness; screenshots land in `artifacts/`. State-seeding vocabulary matches Android's
  `DebugStateReceiver` (`seed`, `share-starting|started|failed|stopped`,
  `connect-connecting|connected|failed|disconnected`, `reset`).
- Rust FFI: `../spora/build-ffi-apple.sh` builds the staticlib + Swift bindings into
  `rust-out/` here. Rust changes are made in `../spora` (its own repo — commit separately).

## Rules

- Every user-facing string via String Catalogs, locales en/ru/be, updated together.
  Micro-labels/statuses/buttons are ALREADY-UPPERCASE in source. `SPORA` literal is hardcoded,
  never localized. Guillemets « » around connection names in prose. No emoji.
- Design system invariants: light theme only; no shadows on cards; no gradients/blur;
  squared toggle; underline inputs; shape-coded status (● active ○ pending ◆ error, dashed =
  waiting-on-a-person); orange = act only, never errors; barcode is the only data-viz.
- Status arrows: ↑ share, ↓ use. Dual role shows both lines, no collapse.
- Errors: enum-mapped to localized strings (raw Rust messages are debug text); attributed to a
  connection at failure time; survive service teardown.
- Identity bytes are secrets → Keychain. Share URLs are bearer credentials.
- The tunnel appex must stay tiny and sandboxed; app-side state reconciles from NEVPNStatus +
  provider messages.
