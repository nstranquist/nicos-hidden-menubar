# Changelog

All notable changes to Nicos Hidden Bar are recorded here.

## Unreleased

## [0.3.0] — 2026-11-02

Source release. This release does not include a downloadable notarized
application; the public binary waits on the clean-machine and permission-flow
checks in `docs/releases/release-checklist.md`.

### Added

- Opt-in **Rescue overflow into hidden lane** setting. When enabled, menu-bar
  extras stranded under the camera gap move just left of the hide separator
  and are verified after the move. It is off by default, requires
  Accessibility and experimental movement, and never runs as a collapse
  fallback.
- Distinct reveal-panel tile captions for sibling extras from the same app,
  assigned by proximity and then left-to-right Accessibility pairing.
- README **Usage** and **Troubleshooting** sections.
- Public product passport and repository launch contract.

### Fixed

- Overflow movement targets the planned hidden-lane band, so extras under the
  gap actually move. Rollback restores both sides of the original position,
  and session cooldown keys include window IDs.
- README images use `raw.githubusercontent.com`. GitHub rewrites relative
  image paths to `/raw/main/...` URLs that return 404.
- Swift formatting cleanup so the publication warning ratchet passes in CI.

### Documentation

- Recorded Apple Developer Program membership and the Developer ID
  Application identity used for local notarized installs.

## [0.2.0] — 2026-08-14

First public source release. This release does not include a downloadable
notarized application.

- Verified spacer collapse on notched and regular displays.
- Searchable below-menu-bar reveal panel.
- Versioned item identity and Hidden Bar preference import.
- Public macOS publication gate with 162 tests, documentation checks, a
  warnings-as-errors build, and full-history secret scanning.
- Compatibility with the hosted Swift 6 toolchain through the reviewed
  `ScreenCaptureKit` concurrency boundary.
- Sanitized public history and a generic signing-identity evidence gate.
- Ice (`jordanbaird/Ice`) attribution recorded in `NOTICE`.

## [0.1.0] — 2026-07-11

- Initial standalone Swift package extracted from the local workspace.
