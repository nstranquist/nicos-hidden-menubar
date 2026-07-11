# ADR-0004: Incremental bounded capture cache

- Status: Proposed
- Date: 2026-07-11
- Requirement refs: CAP-001, PERF-001

## Context

The current panel waits for sequential per-window captures before it appears.
This is simple and memory-safe after close, but cold reveal latency grows with
the item count.

## Proposed decision

Open the panel immediately from discovered metadata, render placeholders or app
icons, and fill actual captures incrementally through a bounded cache keyed by
stable item identity plus frame/display scale. Invalidate on frame, owner,
appearance, permission, or display-scale changes.

## Consequences

- Warm reveal can meet an interactive latency budget.
- Cache ownership and invalidation become explicit.
- Screen Recording remains optional.
- The cache must have count/byte bounds and release all entries under memory
  pressure or app termination.
