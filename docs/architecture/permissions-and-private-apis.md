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

Ad-hoc source builds may receive a new code identity after reinstall, causing
macOS to request Screen Recording or Accessibility again. Distribution-quality
releases therefore require a stable signing identity, notarization, and a
permission regression smoke.

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
