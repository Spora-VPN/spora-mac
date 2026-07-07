#!/usr/bin/env bash
# Spora macOS feedback harness — the counterpart to Android's emu.sh (ADR D6).
# Subcommands: build · run [locale] · quit · shot [name] · state <cmd> [k=v…] · log
#
# States are driven through the DEBUG-only spora-debug:// URL scheme (same
# command vocabulary as Android's DebugStateReceiver), so screenshot matrices
# stay portable. Screenshots self-capture the window into artifacts/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="Spora.xcodeproj"
SCHEME="Spora"
CONFIG="Debug"
DERIVED="build"
ARCH="$(uname -m)"
APP="$DERIVED/Build/Products/$CONFIG/Spora.app"
BIN="$APP/Contents/MacOS/Spora"
ARTIFACTS="$ROOT/artifacts"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

send() { open "spora-debug://$1" >/dev/null 2>&1 || true; }

cmd_build() {
  command -v xcodegen >/dev/null && xcodegen generate >/dev/null
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" -arch "$ARCH" build \
    CODE_SIGNING_ALLOWED=NO | tail -1
  # Register so `open spora-debug://…` routes to the app.
  [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
}

cmd_run() {
  local locale="${1:-be}"
  [ -x "$BIN" ] || cmd_build
  mkdir -p "$ARTIFACTS"
  # Relaunch fresh.
  pkill -x Spora >/dev/null 2>&1 || true
  sleep 0.4
  SPORA_ARTIFACTS_DIR="$ARTIFACTS" "$BIN" \
    -AppleLanguages "($locale)" -AppleLocale "${locale}_BY" \
    >/dev/null 2>&1 &
  echo "launched Spora (locale=$locale, pid=$!)"
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
  log stream --style compact --predicate 'process == "Spora"' --level debug
}

case "${1:-}" in
  build) shift; cmd_build "$@" ;;
  run)   shift; cmd_run "$@" ;;
  quit)  shift; cmd_quit "$@" ;;
  shot)  shift; cmd_shot "$@" ;;
  state) shift; cmd_state "$@" ;;
  log)   shift; cmd_log "$@" ;;
  *) echo "usage: dev.sh {build|run [locale]|quit|shot [name]|state <cmd> [k=v…]|log}" >&2; exit 1 ;;
esac
