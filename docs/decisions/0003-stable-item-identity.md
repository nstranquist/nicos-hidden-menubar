# ADR-0003: Stable identity for menu-bar items

- Status: Accepted (implemented 2026-07-14)
- Date: 2026-07-11
- Requirement refs: ITEM-001, ACT-001

## Context

`bundleID:title` collides for image-only and repeated Control Center items. The
result is duplicate labels, weak caching, and ambiguous activation.

## Proposed decision

Define a versioned identity record using the strongest available signals:

- owner bundle identifier and process role;
- normalized item title or accessibility identifier;
- Control Center module metadata table;
- stable control-item autosave identity where owned by this app;
- frame/order only as a temporary reconciliation hint, never durable identity.

Persist user policy against the versioned identity. Migration must preserve
recognizable old entries and surface ambiguous matches for repair.

## Consequences

- Search, caching, profiles, and activation share one identity.
- Control Center needs explicit, tested specialization.
- Identity schema changes require migrations and fixtures.
