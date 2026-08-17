# Changelog

All notable changes to Nicos Hidden Bar are recorded here.

## Unreleased

- Point README images at `raw.githubusercontent.com`. GitHub currently
  rewrites relative image paths to `/raw/main/...` URLs that return 404.

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
