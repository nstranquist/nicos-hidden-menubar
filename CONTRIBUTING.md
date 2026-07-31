# Contributing to Nicos Hidden Bar

Native macOS menu-bar organizer (Swift 6, AppKit + SwiftUI). Local-first; no
account or network service.

## Setup

```sh
make build
swift test                 # 162 package tests at the current v0.2 checkpoint
make format-check          # no-regression ratchet for visible formatting debt
make docs-check            # requirements evidence gate
make verify-publication    # tests + format/docs + strict release build + gitleaks
make perf-check            # five-minute installed-app performance receipt
make headless-smoke        # optional: real settings window off-screen
make release-artifact      # local ZIP + checksum/provenance, never auto-publishes
```

Requires macOS 14+, Xcode CLT / Swift 6 toolchain.

## Agent notes

- Single gate: `make verify-publication`.
- Do not commit real Screen Recording captures of personal menu-bar apps;
  use the privacy-safe screenshot under `docs/assets/`.
- GPL-3.0 with upstream Hidden Bar attribution in `NOTICE`.
- Publication push remains human-gated (`docs/PUBLICATION_READINESS.md`).

## Layout

| Path | Role |
| --- | --- |
| `Sources/` | App + library targets |
| `scripts/` | headless smoke, docs evidence |
| `docs/initiatives/` | v0.2 production hardening requirements |
| `.github/workflows/ci.yml` | macOS-15 publication gate (activates on public remote) |
