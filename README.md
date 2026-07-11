# Nicos Hidden Bar

A native macOS menu-bar organizer for hiding the status items you do not need
all the time. It is local-first, has no account or network service, and is built
with Swift, AppKit, and SwiftUI.

The app provides three regions—visible, hidden, and optionally always hidden—
with a compact chevron in the menu bar to reveal or collapse them. A searchable
floating panel provides a notch-safe way to reach hidden items on modern
MacBooks.

## Highlights

- Native menu-bar app with no Dock icon during normal use
- Visible, hidden, and always-hidden regions
- Auto-collapse profiles for focus, presenting, and recording
- Global keyboard shortcut
- Searchable hidden-items panel with text fallback
- Multi-display and notch-aware geometry diagnostics
- Optional import of existing Hidden Bar preferences
- Optional experimental item movement behind an explicit safety toggle
- JSON configuration and diagnostics that stay on your Mac

## Requirements

- macOS 14 Sonoma or newer
- Apple Silicon or Intel Mac supported by the Swift 6 toolchain
- Xcode Command Line Tools for source builds

## Install from source

```bash
git clone git@github.com:nstranquist/nicos-hidden-menubar.git
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
6. Click the chevron to verify that the intended items collapse and return.

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

The headless smoke opens and captures the real settings window off-screen while
asserting that the app never steals focus. Reports and screenshots are written
under `.local/headless-smoke/` and are ignored by Git.

## Architecture and tradeoffs

The app owns AppKit `NSStatusItem` controls and uses their persisted positions
as section boundaries. SwiftUI owns Settings, Onboarding, Profiles, and
Diagnostics. Notch-aware discovery reads menu-item window frames through private
CoreGraphics window-server symbols; this makes the app appropriate for direct,
open-source distribution rather than the sandboxed Mac App Store.

Experimental movement synthesizes the same Command-drag interaction a user can
perform manually. It remains off by default because third-party menu items can
respond at different speeds. The normal marker-and-spacer path is the safe
default.

No configuration, diagnostics, screenshots, or telemetry leave the machine.

## License and provenance

Nicos Hidden Bar is released under the GNU General Public License v3.0. Parts of
its menu-bar discovery and movement design are adapted from
[Ice](https://github.com/jordanbaird/Ice), also GPL-3.0. See [NOTICE](NOTICE) for
attribution and [LICENSE](LICENSE) for the complete terms.

