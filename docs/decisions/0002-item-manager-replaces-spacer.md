# ADR-0002: Item manager replaces the spacer as the primary abstraction

- Status: Proposed
- Date: 2026-07-11
- Requirement refs: ARC-001, MOVE-001, DSP-001

## Context

The spacer is compact and dependency-free, but it cannot deterministically hide
items across a notched display. A failed spacer can create large blank regions
without hiding anything. The compact fallback fixes the damage, not the missing
capability.

## Proposed decision

Make a reconciled `MenuBarItemManager` the primary owner of identity, desired
lane, live frame, movement, activation, and per-display state. Keep the spacer
only as a compatibility fallback on displays where live verification proves it
works.

## Consequences

- True hiding and activation become observable state transitions.
- Accessibility-dependent movement becomes a first-class permission boundary.
- More code and OS-specific testing are required.
- The reveal panel becomes a view over canonical managed items instead of an
  independent window scan.

## Acceptance condition

Accept this ADR only with a bounded movement/activation design, rollback model,
and hardware test matrix. Do not enable mutation by default before those exist.
