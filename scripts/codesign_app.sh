#!/usr/bin/env bash
# Sign NicosHiddenMenuBar.app with a stable identity when available.
# Prefer Apple Development (dogfood / TCC stability). Ad-hoc is last resort.
set -euo pipefail

APP_PATH="${1:?usage: codesign_app.sh /path/to/App.app}"
BUNDLE_ID="${BUNDLE_ID:-com.nstranquist.nicos-hidden-menubar}"

pick_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "$CODESIGN_IDENTITY"
    return
  fi
  if [[ -n "${DEVELOPER_ID_IDENTITY:-}" ]]; then
    echo "$DEVELOPER_ID_IDENTITY"
    return
  fi
  # Prefer Apple Development for local dogfood (survives rebuilds under same cert).
  local dev
  dev="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | head -1 || true)"
  if [[ -n "$dev" ]]; then
    echo "$dev"
    return
  fi
  # Developer ID Application when present (distribution).
  local did
  did="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -1 || true)"
  if [[ -n "$did" ]]; then
    echo "$did"
    return
  fi
  echo ""
}

IDENTITY="$(pick_identity)"
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  echo "  codesign: ad-hoc (no stable identity). Accessibility will break on every reinstall."
  codesign --force --deep --sign - "$APP_PATH"
  echo "ADHOC" >"${APP_PATH}.codesign-mode"
  exit 0
fi

echo "  codesign: $IDENTITY"
# Hardened runtime when using a real identity (required for notarization path).
if codesign --force --deep --options runtime --sign "$IDENTITY" --timestamp=none "$APP_PATH" 2>/dev/null; then
  :
else
  # Some Development certs reject --options runtime in local builds; retry without.
  codesign --force --deep --sign "$IDENTITY" "$APP_PATH"
fi
codesign --verify --verbose=2 "$APP_PATH" 2>&1 | sed 's/^/  /' | head -8 || true
if [[ "$IDENTITY" == Developer\ ID* ]]; then
  echo "DEVELOPER_ID" >"${APP_PATH}.codesign-mode"
elif [[ "$IDENTITY" == Apple\ Development* ]]; then
  echo "APPLE_DEVELOPMENT" >"${APP_PATH}.codesign-mode"
else
  echo "CUSTOM" >"${APP_PATH}.codesign-mode"
fi
echo "  identity stable → Accessibility should survive rebuilds (grant once per identity)."
