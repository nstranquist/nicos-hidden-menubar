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
| Geometry | pure ordering, width, notch fallback predicates | `MarkerGeometry` |
| Discovery | enumerate real menu-item windows and frames | injected `LiveMenuBarDiscoveryService` over `MenuBarItemScanner` + `MenuBarBridging` |
| Item identity | owner, title, display label | `MenuBarItemInfo` |
| Item movement | opt-in synthesized Command-drag | injected `LiveMenuBarPlacementService` over `MenuBarItemMover` |
| Reveal-for-activation | safe visible-lane routing and fallback | injected `LiveMenuBarActivationService` |
| Reveal panel | layout, search, capture lifecycle | `IceBarPanel` + injected-owner `IceBarModel` |
| Image capture | ScreenCaptureKit snapshots | injected `LiveMenuBarCaptureService` over `MenuBarItemImageCapture` |
| Configuration | validation and atomic JSON persistence | `PreferencesStore` |
| Service contracts | discovery, placement, activation, capture, diagnostics | `MenuBarServiceBoundaries` protocols |
| Diagnostics | structured local events plus permission/geometry health | injected `LiveMenuBarDiagnosticsRecorder` + `PreferencesStore` + views |
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

## Current limitation

The spacer is a compatibility mechanism, not a reliable notch architecture. If
live verification proves it hid nothing, the app releases it rather than leave
a large blank region. True deterministic placement and activation require the
proposed item-manager architecture in ADR-0002.

The state reducer and live service owners are extracted and injected. The
activation owner currently preserves v0.1 reveal-for-click behavior rather than
claiming direct activation; `ACT-001` owns the stronger direct activation,
permission outcome, retry, and recovery contract.

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
