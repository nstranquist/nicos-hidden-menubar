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

No v0.2 requirement is accepted or verified yet. Existing v0.1 evidence is a
baseline, not proof of the stronger contracts proposed here.
