# Spec: v0.2 production hardening

- Status: Proposed
- Date: 2026-07-11
- Requirement source: [`requirements.yaml`](requirements.yaml)

## Problem

The app now avoids destructive notch spacing and presents a useful adaptive
panel, but its core abstraction remains a spacer. Item identity is ambiguous,
panel selection does not reliably activate items, capture is sequential, the
central controller owns too many concerns, and release automation is minimal.

## Goals

- MUST model menu-item state and transitions independently from AppKit views.
- MUST activate a selected panel item or return an explicit recoverable outcome.
- MUST identify repeated Control Center and image-only items distinctly.
- MUST reconcile lane placement per display with bounded retries and rollback.
- MUST show the panel immediately and load captured icons incrementally.
- MUST test state transitions, permission permutations, and display changes.
- MUST ship CI, formatting, warning, and release gates suitable for open source.
- SHOULD preserve idle physical footprint at or below the v0.1 budget.

## Non-goals

- Mac App Store sandboxing.
- cloud sync, accounts, or uploaded telemetry.
- arbitrary theming or Control Center reimplementation.
- enabling unproven item mutation silently.

## Target design

1. Extract a pure `MenuBarStateMachine` and typed effects.
2. Introduce a stable identity repository and Control Center metadata adapter.
3. Add an `ItemActivationService` with explicit outcomes, permission handling,
   frame waiters, bounded retries, and recovery.
4. Promote a per-display item manager to canonical placement ownership.
5. Make the reveal panel an incremental projection of managed item state.
6. Isolate diagnostics receipts from user configuration.

## Migration

- Preserve schema-v1 configuration reads.
- Introduce versioned item identities behind a migration adapter.
- Keep legacy spacer behavior available only as a verified compatibility path.
- Do not remove a legacy field until fixtures prove decode and migration.
- Never mutate another app's item during migration.

## Safety

- Private API failure, permission denial, ambiguous identity, or unreadable
  geometry MUST fail closed.
- Movement attempts MUST be bounded and restore pointer/state on failure.
- Profile and lane policy MUST remain recoverable from local configuration.
- Captured images MUST remain local and memory-bounded.

## Graduation

Every `must` requirement is `verified`, all acceptance evidence is linked, the
compatibility matrix has required hardware coverage, the release checklist is
complete, and no known P0/P1 gap is hidden or mislabeled.
