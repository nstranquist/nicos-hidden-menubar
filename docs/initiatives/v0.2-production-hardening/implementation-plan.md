# Implementation plan

- Status: Accepted; Slice 1 active
- Scope source: [`requirements.yaml`](requirements.yaml)

No slice starts merely because it appears here. Accept the relevant requirements
and proposed ADRs before implementation. `ARC-001` and `TEST-001` were accepted
on 2026-07-11 for Slice 1; later slices remain unaccepted.

## Slice 0: Documentation and baseline

- Establish the documentation index, architecture truth, ADRs, requirement
  registry, quality matrices, and v0.1 known-gap record.
- Add deterministic requirement/link validation.
- Capture current test, performance, and hardware baselines.

Exit: DOC-001 accepted and its automated checks are green.

## Slice 1: State and effect boundaries

- Extract `MenuBarStateMachine` with typed input, state, transition, and effect.
- Introduce protocols for discovery, placement, activation, capture, and
  diagnostics.
- Keep AppKit adaptation in the existing controller until parity tests pass.

Requirements: ARC-001, TEST-001.

## Slice 2: Identity and activation

- Implement versioned identity and Control Center fixtures.
- Add `ItemActivationService` and explicit outcome UI.
- Prove third-party and Control Center activation on the notched baseline Mac.

Requirements: ITEM-001, ACT-001.

## Slice 3: Reconciled placement

- Implement frame observation, bounded retry, cancellation, and recovery.
- Promote item manager state to canonical per-display placement ownership.
- Retain spacer only as a verified compatibility adapter.

Requirements: MOVE-001, DSP-001.

## Slice 4: Incremental panel

- Open immediately from metadata.
- Add placeholder/app-icon fallback and incremental capture delivery.
- Add bounded cache, invalidation, memory pressure, and permission transitions.

Requirements: CAP-001, PERF-001.

## Slice 5: Verification matrix

- Add controller and service integration tests.
- Run topology, resolution, full-screen, permission, restart, and owner matrix.
- Record machine-readable performance and hardware receipts.

Requirements: TEST-001, DSP-001, PERF-001.

## Slice 6: Distribution

- Add macOS CI, formatting, warnings-as-errors, docs validation, and coverage.
- Create versioned packaging, stable signing, notarization, and staple checks.
- Run clean-machine install, login-item, permissions, upgrade, and rollback smoke.

Requirements: REL-001, DOC-001.

## Commit policy

Each slice lands in reviewable commits that name requirement IDs. Do not combine
state extraction with behavior changes, or signing/release changes with core
item movement. Preserve unrelated user work and keep failed evidence visible.
