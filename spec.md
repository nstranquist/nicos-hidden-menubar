# Spec: Nicos Hidden Bar

Status: approved and frozen on 2026-07-11

## 1. Scope

Ship a dependable, personal macOS menu-bar organizer under the existing
`NicosHiddenMenuBar` app. The app divides menu extras into visible, hidden, and
optional always-hidden regions; reveals or collapses them from a menu-bar
toggle; survives relaunch; and works on notched displays through an optional
searchable floating item panel.

This slice finishes the existing implementation rather than creating a second
app. It includes a focused settings/onboarding polish pass, installation into
`/Applications`, launch-at-login wiring, migration from an installed Hidden Bar
configuration when present, and live acceptance testing on this Mac.

The default path must be safe: ordinary marker-based hide/reveal is enabled;
synthetic Command-drag movement of other apps' items remains explicitly opt-in.

## 2. Interface

- A native menu-bar toggle with collapsed and expanded states and no Dock icon.
- Command-drag-positionable separators defining visible, hidden, and optional
  always-hidden regions.
- Left click toggles visibility. Right click opens commands for Settings,
  Diagnostics, the searchable hidden-items panel, and Quit.
- A configurable global keyboard shortcut toggles or reveals hidden items.
- Settings cover launch at login, auto-collapse timing, lane behavior, shortcut,
  active profile, searchable panel, experimental item movement, and permission
  status. Text must fit at normal macOS display scaling without truncation.
- First-run onboarding explains marker placement and any required permissions.
- Existing `nicoshiddenbar://` actions remain supported.

## 3. Data Model

- Canonical user configuration:
  `~/.config/apps/desktop/nicos-hidden-menubar/config.json`.
- Persist active profile, auto-collapse settings, shortcut, lanes, panel and
  movement feature flags, first-party-visible titles, and onboarding state.
- Persist marker positions through stable `NSStatusItem.autosaveName` values.
- Keep diagnostics and the Hammerspoon bridge advisory; configuration remains
  authoritative when they disagree.
- On first launch only, import supported values from an existing Hidden Bar
  defaults domain without deleting or modifying the original preferences.

## 4. Dependencies

- Swift 6, AppKit, SwiftUI, CoreGraphics, and ScreenCaptureKit on macOS 14+.
- Private read-only CGS window-list/frame symbols for notch-aware menu-item
  discovery. This makes the app appropriate for personal/local distribution,
  not a sandboxed Mac App Store release.
- Accessibility permission is required only for the opt-in synthetic
  Command-drag item mover.
- Screen Recording permission is optional and used only to render live icons in
  the searchable panel; the panel must retain a text fallback without it.
- No new third-party runtime dependencies.

## 5. Success Criteria

1. `swift test` passes with no failures and `make headless-smoke` passes.
2. Release build installs as `/Applications/NicosHiddenMenuBar.app`, launches
   without a Dock icon, and has a loaded per-user login agent.
3. First launch creates valid config and presents understandable onboarding.
4. On this Mac, clicking the toggle hides and restores the intended menu items;
   auto-collapse and the global shortcut work; marker order survives relaunch.
5. The searchable panel opens and identifies hidden items on a notched display,
   with a usable fallback when Screen Recording is denied.
6. Settings and diagnostics are visually inspected at normal scale: no clipped
   controls, truncated essential copy, overlapping content, or dead actions.
7. Invalid config or unreadable marker geometry fails closed, leaves menu items
   recoverable, and points to a concrete repair action.

## 6. Failure Modes

- Invalid config: retain the last valid/default configuration, report the exact
  validation problem, and do not manipulate other menu items.
- Missing or denied permissions: keep the basic toggle usable, explain the
  degraded feature, and provide the relevant System Settings action.
- Invalid marker ordering or unreadable geometry: do not collapse; surface a
  repair instruction in Diagnostics.
- A collapse that hides no items: report it rather than claiming success and
  offer the searchable panel as the notch-safe path.
- Item movement timeout/failure: restore the pointer, stop retrying, preserve
  the current menu-bar order, and record diagnostics.
- Missing Hidden Bar preferences: skip migration silently and initialize clean
  defaults.
- Login-agent installation failure: leave the app runnable and report the
  failed installation step without deleting user config.

## 7. Deferred / Out of Scope

- Mac App Store distribution, sandboxing, notarization, and auto-update service.
- Menu-bar tint/theming and arbitrary per-item spacing.
- Reimplementing Control Center or managing Apple-owned immovable items.
- Cloud sync, analytics upload, or a cross-platform version.
- Making experimental synthetic item movement the default until live testing
  proves it reliable across multiple third-party item owners.
