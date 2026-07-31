# Architecture overview

## Purpose

Nicos Hidden Bar is a local-first macOS menu-bar manager. It observes real
menu-item windows, owns section-control status items, and presents either an
inline reveal or a below-menu-bar panel. It does not use a network service.

## Current components

| Component | Responsibility | Current owner |
| --- | --- | --- |
| Application lifecycle | windows, URL commands, login item, hotkey | `AppDelegate` |
| Section state | pure expanded/collapsed transitions and typed effects | `MenuBarStateMachine` |
| AppKit section adapter | geometry inputs, status items, menus, effect execution | `StatusSectionController` |
| Geometry | pure ordering, spacer width, verification, and fail-closed predicates | `MarkerGeometry` |
| Discovery | enumerate real menu-item windows and frames once per consistent snapshot | injected `LiveMenuBarDiscoveryService` over `MenuBarItemScanner` + `MenuBarBridging` |
| Item identity | owner, title, display label | `MenuBarItemInfo` |
| Item movement | opt-in synthesized Command-drag | injected `LiveMenuBarPlacementService` over `MenuBarItemMover` |
| Reveal-for-activation | safe visible-lane routing and fallback | injected `LiveMenuBarActivationService` |
| Reveal panel | layout, search, capture lifecycle | `RevealPanel` + injected-owner `RevealPanelModel` |
| Image capture | ScreenCaptureKit snapshots with direct `CGImage` ownership | injected `LiveMenuBarCaptureService` over `MenuBarItemImageCapture` |
| Configuration | validation and atomic JSON persistence | `PreferencesStore` |
| Service contracts | discovery, placement, activation, capture, diagnostics | `MenuBarServiceBoundaries` protocols |
| Diagnostics | categorized local events with explicit public/private fields plus permission/geometry health | injected `LiveMenuBarDiagnosticsRecorder` + `PreferencesStore` + views |
| Display changes | debounced macOS notifications | `ScreenObserver` |

## Current data flow

```text
click / hotkey / URL
        |
        v
StatusSectionController
        | injected MenuBarServices
        v
MenuBarStateMachine -> typed effects
  |          |                    |
  v          v                    v
geometry  discovery owner   reveal panel model
             |                    |
             +-----------> capture owner
             |
             +-----------> activation owner -> placement owner
  |                               |
  +-----------------------> diagnostics owner
                           |
                           v
                 local JSON under ~/.config
```

## Source-of-truth boundaries

- `config.json` owns user intent.
- `NSStatusItem.autosaveName` defaults own macOS-restored control positions.
- the window server owns live item frames and visibility.
- diagnostics report observed state; they do not override configuration.
- `requirements.yaml` owns v0.2 requirement lifecycle and evidence references.
- ADRs own durable architectural rationale.

## Current collapse boundary

The verified spacer is the primary automatic collapse mechanism on notched and
non-notched displays (ADR-0005). Verification snapshots the exact rendered
items in hidden lanes, excludes Window Server chrome and this app's controls,
and requires all planned IDs to disappear. A failure releases the spacer and
remains expanded with `hide_unavailable`; automatic collapse never falls
through to synthetic item movement.

The item manager remains responsible for discovery, identity, panel activation,
and explicit relative placement. Movement is used only for user-directed
unhide/reorder/reveal actions and retains its permission and opt-in boundaries.
External-display hardware acceptance remains open under `DSP-001-B`.

The headless self-test constructs the production service graph before its early
exit and validates the concrete owners plus activation's shared placement-owner
identity. This proves composition wiring, not hardware behavior; the later
placement, activation, capture, and display requirements retain those claims.

## Target boundaries

The v0.2 target splits the current controller into:

- `MenuBarStateMachine` — pure transitions and invariants;
- `MenuBarItemRepository` — discovery and stable identity;
- `SectionLayoutEngine` — per-display lane placement;
- `ItemActivationService` — activate, move, retry, and recover;
- `RevealPanelController` — panel lifecycle and incremental presentation;
- `CaptureCache` — bounded captured-image ownership;
- `DiagnosticsRecorder` — observed facts and receipts.

AppKit objects remain `@MainActor`; pure models and reducers remain isolated from
AppKit so they are deterministic and unit-testable.
