# Nicos Hidden Bar: native macOS behavior under real display constraints

## Problem

Crowded macOS menu bars become harder to use on notched displays, but a menu-bar
organizer must manipulate system-owned geometry carefully. Incorrect collapse
logic can hide the wrong items, drift after repeated toggles, steal focus, or
strand controls on another display.

## Nico's role

Nico designed and built the standalone Swift/AppKit application, SwiftUI
settings and diagnostics, screen-aware geometry and state machine, optional
movement path, configuration and import boundary, headless native smoke, and
release documentation.

## Key decisions

- Treat the app's own status items as explicit section boundaries rather than
  continuously polling or scraping every menu item.
- Make spacer collapse idempotent and screen-aware, then verify the exact
  hidden-lane window IDs disappeared from the rendered menu bar.
- Use a below-menu-bar reveal panel as the notch-safe access surface while
  preserving selected standalone items in the visible lane.
- Fail closed and remain expanded when collapse cannot be verified; never fall
  through to automatic third-party item movement.
- Keep synthesized Command-drag movement off by default behind an explicit
  Accessibility permission and safety toggle.
- Keep all configuration and diagnostics local, with no account, network
  service, or telemetry.
- Preserve GPL-3.0 compatibility and explicit Ice attribution for adapted
  discovery and movement techniques.

## Verified result

The current local release passes 162 Swift tests, an
11-requirement/24-criterion documentation check, a warnings-as-errors signed
release build, both repository secret scans, and five-minute RSS/reveal
performance evidence,
and a native smoke that opens and captures the real settings window without
stealing focus. Three live cycles on the built-in notched display each verified
eight hidden-lane items removed while two standalone third-party items and two
system items remained visible. The reviewed screenshot is committed at
`docs/assets/preferences-window.png` (current Layout tab; no personal menu-bar
or account data). Public GitHub Actions CI on `main` runs the same publication
boundary on macOS.

## Evidence boundary

The source is public at
[`nstranquist/nicos-hidden-menubar`](https://github.com/nstranquist/nicos-hidden-menubar)
under GPL-3.0. The screenshot contains only the
application’s synthetic/default settings surface and no operator menu-bar,
configuration, account, or diagnostic data. External-display, Control Center
activation, repeated successful movement, Screen Recording icon completion,
Developer ID notarization, and clean-machine installation are not claimed.
