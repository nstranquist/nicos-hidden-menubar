# v0.2 production hardening

- Status: Proposed
- Owner: `@nstranquist`
- Started: 2026-07-11
- Supersedes: no artifact; extends the frozen v0.1 contract

## Objective

Turn the current portfolio-quality v0.1 into a trustworthy daily menu-bar
manager by replacing implicit spacer behavior with explicit item lifecycle,
activation, evidence, and release contracts.

## Canonical artifacts

- [`spec.md`](spec.md) — scope and target architecture.
- [`requirements.yaml`](requirements.yaml) — lifecycle and evidence index.
- [`implementation-plan.md`](implementation-plan.md) — ordered execution slices.
- [`acceptance.md`](acceptance.md) — baseline and graduation evidence.

## Source-of-truth rule

Markdown owns rationale and design. `requirements.yaml` owns requirement state
and evidence references. GitHub issues may mirror tasks but do not change scope
or mark a requirement verified.

## Current state

`ARC-001` is verified. Slice 2–4 software contracts are **accepted** (code +
automated evidence landed 2026-07-14; promote to `verified` after a commit
receipt + hardware smokes). The 2026-07-31 local closeout passed the guarded
publication gate, generated a checksummed local artifact, reconciled the
installed runtime to the current bundle identity, and passed the headless
settings smoke; see
[`LOCAL-20260731.json`](receipts/LOCAL-20260731.json).

- `ITEM-001` versioned identity + Control Center fixtures + legacy migration
- `ACT-001` in-place panel activation with explicit outcomes + permission repair UI
- `MOVE-001` pure placement engine + bounded retry/timeout/rollback in the mover
- `CAP-001` shell-first RevealPanel, incremental capture updates, bounded icon cache

Built-in-display `PERF-001` has a five-minute machine-readable v0.2 receipt for
RSS and reveal latency. Its CPU observation is awaiting a user-approved refresh
with the corrected CPU-time delta metric. Screen Recording icon-completion
performance (`CAP-001-B`), hardware
acceptance (`ACT-001-B`, `MOVE-001-B`, `DSP-001-B`), and distribution
completion (`REL-001-B`) remain open. `DOC-001` is implemented and `TEST-001`
is accepted for automated coverage of must software contracts.
