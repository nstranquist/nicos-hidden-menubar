# Repository guidance

Nicos Hidden Bar is a native Swift 6 macOS menu-bar app targeting macOS 14+.

- Keep normal use Dock-less through the accessory activation policy.
- Keep experimental movement opt-in and fail closed when geometry or permissions
  are unavailable.
- Preserve local-only behavior; do not add network calls or uploaded telemetry.
- Keep configuration backward compatible unless the schema version is migrated
  deliberately with tests.
- Keep initiative requirements in `docs/initiatives/*/requirements.yaml` and
  run `make docs-check` after documentation changes.
- Run `swift test` and `make headless-smoke` after app changes.
- Run a case-insensitive repository audit before public-release commits.
- Do not commit `.build/`, `.local/`, user configuration, or captured menu-bar
  images.
