# Nicos Hidden Bar

Native macOS Hidden Bar clone for Nicos-owned menubar control.

Repo compass: [../docs/active/CODEBASE_MAP.md](../docs/active/CODEBASE_MAP.md).

## Architecture

- AppKit-owned `NSStatusItem` marker items for the spacer-width collapse mechanism
- SwiftUI-owned preferences, onboarding, profile editor, and diagnostics windows
- JSON config at `~/.config/apps/desktop/nicos-hidden-menubar/config.json`
- Advisory Hammerspoon bridge at `~/.config/apps/desktop/nicos-hidden-menubar/hammerspoon-bridge.json`

## Build & Run

```bash
make build
make run
make install
make uninstall
```
