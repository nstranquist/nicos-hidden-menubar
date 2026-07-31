#!/usr/bin/env bash
# Optional distribution path: Developer ID sign + notarytool submit + staple.
# Requires:
#   DEVELOPER_ID_IDENTITY="Developer ID Application: …"
#   APPLE_ID / APPLE_TEAM_ID / APPLE_APP_SPECIFIC_PASSWORD
#   or NOTARYTOOL_PROFILE (keychain profile from `xcrun notarytool store-credentials`)
set -euo pipefail

APP_PATH="${1:?usage: notarize_app.sh /path/to/App.app}"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found: $APP_PATH" >&2
  exit 1
fi

IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -1 || true)"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "error: set DEVELOPER_ID_IDENTITY to a Developer ID Application cert." >&2
  echo "  Dogfood should use Apple Development via make install (no notarization needed)." >&2
  exit 1
fi

echo "  Signing for distribution: $IDENTITY"
codesign --force --deep --options runtime --sign "$IDENTITY" --timestamp "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

ZIP="${APP_PATH%.app}-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  echo "  Submitting with keychain profile: $NOTARYTOOL_PROFILE"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
else
  : "${APPLE_ID:?set APPLE_ID or NOTARYTOOL_PROFILE}"
  : "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}"
  : "${APPLE_APP_SPECIFIC_PASSWORD:?set APPLE_APP_SPECIFIC_PASSWORD}"
  echo "  Submitting with Apple ID credentials…"
  xcrun notarytool submit "$ZIP" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
fi

xcrun stapler staple "$APP_PATH"
spctl --assess --type execute -vv "$APP_PATH" 2>&1 | sed 's/^/  /' || true
rm -f "$ZIP"
echo "  Notarized and stapled: $APP_PATH"
