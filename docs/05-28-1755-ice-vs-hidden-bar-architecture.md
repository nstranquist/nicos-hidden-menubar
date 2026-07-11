# Ice vs. nicos-hidden-menubar — architecture comparison

Date: 2026-05-28. Ice studied at `~/code/refs/Ice` (jordanbaird/Ice, shallow clone).

## TL;DR

Our app is a faithful **Hidden Bar clone**: it owns three of its own
`NSStatusItem`s and collapses by inflating a spacer's `length` to shove its
left-neighbors past the screen's right edge. Ice is a **menu bar manager**: it
sees *every* app's menu bar items through the private window server and physically
*moves* them, so it can truly hide/arrange any item and show them in a separate
popover. The clone breaks on notched displays because the spacer pushes items
*under the notch* rather than off-screen. We closed the biggest part of that gap
(ground-truth visibility + collapse verification); the rest (item movement,
IceBar) is documented as future work.

## Mechanism, side by side

| Concern | nicos-hidden-menubar (before) | Ice |
|---|---|---|
| What it controls | Only its own 3 status items | Every app's menu bar items |
| How it "sees" the bar | `statusItem.button.window.frame` (its own items only; laggy) | `CGSGetProcessMenuBarWindowList` + `CGSGetScreenRectForWindow` — real frames of all items |
| How it hides | Inflate primary-separator `length` so items left of it fall off the right edge | Synthesizes Cmd-drag `CGEvent`s to *move* an item to a destination x |
| Section model | toggle + primary + (optional) secondary spacer | Control items (`NSStatusItem` w/ autosave) as visible/hidden/always-hidden boundaries; moves other items relative to them |
| Revealing hidden items | Shrink the spacer; items reflow back into the bar | **IceBar**: a floating panel that renders captured item images on hover/click |
| Item images | n/a | `ScreenCaptureKit` cache (`MenuBarItemImageCache`) |
| Notch handling | Fails — spacer shoves items into the notch dead-zone | Reads true frames + shows hidden items in IceBar, so the notch never swallows anything |
| Extras | profiles, auto-collapse, HS bridge | search, hotkeys, appearance/tint, spacing, per-display |

## Why the clone fails on notched Macs

The spacer trick assumes "everything left of the separator that gets pushed past
`visibleFrame.maxX` is hidden." On a notched display the usable menu bar is split
by the notch; pushing items leftward can land them in the center dead-zone where
they're invisible *and* not actually removed. Because the app could only read its
own status-item frames, it had no way to notice this happened.

## What we changed (this commit)

Adopted Ice's *foundational* capability without its full machinery:

1. **`CGSPrivate.swift`** — `@_silgen_name` shims for the private CGS window-list
   / frame symbols (a subset of Ice's `Bridging/Shims/Private.swift`).
2. **`MenuBarBridging.swift`** — read-only wrapper: on-screen menu bar window IDs
   and per-item frames.
3. **`MenuBarItemScanner.swift`** — turns frames into facts: total item count,
   hideable count (left of toggle), leftmost x, notch presence, and whether a
   collapse actually pushed an item past the visible edge. Pure `summarize()`
   core is unit-tested (`MenuBarItemScannerTests`).
4. **`StatusSectionController`** — geometry snapshot now carries real-frame data,
   and every collapse is *verified* against real frames; a collapse that hides
   nothing is logged and surfaced (the notch failure mode is now observable).
5. **`DiagnosticsView`** — shows real item count, notch state, and a
   collapse-hid-items ✓/⚠ indicator.

Still **read-only**: we do not synthesize Cmd-drag events to move other apps'
items.

## Parity status (2026-05-28 — implemented)

All roadmap items below are now in the codebase:

1. **Item movement** — `MenuBarItemMover.swift` ports Ice's core Cmd-drag
   `CGEvent` synthesis (grab via Command-flagged `leftMouseDown` at a far point,
   release at the destination item's edge), with mouse hide/warp/restore and the
   private event-field setup. **Gated behind `enableExperimentalItemMovement`
   (default OFF)** and never auto-invoked — it rearranges the real menu bar and
   needs live, supervised validation + Accessibility permission. Simplified vs.
   Ice: a post/settle delay instead of the full event-tap continuation + 5x
   retry machinery; harden if it proves flaky in real use.
2. **IceBar popover** — `IceBarPanel.swift` + `MenuBarItemImageCapture.swift`: a
   floating `NSPanel` that renders hidden items (icons via `SCScreenshotManager`,
   text labels when Screen Recording isn't granted), with a search field. Opens
   via the context menu, the `nicoshiddenbar://icebar` URL, or the global hotkey
   when `iceBarEnabled`. This is the real notch fix — hidden items need no menu
   bar space.
3. **Control-item section model** — `ControlSection.swift` + `StatusItemDefaults`:
   the toggle/primary/secondary status items now carry `autosaveName`s with
   seeded positions, so macOS persists their layout across launches (previously
   absent — a real cause of position drift).
4. **Reveal hotkey / search / capture permission** — hotkey opens the IceBar when
   enabled; IceBar has inline search; Preferences exposes the new toggles and a
   Screen Recording permission button.

### Still simplified vs. Ice (honest deltas)

- Movement uses a fixed-delay post rather than Ice's frame-change waiters +
  retries, so it's less robust on slow/unresponsive item owners.
- No per-item spacing control or menu-bar tint/appearance theming.
- IceBar activation, when movement is OFF, falls back to expanding the bar rather
  than clicking the hidden item in place.
- Identity is `bundleID:title` (no Control-Center special-casing table like
  Ice's `MenuBarItemInfo`).

### Validation done

- Builds clean (`swift build -c release`).
- 34 unit tests pass, covering scanner summarize logic, config backward-compat
  decode of the new optional flags, control-section ordering, and item identity.
- Live behaviors (image capture, Cmd-drag movement) require the user to grant
  permissions and validate on their real bar — intentionally not auto-run.
