# Permissions and private APIs

## Permission matrix

| Capability | Permission | Degraded behavior |
| --- | --- | --- |
| Discover item windows and frames | none; private CGS symbols | fail closed if symbols or frames are unavailable |
| Show captured icons | Screen Recording | text/app-icon fallback with an explicit permission action |
| Synthesized movement or activation | Accessibility | no mutation; return `permission_required` |
| Launch at login | Service Management approval | app remains runnable and reports registration state |

## Private API boundary

Private CGS/SkyLight declarations MUST remain isolated in `CGSPrivate.swift` and
wrapped by a narrow typed facade. No view, state machine, or configuration code
may call private symbols directly.

Private API failure MUST be treated as a supported runtime condition:

- return an empty/unreadable result rather than crash;
- preserve the current menu-bar arrangement;
- record symbol/operation health without private user content;
- offer a visible recovery or unsupported message.

## Signing and privacy permissions

**Ad-hoc** (`codesign -s -`) binds Accessibility to a one-off CDHash. Every
`make install` re-breaks trust even when Settings still shows the app as ON.

**Dogfood (default):** `make install` prefers an **Apple Development** identity
via `scripts/codesign_app.sh` so rebuilds keep the same designated requirement.
Grant Accessibility once per identity (`make install-stable` resets the TCC row
and opens Privacy settings).

**Distribution:** set `DEVELOPER_ID_IDENTITY` and run `make notarize` (notarytool
+ staple). Requires Apple Developer Program credentials / `NOTARYTOOL_PROFILE`.

Override anytime:

```bash
CODESIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" make install
DEVELOPER_ID_IDENTITY="Developer ID Application: …" make notarize
```

## OS compatibility

Every supported macOS release needs evidence for:

- CGS enumeration and frame reads;
- notch detection;
- menu-item identity for third-party and Control Center items;
- ScreenCaptureKit icon capture;
- Accessibility activation/movement;
- login-item registration.

Unknown or changed behavior fails closed. Compatibility claims live in
`../quality/compatibility-matrix.md`.
