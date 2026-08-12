# Security

Nicos Hidden Bar is a local-first macOS menu-bar organizer. It has no account
and no network service. Configuration and diagnostics stay on the machine.

## Reporting

Do not disclose security issues in a public issue. Use GitHub private
vulnerability reporting once a public repository exists. Until then, contact
[@nstranquist](https://github.com/nstranquist) privately.

## Permissions

| Permission | Required | Used for |
|---|---|---|
| Accessibility | Recommended | Opening hidden items from the panel; experimental item movement; Control Center labels |
| Screen Recording | Optional | Live pixel icons of menu-bar items |

Basic marker-based collapse and reveal work without either permission.

## Private APIs

The app reads menu-item window frames through private CoreGraphics / SkyLight
symbols. That makes it appropriate for direct, open-source distribution rather
than the sandboxed Mac App Store. See `docs/architecture/permissions-and-private-apis.md`.

## Local data

User state is stored under `~/.config/nicos-hidden-menubar/`. Do not commit
those files, Screen Recording captures of a personal menu bar, or signing
identities.

## Secrets in this tree

`make verify-publication` runs full-history and working-tree `gitleaks` scans.
Do not add personal emails, Apple Development identities, or private menu-bar
screenshots.
