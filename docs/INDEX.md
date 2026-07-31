# Documentation index

This index is the front door for product, architecture, execution, quality, and
release documentation. Chat and GitHub issues may point here, but they are not
canonical substitutes for these files.

## Product and architecture

- [`../README.md`](../README.md) — public product story, installation, and use.
- [`../spec.md`](../spec.md) — frozen v0.1 product contract. Historical; do not
  rewrite it to describe later behavior.
- [`architecture/overview.md`](architecture/overview.md) — current component and
  source-of-truth map.
- [`architecture/item-lifecycle.md`](architecture/item-lifecycle.md) — discovery,
  identity, placement, reveal, and activation lifecycle.
- [`architecture/permissions-and-private-apis.md`](architecture/permissions-and-private-apis.md)
  — permission boundaries and OS-fragile dependencies.
- [`05-28-1755-ice-vs-hidden-bar-architecture.md`](05-28-1755-ice-vs-hidden-bar-architecture.md)
  — historical comparison and implementation chronology.

## Decisions

Decision records are append-only. Supersede a decision with a new record rather
than silently changing its rationale.

- [`decisions/0001-direct-distribution-and-private-cgs.md`](decisions/0001-direct-distribution-and-private-cgs.md)
- [`decisions/0002-item-manager-replaces-spacer.md`](decisions/0002-item-manager-replaces-spacer.md)
- [`decisions/0003-stable-item-identity.md`](decisions/0003-stable-item-identity.md)
- [`decisions/0004-panel-capture-and-cache.md`](decisions/0004-panel-capture-and-cache.md)
- [`decisions/0005-verified-spacer-primary.md`](decisions/0005-verified-spacer-primary.md)

## Active initiative

- [`initiatives/v0.2-production-hardening/README.md`](initiatives/v0.2-production-hardening/README.md)
- [`initiatives/v0.2-production-hardening/spec.md`](initiatives/v0.2-production-hardening/spec.md)
- [`initiatives/v0.2-production-hardening/requirements.yaml`](initiatives/v0.2-production-hardening/requirements.yaml)
- [`initiatives/v0.2-production-hardening/implementation-plan.md`](initiatives/v0.2-production-hardening/implementation-plan.md)
- [`initiatives/v0.2-production-hardening/acceptance.md`](initiatives/v0.2-production-hardening/acceptance.md)

## Quality and release

- [`quality/test-matrix.md`](quality/test-matrix.md)
- [`quality/compatibility-matrix.md`](quality/compatibility-matrix.md)
- [`quality/performance-budgets.md`](quality/performance-budgets.md)
- [`releases/v0.1-known-gaps.md`](releases/v0.1-known-gaps.md)
- [`releases/v0.2-progress.md`](releases/v0.2-progress.md)
- [`releases/release-checklist.md`](releases/release-checklist.md)

## Lifecycle rules

Requirements move through:

```text
proposed -> accepted -> implemented -> verified -> shipped
                         \-> deferred
```

- `implemented` requires a commit reference.
- `verified` requires evidence for every acceptance item.
- hardware claims include OS, display topology, and observation date.
- `shipped` requires a versioned installed or distributed artifact.
- incomplete or failed acceptance remains visible.
