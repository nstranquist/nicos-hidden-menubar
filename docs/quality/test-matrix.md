# Test matrix

## Current automated coverage

The v0.1 suite covers configuration, migration/import, geometry predicates,
scanner summarization, bridge behavior, first-party title rules, item candidate
filtering, layout calculations, exit-code shapes, ARC-001 pure section-state
transitions, exact live-owner composition, shared placement-owner identity,
single-pass discovery, direct image transport, categorized diagnostic privacy,
injected discovery/capture routing, activation-to-placement delegation,
disabled-movement fallback, and typed live-placement failure propagation.

## Required v0.2 coverage

| Layer | Required coverage | Requirement |
| --- | --- | --- |
| Pure state | expand, collapse, compact fallback, permission, cancellation | ARC-001 |
| Identity | third-party, image-only, repeated Control Center, migration | ITEM-001 |
| Activation | success, denied, unsupported, timeout, recovered failure | ACT-001 |
| Movement | observed frame success, retry, timeout, rollback | MOVE-001 |
| Displays | offset, scaled, attach, detach, resize, full screen | DSP-001 |
| Capture | denied, incremental success, cancellation, invalidation, bounds | CAP-001 |
| Controller integration | input -> effects -> diagnostics -> presentation | TEST-001 |
| Persistence | schema migration, atomic failure, last-good recovery | TEST-001 |
| Release | clean build, launch, login item, permissions, upgrade, rollback | REL-001 |

## Naming and traceability

Acceptance tests include their requirement ID, for example:

```text
testACT001PanelSelectionActivatesThirdPartyItem
testDSP001DisplayRemovalInvalidatesFrames
```

Hardware smokes produce checked-in redacted receipts or immutable CI/release
references. Screenshots alone are supporting evidence, not the only assertion.
