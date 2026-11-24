#!/usr/bin/env bash
# Spora macOS feedback harness — the counterpart to Android's emu.sh (ADR D6).
# Subcommands: build [xcodebuild args…] · run [locale] · quit · shot [name] · state <cmd> [k=v…] · log
# With --direct first: the direct download's build (SporaDirect, the tunnel as a
# system extension), plus `notarize` and `install`.
#
# `build` signs only with a team: DEVELOPMENT_TEAM=<team ID> in the environment
# or as an argument. Without one the build is unsigned, and runs everything but
# the packet tunnel (whose NetworkExtension entitlement needs a paid team).
# Extra arguments go to xcodebuild.
#
# --direct builds the SporaDirect scheme into build-direct/. With a team it signs
# with Developer ID by hand: the certificate in the keychain and the Developer ID
# profiles named by SPORA_PROFILE_APP and SPORA_PROFILE_TUNNEL (defaults: "Spora
# macOS", "Spora macOS Tunnel"), and a fresh build number each time, so that
# sysextd replaces the running extension. macOS activates a system extension
# only from /Applications, and only once Apple has notarized it (a local test
# build too): `--direct notarize` submits the build (keychain profile
# SPORA_NOTARY_PROFILE, default spora-notary) and staples it, `--direct
# install` copies it to /Applications, and `--direct run` starts that copy.
# Signing and notarizing use the login keychain: over SSH, run them in the
# logged-in user's session (`sudo launchctl asuser <uid> …`).
#
# States are driven through the DEBUG-only spora-debug:// URL scheme (same
# command vocabulary as Android's DebugStateReceiver), so screenshot matrices
# stay portable. Screenshots self-capture the window into artifacts/ (an open
# sheet lands next to it as <name>-sheet.png).
#
# Never contact production from development: `run` pins the core's API to
# SPORA_API, by default an address that answers nothing (set SPORA_API to a
# local spora-web to see the reachable relay/telemetry states).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIRECT=0
if [ "${1:-}" = "--direct" ]; then DIRECT=1; shift; fi

PROJECT="Spora.xcodeproj"
SCHEME="Spora"
CONFIG="Debug"
DERIVED="build"
ARCH="$(uname -m)"
if [ "$DIRECT" = 1 ]; then SCHEME="SporaDirect"; DERIVED="build-direct"; fi
APP="$DERIVED/Build/Products/$CONFIG/Spora.app"
INSTALLED="/Applications/Spora.app"
# The direct build runs from /Applications (the only place macOS activates its
# extension from).
if [ "$DIRECT" = 1 ]; then RUN_APP="$INSTALLED"; else RUN_APP="$APP"; fi
BIN="$RUN_APP/Contents/MacOS/Spora"
ARTIFACTS="$ROOT/artifacts"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

send() { open "spora-debug://$1" >/dev/null 2>&1 || true; }

