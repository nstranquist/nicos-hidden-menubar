# Nicos Hidden Bar

A native macOS menu-bar organizer for hiding the status items you do not need
all the time. It is local-first, has no account or network service, and is built
with Swift, AppKit, and SwiftUI.

<img src="assets/brand/nicos-hidden-menubar.svg" width="96" height="96" alt="Nicos Hidden Bar application icon">

The app provides three regions—visible, hidden, and optionally always hidden—
with a compact chevron in the menu bar to reveal or collapse them. A searchable
floating panel provides a notch-safe way to reach hidden items on modern
MacBooks.

![Nicos Hidden Bar settings showing reveal, permission, auto-collapse, and shortcut controls](docs/assets/preferences-window.png)

## Highlights

- Native menu-bar app with no Dock icon during normal use
- Visible, hidden, and always-hidden regions
- Auto-collapse profiles for focus, presenting, and recording
- Global keyboard shortcut
- Searchable hidden-items panel with text fallback
- Automatic below-menu-bar reveal on notched displays
- Per-display panel sizing with live display-change handling
- Optional import of existing Hidden Bar preferences
- Optional experimental item movement behind an explicit safety toggle
- JSON configuration and diagnostics that stay on your Mac

## Requirements

- macOS 14 Sonoma or newer
- Apple Silicon or Intel Mac supported by the Swift 6 toolchain
- Xcode Command Line Tools for source builds

## Install from source

```bash
git clone https://github.com/nstranquist/nicos-hidden-menubar.git
cd nicos-hidden-menubar
make install
```

`make install` builds a release app, ad-hoc signs it, installs it at
`/Applications/NicosHiddenMenuBar.app`, and opens it. Launch at login is managed
from Settings using macOS Service Management.

To remove the app, first disable **Launch at login** in Settings, then run:

```bash
make uninstall
```

## First-run setup

1. Find the chevron and separator markers in the menu bar.
2. Hold Command and drag menu-bar items into the desired regions.
3. Keep frequently used items to the right of the primary separator.
4. Put items you want to collapse to the left of the primary separator.
5. Enable the optional always-hidden region if you want a second boundary.
6. Choose **Automatic**, **In the menu bar**, or **Below the menu bar** in
   Settings, then click the chevron to verify the reveal behavior.

Option-click the chevron to temporarily reveal the marker controls. Right-click
it to open Settings, Diagnostics, the hidden-items panel, or Quit.

## Permissions

| Permission | Required | Used for |
|---|---:|---|
| Accessibility | No | Experimental synthesized Command-drag item movement |
| Screen Recording | No | Capturing live icons for the hidden-items panel |

Basic marker-based collapse and reveal work without either permission. When
Screen Recording is unavailable, the hidden-items panel uses text labels.

## Configuration

User state is stored under:

```text
~/.config/nicos-hidden-menubar/config.json
~/.config/nicos-hidden-menubar/diagnostics.json
~/.config/nicos-hidden-menubar/hammerspoon-bridge.json
```

The Hammerspoon bridge is advisory. The app's JSON configuration remains the
source of truth when they disagree.

The URL scheme can be used by Shortcuts, Hammerspoon, or shell automation:

```text
nicoshiddenbar://toggle
nicoshiddenbar://expand
nicoshiddenbar://collapse
nicoshiddenbar://icebar
nicoshiddenbar://open/settings
nicoshiddenbar://open/diagnostics
nicoshiddenbar://profile/focus
```

## Development

```bash
swift test
make build
make headless-smoke
make run
```

Project architecture, decisions, active requirements, quality matrices, and
release evidence are indexed in [`docs/INDEX.md`](docs/INDEX.md).
Validate their links and evidence contract with `make docs-check`.

The headless smoke opens and captures the real settings window off-screen while
asserting that the app never steals focus. Reports and screenshots are written
under `.local/headless-smoke/` and are ignored by Git.

Run `make verify-publication && make headless-smoke` before release. The
reviewed repository screenshot above is copied from that smoke output and
contains no account, menu-bar, configuration, or other private user data.

## Architecture and tradeoffs

The app owns AppKit `NSStatusItem` controls and uses their persisted positions
as section boundaries. SwiftUI owns Settings, Onboarding, Profiles, and
Diagnostics. Notch-aware discovery reads menu-item window frames through private
CoreGraphics window-server symbols; this makes the app appropriate for direct,
open-source distribution rather than the sandboxed Mac App Store.

Display topology and resolution changes are handled through macOS notifications,
without a background polling loop. The reveal panel is sized and clamped to the
display containing the status item, then releases captured icon images when it
closes.

Experimental movement synthesizes the same Command-drag interaction a user can
perform manually. It remains off by default because third-party menu items can
respond at different speeds. Automatic reveal keeps the normal marker-and-spacer
path on regular displays and uses the below-menu-bar panel when a notch is
detected.

No configuration, diagnostics, screenshots, or telemetry leave the machine.

## License and provenance

Nicos Hidden Bar is released under the GNU General Public License v3.0. Parts of
its menu-bar discovery and movement design are adapted from
[Ice](https://github.com/jordanbaird/Ice), also GPL-3.0. See [NOTICE](NOTICE) for
attribution and [LICENSE](LICENSE) for the complete terms.
