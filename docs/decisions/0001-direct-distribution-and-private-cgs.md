# ADR-0001: Direct distribution and private CGS discovery

- Status: Accepted
- Date: 2026-07-11
- Context: frozen v0.1 spec and current architecture

## Context

Public AppKit APIs expose this app's status items but not a complete inventory
of other applications' menu extras. Reliable diagnostics and notch-aware item
discovery require real window-server frames.

## Decision

Use a narrow, read-only wrapper around the private CGS menu-window and frame
symbols. Distribute directly rather than targeting the sandboxed Mac App Store.
Keep all private declarations isolated behind `MenuBarBridging`.

## Consequences

- The app can inspect real menu-item geometry and verify collapse behavior.
- App Store distribution is not a target.
- Each macOS release requires compatibility evidence.
- Missing or changed symbols must fail closed without rearranging user items.

## Alternatives rejected

- Own-status-item geometry only: insufficient around notches and multiple apps.
- Accessibility-only inventory: incomplete and permission-dependent.
- Reimplementing Control Center: far beyond product scope.
