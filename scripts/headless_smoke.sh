#!/usr/bin/env bash
# Headless launch-verify: boot NicosHiddenMenuBar with
# NICOS_HIDDEN_MENUBAR_HEADLESS=1, open the preferences window (its real
# foregrounding path), and assert it never stole focus or popped a window onto
# the screen — then exit. Mirrors nicos-scratchpad's native_smoke.sh
# `headless-no-foreground` + `window-screenshot` assertions.
#
# Launches the binary INSIDE the assembled .app bundle directly (never `open`),
# so it does NOT disturb the user's already-running NicosHiddenMenuBar instance.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE="NicosHiddenMenuBar"
APP_DIR="$ROOT_DIR/.build/release/$EXECUTABLE.app"
BIN="$APP_DIR/Contents/MacOS/$EXECUTABLE"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$ROOT_DIR/.local/headless-smoke/$RUN_ID"
REPORT="$RUN_DIR/report.json"
SCREENSHOT="$RUN_DIR/preferences-window.png"
APP_PID=""

mkdir -p "$RUN_DIR"

cleanup() {
  if [ -n "${APP_PID:-}" ] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

cd "$ROOT_DIR"

# Opt-in macOS GUI launch-verify: skip gracefully where the toolchain is absent
# so a registry run on a non-mac / toolchain-less box stays green.
if ! command -v swift >/dev/null 2>&1; then
  echo "headless smoke skipped: swift not on PATH (opt-in macOS GUI launch-verify)"
  exit 0
fi

make build >/dev/null   # assembles .build/release/NicosHiddenMenuBar.app

NICOS_HIDDEN_MENUBAR_HEADLESS=1 \
NICOS_HIDDEN_MENUBAR_SELFTEST=1 \
NICOS_HIDDEN_MENUBAR_SELFTEST_REPORT="$REPORT" \
NICOS_HIDDEN_MENUBAR_SELFTEST_SCREENSHOT="$SCREENSHOT" \
"$BIN" >"$RUN_DIR/app.stdout" 2>"$RUN_DIR/app.stderr" &
APP_PID=$!

for _ in $(seq 1 30); do
  kill -0 "$APP_PID" >/dev/null 2>&1 || break
  sleep 1
done

if kill -0 "$APP_PID" >/dev/null 2>&1; then
  kill "$APP_PID" >/dev/null 2>&1 || true
  wait "$APP_PID" >/dev/null 2>&1 || true
  echo "headless smoke timed out; see $RUN_DIR" >&2
  exit 1
fi
wait "$APP_PID" >/dev/null 2>&1 || true
APP_PID=""

if [ ! -f "$REPORT" ]; then
  echo "headless smoke report missing; see $RUN_DIR" >&2
  [ -s "$RUN_DIR/app.stderr" ] && cat "$RUN_DIR/app.stderr" >&2
  exit 1
fi

if [ "$(plutil -extract ok raw -o - "$REPORT")" != "true" ]; then
  cat "$REPORT" >&2
  echo "headless smoke failed; see $RUN_DIR" >&2
  exit 1
fi

cat <<EOF
headless smoke passed
report: $REPORT
screenshot: $SCREENSHOT
EOF