cmd_build() {
  command -v xcodegen >/dev/null && xcodegen generate >/dev/null
  # Unsigned unless a team is named. The empty app group keeps an unsigned
  # build out of a group container it has no entitlement for.
  local signing=(CODE_SIGNING_ALLOWED=NO SPORA_APP_GROUP=) arg team="${DEVELOPMENT_TEAM:-}"
  for arg in "$@"; do
    if [[ $arg == DEVELOPMENT_TEAM=?* ]]; then team="${arg#DEVELOPMENT_TEAM=}"; fi
  done
  if [ -n "$team" ] && [ "$DIRECT" = 1 ]; then
    # No base entitlements: Developer ID never carries get-task-allow.
    signing=(DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Manual
             CODE_SIGN_IDENTITY="Developer ID Application"
             CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
             SPORA_PROFILE_APP="${SPORA_PROFILE_APP:-Spora macOS}"
             SPORA_PROFILE_TUNNEL="${SPORA_PROFILE_TUNNEL:-Spora macOS Tunnel}"
             CURRENT_PROJECT_VERSION="$(date +%s)" OTHER_CODE_SIGN_FLAGS=--timestamp)
  elif [ -n "$team" ]; then
    signing=(DEVELOPMENT_TEAM="$team" -allowProvisioningUpdates)
  fi
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" -arch "$ARCH" build \
    "${signing[@]}" "$@" | tail -1
  # Register so `open spora-debug://…` routes to the app. The touch makes the
  # Dock's icon cache notice an in-place rebuild (a new app icon otherwise
  # keeps showing the old one).
  [ "$DIRECT" = 1 ] && return 0 # registered where it runs, by `install`
  touch "$APP"
  [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
}

# Notarize the direct build and staple its ticket (sysextd refuses an
# extension Apple has not notarized).
cmd_notarize() {
  [ "$DIRECT" = 1 ] || { echo "notarize: only with --direct" >&2; return 1; }
  [ -d "$APP" ] || { echo "notarize: build first" >&2; return 1; }
  local zip="$DERIVED/Spora-notarize.zip"
  rm -f "$zip"
  ditto -c -k --keepParent "$APP" "$zip"
  xcrun notarytool submit "$zip" --keychain-profile "${SPORA_NOTARY_PROFILE:-spora-notary}" --wait
  rm -f "$zip"
  xcrun stapler staple "$APP"
}

# The direct build into /Applications. The extension macOS already runs stays
# until the app's next connect asks to replace it.
cmd_install() {
  [ "$DIRECT" = 1 ] || { echo "install: only with --direct" >&2; return 1; }
  [ -d "$APP" ] || cmd_build
  # Only a running app: the quit URL would otherwise launch one, unpinned from
  # SPORA_API.
  if pgrep -x Spora >/dev/null; then cmd_quit; fi
  rm -rf "$INSTALLED"
  ditto "$APP" "$INSTALLED"
  touch "$INSTALLED"
  [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$INSTALLED" >/dev/null 2>&1 || true
  echo "installed $INSTALLED ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALLED/Contents/Info.plist"))"
}

cmd_run() {
  local locale="${1:-be}"
  if [ ! -x "$BIN" ]; then
    if [ "$DIRECT" = 1 ]; then cmd_install; else cmd_build; fi
  fi
  mkdir -p "$ARTIFACTS"
  # Relaunch fresh.
  pkill -x Spora >/dev/null 2>&1 || true
  sleep 0.4
  SPORA_API="${SPORA_API-http://127.0.0.1:9}" SPORA_ARTIFACTS_DIR="$ARTIFACTS" "$BIN" \
    -AppleLanguages "($locale)" -AppleLocale "${locale}_BY" \
    >/dev/null 2>&1 &
  echo "launched Spora (locale=$locale, SPORA_API=${SPORA_API-http://127.0.0.1:9}, pid=$!)"
  sleep 1.2
}

cmd_quit() { send "quit"; sleep 0.3; pkill -x Spora >/dev/null 2>&1 || true; }

cmd_shot() {
  local name="${1:-shot}"
  local out="$ARTIFACTS/$name.png"
  rm -f "$out"
  send "shot?name=$name"
  # Wait for the self-capture to land.
  for _ in $(seq 1 30); do [ -f "$out" ] && break; sleep 0.2; done
  if [ -f "$out" ]; then echo "wrote $out"; else echo "shot failed: $out not written" >&2; return 1; fi
}

cmd_state() {
  local sub="${1:?usage: state <cmd> [k=v…]}"; shift || true
  local query=""
  for kv in "$@"; do
    local enc="${kv// /%20}"
    query+="${query:+&}$enc"
  done
  send "$sub${query:+?$query}"
  sleep 0.3
}

cmd_log() {
  # The app, and the tunnel: the app extension, or the system extension (its
  # process is named after its bundle identifier).
  log stream --style compact --level debug --predicate \
    'process == "Spora" OR process == "SporaTunnelExt" OR process == "to.spora.macos.tunnel"'
}

case "${1:-}" in
  build) shift; cmd_build "$@" ;;
  install) shift; cmd_install "$@" ;;
  notarize) shift; cmd_notarize "$@" ;;
  run)   shift; cmd_run "$@" ;;
  quit)  shift; cmd_quit "$@" ;;
  shot)  shift; cmd_shot "$@" ;;
  state) shift; cmd_state "$@" ;;
  log)   shift; cmd_log "$@" ;;
  *) echo "usage: dev.sh [--direct] {build [xcodebuild args…]|notarize|install|run [locale]|quit|shot [name]|state <cmd> [k=v…]|log}" >&2; exit 1 ;;
esac
